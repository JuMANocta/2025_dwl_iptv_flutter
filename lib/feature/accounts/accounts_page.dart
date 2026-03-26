import 'dart:io';
import 'dart:convert'; // Nécessaire pour l'optimisation Stream
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:aetherStream/feature/accounts/edit_account_sheet.dart';
import 'package:aetherStream/data/models/stream_account.dart';
import 'package:aetherStream/data/services/stream_account_service.dart';
import 'package:aetherStream/data/services/playlist_service.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:aetherStream/data/services/tmdb_api_service.dart';
import 'package:aetherStream/data/services/tmdb_service.dart';
import 'package:aetherStream/data/services/xmltv_service.dart';
import 'package:aetherStream/data/models/account_info.dart';

class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key, this.initialPlaylistPath});
  final String? initialPlaylistPath;

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  late Future<List<StreamAccount>> _accountsFuture;
  late Future<_CombinedCardInfo> _combinedInfoFuture;

  final _tmdbApiKeyController = TextEditingController();
  bool _isTmdbKeyVisible = false;
  bool _hasSavedKey = false;
  bool _xmltvLoading = false;
  // ID du compte prioritaire (chargé une fois, mis à jour localement)
  String? _priorityAccountId;

  @override
  void initState() {
    super.initState();
    _accountsFuture = _loadAccounts();
    _combinedInfoFuture = _loadCardInfo(initialPath: widget.initialPlaylistPath);
    _initTmdbState();
  }

  Future<void> _initTmdbState() async {
    final key = await TmdbApiService.getApiKey();
    if (key != null && key.isNotEmpty) {
      if (mounted) {
        setState(() {
          _tmdbApiKeyController.text = key;
          _hasSavedKey = true;
        });
      }
    }
  }

  Future<List<StreamAccount>> _loadAccounts() async {
    await StreamAccountService.migrateFromLegacyIfNeeded();
    final accounts = await StreamAccountService.listAccounts();
    final current  = await StreamAccountService.getCurrentAccount();
    if (mounted) setState(() => _priorityAccountId = current?.id);
    return accounts;
  }

  Future<_CombinedCardInfo> _loadCardInfo({String? initialPath}) async {
    // 1. Charger les infos de la playlist (logique existante)
    _PlaylistInfo? pInfo;
    try {
      final path = initialPath ?? await PlaylistService.getOrDownloadPlaylist();
      pInfo = await _readPlaylistInfo(path);
    } catch (_) {
      pInfo = null; // En cas d'erreur, on continue sans les infos de playlist
    }

    // 2. Charger les infos du compte courant
    final account = await StreamAccountService.getCurrentAccount();
    AccountInfo? aInfo;
    if (account != null) {
      // On récupère les détails de l'API pour ce compte
      aInfo = await StreamAccountService.fetchAccountInfo(account);
    }

    // 3. Retourner l'objet combiné
    return _CombinedCardInfo(playlistInfo: pInfo, accountInfo: aInfo, account: account);
  }

  Future<void> _refresh() async {
    setState(() {
      _accountsFuture = _loadAccounts();
      _combinedInfoFuture = _loadCardInfo();
    });
  }

  // --- ACTIONS COMPTES ---

  /// Définit le compte prioritaire sans fermer la page.
  Future<void> _setPriority(String id) async {
    await StreamAccountService.setCurrentAccount(id);
    if (!mounted) return;
    setState(() => _priorityAccountId = id);
    debugPrint("✅ Compte prioritaire : $id");
  }

  Future<void> _delete(String id) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteAccountDialogTitle),
        content: Text(l10n.deleteAccountDialogContent),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.deleteAccountConfirm, style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      await StreamAccountService.deleteAccount(id);
      _refresh();
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
      // Si c'est un nouveau compte ou modif, on le set comme courant par confort
      await StreamAccountService.setCurrentAccount(result.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    }
  }

  // --- ACTIONS PLAYLIST ---

  Future<void> _forceReloadPlaylist() async {
    try {
      await PlaylistService.downloadCurrentM3U();
      if (!mounted) return;
      await _refresh();
      debugPrint("🔄 Playlist rechargée et affichage mis à jour.");
    } catch (e) {
      debugPrint("❌ Échec du rechargement : $e");
    }
  }

  /// 🚀 OPTIMISATION CYBERPUNK : Lecture par Stream
  /// Évite de charger un fichier de 50Mo en RAM d'un coup.
  Future<_PlaylistInfo?> _readPlaylistInfo(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return null;

      final stat = await f.stat();
      int filmCount = 0, seriesCount = 0, tvCount = 0;

      // Lecture ligne par ligne (faible empreinte mémoire)
      await f.openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((line) {
        final s = line.trim();
        if (s.startsWith('http://') || s.startsWith('https://')) {
          final lower = s.toLowerCase();
          if (lower.contains('/movie/')) { filmCount++; }
          else if (lower.contains('/series/')) { seriesCount++; }
          else { tvCount++; }
        }
      });

      return _PlaylistInfo(
        path: path,
        size: stat.size,
        modified: stat.modified,
        filmCount: filmCount,
        seriesCount: seriesCount,
        tvCount: tvCount,
      );
    } catch (_) {
      return null;
    }
  }

  // --- UI WIDGETS ---

  Widget _buildTmdbCard() {
    // Si la clé est sauvegardée, on verrouille l'input visuellement
    final bool isLocked = _hasSavedKey;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                "API TheMovieDB",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tmdbApiKeyController,
                    obscureText: !_isTmdbKeyVisible,
                    readOnly: isLocked, // 🔒 Lecture seule si sauvegardé
                    style: TextStyle(
                      color: isLocked ? Colors.green.shade300 : null,
                      fontWeight: isLocked ? FontWeight.bold : FontWeight.normal,
                    ),
                    decoration: InputDecoration(
                      labelText: isLocked ? "Clé active" : "Saisir Clé API (v3/v4)",
                      hintText: "Bearer Token...",
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isTmdbKeyVisible ? Icons.visibility_off : Icons.visibility,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _isTmdbKeyVisible = !_isTmdbKeyVisible),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // ⚡ BOUTON D'ACTION DYNAMIQUE
                if (isLocked)
                // Mode SUPPRESSION
                  IconButton.filledTonal(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await TmdbApiService.deleteApiKey();
                      setState(() {
                        _tmdbApiKeyController.clear();
                        _hasSavedKey = false;
                      });
                      messenger.showSnackBar(
                        const SnackBar(content: Text("Clé supprimée."), backgroundColor: Colors.red),
                      );
                    },
                    icon: const Icon(Icons.delete_outline),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.red.withValues(alpha: 0.1),
                      foregroundColor: Colors.red,
                    ),
                    tooltip: "Supprimer la clé",
                  )
                else
                // Mode SAUVEGARDE
                  IconButton.filled(
                    onPressed: () async {
                      final key = _tmdbApiKeyController.text.trim();
                      if (key.isNotEmpty) {
                        final focusScope = FocusScope.of(context);
                        final messenger = ScaffoldMessenger.of(context);
                        final navigator = Navigator.of(context);
                        await TmdbApiService.saveApiKey(key);
                        // Force le reload du service
                        TmdbService.resetInstance();

                        focusScope.unfocus();
                        if (!mounted) return;

                        setState(() => _hasSavedKey = true);

                        messenger.showSnackBar(
                          const SnackBar(content: Text("TMDb connecté !"), backgroundColor: Colors.green),
                        );
                        // On quitte pour rafraîchir la recherche parente
                        navigator.pop(true);
                      }
                    },
                    icon: const Icon(Icons.save),
                    tooltip: "Sauvegarder",
                  ),
              ],
            ),
            if (!isLocked)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  "Requis pour les affiches et synopsis.",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _forceReloadXmltv() async {
    setState(() => _xmltvLoading = true);
    try {
      XmltvService.invalidate();
      await XmltvService.ensureLoaded();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Guide des chaînes mis à jour."), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Échec mise à jour XMLTV : $e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _xmltvLoading = false);
    }
  }

  Widget _buildXmltvCard() {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            Icon(Icons.tv, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Guide des chaînes (XMLTV)",
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Text("TNT France — cache 12h",
                      style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            _xmltvLoading
                ? const SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton.filledTonal(
                    onPressed: _forceReloadXmltv,
                    icon: const Icon(Icons.refresh),
                    tooltip: "Forcer la mise à jour du guide",
                  ),
          ],
        ),
      ),
    );
  }

  Widget _playlistInfoCard(AppLocalizations l10n) {
    return FutureBuilder<_CombinedCardInfo>(
      future: _combinedInfoFuture,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator();
        }

        final playlistInfo = snap.data?.playlistInfo;
        final accountInfo = snap.data?.accountInfo;
        final account = snap.data?.account;

        return Card(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- TITRE ---
                Row(
                  children: [
                    Text(l10n.playlistInfoTitle, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (playlistInfo != null) ...[
                      Icon(Icons.sd_storage_outlined, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 3),
                      Text(_formatBytes(playlistInfo.size), style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(width: 10),
                      Icon(Icons.access_time, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 3),
                      Text(_formatDate(playlistInfo.modified), style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
                const Divider(),
                if (playlistInfo != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _StatChip(Icons.movie_outlined, 'Films', playlistInfo.filmCount),
                        _StatChip(Icons.tv_outlined, 'Séries', playlistInfo.seriesCount),
                        _StatChip(Icons.live_tv_outlined, 'Chaînes', playlistInfo.tvCount),
                      ],
                    ),
                  ),

                // --- INFOS DU COMPTE (si disponibles) ---
                if (account != null && accountInfo != null) ...[
                  Row(
                    children: [
                      Icon(Icons.person_outline, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          account.label,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        "Expiration : ${accountInfo.expirationDate != null ? DateFormat('dd/MM/yyyy').format(accountInfo.expirationDate!) : 'N/A'}",
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const Spacer(),
                      Icon(Icons.wifi_tethering, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        "Connexions : ${accountInfo.activeConnections}/${accountInfo.maxConnections}",
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                ],

                // --- INFOS DE LA PLAYLIST (si disponibles) ---
                if (playlistInfo == null) ...[
                  Text(l10n.playlistInfoUnavailable),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      onPressed: _forceReloadPlaylist,
                      icon: const Icon(Icons.download),
                      label: Text(l10n.playlistInfoTryReload),
                    ),
                  ),
                ] else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _forceReloadPlaylist,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text(l10n.playlistInfoReloadButton),
                        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () async {
                          final p = await PlaylistService.playlistPath();
                          final f = File(p);
                          if (await f.exists()) await f.delete();
                          _refresh();
                        },
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        tooltip: l10n.playlistInfoDeleteButton,
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

  // --- BUILD ---

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.accountsTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: Text(l10n.accountsListEmpty),
      ),
      body: FutureBuilder<List<StreamAccount>>(
        future: _accountsFuture,
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final accounts = snap.data ?? [];

          return Column(
            children: [
              // 1. TMDB en premier (Plus important pour la config)
              _buildTmdbCard(),

              // 2. Guide des chaînes XMLTV
              _buildXmltvCard(),

              // 3. Playlist Info
              _playlistInfoCard(l10n),

              const Divider(height: 32),

              // 3. Liste des comptes
              Expanded(
                child: accounts.isEmpty
                    ? Center(
                  child: FilledButton.icon( // Bouton plus visible
                    onPressed: () => _openEditor(),
                    icon: const Icon(Icons.add),
                    label: Text(l10n.accountsListEmpty),
                  ),
                )
                    : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: accounts.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (_, i) {
                      final a = accounts[i];
                      return _buildAccountTile(a, l10n);
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAccountTile(StreamAccount a, AppLocalizations l10n) {
    final cs        = Theme.of(context).colorScheme;
    final isPriority = _priorityAccountId == a.id;
    final host = a.mode == StreamAuthMode.separate
        ? (Uri.tryParse(a.baseUrl ?? '')?.host ?? '?')
        : (Uri.tryParse(a.completeUrl ?? '')?.host ?? '?');
    final subtitle = a.mode == StreamAuthMode.completeUrl ? host : '${a.username} @ $host';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      // Radio de priorité : tap = définir ce compte comme prioritaire
      leading: GestureDetector(
        onTap: () => _setPriority(a.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 40, height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isPriority
                ? Colors.green.withAlpha(30)
                : cs.surfaceContainerHighest,
            border: Border.all(
              color: isPriority ? Colors.green : cs.outlineVariant,
              width: isPriority ? 2 : 1,
            ),
          ),
          child: Icon(
            isPriority ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isPriority ? Colors.green : cs.onSurfaceVariant,
            size: 22,
          ),
        ),
      ),
      title: Text(
        a.label,
        style: TextStyle(
          fontWeight: isPriority ? FontWeight.bold : FontWeight.normal,
          color: isPriority ? cs.onSurface : cs.onSurfaceVariant,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        maxLines: 1, overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.edit_outlined, size: 20, color: cs.onSurfaceVariant),
            onPressed: () => _openEditor(initial: a),
            tooltip: l10n.accountActionEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
            onPressed: () => _delete(a.id),
            tooltip: l10n.accountActionDelete,
          ),
        ],
      ),
    );
  }

  // --- UTILITAIRES ---

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
    return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }
}

class _PlaylistInfo {
  final String path;
  final int size;
  final DateTime modified;
  final int filmCount;
  final int seriesCount;
  final int tvCount;

  int get count => filmCount + seriesCount + tvCount;

  _PlaylistInfo({required this.path, required this.size, required this.modified,
    required this.filmCount, required this.seriesCount, required this.tvCount});
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  const _StatChip(this.icon, this.label, this.count);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.blue.shade300),
        const SizedBox(height: 4),
        Text(
          count.toString(),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _CombinedCardInfo {
  final _PlaylistInfo? playlistInfo;
  final AccountInfo? accountInfo;
  final StreamAccount? account; // Pour afficher le nom du compte

  _CombinedCardInfo({this.playlistInfo, this.accountInfo, this.account});
}
