import 'dart:io';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

// L'enum reste la même, c'est parfait pour la compatibilité
enum VideoSourceType { network, file }

class PlayerPage extends StatefulWidget {
  final String path;
  final String title;
  final VideoSourceType sourceType;

  const PlayerPage({
    super.key,
    required this.path,
    required this.title,
    this.sourceType = VideoSourceType.network,
  });

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = "Impossible de lire ce média.";

  @override
  void initState() {
    super.initState();
    initializePlayer();
  }

  Future<void> initializePlayer() async {
    try {
      // 1. Initialiser le contrôleur video_player
      if (widget.sourceType == VideoSourceType.network) {
        _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(widget.path));
      } else {
        _videoPlayerController = VideoPlayerController.file(File(widget.path));
      }

      await _videoPlayerController.initialize();

      // 2. Créer le ChewieController avec toutes les options
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        autoPlay: true,
        looping: false,

        // --- OPTIONS D'INTERFACE COMPLETES ---
        aspectRatio: _videoPlayerController.value.aspectRatio,
        showControls: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: Colors.greenAccent,
          handleColor: Colors.greenAccent,
          bufferedColor: Colors.grey,
          backgroundColor: Colors.black45,
        ),
        placeholder: const Center(child: CircularProgressIndicator()),
        autoInitialize: true,

        // --- GESTION DU PLEIN ÉCRAN ---
        allowedScreenSleep: false, // Empêche l'écran de se mettre en veille
        allowFullScreen: true,
        fullScreenByDefault: true, // Passe en plein écran au démarrage

        // Permet d'ajouter des boutons personnalisés !
        customControls: const CupertinoControls(
          backgroundColor: Color.fromRGBO(41, 41, 41, 0.7),
          iconColor: Colors.white,
        ),
      );

      setState(() {
        _isLoading = false;
        _hasError = false;
      });
    } catch (error) {
      // Gérer les erreurs (URL invalide, fichier corrompu, etc.)
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = "Erreur de chargement: ${error.toString()}";
      });
      debugPrint("Erreur Chewie/VideoPlayer: $error");
    }
  }

  @override
  void dispose() {
    // Très important de bien tout libérer
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: _isLoading
            ? _buildLoading()
            : _hasError
            ? _buildError()
            : Chewie(controller: _chewieController!),
      ),
    );
  }

  Widget _buildLoading() => const Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      CircularProgressIndicator(color: Colors.white),
      SizedBox(height: 16),
      Text("Initialisation du lecteur...", style: TextStyle(color: Colors.white))
    ],
  );

  Widget _buildError() => Padding(
    padding: const EdgeInsets.all(24.0),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, color: Colors.red, size: 48),
        const SizedBox(height: 16),
        Text(_errorMessage, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
      ],
    ),
  );
}

