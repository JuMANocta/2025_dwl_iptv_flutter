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
  /// §fleetState — Une ligne par compte, avec de quoi ne PAS mentir :
  ///   - [entries] : ce qui est réellement en mémoire (0 = déchargé) ;
  ///   - [diskEntries] : ce que le cache analysé contient, lu dans son en-tête,
  ///     pour afficher « sur disque · 18 133 entrées » au lieu de « 0 entrées »
  ///     quand la mémoire a été libérée volontairement ;
  ///   - [sourceBytes] / [cacheBytes] : le poids disque **détaillé**, parce
  ///     qu'une somme opaque de 11 Mo ne dit pas ce qu'on récupérerait en
  ///     vidant l'un ou l'autre.
  ({
    int rssMb,
    int maxRssMb,
    int imgCacheMb,
    int ramUsedMb,
    int ramMaxMb,
    int ramCount,
    int ramMaxCount,
    List<
        ({
          String label,
          int entries,
          int? diskEntries,
          int sourceBytes,
          int cacheBytes
        })> accounts
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
      final list = <({
        String label,
        int entries,
        int? diskEntries,
        int sourceBytes,
        int cacheBytes
      })>[];
      for (final acc in accounts) {
        // ⚠️ §lazyUnload — `entriesCountOf`, **jamais** `getAccount()` : ce
        // dernier touche `_lastAccess`, donc ouvrir la carte de diagnostic
        // repoussait le déchargement des comptes qu'on est justement en train
        // d'observer. C'est exactement le défaut que §secondaryCounts a corrigé
        // sur le bandeau de la page Comptes — il vivait encore ici.
        final entries = ParsedPlaylistService.entriesCountOf(acc.id);
        // playlist source : catalogue .json (§23) OU .m3u legacy
        final catalog = File('${docsDir.path}/playlist_${acc.id}.json');
        final m3u = File('${docsDir.path}/playlist_${acc.id}.m3u');
        // parsed cache JSON.gz
        final json = File('${supportDir.path}/parsed_playlist_${acc.id}.json.gz');
        int sourceBytes = 0;
        int cacheBytes = 0;
        if (await catalog.exists()) sourceBytes += await catalog.length();
        if (await m3u.exists()) sourceBytes += await m3u.length();
        if (await json.exists()) cacheBytes += await json.length();
        // §fleetState — Mémoire vide ≠ liste vide. L'en-tête du cache analysé
        // dit combien d'entrées reviendraient au prochain accès ; sans lui, la
        // carte annonçait « 0 entrées · 11 Mo », ce qui se lit comme une liste
        // perdue alors qu'elle est intacte sur le disque.
        int? diskEntries;
        if (entries == 0) {
          diskEntries = (await ParsedPlaylistService.countsOf(acc.id))?.total;
        }
        list.add((
          label: acc.label,
          entries: entries,
          diskEntries: diskEntries,
          sourceBytes: sourceBytes,
          cacheBytes: cacheBytes,
        ));
      }
      // §imgDiskCache — poids du cache disque des vignettes.
      final imgBytes = await AetherImageCache.totalSizeBytes();
      // §imgThrash — état du cache image EN RAM. La TV n'ayant pas de logcat,
      // c'est le SEUL moyen de vérifier sur l'appareil que le thrash a cessé.
      final ram = PaintingBinding.instance.imageCache;
      if (!mounted) return;
      setState(() => _stats = (
            rssMb: rss,
            maxRssMb: maxRss,
            imgCacheMb: (imgBytes / (1024 * 1024)).round(),
            ramUsedMb: (ram.currentSizeBytes / (1024 * 1024)).round(),
            ramMaxMb: (ram.maximumSizeBytes / (1024 * 1024)).round(),
            ramCount: ram.currentSize,
            ramMaxCount: ram.maximumSize,
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
                // §touchTarget — La cible faisait 24x24. L'icône reste à 16 px
                // (l'encart est dense), seule la zone tactile passe à 48.
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
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
            _statRow(context, 'Cache images (disque)', '${s.imgCacheMb} Mo'),
            const SizedBox(height: 4),
            // §imgThrash — Lecture : proche du plafond et STABLE = sain. Une
            // valeur qui retombe sans cesse près de zéro pendant qu'on scrolle
            // signale que les vignettes sont re-décodées en boucle.
            _statRow(
              context,
              'Cache images (RAM)',
              '${s.ramUsedMb} / ${s.ramMaxMb} Mo · ${s.ramCount} / ${s.ramMaxCount} img',
            ),
            const SizedBox(height: 6),
            for (final a in s.accounts)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _statRow(context, a.label, _accountValue(a)),
                    // Le détail du poids disque : « source » = le catalogue
                    // téléchargé, « analysé » = le cache JSON.gz relu au
                    // démarrage. Une somme unique ne disait pas lequel des deux
                    // pèse, ni ce que « Recharger » va réécrire.
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        'source ${_fmtBytes(a.sourceBytes)} · '
                        'analysé ${_fmtBytes(a.cacheBytes)}',
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurfaceVariant.withAlpha(160),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// §fleetState — Ce qu'on écrit à droite du nom d'un compte.
  ///
  /// Trois cas, et un seul mentait : mémoire vide + cache disque intact
  /// affichait « 0 entrées », qui se lit comme une liste perdue. On dit
  /// désormais « sur disque » avec le total réel du cache.
  String _accountValue(
      ({
        String label,
        int entries,
        int? diskEntries,
        int sourceBytes,
        int cacheBytes
      }) a) {
    final total = a.sourceBytes + a.cacheBytes;
    if (a.entries > 0) {
      return '${_fmtCount(a.entries)} entrées · ${_fmtBytes(total)}';
    }
    final d = a.diskEntries;
    if (d != null && d > 0) {
      return 'sur disque · ${_fmtCount(d)} entrées · ${_fmtBytes(total)}';
    }
    // Ni mémoire ni cache lisible : là, « 0 entrées » est la vérité.
    return '0 entrée · ${_fmtBytes(total)}';
  }

  /// Espace fine tous les 3 chiffres (18 133) — la carte se lit à 3 m sur TV.
  String _fmtCount(int n) => n
      .toString()
      .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');

  /// Poids lisible : sous le Mo, un arrondi au Mo affichait « 0 Mo » pour des
  /// fichiers bien présents.
  String _fmtBytes(int bytes) {
    if (bytes <= 0) return '—';
    if (bytes < 1024) return '$bytes o';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} ko';
    final mb = bytes / (1024 * 1024);
    return mb < 10
        ? '${mb.toStringAsFixed(1).replaceAll('.', ',')} Mo'
        : '${mb.round()} Mo';
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
