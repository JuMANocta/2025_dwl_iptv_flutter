import 'dart:io';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:aetherStream/l10n/app_localizations.dart';

enum VideoSourceType { network, file, networkWithCache }

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
  CachedVideoPlayerPlus? _cachedVideoPlayerPlus;
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  bool _hasError = false;
  late String _errorMessage;

  @override
  void initState() {
    super.initState();
    // Force le paysage pendant la lecture.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    initializePlayer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _errorMessage = AppLocalizations.of(context)!.playerGenericError;
  }

  Future<void> initializePlayer() async {
    try {
      switch (widget.sourceType) {
        case VideoSourceType.network:
          _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(widget.path));
          break;
        case VideoSourceType.file:
          _videoPlayerController = VideoPlayerController.file(File(widget.path));
          break;
        case VideoSourceType.networkWithCache:
          _cachedVideoPlayerPlus = CachedVideoPlayerPlus.networkUrl(Uri.parse(widget.path));
          await _cachedVideoPlayerPlus!.initialize();
          _videoPlayerController = _cachedVideoPlayerPlus!.controller;
          break;
      }

      if (widget.sourceType != VideoSourceType.networkWithCache) {
        await _videoPlayerController!.initialize();
      }

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
        fullScreenByDefault: true,
        customControls: const CupertinoControls(
          backgroundColor: Color.fromRGBO(41, 41, 41, 0.7),
          iconColor: Colors.white,
        ),
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = false;
        });
      }
    } catch (error) {
      debugPrint("Erreur Chewie/VideoPlayer: $error");
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = l10n.playerLoadingError(error.toString());
        });
      }
    }
  }

  @override
  void dispose() {
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    _cachedVideoPlayerPlus?.dispose();
    // Restaure l'orientation par défaut (portrait) en quittant le player.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: const [],
      ),
      body: Center(
        child:
            _isLoading
            ? _buildLoading(l10n)
            : _hasError
            ? _buildError()
            : Chewie(controller: _chewieController!),
      ),
    );
  }

  Widget _buildLoading(AppLocalizations l10n) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const CircularProgressIndicator(color: Colors.white),
      const SizedBox(height: 16),
      Text(l10n.playerLoading, style: const TextStyle(color: Colors.white))
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
