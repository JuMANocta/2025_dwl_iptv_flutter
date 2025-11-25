import 'dart:io';
import 'package:flutter/material.dart';
import '../../data/models/stream_account.dart';
import '../../data/services/stream_account_service.dart';
import '../../data/services/playlist_service.dart';
import 'edit_account_sheet.dart';
import '../../l10n/app_localizations.dart';

class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  late Future<List<StreamAccount>> _future;
  late Future<_PlaylistInfo?> _playlistInfoFuture;

  @override
  void initState() {
    super.initState();
    _future = _load();
    // On utilise la même logique de chargement intelligente au démarrage.
    _playlistInfoFuture = _loadAndDisplayPlaylistInfo();
  }

  Future<List<StreamAccount>> _load() async {
    await StreamAccountService.migrateFromLegacyIfNeeded();
    return StreamAccountService.listAccounts();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
      // On utilise la même logique de chargement au rafraîchissement.
      _playlistInfoFuture = _loadAndDisplayPlaylistInfo();
    });
  }

  Future<void> _setCurrent(String id) async {
    await StreamAccountService.setCurrentAccount(id);
    if (!mounted) return;
      debugPrint("✅ Compte sélectionné.");
      // Signale au parent qu'il doit recharger la playlist, et ferme l'écran
      Navigator.of(context).pop(true);
  }

  Future<void> _delete(String id) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n!.deleteAccountDialogTitle),
        content: Text(l10n.deleteAccountDialogContent),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(ctx,false), child: Text(l10n.cancel)),
          TextButton(onPressed: ()=>Navigator.pop(ctx,true), child: Text(l10n.deleteAccountConfirm, style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      await StreamAccountService.deleteAccount(id);
      await _refresh();
    }
  }

  Future<void> _openEditor({StreamAccount? initial}) async {
    final result = await showModalBottomSheet<StreamAccount>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => EditAccountSheet(initial: initial),
    );
    if (result != null) {
      await StreamAccountService.saveAccount(result);
      await StreamAccountService.setCurrentAccount(result.id);
      if (!mounted) return;
      // Ferme en signalant un changement
      Navigator.of(context).pop(true);
    }
  }

  // Comportement du bouton "Recharger" : force le téléchargement.
  Future<void> _forceReloadPlaylist() async {
    try {
      final path = await PlaylistService.downloadCurrentM3U();
      final info = await _readPlaylistInfo(path);
      if (!mounted) return;
      setState(() {
        _playlistInfoFuture = Future.value(info);
      });
      debugPrint("🔄 Playlist rechargée (${info?.count ?? 0} entrées)");
    } catch (e) {
      if (!mounted) return;
        debugPrint("❌ Échec du rechargement : $e");
    }
  }

  // ---------- Playlist info ----------
  Future<_PlaylistInfo?> _loadAndDisplayPlaylistInfo() async {
    try {
      final path = await PlaylistService.getOrDownloadPlaylist();
      return _readPlaylistInfo(path);
    } catch (e) {
      // Si une erreur se produit (ex: réseau pendant le dl), on la propage au FutureBuilder.
      if (!mounted) return null;
        debugPrint("❌ Erreur chargement playlist : $e");
      return null;
    }
  }

  Future<_PlaylistInfo?> _readPlaylistInfo(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return null;
      final stat = await f.stat();
      final lines = await f.readAsLines();
      final count = lines.where((l) {
        final s = l.trim().toLowerCase();
        return s.startsWith('http://') || s.startsWith('https://');
      }).length;
      return _PlaylistInfo(
        path: path,
        size: stat.size,
        modified: stat.modified,
        count: count,
      );
    } catch (_) {
      return null;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return "$bytes B";
    const units = ["KB", "MB", "GB", "TB"];
    double v = bytes / 1024.0;
    int i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024.0;
      i++;
    }
    return "${v.toStringAsFixed(2)} ${units[i]}";
  }

  String _formatDate(DateTime dt) {
    return "${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/${dt.year} "
        "${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}";
  }

  Widget _playlistInfoCard() {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<_PlaylistInfo?>(
      future: _playlistInfoFuture,
      builder: (ctx, snap) {

        // Gestion de l'état de chargement
        if (snap.connectionState == ConnectionState.waiting) {
          return Card(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(child: Text(l10n!.playlistInfoChecking)),
            ),
          );
        }

        final info = snap.data;
        return Card(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n!.playlistInfoTitle, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (info == null) ...[
                  Text(l10n.playlistInfoUnavailable),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    // Ce bouton doit forcer le rechargement
                    onPressed: _forceReloadPlaylist,
                    icon: const Icon(Icons.refresh),
                    label: Text(l10n.playlistInfoTryReload),
                  ),
                ] else ...[
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.playlistInfoLocalFile),
                    subtitle: Text(
                      "${l10n.playlistInfoSize} ${_formatBytes(info.size)} • ${l10n.playlistInfoLastUpdate} : ${_formatDate(info.modified)}",
                    ),
                    trailing: Chip(label: Text("${l10n.playlistInfoEntries} : ${info.count}")),
                  ),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        // Ce bouton force le rechargement
                        onPressed: _forceReloadPlaylist,
                        icon: const Icon(Icons.refresh),
                        label: Text(l10n.playlistInfoReloadButton),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () async {
                          final p = await PlaylistService.playlistPath();
                          final f = File(p);
                          if (await f.exists()) {
                            try { await f.delete(); } catch (_) {}
                          }
                          _refresh(); // Rafraîchit l'UI
                          if (mounted) {
                            debugPrint("🗑️ Playlist supprimée.");
                          }
                        },
                        icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red
                        ),
                        label: Text(
                            l10n.playlistInfoDeleteButton,
                            style: TextStyle(color: Colors.red)
                        ),
                      ),
                    ],
                  )
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n!.accountsTitle)),
      body: FutureBuilder<List<StreamAccount>>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final accounts = snap.data ?? [];

          return Column(
            children: [
              _playlistInfoCard(),
              Expanded(
                child: accounts.isEmpty
                    ? Center(
                  child: TextButton.icon(
                    onPressed: ()=>_openEditor(),
                    icon: const Icon(Icons.add),
                    label: Text(l10n.accountsListEmpty),
                  ),
                )
                    : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.only(top: 8),
                    itemCount: accounts.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final a = accounts[i];
                      return FutureBuilder<StreamAccount?>(
                        future: StreamAccountService.getCurrentAccount(),
                        builder: (ctx, curSnap) {
                          final currentId = curSnap.data?.id;
                          final isCurrent = currentId == a.id;
                          final host = a.mode == StreamAuthMode.separate
                              ? (Uri.tryParse(a.baseUrl ?? "")?.host ?? "?")
                              : (Uri.tryParse(a.completeUrl ?? "")?.host ?? "?");
                          return ListTile(
                            leading: Icon(
                              isCurrent ? Icons.radio_button_checked : Icons.radio_button_off,
                              color: isCurrent ? Colors.green : null,
                            ),
                            title: Text(a.label),
                            subtitle: Text(
                              a.mode == StreamAuthMode.completeUrl
                                  ? l10n.accountModeComplete(host)
                                  : l10n.accountModeSeparate(a.username ?? "?", host),
                            ),
                            onTap: ()=>_setCurrent(a.id),
                            trailing: Wrap(spacing: 4, children: [
                              IconButton(
                                tooltip: l10n.accountActionEdit,
                                icon: const Icon(Icons.edit),
                                onPressed: ()=>_openEditor(initial: a),
                              ),
                              IconButton(
                                tooltip: l10n.accountActionDelete,
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: ()=>_delete(a.id),
                              ),
                            ]),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: ()=>_openEditor(),
        icon: const Icon(Icons.add),
        label: Text(l10n.accountsFab),
      ),
    );
  }
}

class _PlaylistInfo {
  final String path;
  final int size;
  final DateTime modified;
  final int count;

  _PlaylistInfo({
    required this.path,
    required this.size,
    required this.modified,
    required this.count
  });
}
