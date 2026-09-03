import 'package:flutter/widgets.dart';

import '../../core/utils/platform_tv.dart';
import 'video_stats.dart';

/// §engineVendor étape 3 — **La frontière entre l'app et son moteur vidéo.**
///
/// ## Pourquoi cette interface existe
///
/// `AetherPlayerController` exposait son `player` **nu**, et six fichiers
/// plongeaient dedans (`player_page`, `player_controls`, `player_gestures`,
/// `player_replay_bar`, `track_selector_sheet`, `video_stats`). Changer de
/// moteur imposait donc de réécrire ces six fichiers — et la fuite la plus
/// profonde était `video_stats.dart`, qui atteignait `player.platform` pour
/// lire des propriétés **mpv**.
///
/// Cette interface referme la frontière. L'app ne parle plus qu'à elle, et un
/// second moteur devient une implémentation de plus au lieu d'un chantier.
///
/// ⚠️ **Elle est volontairement PETITE** : exactement ce que les six fichiers
/// consomment, relevé un par un, et rien de plus. Une interface qui anticipe
/// des besoins imaginaires oblige chaque moteur à mentir sur ce qu'il sait
/// faire.
///
/// ⚠️ **Aucun type de moteur ne traverse cette frontière** — ni `Player`, ni
/// `AudioTrack` de media_kit, ni `NativeVideoPlayerController`. C'est la
/// condition pour que le remplacement soit réel et pas cosmétique.
/// §audio — Volume de départ et plafond, **communs à tous les moteurs**.
///
/// ⚠️ Ces valeurs vivaient dans l'implémentation media_kit : un second moteur
/// ne les aurait jamais appliquées, et le son serait reparti à 100 % sans que
/// personne ne comprenne pourquoi. C'est une règle de l'APP (les flux IPTV sont
/// souvent encodés à faible niveau), pas une particularité de libmpv.
abstract final class AetherVolume {
  /// Sur téléviseur, le boost natif du poste est déjà important → 125 %.
  static double get initial => PlatformTv.isTv ? 125.0 : 130.0;

  /// Au-delà de 100 %, l'amplification est logicielle (mpv `volume-max`,
  /// `LoudnessEnhancer` côté Media3 — cf. §engineVendor patch 1).
  static const double max = 200.0;
}

/// §stallCount — Santé d'UNE session de lecture, lisible de façon **synchrone**.
///
/// Synchrone à dessein : le bilan est relevé dans `dispose()` du lecteur, où
/// aucun `await` n'est possible — c'est justement le moment où la mesure est
/// complète.
@immutable
class AetherPlaybackHealth {
  /// Blocages depuis le début de la session — **hors** mise en tampon initiale
  /// et hors `seek` (cf. `Media3Engine`).
  final int stalls;

  /// Temps cumulé passé bloqué.
  final Duration stalled;

  /// Délai entre l'ouverture et la première image. `null` si jamais parti.
  final Duration? startup;

  /// Temps réellement passé à lire (hors pause, hors blocage).
  final Duration watched;

  const AetherPlaybackHealth({
    this.stalls = 0,
    this.stalled = Duration.zero,
    this.startup,
    this.watched = Duration.zero,
  });

  static const AetherPlaybackHealth empty = AetherPlaybackHealth();

  /// Une session sans lecture effective ne dit rien : ni bonne, ni mauvaise.
  bool get isMeaningful => watched.inSeconds >= 10;
}

abstract class AetherPlaybackEngine {
  // ── Commandes ──────────────────────────────────────────────────────────────

  Future<void> play();
  Future<void> pause();
  Future<void> playOrPause();
  Future<void> seek(Duration position);

  /// Vitesse de lecture (0.25 → 2.0).
  Future<void> setRate(double rate);

  /// Volume **0 → 200** (et non 0 → 1) : les flux IPTV sont souvent encodés à
  /// faible niveau, l'app démarre à 125 % sur TV (§audio).
  Future<void> setVolume(double volume);

  Future<void> setAudioTrack(AetherTrack track);
  Future<void> setSubtitleTrack(AetherTrack track);

  /// Coupe l'audio en sélectionnant « aucune piste ».
  ///
  /// ⚠️ Méthode SÉMANTIQUE plutôt qu'un identifiant : mpv utilise `'no'`, un
  /// autre moteur ne le fera pas. §audioFallback en a besoin pour lire **sans
  /// son** quand aucune piste n'est décodable — une image sans audio reste
  /// regardable, un écran d'erreur non.
  Future<void> disableAudio();

  // ── Ouverture ──────────────────────────────────────────────────────────────

  /// Ouvre un flux réseau.
  ///
  /// [start] est passé **nativement** au moteur (§resumeStart) : un `seek`
  /// après ouverture était parfois avalé pendant le buffering initial.
  /// [audioLang]/[subLang] sont posés **avant** l'ouverture (§trackLangPref) —
  /// les poser après provoque un re-demux ~3 s plus tard, l'effet « le film se
  /// relance ».
  Future<void> open(
    String url, {
    Duration? start,
    String? audioLang,
    String? subLang,
  });

  Future<void> openFile(
    String path, {
    Duration? start,
    String? audioLang,
    String? subLang,
  });

  // ── État instantané ────────────────────────────────────────────────────────

  Duration get position;
  Duration get duration;
  bool get playing;

  List<AetherTrack> get audioTracks;
  List<AetherTrack> get subtitleTracks;
  AetherTrack? get currentAudioTrack;
  AetherTrack? get currentSubtitleTrack;

  // ── Flux ───────────────────────────────────────────────────────────────────

  Stream<bool> get playingStream;
  Stream<bool> get bufferingStream;
  /// `true` quand la lecture atteint sa fin.
  ///
  /// ⚠️ Un flux live ou un replay n'a pas de fin exploitable, et l'événement
  /// peut arriver alors que la durée est encore nulle : c'est à l'appelant de
  /// filtrer (cf. `_listenCompleted`).
  Stream<bool> get completedStream;
  Stream<String> get errorStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;

  /// Position tamponnée, pour la partie « chargée » de la barre de progression.
  Stream<Duration> get bufferStream;

  /// Émis quand les caractéristiques de l'image changent — c'est ce qui
  /// déclenche la mesure §qualityTruth.
  ///
  /// ⚠️ Porte la **définition réellement décodée**, pas celle annoncée par la
  /// liste : c'est toute la raison d'être de §qualityTruth. Republié à chaque
  /// reconfiguration de la chaîne vidéo, d'où le garde-fou `_measuredKey` côté
  /// appelant.
  Stream<AetherVideoSize> get videoParamsStream;

  // ── Rendu ──────────────────────────────────────────────────────────────────

  /// La surface vidéo, telle que le moteur sait la produire.
  ///
  /// ⚠️ Le moteur décide **comment** il rend (texture ou SurfaceView) : c'est
  /// précisément la différence qui a motivé toute la migration, et l'app n'a
  /// pas à la connaître.
  Widget buildSurface(BoxFit fit);

  // ── Diagnostic ─────────────────────────────────────────────────────────────

  /// §videoStats — Instantané de diagnostic.
  ///
  /// ⚠️ **C'est le moteur qui le produit**, pas un lecteur externe : les
  /// sources diffèrent radicalement (propriétés mpv d'un côté,
  /// `AnalyticsListener` de Media3 de l'autre). C'était la fuite la plus
  /// profonde de l'ancien code.
  ///
  /// ⚠️ Un champ que le moteur ne sait pas renseigner doit rester **`null`**,
  /// jamais zéro : un zéro se lit comme une mesure (leçon §hwdecUnknown).
  Future<VideoStatsSnapshot> readStats();

  /// §stallCount — Bilan de la session en cours. Toujours lisible, y compris
  /// pendant `dispose()`.
  AetherPlaybackHealth get health;

  /// §liveRecover — Tente de repartir **sans rouvrir le flux**.
  ///
  /// Le cas qui l'impose : sur une CHAÎNE, un tampon vidé fait émettre une
  /// erreur au moteur. La seule réponse dont disposait l'app était de
  /// réouvrir l'URL — nouvelle connexion, décodeur recréé, écran noir, ~3,5 s
  /// avant la première image. Mesuré au journal : un `load` complet et toutes
  /// les statistiques remises à zéro. Sur du 4K, c'est très visible.
  ///
  /// Renvoie `false` si le moteur n'a rien à reprendre — l'appelant retombe
  /// alors sur la réouverture, qui reste le filet.
  Future<bool> recoverInPlace();

  void dispose();
}

/// Définition d'image réellement décodée, indépendante du moteur.
@immutable
class AetherVideoSize {
  /// `null` tant que le moteur n'a rien décodé — **jamais 0**, qui se lirait
  /// comme une mesure (leçon §hwdecUnknown).
  final int? w;
  final int? h;

  const AetherVideoSize(this.w, this.h);
}

/// Une piste audio ou sous-titre, **indépendante du moteur**.
///
/// ⚠️ Les identifiants ne sont PAS interchangeables entre moteurs : mpv utilise
/// `'auto'`/`'no'` et des index, Media3 des identifiants de groupe. [id] n'a de
/// sens que pour le moteur qui l'a produit — ne jamais le persister.
@immutable
class AetherTrack {
  final String id;
  final String? title;
  final String? language;

  /// Piste « automatique » ou « aucune » : à présenter différemment d'une
  /// vraie piste dans le sélecteur.
  final bool isSpecial;

  const AetherTrack({
    required this.id,
    this.title,
    this.language,
    this.isSpecial = false,
  });

  /// Libellé affichable, avec repli en cascade — une piste sans titre ni langue
  /// reste sélectionnable plutôt que d'apparaître vide.
  String get label {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) {
      final l = language?.trim();
      return (l != null && l.isNotEmpty && l != t) ? '$t · $l' : t;
    }
    final l = language?.trim();
    if (l != null && l.isNotEmpty) return l;
    return id;
  }

  @override
  bool operator ==(Object other) => other is AetherTrack && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
