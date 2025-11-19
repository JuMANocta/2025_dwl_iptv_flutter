import 'dart:io';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import '../../main.dart';
import '../downloads/logic/download_initiator.dart';

enum VideoSourceType {
  network,
  file,
  networkWithCache
}

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
  // On a besoin d'une référence à l'objet CachedVideoPlayerPlus quand on est en mode cache
  CachedVideoPlayerPlus? _cachedVideoPlayerPlus;
  // ET on a toujours besoin de la référence au contrôleur pour Chewie
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = "Impossible de lire ce média.";
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    initializePlayer();
  }


  // Une méthode de nettoyage centralisée
  void _cleanUpControllers() {
    // Si déjà libéré, on ne fait rien pour éviter l'erreur.
    if (_isDisposed) return;

    _chewieController?.pause();
    _chewieController?.dispose();
    _cachedVideoPlayerPlus?.dispose();

    _isDisposed = true; // On marque comme libéré.
  }

  Future<void> initializePlayer() async {
    try {
      // --- LOGIQUE D'INITIALISATION AMÉLIORÉE ---
      switch (widget.sourceType) {
        case VideoSourceType.network:
          _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(widget.path));
          await _videoPlayerController!.initialize();
          break;
        case VideoSourceType.file:
          _videoPlayerController = VideoPlayerController.file(File(widget.path));
          await _videoPlayerController!.initialize();
          break;
      case VideoSourceType.networkWithCache:
      // 1. On crée l'objet principal
      _cachedVideoPlayerPlus = CachedVideoPlayerPlus.networkUrl(Uri.parse(widget.path), invalidateCacheIfOlderThan: const Duration(minutes: 69),);      ;
      await _cachedVideoPlayerPlus!.initialize();
      _videoPlayerController = _cachedVideoPlayerPlus!.controller;
      break;
      }

      // Le reste de la création du ChewieController ne change pas,
      // car Chewie s'attend juste à recevoir un `VideoPlayerController`.
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: false,
        aspectRatio: _videoPlayerController!.value.aspectRatio,
        materialProgressColors: ChewieProgressColors(
          playedColor: Colors.greenAccent,
          handleColor: Colors.greenAccent,
          bufferedColor: Colors.grey,
          backgroundColor: Colors.black45,
        ),
        placeholder: const Center(child: CircularProgressIndicator()),
        autoInitialize: true,
        allowedScreenSleep: false,
        allowFullScreen: true,
        customControls: const CupertinoControls(
          backgroundColor: Color.fromRGBO(41, 41, 41, 0.7),
          iconColor: Colors.white,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) {
        _chewieController?.enterFullScreen();
      }

      setState(() {
        _isLoading = false;
        _hasError = false;
      });
    } catch (error) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = "Erreur de chargement: ${error.toString()}";
      });
      debugPrint("Erreur Chewie/VideoPlayer: $error");
    }
  }

  Future<void> _promoteCacheToDownload() async {
    // On vérifie que le lecteur cache est bien actif
    if (_cachedVideoPlayerPlus == null) {
      debugPrint("Cette vidéo n'est pas mise en cache.");
      return;
    }

    // flutter_cache_manager ne fournit pas de méthode directe pour obtenir le fichier.
    // PLAN B - Plus simple et tout aussi efficace :
    // On relance simplement la fonction de téléchargement. Si le fichier est déjà

    debugPrint("Lancement de la sauvegarde en arrière-plan...");

    final rootContext = navigatorKey.currentContext;
    if (rootContext == null || !rootContext.mounted) {
      debugPrint("Erreur critique : Impossible d'obtenir le contexte global pour le téléchargement.");
      return;
    }

    // On appelle la fonction de téléchargement classique.
    // Elle s'occupera de tout (vérification, dialogue, etc.)
    verifierEtTelecharger(
      url: widget.path, // On utilise l'URL originale
      nom: widget.title,
      context: rootContext,
    );
  }

  @override
  void dispose() {
    _cleanUpControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      // onPopInvoked est remplacé par onPopInvokedWithResult
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        // Le reste de la logique est identique.
        if (didPop) return;

        // 1. On libère les ressources du lecteur.
        _cleanUpControllers();

        // 2. On attend un court instant.
        await Future.delayed(const Duration(milliseconds: 50));

        // 3. On ferme manuellement la page.
        if (mounted) {
          // La méthode pop() de base ne retourne pas de résultat, donc c'est parfait.
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(widget.title, style: const TextStyle(fontSize: 16)),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          actions: [
            // Le bouton apparaît systématiquement pour les flux réseau
            if (widget.sourceType == VideoSourceType.networkWithCache)
              IconButton(
                icon: const Icon(Icons.save_alt_outlined),
                tooltip: 'Sauvegarder cette vidéo',
                onPressed: _promoteCacheToDownload,
              ),
          ],
        ),
        body: Center(
          child: _isLoading
              ? _buildLoading()
              : _hasError
              ? _buildError()
              : Chewie(controller: _chewieController!),
        ),
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
