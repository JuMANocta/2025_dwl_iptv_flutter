import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

/// §trailerInApp — Lecteur de bande-annonce YouTube **dans l'application**
/// (au lieu d'ouvrir l'app YouTube externe). S'appuie sur `youtube_player_iframe`
/// (lecteur YouTube officiel embarqué dans une WebView).
///
/// Important : ce lecteur est **totalement indépendant** du player principal
/// (`media_kit`) et de `WatchProgressService` → une bande-annonce n'est JAMAIS
/// ajoutée à l'historique / la reprise de l'utilisateur.
class TrailerPlayerPage extends StatefulWidget {
  /// Identifiant vidéo YouTube (le `key` TMDB, ex: `dQw4w9WgXcQ`).
  final String videoId;
  final String title;

  const TrailerPlayerPage({
    super.key,
    required this.videoId,
    required this.title,
  });

  @override
  State<TrailerPlayerPage> createState() => _TrailerPlayerPageState();
}

class _TrailerPlayerPageState extends State<TrailerPlayerPage> {
  late final YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        // Pas de vidéos liées "ailleurs" en fin de lecture (reste sur la chaîne).
        enableCaption: true,
      ),
    );
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return YoutubePlayerScaffold(
      controller: _controller,
      aspectRatio: 16 / 9,
      builder: (context, player) {
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
            title: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: Center(child: player),
        );
      },
    );
  }
}
