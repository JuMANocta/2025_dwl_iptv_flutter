import 'package:flutter/material.dart';
import 'package:aetherStream/feature/accounts/accounts_page.dart';
import 'package:aetherStream/feature/downloads/downloads_page.dart';
import 'package:aetherStream/feature/search/recherche_m3u.dart';
import 'package:aetherStream/data/services/stream_account_service.dart';
import 'package:aetherStream/data/services/playlist_service.dart';
import 'package:aetherStream/data/services/parsed_playlist_service.dart';
import 'package:aetherStream/l10n/app_localizations.dart';

class RecherchePage extends StatefulWidget {
  /// Données pré-chargées par _LaunchDecider — évite un double appel réseau.
  final ({String path, String accountId, String accountName})? initialData;
  const RecherchePage({super.key, this.initialData});

  @override
  State<RecherchePage> createState() => _RecherchePageState();
}

class _RecherchePageState extends State<RecherchePage> {
  late Future<({String path, String accountId, String accountName})> _dataFuture;
  String? _currentAccountLabel;
  Key _rechercheM3UKey = UniqueKey();
  bool _initialDataConsumed = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData({bool forceDownload = false}) {
    setState(() {
      if (forceDownload) {
        _dataFuture = _fetchData(forceDownload: true);
      } else if (!_initialDataConsumed && widget.initialData != null) {
        _initialDataConsumed = true;
        _dataFuture = Future.value(widget.initialData!);
      } else {
        _dataFuture = _fetchData();
      }

      _dataFuture.then((d) {
        if (mounted) setState(() => _currentAccountLabel = d.accountName);
      }).catchError((_) {
        if (mounted) setState(() => _currentAccountLabel = "Erreur de connexion");
      });
    });
  }

  /// Charge le chemin + les infos du compte actif en parallèle.
  Future<({String path, String accountId, String accountName})> _fetchData({bool forceDownload = false}) async {
    final path = forceDownload
        ? await PlaylistService.downloadCurrentM3U()
        : await PlaylistService.getOrDownloadPlaylist();
    final acc = await StreamAccountService.getCurrentAccount();
    return (
      path: path,
      accountId: acc?.id ?? '',
      accountName: acc?.label ?? '',
    );
  }

  void _forceReload() {
    debugPrint("🔄 Forçage du rechargement de la playlist...");
    setState(() => _rechercheM3UKey = UniqueKey());
    _loadData(forceDownload: true);
  }

  Future<void> _openSettings() async {
    final dynamic result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AccountsPage()),
    );
    if (result == true) {
      // Vider le cache mémoire du compte actif pour forcer le rechargement
      final acc = await StreamAccountService.getCurrentAccount();
      if (acc != null) ParsedPlaylistService.invalidate(acc.id);
      setState(() {
        _rechercheM3UKey = UniqueKey();
        _loadData(forceDownload: false);
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
      body: FutureBuilder<({String path, String accountId, String accountName})>(
        future: _dataFuture,
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
          final d = snapshot.data!;
          return RechercheM3U(
            key: _rechercheM3UKey,
            accountId:   d.accountId,
            accountName: d.accountName,
            m3uPath:     d.path,
          );
        },
      ),
    );
  }
}
