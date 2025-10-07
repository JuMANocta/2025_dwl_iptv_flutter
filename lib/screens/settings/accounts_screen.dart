import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/iptv_account.dart';
import '../../services/iptv_account_service.dart';
import '../../services/playlist_service.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  late Future<List<IptvAccount>> _future;
  late Future<_PlaylistInfo?> _playlistInfoFuture;

  @override
  void initState() {
    super.initState();
    _future = _load();
    // CORRECTION : On lance la logique de chargement intelligente au démarrage.
    _playlistInfoFuture = _loadAndDisplayPlaylistInfo();
  }

  Future<List<IptvAccount>> _load() async {
    await IptvAccountService.migrateFromLegacyIfNeeded();
    return IptvAccountService.listAccounts();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
      // On utilise la même logique de chargement au rafraîchissement.
      _playlistInfoFuture = _loadAndDisplayPlaylistInfo();
    });
  }

  Future<void> _setCurrent(String id) async {
    await IptvAccountService.setCurrentAccount(id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("✅ Compte sélectionné.")),
    );
    // Signale au parent qu'il doit recharger la playlist, et ferme l'écran
    Navigator.of(context).pop(true);
  }

  Future<void> _delete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer le compte ?"),
        content: const Text("Cette action est définitive."),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(ctx,false), child: const Text("Annuler")),
          TextButton(onPressed: ()=>Navigator.pop(ctx,true), child: const Text("Supprimer", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      await IptvAccountService.deleteAccount(id);
      await _refresh();
    }
  }

  Future<void> _openEditor({IptvAccount? initial}) async {
    final result = await showModalBottomSheet<IptvAccount>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EditAccountSheet(initial: initial),
    );
    if (result != null) {
      await IptvAccountService.saveAccount(result);
      await IptvAccountService.setCurrentAccount(result.id);
      if (!mounted) return;
      // Ferme en signalant un changement (le parent relancera le chargement)
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("🔄 Playlist rechargée (${info?.count ?? 0} entrées)")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Échec du rechargement : $e")),
      );
    }
  }

  // ---------- Playlist info ----------

  // NOUVELLE FONCTION : Utilise la logique de cache pour le chargement initial.
  Future<_PlaylistInfo?> _loadAndDisplayPlaylistInfo() async {
    try {
      final path = await PlaylistService.getOrDownloadPlaylist();
      return _readPlaylistInfo(path);
    } catch (e) {
      // Si une erreur se produit (ex: réseau pendant le dl), on la propage au FutureBuilder.
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Erreur chargement playlist : $e")),
      );
      // Retourne null pour que l'UI puisse afficher l'état d'erreur.
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
    return FutureBuilder<_PlaylistInfo?>(
      future: _playlistInfoFuture,
      builder: (ctx, snap) {

        // Gestion de l'état de chargement
        if (snap.connectionState == ConnectionState.waiting) {
          return const Card(
            margin: EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: Text("Vérification de la playlist...")),
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
                const Text("Infos playlist", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (info == null) ...[
                  const Text("Aucune playlist disponible ou erreur de chargement."),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    // Ce bouton doit forcer le rechargement
                    onPressed: _forceReloadPlaylist,
                    icon: const Icon(Icons.refresh),
                    label: const Text("Tenter un rechargement"),
                  ),
                ] else ...[
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text("iptv_links.m3u"),
                    subtitle: Text(
                      "Taille : ${_formatBytes(info.size)} • Maj : ${_formatDate(info.modified)}",
                    ),
                    trailing: Chip(label: Text("Entrées : ${info.count}")),
                  ),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        // Ce bouton force le rechargement
                        onPressed: _forceReloadPlaylist,
                        icon: const Icon(Icons.refresh),
                        label: const Text("Recharger"),
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
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("🗑️ Playlist supprimée.")),
                            );
                          }
                        },
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        label: const Text("Supprimer", style: TextStyle(color: Colors.red)),
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
    return Scaffold(
      appBar: AppBar(title: const Text("Comptes IPTV")),
      body: FutureBuilder<List<IptvAccount>>(
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
                    label: const Text("Ajouter un compte IPTV"),
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
                      return FutureBuilder<IptvAccount?>(
                        future: IptvAccountService.getCurrentAccount(),
                        builder: (ctx, curSnap) {
                          final currentId = curSnap.data?.id;
                          final isCurrent = currentId == a.id;
                          final host = a.mode == IptvAuthMode.separate
                              ? (Uri.tryParse(a.baseUrl ?? "")?.host ?? "?")
                              : (Uri.tryParse(a.completeUrl ?? "")?.host ?? "?");
                          return ListTile(
                            leading: Icon(
                              isCurrent ? Icons.radio_button_checked : Icons.radio_button_off,
                              color: isCurrent ? Colors.green : null,
                            ),
                            title: Text(a.label),
                            subtitle: Text(
                              a.mode == IptvAuthMode.completeUrl
                                  ? "Mode: URL complète — $host"
                                  : "Mode: séparé — ${a.username ?? "?"}@$host",
                            ),
                            onTap: ()=>_setCurrent(a.id),
                            trailing: Wrap(spacing: 4, children: [
                              IconButton(
                                tooltip: "Modifier",
                                icon: const Icon(Icons.edit),
                                onPressed: ()=>_openEditor(initial: a),
                              ),
                              IconButton(
                                tooltip: "Supprimer",
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
        label: const Text("Nouveau"),
      ),
    );
  }
}

// ---------- Sheet d'édition de compte ----------

class _EditAccountSheet extends StatefulWidget {
  final IptvAccount? initial;
  const _EditAccountSheet({this.initial});

  @override
  State<_EditAccountSheet> createState() => _EditAccountSheetState();
}

class _EditAccountSheetState extends State<_EditAccountSheet> {
  final _form = GlobalKey<FormState>();
  late TextEditingController _label;
  late TextEditingController _completeUrl;
  late TextEditingController _baseUrl;
  late TextEditingController _username;
  late TextEditingController _password;
  late TextEditingController _cookies;
  IptvAuthMode _mode = IptvAuthMode.completeUrl;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _label = TextEditingController(text: i?.label ?? "Compte IPTV");
    _completeUrl = TextEditingController(text: i?.completeUrl ?? "");
    _baseUrl = TextEditingController(text: i?.baseUrl ?? "");
    _username = TextEditingController(text: i?.username ?? "");
    _password = TextEditingController(text: i?.password ?? "");
    _cookies = TextEditingController(text: i?.cookies ?? "");
    _mode = i?.mode ?? IptvAuthMode.completeUrl;
  }

  @override
  void dispose() {
    _label.dispose(); _completeUrl.dispose(); _baseUrl.dispose();
    _username.dispose(); _password.dispose(); _cookies.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final id = widget.initial?.id ?? "acc_${DateTime.now().millisecondsSinceEpoch}";
    final acc = IptvAccount(
      id: id,
      label: _label.text.trim().isEmpty ? "Compte IPTV" : _label.text.trim(),
      mode: _mode,
      completeUrl: _mode == IptvAuthMode.completeUrl ? _completeUrl.text.trim() : null,
      baseUrl: _mode == IptvAuthMode.separate ? _baseUrl.text.trim() : null,
      username: _mode == IptvAuthMode.separate ? _username.text.trim() : null,
      password: _mode == IptvAuthMode.separate ? _password.text.trim() : null,
      cookies: _cookies.text.trim().isEmpty ? null : _cookies.text.trim(),
    );
    Navigator.of(context).pop(acc);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Éditer le compte", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _label,
                  decoration: const InputDecoration(
                    labelText: "Nom du compte",
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<IptvAuthMode>(
                  segments: const [
                    ButtonSegment(
                      value: IptvAuthMode.completeUrl,
                      icon: Icon(Icons.link),
                      label: Text("URL complète"),
                    ),
                    ButtonSegment(
                      value: IptvAuthMode.separate,
                      icon: Icon(Icons.vpn_key_outlined),
                      label: Text("Séparé"),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s)=>setState(()=>_mode = s.first),
                ),
                const SizedBox(height: 12),
                if (_mode == IptvAuthMode.completeUrl) ...[
                  TextFormField(
                    controller: _completeUrl,
                    decoration: const InputDecoration(labelText: "URL .m3u complète"),
                    validator: (v)=> (v==null || v.trim().isEmpty) ? "Requis" : null,
                  ),
                ] else ...[
                  TextFormField(
                    controller: _baseUrl,
                    decoration: const InputDecoration(labelText: "Base URL (ex: https://host:port/)"),
                    validator: (v)=> (v==null || v.trim().isEmpty) ? "Requis" : null,
                  ),
                  Row(
                    children: [
                      Expanded(child: TextFormField(
                        controller: _username,
                        decoration: const InputDecoration(labelText: "Username"),
                        validator: (v)=> (v==null || v.trim().isEmpty) ? "Requis" : null,
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: TextFormField(
                        controller: _password,
                        decoration: const InputDecoration(labelText: "Password"),
                        validator: (v)=> (v==null || v.trim().isEmpty) ? "Requis" : null,
                      )),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _cookies,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: "Cookies (optionnel)",
                      helperText: "Format: 'key1=value1; key2=value2'",
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(onPressed: _save, child: const Text("Enregistrer")),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Classe pour contenir les infos de la playlist
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
