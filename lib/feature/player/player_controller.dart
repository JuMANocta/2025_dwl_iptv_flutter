import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/utils/platform_tv.dart';

/// Wrapper media_kit — gère le cycle de vie du Player et du VideoController.
///
/// **Audio boost** : `volume-max=200` permet de pousser `setVolume()` jusqu'à
/// 200 (au lieu du max natif 100). On initialise à 130% pour compenser les flux
/// IPTV souvent encodés à faible niveau. `audio-pitch-correction=yes` conserve
/// la tonalité de la voix en cas de changement de vitesse.
///
/// **A/V sync** : libmpv resync l'audio sur la vidéo par défaut. On force
/// `video-sync=display-resample` (resample audio pour caler sur le refresh
/// de l'écran) qui donne le meilleur résultat sur Android et Windows. `cache-pause=no`
/// évite que mpv mette en pause sur de petits creux de buffer, ce qui
/// désynchronise les dialogues sur les flux HLS un peu instables.
class AetherPlayerController {
  /// Volume initial poussé à 130% (mobile) pour compenser les flux IPTV
  /// faiblement encodés. Sur Android TV / Fire TV, le boost natif des
  /// téléviseurs est déjà important → on démarre à 125%.
  /// L'utilisateur peut monter jusqu'à 200% via le swipe vertical.
  static double get initialVolume => PlatformTv.isTv ? 125.0 : 130.0;
  static const double maxVolume = 200.0;

  late final Player player;
  late final VideoController videoController;

  /// §replayBuffer — Vrai pour le timeshift (replay). Les panels servent le
  /// timeshift en segments HLS longs (souvent 30-60 s), parfois bridés à
  /// vitesse réelle : à chaque frontière de segment le buffer se vide →
  /// saccades périodiques (~toutes les 30 s) avec les réglages "live".
  /// Ce flag applique un profil mpv adapté au différé (voir [_applyAudioTuning]).
  final bool timeshift;

  AetherPlayerController({this.timeshift = false}) {
    player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 64 * 1024 * 1024, // 64 Mo : marge anti-désync sur HLS instable
        logLevel: MPVLogLevel.warn,
      ),
    );
    videoController = VideoController(player);
    _applyTuning();
    // Boost initial : appliqué après que mpv ait pris la propriété volume-max.
    player.setVolume(initialVolume);
  }

  /// Configure mpv pour un volume amplifiable, une meilleure synchro A/V
  /// et l'accélération matérielle sur Windows.
  Future<void> _applyTuning() async {
    try {
      if (player.platform is! NativePlayer) return;
      final np = player.platform as NativePlayer;

      // ── Audio & Sync ──────────────────────────────────────────────────────
      // Boost volume jusqu'à 200% (au-dessus de 100% = amplification logicielle).
      await np.setProperty('volume-max', '200');
      // Préserve la hauteur des voix quand on accélère/ralentit la lecture.
      await np.setProperty('audio-pitch-correction', 'yes');
      // Resample audio sur le refresh de l'écran → suppression des micro-décalages
      // qui font "claquer" les dialogues sur les flux 50fps européens.
      await np.setProperty('video-sync', 'display-resample');
      // Latence audio plus serrée → meilleure synchro lèvres.
      await np.setProperty('audio-buffer', '0.2');

      // ── Windows Specific ──────────────────────────────────────────────────
      if (Platform.isWindows) {
        // Accélération matérielle (D3D11VA / DXVA2).
        await np.setProperty('hwdec', 'auto-safe');
        // On ne définit PAS 'vo' ni 'gpu-api' ici pour que media_kit_video
        // puisse intégrer la texture directement dans le widget Flutter.
      }

      // Évite un seek subtil au démarrage de certains MKV qui désync 200-500 ms
      // dès la première lecture (probe du start time → dérive PTS).
      await np.setProperty('demuxer-mkv-probe-start-time', 'no');
      // Force la correction des PTS aberrants côté demuxer (au lieu d'attendre
      // que le décodeur s'en aperçoive et lag).
      await np.setProperty('correct-pts', 'yes');

      // §playerBackBuffer — `PlayerConfiguration.bufferSize` (64 Mo) est appliqué
      // par media_kit aux DEUX sens : `demuxer-max-bytes` ET
      // `demuxer-max-back-bytes` (media_kit real.dart:2425-2426). Soit 128 Mo de
      // demuxer, dont 64 Mo de données DÉJÀ LUES — qui ne servent qu'à reculer
      // sans retélécharger. Ce buffer arrière se remplit au fil de la lecture :
      // sur une box TV, c'est autant de RAM qui disparaît pendant un long film,
      // en plus de la playlist en mémoire et du cache d'images.
      // On garde la marge AVANT (anti-désync sur HLS instable) et on ramène
      // l'arrière à 16 Mo : largement de quoi absorber un retour en arrière.
      await np.setProperty('demuxer-max-back-bytes', '${16 * 1024 * 1024}');

      if (timeshift) {
        // §replayBuffer — Profil TIMESHIFT : le différé n'a aucune contrainte
        // de latence, on privilégie la fluidité aux frontières de segments.
        // 1. Hacks basse-latence INUTILES en différé (forçaient des resyncs
        //    agressifs à chaque discontinuité de PTS entre segments).
        await np.setProperty('video-latency-hacks', 'no');
        // 2. Au creux de buffer : vraie pause de re-buffering ~2 s plutôt que
        //    des saccades de lecture (le "ça relance toutes les 30 s").
        await np.setProperty('cache-pause', 'yes');
        await np.setProperty('cache-pause-wait', '2');
        // 3. Précharge large au-delà de la frontière du segment courant —
        //    si le serveur ne bride pas le débit, plus aucun creux visible.
        await np.setProperty('demuxer-readahead-secs', '60');
      } else {
        // Profil LIVE / VOD (§audio + §avSync, inchangé).
        // Ne pas mettre en pause sur un creux de buffer (HLS instable).
        await np.setProperty('cache-pause', 'no');
        // §avSync — Sync agressive sur streams instables : autorise mpv à
        // "tricher" sur les PTS pour rester collé à l'audio (drop frames vidéo
        // ou rate-resample audio plutôt que de laisser dériver). Indispensable
        // sur les flux IPTV qui ont parfois des PTS dégueulasses (encodeurs
        // bidons des panels).
        await np.setProperty('video-latency-hacks', 'yes');
      }
    } catch (e) {
      debugPrint('⚠️ AetherPlayerController: tuning échoué — $e');
    }
  }

  // §tv4kScale RETIRÉ (2026-06-30) — l'ancien downscale `vf=scale=<W>:-2` était
  // un FIX FANTÔME : le build libmpv embarqué par media_kit sur Android n'inclut
  // PAS le filtre libavfilter `scale` → mpv rejette l'option (« Option vf: scale
  // doesn't exist »). Pire, ce `vf` invalide forçait une reconfiguration de la
  // chaîne vidéo en pleine lecture = l'effet « le film se relance » sur TV. Le
  // cap résolution n'a donc jamais marché. La vraie piste 4K/zoom reste hwdec /
  // upgrade media_kit_video v2 (roadmap §tv4kTexture).

  /// Ouvre un flux réseau (live, VOD, timeshift).
  /// Bypass SSL pour les providers IPTV sans certificat valide.
  /// §resumeStart — [start] = position de reprise : passée à `Media(start:)`
  /// (= option mpv `--start=`) → mpv démarre le décodage à cette position
  /// NATIVEMENT. Bien plus fiable que `seek()` après l'open (qui, surtout
  /// depuis media_kit v2, était parfois avalé pendant le buffering initial →
  /// la lecture repartait à 0).
  Future<void> open(String url,
      {Duration? start, String? audioLang, String? subLang}) async {
    try {
      if (player.platform is NativePlayer) {
        final np = player.platform as NativePlayer;
        await np.setProperty('tls-verify', 'no');
        await np.setProperty('insecure', 'yes');
        await _applyLangPrefs(np, audioLang, subLang);
      }
    } catch (_) {}
    await player.open(Media(url, start: start), play: true);
  }

  /// Ouvre un fichier local. [start] = position de reprise (cf. [open]).
  Future<void> openFile(String path,
      {Duration? start, String? audioLang, String? subLang}) async {
    try {
      if (player.platform is NativePlayer) {
        final np = player.platform as NativePlayer;
        await _applyLangPrefs(np, audioLang, subLang);
      }
    } catch (_) {}
    await player.open(Media('file://$path', start: start), play: true);
  }

  /// §trackLangPref — Préférence de langue audio/sous-titre posée AVANT l'open
  /// via les options mpv `alang`/`slang`/`sid` : mpv sélectionne la bonne piste
  /// **au chargement**, donc **aucun switch mid-stream** (qui re-demuxait le flux
  /// ~3 s après le démarrage = l'effet « le film se relance »). [audioLang] /
  /// [subLang] = code langue (ex. `fre`) ou null = laisser mpv choisir ;
  /// `subLang == 'no'` = sous-titres désactivés.
  Future<void> _applyLangPrefs(
      NativePlayer np, String? audioLang, String? subLang) async {
    if (audioLang != null && audioLang.isNotEmpty) {
      await np.setProperty('alang', audioLang);
    }
    if (subLang == 'no') {
      await np.setProperty('sid', 'no');
    } else if (subLang != null && subLang.isNotEmpty) {
      await np.setProperty('slang', subLang);
    }
  }

  void dispose() => player.dispose();
}
