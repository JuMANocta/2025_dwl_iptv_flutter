/// §favIndex + §resumeIndex (2026-09-06, lot 13 suite) — La rangée Favoris et
/// les cartes « reprise » du hero se calculent À PARTIR des favoris et des
/// reprises (quelques dizaines), retrouvés dans le rangement par un index —
/// et non plus en parcourant TOUT le catalogue à chaque fois.
///
/// **Ce que la télé a mesuré** (`§homeMeter`, 1.18.11, vraies listes) : à
/// chaque retour du lecteur, la rangée Favoris se recomposait en testant
/// chaque groupe (deux clés construites par groupe, ~30 000 groupes) :
/// **84-110 ms** sur Films, 32 ms Séries ; et le hero balayait toutes les URL
/// du catalogue pour retrouver les reprises : **31-43 ms** Films, 11 ms Séries.
/// À eux deux, la moitié de la pire frame (177-358 ms) du retour à l'accueil.
///
/// Les deux fonctions sont PURES : elles reçoivent les index du mémo de
/// regroupement (`byKey`, `byUrl`) et rendent les groupes dans l'ordre du
/// catalogue, exactement comme le parcours qu'elles remplacent.
library;

import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/services/watch_progress_service.dart';

/// Les groupes favoris de [type], dans l'ordre de [groups] (ordre catalogue).
///
/// [favoriteKeys] — les clés persistées par `FavoritesService` :
/// `movie|<clé de groupe>|<année ou vide>` (§homonymYear), ou la forme
/// héritée `movie|<clé de groupe>` (toute année). Les clés d'un autre type
/// sont ignorées. Même sémantique que `FavoritesService.isEntryFavorite`
/// appliqué à la première version de chaque groupe.
///
/// [byKey] — index « clé de groupe → groupes » (plusieurs si le titre est
/// éclaté par année). ⚠️ Films et séries seulement : les chaînes ont une autre
/// clé (`tvGroupKey`) et gardent leur parcours (4 000 entrées, 20 ms).
List<List<M3uEntry>> favoriteGroupsFor({
  required Iterable<String> favoriteKeys,
  required M3uContentType type,
  required Map<String, List<List<M3uEntry>>> byKey,
  required List<List<M3uEntry>> groups,
}) {
  final String prefix = switch (type) {
    M3uContentType.movie => 'movie',
    M3uContentType.series => 'series',
    M3uContentType.tv => 'tv',
  };
  final Set<List<M3uEntry>> wanted = Set<List<M3uEntry>>.identity();
  for (final String key in favoriteKeys) {
    final List<String> parts = key.split('|');
    if (parts.length < 2 || parts.length > 3 || parts[0] != prefix) continue;
    final List<List<M3uEntry>>? candidates = byKey[parts[1]];
    if (candidates == null) continue;
    if (parts.length == 2) {
      // Clé héritée (sans année) : toute année.
      wanted.addAll(candidates);
      continue;
    }
    final String year = parts[2];
    for (final List<M3uEntry> g in candidates) {
      if ((g.first.title.year ?? '') == year) wanted.add(g);
    }
  }
  if (wanted.isEmpty) return const [];
  // L'ordre du catalogue, comme le parcours qu'on remplace : une passe par
  // identité sur les groupes, sans clé construite.
  final out = <List<M3uEntry>>[];
  for (final List<M3uEntry> g in groups) {
    if (wanted.contains(g)) {
      out.add(g);
      if (out.length == wanted.length) break;
    }
  }
  return out;
}

/// Une reprise attachée à son groupe.
typedef ResumeHit = ({List<M3uEntry> group, DateTime lastWatched});

/// Les groupes « en cours », les plus récents d'abord, au plus [max].
///
/// Même sémantique que l'ancien parcours (`getProgressForAny` par groupe) :
/// pour un groupe à plusieurs versions, c'est la progression la PLUS RÉCENTE
/// qui décide — et un titre vu en entier (≥ 95 %) ne se propose pas, même si
/// une version plus ancienne s'était arrêtée avant.
///
/// [byUrl] — index « URL d'entrée → groupe » du rangement ; une URL inconnue
/// (compte déchargé, chaîne) est ignorée.
List<ResumeHit> resumeGroupsFor({
  required Iterable<WatchProgress> progress,
  required Map<String, List<M3uEntry>> byUrl,
  required int max,
}) {
  if (max <= 0) return const [];
  // Le plus récent par groupe (identité).
  final Map<List<M3uEntry>, WatchProgress> best =
      Map<List<M3uEntry>, WatchProgress>.identity();
  for (final WatchProgress p in progress) {
    final List<M3uEntry>? g = byUrl[p.url];
    if (g == null) continue;
    final WatchProgress? cur = best[g];
    if (cur == null || p.lastWatched.isAfter(cur.lastWatched)) best[g] = p;
  }
  final List<ResumeHit> hits = [
    for (final MapEntry<List<M3uEntry>, WatchProgress> e in best.entries)
      if (e.value.ratio < 0.95)
        (group: e.key, lastWatched: e.value.lastWatched),
  ];
  hits.sort((a, b) => b.lastWatched.compareTo(a.lastWatched));
  // Dédoublonnage par nom + année sur les seuls retenus (§heroFanDedup).
  final Set<String> seen = {};
  final List<ResumeHit> out = [];
  for (final ResumeHit h in hits) {
    if (out.length >= max) break;
    final M3uEntry first = h.group.first;
    if (seen.add('${first.displayName}|${first.title.year ?? ''}')) out.add(h);
  }
  return out;
}
