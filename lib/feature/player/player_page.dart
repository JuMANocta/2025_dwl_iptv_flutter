import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'player_controller.dart';
import 'widgets/player_controls.dart';
import 'widgets/player_gestures.dart';
import 'widgets/player_replay_bar.dart';

enum VideoSourceType {
  network,       // live / VOD réseau (et timeshift simple)
  networkReplay, // timeshift avec barre replay + bouton "Retour au direct"
  file,          // fichier local
  // networkWithCache supprimé : media_kit gère le cache nativement
}

/// Badge affiché en haut à droite du player.
enum PlayerBadgeType {
  none,    // aucun badge (fichier local…)
  live,    // ● DIRECT rouge (flux TV en direct)
  replay,  // ↩ REPLAY violet (timeshift)
  movie,   // FILM bleu
  series,  // SÉRIE violet
}

class PlayerPage extends StatefulWidget {
  final String path;
  final String title;
  final VideoSourceType sourceType;
  /// Badge affiché en haut à droite.
  final PlayerBadgeType badgeType;
  /// Heure de début du replay — alimente la barre replay (optionnel).
  final DateTime? replayStart;
  /// Durée totale du replay — alimente la barre replay (optionnel).
  final Duration? replayDuration;
  const PlayerPage({
    super.key,
    required this.path,
    required this.title,
    this.sourceType = VideoSourceType.network,
    this.badgeType = PlayerBadgeType.none,
    this.replayStart,
    this.replayDuration,
  });

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final AetherPlayerController _ctrl;

  bool _controlsVisible = true;
  Timer? _hideTimer;

  bool _hasError = false;
  String _errorMessage = '';
  int _retryCount = 0;
  static const _maxRetries = 3;
  // Chemin courant utilisé pour le retry (peut alterner .m3u8 ↔ .ts).
  late String _currentPath;

  // Luminosité courante (0.0–1.0), initialisée à 0.5 par défaut.
  double _brightness = 0.5;
  // Volume courant (0.0–100.0).
  double _volume = 100.0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _currentPath = widget.path;
    _ctrl = AetherPlayerController();
    _listenErrors();
    _openMedia();
    _startHideTimer();
    _initBrightness();
  }

  Future<void> _initBrightness() async {
    try {
      _brightness = await ScreenBrightness().current;
    } catch (_) {}
  }

  Future<void> _openMedia() async {
    try {
      if (widget.sourceType == VideoSourceType.file) {
        await _ctrl.openFile(_currentPath);
      } else {
        await _ctrl.open(_currentPath);
      }
    } catch (e) {
      _handleError(e.toString());
    }
  }

  /// Retourne l'URL avec l'extension alternative (.m3u8 ↔ .ts), ou null si non applicable.
  String? _altExtUrl(String url) {
    if (url.contains('.m3u8')) return url.replaceFirst(RegExp(r'\.m3u8$'), '.ts');
    if (url.contains('.ts')) return url.replaceFirst(RegExp(r'\.ts$'), '.m3u8');
    return null;
  }

  void _listenErrors() {
    _ctrl.player.stream.error.listen((error) {
      if (error.isNotEmpty && mounted) {
        _handleError(error);
      }
    });
  }

  /// Reconnexion automatique (×3, délai 5s).
  /// Retry 1 : même URL (serveur pas encore prêt).
  /// Retry 2 : extension alternative (.m3u8 ↔ .ts) — certains serveurs ne supportent qu'un format.
  /// Retry 3 : retour à l'URL originale.
  void _handleError(String error) {
    if (_retryCount < _maxRetries) {
      _retryCount++;
      // Retry 2 : tente l'extension alternative
      if (_retryCount == 2) {
        final alt = _altExtUrl(widget.path);
        if (alt != null) {
          _currentPath = alt;
          debugPrint('⚠️ PlayerPage: retry $_retryCount/$_maxRetries — extension alternative: $alt');
        }
      } else {
        _currentPath = widget.path; // retour à l'URL originale
      }
      debugPrint(
          '⚠️ PlayerPage: erreur stream — retry $_retryCount/$_maxRetries dans 5s\n$error');
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) _openMedia();
      });
    } else {
      debugPrint('❌ PlayerPage: échec définitif après $_maxRetries tentatives\n$error');
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = error;
        });
      }
    }
  }

  void _showControls() {
    if (!mounted) return;
    setState(() => _controlsVisible = true);
    _startHideTimer();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _handleSeek(Duration delta) {
    final pos = _ctrl.player.state.position + delta;
    _ctrl.player.seek(pos.isNegative ? Duration.zero : pos);
    _showControls();
  }

  void _handleVolumeChange(double delta) {
    _volume = (_volume + delta).clamp(0.0, 100.0);
    _ctrl.player.setVolume(_volume);
  }

  void _handleBrightnessChange(double delta) {
    _brightness = (_brightness + delta).clamp(0.0, 1.0);
    // fire-and-forget : dispose() restore de toute façon la luminosité d'origine.
    ScreenBrightness().setScreenBrightness(_brightness).catchError((_) {});
  }

  void _retry() {
    setState(() {
      _hasError = false;
      _retryCount = 0;
      _currentPath = widget.path;
    });
    _openMedia();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _ctrl.dispose();
    ScreenBrightness().resetScreenBrightness().catchError((_) {});
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) return _buildErrorScreen();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Rendu vidéo plein écran.
          Video(controller: _ctrl.videoController),

          // 2. Couche gesture (transparente, capte tout sauf les contrôles).
          PlayerGestures(
            player: _ctrl.player,
            onTap: _showControls,
            onSeek: _handleSeek,
            onVolumeChange: _handleVolumeChange,
            onBrightnessChange: _handleBrightnessChange,
          ),

          // 3. Overlay contrôles.
          PlayerControls(
            player: _ctrl.player,
            title: widget.title,
            visible: _controlsVisible,
            badgeType: widget.badgeType,
            onBack: () => Navigator.of(context).pop(),
            onInteraction: _showControls,
          ),

          // 4. Barre replay (uniquement en mode networkReplay).
          if (widget.sourceType == VideoSourceType.networkReplay)
            Positioned(
              left: 16,
              right: 16,
              bottom: 90,
              child: PlayerReplayBar(
                player: _ctrl.player,
                replayStart: widget.replayStart,
                replayDuration: widget.replayDuration,
                visible: _controlsVisible,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 56),
              const SizedBox(height: 16),
              Text(
                _errorMessage,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Réessayer'),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Quitter',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
