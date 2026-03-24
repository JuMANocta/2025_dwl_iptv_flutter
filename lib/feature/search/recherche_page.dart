import 'package:flutter/material.dart';
import 'package:aetherStream/feature/accounts/accounts_page.dart';
import 'package:aetherStream/feature/downloads/downloads_page.dart';
import 'package:aetherStream/feature/search/recherche_m3u.dart';
import 'package:aetherStream/data/services/stream_account_service.dart';
import 'package:aetherStream/data/services/playlist_service.dart';
import 'package:aetherStream/l10n/app_localizations.dart';

class RecherchePage extends StatefulWidget {
  /// Chemin de playlist pré-chargé par _LaunchDecider — évite un double appel à getOrDownloadPlaylist().
  final String? initialPlaylistPath;
  const RecherchePage({super.key, this.initialPlaylistPath});

  @override
  State<RecherchePage> createState() => _RecherchePageState();
}

class _RecherchePageState extends State<RecherchePage> {
  late Future<String> _playlistPathFuture;
  String? _currentAccountLabel;
  Key _rechercheM3UKey = UniqueKey();
  bool _initialPathConsumed = false;

  @override
  void initState() {
    super.initState();
    _loadPlaylistPath();
  }

  void _loadPlaylistPath({bool forceDownload = false}) {
    setState(() {
      if (forceDownload) {
        _playlistPathFuture = PlaylistService.downloadCurrentM3U();
      } else if (!_initialPathConsumed && widget.initialPlaylistPath != null) {
        _initialPathConsumed = true;
        _playlistPathFuture = Future.value(widget.initialPlaylistPath);
      } else {
        _playlistPathFuture = PlaylistService.getOrDownloadPlaylist();
      }

      _playlistPathFuture.then((_) {
        StreamAccountService.getCurrentAccount().then((acc) {
          if (mounted) setState(() => _currentAccountLabel = acc?.label);
        });
      }).catchError((_) {
        if (mounted) setState(() => _currentAccountLabel = "Erreur de connexion");
      });
    });
  }

  void _forceReload() {
    debugPrint("🔄 Forçage du rechargement de la playlist...");
    setState(() => _rechercheM3UKey = UniqueKey());
    _loadPlaylistPath(forceDownload: true);
  }

  Future<void> _openSettings() async {
    final dynamic result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AccountsPage()),
    );
    if (result == true) {
      setState(() {
        _rechercheM3UKey = UniqueKey();
        _loadPlaylistPath(forceDownload: false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentAccountLabel ?? l10n.searchPageDefaultTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: l10n.searchPageDownloadsTooltip,
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadsPage())),
          ),
          IconButton(
            tooltip: l10n.searchPageReloadTooltip,
            icon: const Icon(Icons.refresh),
            onPressed: _forceReload,
          ),
          IconButton(
            tooltip: l10n.searchPageAccountsTooltip,
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: FutureBuilder<String>(
        future: _playlistPathFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.broken_image_outlined, color: Colors.orange, size: 48),
                  const SizedBox(height: 16),
                  Text(l10n.searchPageLoadingError, style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _forceReload,
                    icon: const Icon(Icons.refresh),
                    label: Text(l10n.searchPageRetryButton),
                  ),
                ]),
              ),
            );
          }
          return RechercheM3U(key: _rechercheM3UKey, filePath: snapshot.data!);
        },
      ),
    );
  }
}
