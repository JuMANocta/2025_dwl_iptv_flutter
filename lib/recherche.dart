import 'dart:io';
import 'package:flutter/material.dart';
import 'screens/settings/accounts_screen.dart';
import 'services/playlist_service.dart';
import 'services/iptv_account_service.dart';
import 'telechargement_fichier.dart' show verifierEtTelecharger;

/// Représentation minimale d’une entrée M3U.
class M3uItem {
  final String name;
  final String url;
  M3uItem({required this.name, required this.url});
}

class RecherchePage extends StatefulWidget {
  const RecherchePage({super.key});

  @override
  State<RecherchePage> createState() => _RecherchePageState();
}

class _RecherchePageState extends State<RecherchePage> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = false;
  String? _currentAccountLabel;

  List<M3uItem> _all = [];
  List<M3uItem> _filtered = [];

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  // --- LOGIQUE DE CHARGEMENT CORRIGÉE ---

  /// Chargement initial : utilise le cache.
  Future<void> _initAndLoad() async {
    setState(() => _loading = true);

    try {
      final acc = await IptvAccountService.getCurrentAccount();
      setState(() => _currentAccountLabel = acc?.label);

      // 👇 CORRECTION PRINCIPALE : On utilise la fonction intelligente ici !
      final path = await PlaylistService.getOrDownloadPlaylist();
      final parsed = await _parseM3uFile(path);

      if (!mounted) return;
      setState(() {
        _all = parsed;
        _filtered = parsed;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Impossible de charger la liste : $e")),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Rechargement manuel : force le téléchargement, ignorant le cache.
  Future<void> _reloadPlaylistForCurrentAccount({bool showSnack = true}) async {
    setState(() {
      _loading = true;
      _all.clear();
      _filtered.clear();
      _searchCtrl.clear();
    });

    try {
      // 👇 Ici, on garde `downloadCurrentM3U` car l'action est manuelle.
      final path = await PlaylistService.downloadCurrentM3U();
      final parsed = await _parseM3uFile(path);

      if (!mounted) return;
      setState(() {
        _all = parsed;
        _filtered = parsed;
      });

      if (showSnack) {
        final acc = await IptvAccountService.getCurrentAccount();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("🔄 Liste rechargée pour « ${acc?.label ?? "Compte"} » (${parsed.length} entrées)")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Impossible de recharger la liste : $e")),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // --- FIN DE LA LOGIQUE CORRIGÉE ---

  Future<void> _openSettings() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AccountsScreen()),
    );
    if (changed == true) {
      // Quand on change de compte, on force le rechargement. C'est logique.
      await _reloadPlaylistForCurrentAccount();
    }
  }

  void _onSearchChanged(String q) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _filtered = List.of(_all));
      return;
    }
    setState(() {
      _filtered = _all.where((e) => e.name.toLowerCase().contains(query)).toList();
    });
  }

  Future<List<M3uItem>> _parseM3uFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return [];
    final lines = await file.readAsLines();

    final items = <M3uItem>[];
    String? pendingName;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTINF')) {
        final idx = line.lastIndexOf(',');
        final name = (idx >= 0 && idx < line.length - 1) ? line.substring(idx + 1).trim() : 'Sans titre';
        pendingName = name.isEmpty ? 'Sans titre' : name;
        continue;
      }

      if (line.startsWith('http://') || line.startsWith('https://')) {
        final url = line;
        final name = pendingName ?? _fallbackNameFromUrl(url);
        items.add(M3uItem(name: name, url: url));
        pendingName = null;
      }
    }
    return items;
  }

  String _fallbackNameFromUrl(String url) {
    try {
      final u = Uri.parse(url);
      final seg = u.pathSegments.isNotEmpty ? u.pathSegments.last : url;
      return seg.isEmpty ? url : seg;
    } catch (_) {
      return url;
    }
  }

  Future<void> _pullToRefresh() async {
    await _reloadPlaylistForCurrentAccount();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = _currentAccountLabel == null
        ? const Text("IPtvFlux")
        : Text("IPtvFlux — ${_currentAccountLabel!}");

    return Scaffold(
      appBar: AppBar(
        title: title,
        actions: [
          IconButton(
            tooltip: 'Recharger',
            icon: const Icon(Icons.refresh),
            onPressed: _reloadPlaylistForCurrentAccount,
          ),
          IconButton(
            tooltip: 'Comptes IPTV',
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: "Rechercher un film/série...",
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchCtrl.clear();
                    _onSearchChanged('');
                  },
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _pullToRefresh,
              child: _filtered.isEmpty && !_loading
                  ? ListView(
                children: const [
                  SizedBox(height: 64),
                  Center(child: Text("Aucun résultat.")),
                ],
              )
                  : ListView.separated(
                itemCount: _filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final it = _filtered[i];
                  return ListTile(
                    title: Text(it.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      it.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    leading: const Icon(Icons.playlist_play),
                    onTap: () async {
                      await verifierEtTelecharger(it.url, context);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
