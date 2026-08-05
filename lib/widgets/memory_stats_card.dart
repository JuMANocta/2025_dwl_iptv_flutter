import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/core/utils/image_cache_config.dart';
import 'package:aetherStream/data/services/parsed_playlist_service.dart';
import 'package:aetherStream/data/services/stream_account_service.dart';

/// §memStats — Carte de diagnostic mémoire & stockage.
///
/// Extraite d'`AboutPage` (§perfSettings) pour être partagée avec la page
/// « Optimisation » : RAM process (`ProcessInfo.currentRss/maxRss`), et par
/// compte : entrées chargées en mémoire + taille disque cumulée (playlist
/// source `.json`/`.m3u` + cache parsé `.json.gz`). Donne à l'utilisateur de
/// quoi JUGER si son terminal est à la peine (Fire Stick ~180 Mo de playlists
/// en mémoire), pas juste un bouton « désactiver au hasard ».
class MemoryStatsCard extends StatefulWidget {
  const MemoryStatsCard({super.key});

  @override
  State<MemoryStatsCard> createState() => _MemoryStatsCardState();
}

class _MemoryStatsCardState extends State<MemoryStatsCard> {
  ({
    int rssMb,
    int maxRssMb,
    int imgCacheMb,
    List<({String label, int entries, int diskMb})> accounts
  })? _stats;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final rss = (ProcessInfo.currentRss / (1024 * 1024)).round();
      final maxRss = (ProcessInfo.maxRss / (1024 * 1024)).round();
      final accounts = await StreamAccountService.listAccounts();
      final supportDir = await getApplicationSupportDirectory();
      final docsDir = await getApplicationDocumentsDirectory();
      final list = <({String label, int entries, int diskMb})>[];
      for (final acc in accounts) {
        final entries = ParsedPlaylistService.getAccount(acc.id)?.entries.length ?? 0;
        // playlist source : catalogue .json (§23) OU .m3u legacy
        final catalog = File('${docsDir.path}/playlist_${acc.id}.json');
        final m3u = File('${docsDir.path}/playlist_${acc.id}.m3u');
        // parsed cache JSON.gz
        final json = File('${supportDir.path}/parsed_playlist_${acc.id}.json.gz');
        int disk = 0;
        if (await catalog.exists()) disk += await catalog.length();
        if (await m3u.exists()) disk += await m3u.length();
        if (await json.exists()) disk += await json.length();
        list.add((
          label: acc.label,
          entries: entries,
          diskMb: (disk / (1024 * 1024)).round(),
        ));
      }
      // §imgDiskCache — poids du cache disque des vignettes.
      final imgBytes = await AetherImageCache.totalSizeBytes();
      if (!mounted) return;
      setState(() => _stats = (
            rssMb: rss,
            maxRssMb: maxRss,
            imgCacheMb: (imgBytes / (1024 * 1024)).round(),
            accounts: list,
          ));
    } catch (_) {
      // silencieux
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = _stats;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: kAccentPrimary.withAlpha(60),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.memory, size: 16, color: kAccentPrimary),
              const SizedBox(width: 8),
              Text(
                'MÉMOIRE & STOCKAGE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: kAccentPrimary,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 16),
                onPressed: _busy ? null : _refresh,
                tooltip: 'Rafraîchir',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (s == null)
            Text(
              'Calcul en cours…',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            )
          else ...[
            _statRow(context, 'RAM process',
                '${s.rssMb} Mo (peak ${s.maxRssMb} Mo)'),
            const SizedBox(height: 4),
            // §imgDiskCache — vignettes persistées (évite les re-téléchargements).
            _statRow(context, 'Cache images', '${s.imgCacheMb} Mo'),
            const SizedBox(height: 6),
            for (final a in s.accounts)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _statRow(
                  context,
                  a.label,
                  '${a.entries.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ')} entrées · ${a.diskMb} Mo disque',
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _statRow(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}
