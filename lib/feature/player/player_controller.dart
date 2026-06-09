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
/// de l'écran) qui donne le meilleur résultat sur Android. `cache-pause=no`
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

  AetherPlayerController() {
    player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 64 * 1024 * 1024, // 64 Mo : marge anti-désync sur HLS instable
        logLevel: MPVLogLevel.warn,
      ),
    );
    videoController = VideoController(player);
    _applyAudioTuning();
    // Boost initial : appliqué après que mpv ait pris la propriété volume-max.
    player.setVolume(initialVolume);
  }

  /// Configure mpv pour un volume amplifiable et une meilleure synchro A/V.
  /// Best-effort : on ignore les erreurs (build natif sans accès aux property).
  Future<void> _applyAudioTuning() async {
    try {
      if (player.platform is! NativePlayer) return;
      final np = player.platform as NativePlayer;
      // Boost volume jusqu'à 200% (au-dessus de 100% = amplification logicielle).
      await np.setProperty('volume-max', '200');
      // Préserve la hauteur des voix quand on accélère/ralentit la lecture.
      await np.setProperty('audio-pitch-correction', 'yes');
      // Resample audio sur le refresh de l'écran → suppression des micro-décalages
      // qui font "claquer" les dialogues sur les flux 50fps européens.
      await np.setProperty('video-sync', 'display-resample');
      // Ne pas mettre en pause sur un creux de buffer (HLS instable).
      await np.setProperty('cache-pause', 'no');
      // Latence audio plus serrée → meilleure synchro lèvres.
      await np.setProperty('audio-buffer', '0.2');
      // §avSync — Sync agressive sur streams instables : autorise mpv à
      // "tricher" sur les PTS pour rester collé à l'audio (drop frames vidéo
      // ou rate-resample audio plutôt que de laisser dériver). Indispensable
      // sur les flux IPTV qui ont parfois des PTS dégueulasses (encodeurs
      // bidons des panels).
      await np.setProperty('video-latency-hacks', 'yes');
      // Évite un seek subtil au démarrage de certains MKV qui désync 200-500 ms
      // dès la première lecture (probe du start time → dérive PTS).
      await np.setProperty('demuxer-mkv-probe-start-time', 'no');
      // Force la correction des PTS aberrants côté demuxer (au lieu d'attendre
      // que le décodeur s'en aperçoive et lag).
      await np.setProperty('correct-pts', 'yes');
    } catch (e) {
      debugPrint('⚠️ AetherPlayerController: audio tuning échoué — $e');
    }
  }

  /// Ouvre un flux réseau (live, VOD, timeshift).
  /// Bypass SSL pour les providers IPTV sans certificat valide.
  Future<void> open(String url) async {
    try {
      if (player.platform is NativePlayer) {
        await (player.platform as NativePlayer).setProperty('tls-verify', 'no');
        await (player.platform as NativePlayer).setProperty('insecure', 'yes');
      }
    } catch (_) {}
    await player.open(Media(url), play: true);
  }

  /// Ouvre un fichier local.
  Future<void> openFile(String path) async {
    await player.open(Media('file://$path'), play: true);
  }

  void dispose() => player.dispose();
}
