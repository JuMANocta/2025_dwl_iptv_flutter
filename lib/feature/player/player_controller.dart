import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Wrapper media_kit — gère le cycle de vie du Player et du VideoController.
class AetherPlayerController {
  late final Player player;
  late final VideoController videoController;

  AetherPlayerController() {
    player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 32 * 1024 * 1024, // 32 Mo de buffer réseau
        logLevel: MPVLogLevel.warn,
      ),
    );
    videoController = VideoController(player);
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
