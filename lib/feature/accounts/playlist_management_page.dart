import 'dart:io';
import 'package:flutter/material.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/data/models/account_info.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/models/stream_account.dart';
import 'package:aetherStream/data/services/parsed_playlist_service.dart';
import 'package:aetherStream/data/services/playlist_service.dart';
import 'package:aetherStream/data/services/stream_account_service.dart';

/// Statistiques playlist par compte (§1L-d).
///
/// Liste tous les comptes configurés et affiche pour chacun :
///   - Stats locales : nb films / séries / chaînes (depuis le hub mémoire
///     `ParsedPlaylistService`) + taille fichier M3U + âge du cache.
///   - Stats Xtream (si compte en mode `separate`) : date d'expiration de
///     l'abonnement et nombre de connexions actives / max.
///   - Bouton "Recharger" plein → re-télécharge le M3U du compte (avec
///     confirmation si la playlist a moins de 24h).
///
/// Remplace la tile "Recharger la playlist" du `SettingsPage` qui agissait
/// uniquement sur le compte actif.
class PlaylistManagementPage extends StatefulWidget {
  const PlaylistManagementPage({super.key});

  @override
  State<PlaylistManagementPage> createState() => _PlaylistManagementPageState();
}

class _PlaylistManagementPageState extends State<PlaylistManagementPage> {
  List<StreamAccount> _accounts = [];
  String? _activeId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final all = await StreamAccountService.listAccounts();
    final active = await StreamAccountService.getCurrentAccount();
    if (!mounted) return;
    setState(() {
      _accounts = all;
      _activeId = active?.id;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistiques playlist'),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: isDark ? null : cs.surface,
          gradient: isDark
              ? RadialGradient(
                  center: const Alignment(0, -1.5),
                  radius: 1.4,
                  colors: [
                    kAccentPrimary.withAlpha(20),
                    cs.surface,
                  ],
                )
              : null,
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _accounts.isEmpty
                ? _EmptyState(cs: cs)
                : ListenableBuilder(
                    listenable: ParsedPlaylistService.version,
                    builder: (context, _) {
                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                        itemCount: _accounts.length,
                        itemBuilder: (_, i) {
                          final acc = _accounts[i];
                          return _AccountStatsCard(
                            account: acc,
                            isActive: acc.id == _activeId,
                            onReloaded: _loadAccounts,
                          );
                        },
                      );
                    },
                  ),
      ),
    );
  }
}

// ─── Empty state (pas de compte configuré) ──────────────────────────────────

class _EmptyState extends StatelessWidget {
  final ColorScheme cs;
  const _EmptyState({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.list_alt, size: 56, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'Aucun compte configuré',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Ajoutez un compte IPTV depuis Paramètres → Comptes pour afficher les statistiques de sa playlist.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Card stats par compte ─────────────────────────────────────────────────

class _AccountStatsCard extends StatefulWidget {
  final StreamAccount account;
  final bool isActive;
  final VoidCallback onReloaded;

  const _AccountStatsCard({
    required this.account,
    required this.isActive,
    required this.onReloaded,
  });

  @override
  State<_AccountStatsCard> createState() => _AccountStatsCardState();
}

class _AccountStatsCardState extends State<_AccountStatsCard> {
  Future<AccountInfo?>? _accountInfoFuture;
  bool _reloading = false;

  @override
  void initState() {
    super.initState();
    // Lance la requête Xtream uniquement pour les comptes en mode "separate"
    // (les comptes "completeUrl" n'ont pas d'API player_api.php exposée).
    if (widget.account.mode == StreamAuthMode.separate) {
      _accountInfoFuture = StreamAccountService.fetchAccountInfo(widget.account);
    }
  }

  Future<void> _reload() async {
    if (_reloading) return;

    // Confirmation si la playlist a moins de 24h.
    final path = await PlaylistService.pathForAccountId(widget.account.id);
    final file = File(path);
    if (await file.exists()) {
      final age = DateTime.now().difference(await file.lastModified());
      if (age.inHours < 24) {
        final ok = await _confirmReload(age);
        if (ok != true) return;
      }
    }

    if (!mounted) return;
    setState(() => _reloading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await PlaylistService.deleteForAccountId(widget.account.id);
      String? newPath;
      if (widget.isActive) {
        // Compte actif → utilise downloadCurrentM3U (messages d'erreur précis).
        newPath = await PlaylistService.downloadCurrentM3U();
      } else {
        newPath = await PlaylistService.ensureDownloadedForAccount(widget.account);
      }
      if (newPath == null) {
        throw const HttpException('Téléchargement impossible (vérifie l\'URL ou la connexion).');
      }
      await ParsedPlaylistService.reloadFromDisk(
        widget.account.id,
        widget.account.label,
        newPath,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('✅ Playlist rechargée pour ${widget.account.label}'),
          backgroundColor: kAccentPrimary.withAlpha(180),
        ),
      );
      widget.onReloaded();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('❌ Échec : $e')),
      );
    } finally {
      if (mounted) setState(() => _reloading = false);
    }
  }

  Future<bool?> _confirmReload(Duration age) {
    final h = age.inHours;
    final m = age.inMinutes % 60;
    final ageStr = h > 0 ? '${h}h${m > 0 ? ' ${m}min' : ''}' : '${m}min';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recharger ?'),
        content: Text(
          'La playlist de "${widget.account.label}" a été téléchargée il y a $ageStr.\n'
          'Recharger quand même depuis le serveur ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Recharger',
              style: TextStyle(color: kWarning, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final parsed = ParsedPlaylistService.getAccount(widget.account.id);
    final entries = parsed?.entries ?? const <M3uEntry>[];

    // Compte par type (le hub mémoire est la source de vérité).
    int films = 0, series = 0, tv = 0;
    for (final e in entries) {
      switch (e.type) {
        case M3uContentType.movie:
          films++;
          break;
        case M3uContentType.series:
          series++;
          break;
        case M3uContentType.tv:
          tv++;
          break;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.isActive
                  ? kAccentPrimary.withAlpha(120)
                  : cs.outlineVariant.withAlpha(80),
              width: widget.isActive ? 1.5 : 1,
            ),
            boxShadow: widget.isActive
                ? [
                    BoxShadow(
                      color: kAccentPrimary.withAlpha(40),
                      blurRadius: 14,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(account: widget.account, isActive: widget.isActive),
              const SizedBox(height: 14),
              _CountsRow(films: films, series: series, tv: tv),
              const SizedBox(height: 12),
              _FileStatsBlock(
                accountId: widget.account.id,
                hasParsed: parsed != null,
              ),
              if (widget.account.mode == StreamAuthMode.separate) ...[
                const SizedBox(height: 10),
                _XtreamInfoBlock(future: _accountInfoFuture),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _reloading ? null : _reload,
                  icon: _reloading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(
                    _reloading
                        ? 'Téléchargement…'
                        : 'Recharger la playlist',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: kAccentPrimary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Sous-blocs ─────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final StreamAccount account;
  final bool isActive;
  const _Header({required this.account, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: kAccentPrimary.withAlpha(isActive ? 35 : 20),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: kAccentPrimary.withAlpha(isActive ? 160 : 60),
              width: 1,
            ),
          ),
          child: Icon(
            Icons.list_alt,
            color: kAccentPrimary,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                account.label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                account.mode == StreamAuthMode.completeUrl
                    ? 'URL complète'
                    : 'Xtream Codes',
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (isActive)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: kAccentPrimary.withAlpha(40),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: kAccentPrimary, width: 1),
            ),
            child: Text(
              'ACTIF',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                color: kAccentPrimary,
                letterSpacing: 1.2,
              ),
            ),
          ),
      ],
    );
  }
}

class _CountsRow extends StatelessWidget {
  final int films;
  final int series;
  final int tv;
  const _CountsRow({required this.films, required this.series, required this.tv});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _CountTile(icon: Icons.movie_outlined, value: films, label: 'Films', color: kAccentPrimary)),
        const SizedBox(width: 8),
        Expanded(child: _CountTile(icon: Icons.video_library_outlined, value: series, label: 'Séries', color: kAccentTertiary)),
        const SizedBox(width: 8),
        Expanded(child: _CountTile(icon: Icons.live_tv_outlined, value: tv, label: 'Chaînes', color: kAccentSecondary)),
      ],
    );
  }
}

class _CountTile extends StatelessWidget {
  final IconData icon;
  final int value;
  final String label;
  final Color color;
  const _CountTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(70), width: 1),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text(
            _formatCount(value),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatCount(int n) {
    if (n < 1000) return '$n';
    if (n < 10000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '${(n / 1000).round()}k';
  }
}

/// Bloc "Fichier M3U" : taille + âge du cache. FutureBuilder car on accède
/// à `File.length()` et `File.lastModified()` qui sont async.
class _FileStatsBlock extends StatelessWidget {
  final String accountId;
  final bool hasParsed;
  const _FileStatsBlock({required this.accountId, required this.hasParsed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<_FileStats?>(
      future: _readStats(),
      builder: (context, snap) {
        final stats = snap.data;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withAlpha(120),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: _MiniStat(
                  icon: Icons.sd_storage_outlined,
                  label: 'Taille M3U',
                  value: stats == null ? '—' : _formatSize(stats.size),
                ),
              ),
              Container(width: 1, height: 26, color: cs.outlineVariant.withAlpha(80)),
              Expanded(
                child: _MiniStat(
                  icon: Icons.access_time,
                  label: 'Âge cache',
                  value: stats == null
                      ? 'Aucun cache'
                      : _formatAge(stats.modified),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<_FileStats?> _readStats() async {
    try {
      final path = await PlaylistService.pathForAccountId(accountId);
      final file = File(path);
      if (!await file.exists()) return null;
      return _FileStats(
        size: await file.length(),
        modified: await file.lastModified(),
      );
    } catch (_) {
      return null;
    }
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes o';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} ko';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} Mo';
  }

  static String _formatAge(DateTime when) {
    final age = DateTime.now().difference(when);
    if (age.inMinutes < 1) return 'à l\'instant';
    if (age.inMinutes < 60) return 'il y a ${age.inMinutes} min';
    if (age.inHours < 24) return 'il y a ${age.inHours} h';
    return 'il y a ${age.inDays} j';
  }
}

class _FileStats {
  final int size;
  final DateTime modified;
  _FileStats({required this.size, required this.modified});
}

/// Bloc Xtream Codes : date d'expiration + connexions actives/max.
/// Réseau requis, donc FutureBuilder + état "—" pendant le chargement.
class _XtreamInfoBlock extends StatelessWidget {
  final Future<AccountInfo?>? future;
  const _XtreamInfoBlock({required this.future});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withAlpha(120),
        borderRadius: BorderRadius.circular(10),
      ),
      child: FutureBuilder<AccountInfo?>(
        future: future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: kAccentSecondary,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Lecture des infos Xtream…',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            );
          }
          final info = snap.data;
          if (info == null) {
            return _InlineError(message: 'Infos Xtream indisponibles');
          }
          return Row(
            children: [
              Expanded(
                child: _MiniStat(
                  icon: Icons.event_outlined,
                  label: 'Expiration',
                  value: _formatExpiration(info.expirationDate),
                  valueColor: _expirationColor(info.expirationDate),
                ),
              ),
              Container(width: 1, height: 26, color: cs.outlineVariant.withAlpha(80)),
              Expanded(
                child: _MiniStat(
                  icon: Icons.cable,
                  label: 'Connexions',
                  value: info.maxConnections > 0
                      ? '${info.activeConnections} / ${info.maxConnections}'
                      : '${info.activeConnections}',
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _formatExpiration(DateTime? exp) {
    if (exp == null) return 'Inconnue';
    final remaining = exp.difference(DateTime.now());
    if (remaining.isNegative) return 'Expiré';
    if (remaining.inDays > 0) return 'Dans ${remaining.inDays} j';
    if (remaining.inHours > 0) return 'Dans ${remaining.inHours} h';
    return 'Dans ${remaining.inMinutes} min';
  }

  static Color? _expirationColor(DateTime? exp) {
    if (exp == null) return null;
    final remaining = exp.difference(DateTime.now());
    if (remaining.isNegative) return kWarning;
    if (remaining.inDays < 7) return kWarning;
    return kAccentPrimary;
  }
}

class _InlineError extends StatelessWidget {
  final String message;
  const _InlineError({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.info_outline, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  const _MiniStat({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurfaceVariant,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? cs.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
