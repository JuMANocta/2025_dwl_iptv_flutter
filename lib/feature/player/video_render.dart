import 'package:flutter/foundation.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// §video4kBench — Banc d'essai du chemin de rendu vidéo.
///
/// ## Pourquoi ce levier existe
///
/// Relevé sur la box Android TV réelle (2026-08-30, §video4k) pendant 2 min 07
/// d'un film 4K HDR 10 bits : `hw=mediacodec-copy`, `res=3840x2072`, 24 img/s,
/// et surtout `perdues=15 → 1029`.
///
/// Soit **8,12 images perdues par seconde, une sur trois**, avec un
/// `decoder-frame-drop-count` resté à zéro : le décodeur tient, c'est
/// l'affichage qui jette. Et surtout, ce taux est **rigoureusement invariant
/// au débit** (identique à 1,4 et à 5,3 Mb/s) — donc ni le réseau ni la source.
/// Le coupable est le chemin `mediacodec-copy` retenu par `hwdec=auto-safe` :
/// chaque image redescend en mémoire centrale (~16 Mo) avant de remonter en
/// texture, deux fois 380 Mo/s à 24 img/s.
///
/// ## Pourquoi un réglage plutôt qu'un correctif direct
///
/// Le levier évident ([VideoRenderMode.direct]) a un **prix** :
/// `mediacodec_embed` est un rendu direct dans la Surface Android, où mpv ne
/// dessine **ni OSD ni sous-titres**. L'OSD ne coûte rien (les contrôles
/// d'AetherStream sont 100 % Flutter par-dessus), mais les **sous-titres
/// VOSTFR seraient perdus**. On ne peut donc pas l'imposer par défaut, et le
/// choix ne peut pas se faire à l'aveugle : il se mesure, sur la box, avec
/// « Infos vidéo ».
///
/// ⚠️ Chaque essai coûte un cycle de release (la box tourne un APK signé CI,
/// un `install` debug effacerait comptes et favoris) — d'où un banc d'essai
/// embarqué plutôt qu'une constante à recompiler.
///
/// ⚠️ Délibérément **hors de `PerfConfig`**, comme `VideoFitPreference` et
/// `VideoStatsPreference` : ce n'est pas un paramètre de profil, ça n'a rien à
/// faire dans les presets Confort/Équilibré/Performance ni dans les backups
/// `.aether` — un réglage de diagnostic qui voyagerait d'un appareil à l'autre
/// appliquerait à un téléphone sain le contournement d'une box malade.
enum VideoRenderMode {
  /// Comportement historique : on laisse media_kit décider (`vo=gpu`,
  /// `hwdec=auto-safe`). Sur la box, ça donne `mediacodec-copy`.
  auto(
    label: 'Auto',
    detail: 'Défaut media_kit — sur box TV : copie mémoire',
    vo: null,
    hwdec: null,
  ),

  /// Zéro copie : MediaCodec décode directement dans la Surface Android.
  /// ⚠️ Supprime les sous-titres rendus par mpv.
  direct(
    label: 'Direct',
    detail: 'Zéro copie · ⚠️ sans sous-titres',
    vo: 'mediacodec_embed',
    hwdec: 'mediacodec',
  ),

  /// Le chemin copy-back, forcé explicitement — pour comparer sans dépendre de
  /// ce qu'`auto-safe` décide ce jour-là sur ce flux.
  copy(
    label: 'Copie',
    detail: 'Copie mémoire forcée — le témoin à battre',
    vo: 'gpu',
    hwdec: 'mediacodec-copy',
  ),

  /// Décodage processeur. C'est ce que l'émulateur imposait (et où il ne
  /// perdait aucune image) : le témoin qui a innocenté le code.
  software(
    label: 'Logiciel',
    detail: 'Décodage processeur — témoin émulateur',
    vo: 'gpu',
    hwdec: 'no',
  );

  const VideoRenderMode({
    required this.label,
    required this.detail,
    required this.vo,
    required this.hwdec,
  });

  final String label;
  final String detail;

  /// `null` ⇒ on ne surcharge pas, media_kit applique son défaut de plateforme.
  final String? vo;
  final String? hwdec;
}

/// §video4kBench — Stratégie de synchro A/V, second levier du banc.
///
/// `display-resample` est le réglage historique (§avSync) : il resample l'audio
/// sur le refresh de l'écran. C'est le plus coûteux, et sur un VO qui peine il
/// peut à lui seul provoquer du framedrop — d'où le témoin `audio`, qui ne
/// coûte rien et, contrairement au rendu direct, **ne casse aucun sous-titre**.
/// À essayer AVANT d'accepter le prix de [VideoRenderMode.direct].
enum VideoSyncMode {
  displayResample(
    label: 'Écran',
    detail: 'display-resample — réglage historique',
    value: 'display-resample',
  ),
  audio(
    label: 'Audio',
    detail: 'video-sync=audio — le plus léger',
    value: 'audio',
  );

  const VideoSyncMode({
    required this.label,
    required this.detail,
    required this.value,
  });

  final String label;
  final String detail;
  final String value;
}

/// §video4kHdr — Troisième levier : le travail GPU imposé par le HDR.
///
/// ## Ce que la mesure a établi (box réelle, 2026-08-30)
///
/// | Chemin | Images perdues | Dérive A/V |
/// |---|---|---|
/// | `mediacodec-copy` (défaut) | 7,99/s | **0,000 s**, verrouillée |
/// | `hwdec=no` (logiciel) | 2,67/s | **+0,50 s par seconde** |
///
/// En matériel, toute la chaîne livre ses 24 img/s au vidéo-output et la
/// synchro reste à zéro : rien en amont n'est en peine, ce sont des images
/// **déjà prêtes** qui sont jetées à la présentation. En logiciel, le décodeur
/// s'effondre (vidéo à mi-vitesse) et s'il perd moins d'images, c'est
/// simplement qu'il en produit moins. **Le goulot est à l'étage de sortie
/// GPU**, et nulle part ailleurs.
///
/// Trois choses s'y passent : la remontée en texture (la copie),
/// le tone-mapping HDR→SDR, et la détection de pic lumineux
/// (`hdr-compute-peak`, un compute shader qui analyse **chaque image**).
/// [VideoRenderMode.direct] aurait supprimé les deux premières d'un coup —
/// il tue l'application en ~20 s sur cette box. Restent les deux autres, et
/// elles se coupent **sans perdre les sous-titres**.
///
/// ## L'indice qui vient de l'utilisateur
///
/// « ma télé est compatible HDR mais je ne vois pas l'image HDR se lancer en
/// bas à droite ». Le téléviseur ne bascule jamais en mode HDR : mpv reçoit
/// bien du HDR (`hdr` dans chaque relevé, bt.2020, 10 bits) mais **sort en
/// SDR**. Il tone-mappe donc chaque image, en 3840×2072, 24 fois par seconde.
/// [VideoHdrMode.passthrough] est la contre-épreuve : si le témoin HDR du
/// téléviseur s'allume, le tone-mapping a quitté le GPU.
enum VideoHdrMode {
  /// Défaut mpv : tone-mapping bt.2390 + détection de pic si le GPU expose des
  /// compute shaders.
  auto(
    label: 'Auto',
    detail: 'Défaut mpv — tone-mapping complet',
    properties: {},
  ),

  /// §hdrIsolate — La moitié BON MARCHÉ de l'ancien « Allégé ».
  ///
  /// C'est le mode à essayer en premier, et le seul candidat sérieux pour
  /// devenir un jour le défaut : couper la mesure du pic lumineux revient à
  /// utiliser une valeur statique au lieu d'une valeur mesurée image par
  /// image — un écart de rendu quasi invisible, alors que `tone-mapping=clip`
  /// écrête franchement les hautes lumières.
  ///
  /// L'essai du 2026-08-30 a prouvé que la PAIRE supprime 100 % des pertes
  /// (7,99 img/s → 0). Il n'a pas dit laquelle des deux fait le travail :
  /// c'est exactement ce que cette entrée sert à trancher.
  noPeak(
    label: 'Sans analyse',
    detail: 'hdr-compute-peak=no — quasi invisible',
    properties: {
      'hdr-compute-peak': 'no',
    },
  ),

  /// Les DEUX propriétés : la configuration mesurée le 2026-08-30, qui
  /// supprime toutes les pertes. Plus coûteuse visuellement que [noPeak].
  lightweight(
    label: 'Allégé',
    detail: 'Sans analyse + courbe simple — 0 perte mesurée',
    properties: {
      'hdr-compute-peak': 'no',
      'tone-mapping': 'clip',
    },
  ),

  /// Demande à envoyer le HDR tel quel à l'écran.
  ///
  /// ⛔ **Mesuré SANS effet le 2026-08-30** : 7,92 img/s perdues, soit
  /// exactement le témoin, et le téléviseur ne bascule pas. Le réglage seul ne
  /// suffit pas à faire sortir du HDR — la texture Flutter dans laquelle
  /// media_kit compose est en SDR, et seul `mediacodec_embed` (rendu direct
  /// dans la Surface) pourrait porter du HDR… mais il tue l'application.
  /// Conservé comme témoin négatif : il isole le coût dans l'analyse de pic
  /// plutôt que dans la signalisation colorimétrique.
  passthrough(
    label: 'Passthrough',
    detail: 'HDR envoyé tel quel à la TV',
    properties: {
      'target-colorspace-hint': 'yes',
    },
  );

  const VideoHdrMode({
    required this.label,
    required this.detail,
    required this.properties,
  });

  final String label;
  final String detail;

  /// Propriétés mpv à poser. Vide = on ne touche à rien.
  final Map<String, String> properties;
}

/// §engineVendor étape 4 — Quel moteur vidéo lit les flux.
///
/// ⚠️ **media_kit reste le DÉFAUT** tant que l'étape 5 n'a pas validé Media3
/// sur les deux matériels réels. Ce sélecteur est là pour comparer, pas encore
/// pour basculer.
///
/// ⚠️ Couvert par §benchGuard, comme les autres leviers du banc : si l'app
/// meurt pendant une lecture avec un moteur non standard, le démarrage suivant
/// revient d'office au défaut. Un moteur qui plante ne doit pas rendre l'app
/// inutilisable.
enum VideoEngineMode {
  /// §engineVendor étape 5 — **DÉFAUT depuis le 2026-09-01.**
  ///
  /// Bascule décidée par la mesure : sur DEUX matériels réels (téléviseur
  /// Philips et téléphone), Media3 n'a **aucun échec de décodage propre** et
  /// libmpv ne rattrape **rien**. Il apporte en plus le **HDR natif**, hors de
  /// portée de media_kit par construction (une texture Flutter impose le SDR).
  media3(
    label: 'Media3',
    detail: 'ExoPlayer sur SurfaceView — HDR natif · défaut',
  ),

  /// Conservé comme **repli** jusqu'à l'étape 6.
  ///
  /// ⚠️ C'est le moteur des réglages Rendu / Synchro / HDR du banc : ils sont
  /// tous des propriétés mpv et n'ont **aucun effet** sur Media3.
  mediaKit(
    label: 'media_kit',
    detail: 'libmpv — moteur historique, repli',
  );

  const VideoEngineMode({required this.label, required this.detail});

  final String label;
  final String detail;
}

/// §video4kBench — Mémorise les choix du banc d'essai d'une lecture à l'autre.
///
/// Persistant par nécessité : un diagnostic se fait sur plusieurs films
/// d'affilée, et sur TV il n'y a pas de logcat (§tvLogs) pour recouper.
///
/// ⚠️ Les deux réglages ne s'appliquent qu'à la **prochaine lecture** : `vo` et
/// `hwdec` sont figés à la construction du `VideoController`, et les changer en
/// pleine lecture forcerait une reconfiguration de la chaîne vidéo — soit
/// exactement l'effet « le film se relance » déjà payé par §tv4kScale.
abstract final class VideoRenderPreference {
  static const _modeKey = 'player_video_render_mode_v1';
  static const _syncKey = 'player_video_sync_mode_v1';
  static const _hdrKey = 'player_video_hdr_mode_v1';
  static const _engineKey = 'player_video_engine_v1';

  static VideoRenderMode _mode = VideoRenderMode.auto;
  static VideoSyncMode _sync = VideoSyncMode.displayResample;
  static VideoHdrMode _hdr = VideoHdrMode.auto;
  static VideoEngineMode _engine = VideoEngineMode.media3;

  static VideoRenderMode get mode => _mode;
  static VideoSyncMode get sync => _sync;
  static VideoHdrMode get hdr => _hdr;

  /// §engineVendor — Moteur retenu pour la PROCHAINE lecture.
  static VideoEngineMode get engine => _engine;

  /// Vrai dès qu'un réglage s'écarte du comportement historique — sert à
  /// signaler dans le journal qu'un relevé n'a PAS été fait en configuration
  /// d'origine (une mesure dont on a oublié le banc est une mesure perdue).
  static bool get isOverridden =>
      _mode != VideoRenderMode.auto ||
      _sync != VideoSyncMode.displayResample ||
      _hdr != VideoHdrMode.auto ||
      _engine != VideoEngineMode.media3;

  /// Configuration à passer au `VideoController`. `null` quand rien n'est
  /// surchargé → media_kit garde strictement son comportement par défaut.
  static VideoControllerConfiguration? get controllerConfiguration {
    if (_mode.vo == null && _mode.hwdec == null) return null;
    return VideoControllerConfiguration(vo: _mode.vo, hwdec: _mode.hwdec);
  }

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _mode = _byName(
          prefs.getString(_modeKey), VideoRenderMode.values, VideoRenderMode.auto);
      _sync = _byName(prefs.getString(_syncKey), VideoSyncMode.values,
          VideoSyncMode.displayResample);
      _hdr = _byName(
          prefs.getString(_hdrKey), VideoHdrMode.values, VideoHdrMode.auto);
      _engine = _byName(prefs.getString(_engineKey), VideoEngineMode.values,
          VideoEngineMode.media3);

      // §benchGuard — Drapeau encore levé ⇒ la session précédente est morte en
      // pleine lecture avec un réglage de diagnostic. On désarme AVANT de
      // rendre la main, sinon la même lecture retue l'app en boucle.
      if (prefs.getBool(_armedKey) == true) {
        debugPrint('💥 §benchGuard — plantage détecté avec un réglage de '
            'diagnostic actif (rendu=${_mode.name} sync=${_sync.name} '
            'hdr=${_hdr.name}) → retour à la configuration par défaut');
        reset();
        _persistBool(_armedKey, false);
        return;
      }

      if (isOverridden) {
        debugPrint('🔬 §video4kBench — moteur=${_engine.name} '
            'rendu=${_mode.name} sync=${_sync.name} hdr=${_hdr.name}');
      }
    } catch (e) {
      debugPrint('⚠️ §video4kBench — lecture impossible : $e');
    }
  }

  static void setMode(VideoRenderMode value) {
    if (value == _mode) return;
    _mode = value;
    _persist(_modeKey, value.name);
  }

  static void setSync(VideoSyncMode value) {
    if (value == _sync) return;
    _sync = value;
    _persist(_syncKey, value.name);
  }

  static void setEngine(VideoEngineMode value) {
    if (value == _engine) return;
    _engine = value;
    _persist(_engineKey, value.name);
  }

  static void setHdr(VideoHdrMode value) {
    if (value == _hdr) return;
    _hdr = value;
    _persist(_hdrKey, value.name);
  }

  /// Remet le banc au comportement d'origine.
  static void reset() {
    setMode(VideoRenderMode.auto);
    setSync(VideoSyncMode.displayResample);
    setHdr(VideoHdrMode.auto);
    setEngine(VideoEngineMode.media3);
  }

  // ── §benchGuard — Garde-fou anti-plantage ───────────────────────────────────
  //
  // ⚠️ Né d'un incident réel (2026-08-30) : `Rendu = Direct` a tué
  // l'application en ~20 s, et le réglage étant PERSISTANT, chaque lecture 4K
  // suivante replantait — au redémarrage, l'utilisateur n'a aucun moyen de
  // deviner qu'un réglage de diagnostic est en cause.
  //
  // Principe : on lève un drapeau juste avant une lecture faite avec un
  // réglage non standard, on le baisse quand le lecteur se ferme proprement.
  // Retrouver le drapeau levé au démarrage suivant signifie que l'app est morte
  // pendant cette lecture → on revient d'office à la configuration d'origine.
  //
  // ⚠️ Un faux positif est possible (l'utilisateur tue l'app à la main en
  // pleine lecture) et c'est ASSUMÉ : il retombe sur la configuration sûre,
  // jamais l'inverse. Un garde-fou qui se trompe doit se tromper du bon côté.
  static const _armedKey = 'player_video_bench_armed_v1';

  /// Appelé à l'ouverture d'un média. Sans surcharge active, ne coûte rien.
  static void armCrashGuard() {
    if (!isOverridden) return;
    _persistBool(_armedKey, true);
  }

  /// Appelé quand le lecteur se ferme normalement.
  static void disarmCrashGuard() => _persistBool(_armedKey, false);

  static void _persistBool(String key, bool value) {
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool(key, value))
        .catchError((e) {
      debugPrint('⚠️ §benchGuard — écriture impossible : $e');
      return false;
    });
  }


  static void _persist(String key, String value) {
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString(key, value))
        .catchError((e) {
      debugPrint('⚠️ §video4kBench — écriture impossible : $e');
      return false;
    });
  }

  /// Repli sur [fallback] si la valeur stockée ne correspond à rien de connu
  /// (réglage retiré d'une version à l'autre) — jamais d'exception au boot.
  static T _byName<T extends Enum>(String? name, List<T> values, T fallback) {
    if (name == null) return fallback;
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }
}
