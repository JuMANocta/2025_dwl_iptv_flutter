import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

// Énumération pour savoir si on lit un fichier local ou un flux réseau.
enum VideoSourceType { network, file }

class PlayerPage extends StatefulWidget {
  final String path; // "path" peut être une URL ou un chemin de fichier
  final String title;
  final VideoSourceType sourceType;

  const PlayerPage({
    super.key,
    required this.path,
    required this.title,
    this.sourceType = VideoSourceType.network, // Par défaut, on lit un flux réseau
  });

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late VideoPlayerController _controller;
  bool _isLoading = true;
  bool _hasError = false;
  bool _showControls = true;
  Timer? _controlsTimer;

  @override
  void initState() {
    super.initState();
    _setLandscape();
    _initializePlayer();
    _startControlsTimer();
  }

  void _initializePlayer() {
    // On initialise le contrôleur différemment selon la source
    if (widget.sourceType == VideoSourceType.network) {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.path));
    } else {
      _controller = VideoPlayerController.file(File(widget.path));
    }

    _controller
      ..initialize().then((_) {
        setState(() => _isLoading = false);
        _controller.play();
      }).catchError((error) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
        debugPrint("Erreur VideoPlayer: $error");
      });

    // On écoute les changements pour reconstruire l'UI (ex: la barre de progression)
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _controller.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls) {
        _startControlsTimer();
      }
    });
  }

  void _setLandscape() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);
  }

  void _setPortrait() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  @override
  void dispose() {
    _controller.dispose();
    _controlsTimer?.cancel();
    _setPortrait(); // On restaure le mode portrait en quittant la page
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: _isLoading
            ? _buildLoading()
            : _hasError
            ? _buildError()
            : _buildPlayerWithControls(),
      ),
    );
  }

  // --- Widgets de construction ---

  Widget _buildPlayerWithControls() {
    return GestureDetector(
      onTap: _toggleControls,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Le lecteur vidéo en arrière-plan
          AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: VideoPlayer(_controller),
          ),
          // Les contrôles superposés
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: _buildControlsOverlay(),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsOverlay() {
    return Stack(
      children: [
        // --- BOUTON DE RETOUR ---
        Positioned(
          top: 10,
          left: 10,
          child: SafeArea(
            child: BackButton(color: Colors.white, onPressed: () => Navigator.of(context).pop()),
          ),
        ),
        // --- BOUTON PLAY/PAUSE CENTRAL ---
        Center(
          child: IconButton(
            icon: Icon(
              _controller.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
              color: Colors.white.withOpacity(0.8),
              size: 64,
            ),
            onPressed: () {
              setState(() => _controller.value.isPlaying ? _controller.pause() : _controller.play());
              _startControlsTimer();
            },
          ),
        ),
        // --- BARRE DE PROGRESSION ET TEMPS (en bas) ---
        Positioned(
          bottom: 10,
          left: 20,
          right: 20,
          child: SafeArea(
            child: Row(
              children: [
                Text(
                  _formatDuration(_controller.value.position),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                Expanded(
                  child: VideoProgressIndicator(
                    _controller,
                    allowScrubbing: true, // Permet de se déplacer dans la vidéo
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    colors: const VideoProgressColors(
                      playedColor: Colors.greenAccent,
                      bufferedColor: Colors.grey,
                      backgroundColor: Colors.black45,
                    ),
                  ),
                ),
                Text(
                  _formatDuration(_controller.value.duration),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoading() => const Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(color: Colors.white), SizedBox(height: 16), Text("Chargement...", style: TextStyle(color: Colors.white))]);

  Widget _buildError() => const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.error_outline, color: Colors.red, size: 48), SizedBox(height: 16), Text("Impossible de lire ce média.", style: TextStyle(color: Colors.white))]);

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final hours = duration.inHours;
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return hours > 0 ? "$hours:$minutes:$seconds" : "$minutes:$seconds";
  }
}
