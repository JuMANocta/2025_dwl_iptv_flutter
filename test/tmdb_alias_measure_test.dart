// §aliasByPoster + R53 (lot 9, 2026-09-25) — MESURE sur les listes réelles de
// `lib/iptv_exemple/` (non versionnées : le test se saute si elles manquent).
//
// Avec le VRAI service (`TmdbGroupAliasService`, `FavoritesService.keyFor`),
// toutes les listes chargées ensemble comme sur l'appareil :
// 1. les vignettes ORPHELINES (aucun identifiant TMDB) — le budget d'un alias
//    par RECHERCHE de titre, écarté au profit de l'affiche ;
// 2. la table AVANT / APRÈS la passe des affiches : fusions, gardes, temps de
//    reconstruction (JIT : l'ordre de grandeur, pas la valeur release) ;
// 3. un ÉCHANTILLON des fusions nouvelles, à relire pour les faux positifs ;
// 4. les FAVORIS simulés — un favori sur CHAQUE vignette : combien
//    s'éteindraient sans la migration (R53), combien après (doit être 0),
//    et encore quand l'alias disparaît ;
// 5. R53 AUJOURD'HUI, sans les affiches : combien de clés de favori bougent
//    quand UNE liste repart de la mémoire (§lazyUnload) ;
// 6. les catégories apprises (`InferredCategoryService`) concernées.
//
// Lancer : flutter test test/tmdb_alias_measure_test.dart
// (`AS_MEASURE_ALL=1` : tout l'échantillon au lieu de 40 grappes.)
@Tags(['bench'])
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/services/favorites_service.dart';
import 'package:aetherStream/data/services/tmdb_group_alias_service.dart';
import 'package:aetherStream/feature/search/m3u_parser.dart';
import 'package:aetherStream/feature/search/xtream_catalog_parser.dart';

const String _dir = 'lib/iptv_exemple';
const List<String> _dumps = [
  'PLATINIUM_vod_cache.json',
  'PREMIUM_vod_cache.json',
  'VOD_vod_cache.json',
  'xenoIptv.json',
  'playlist_racine_2025-12.m3u',
  'VOD_get.m3u',
];

final bool _all = Platform.environment['AS_MEASURE_ALL'] == '1';

bool _hasId(M3uEntry e) {
  final String? id = e.tmdbId;
  return id != null && id.isNotEmpty && id != '0';
}

/// Canonique de chaque clé brute sous la table COURANTE.
Map<String, String> _snapshot(Iterable<String> rawKeys) => {
      for (final k in rawKeys) k: TmdbGroupAliasService.canonical(k),
    };

int _rebuildMs(List<M3uEntry> all) {
  final sw = Stopwatch()..start();
  TmdbGroupAliasService.rebuild(all);
  return sw.elapsedMilliseconds;
}

void main() {
  test('§aliasByPoster + R53 — mesure sur les dumps réels', () async {
    final Map<String, List<M3uEntry>> byList = {};
    for (final String n in _dumps) {
      final String path = '$_dir/$n';
      if (!File(path).existsSync()) continue;
      final films = <M3uEntry>[], series = <M3uEntry>[], tv = <M3uEntry>[];
      if (n.endsWith('.json')) {
        await XtreamCatalogParser.parseFile(path, films, series, tv,
            accountId: n);
      } else {
        await M3uParser.parseFile(path, films, series, tv, accountId: n);
      }
      byList[n] = [...films, ...series];
    }
    final List<M3uEntry> all = [for (final l in byList.values) ...l];
    final Set<String> rawKeys = {
      for (final e in all)
        if (e.title.groupKey.isNotEmpty) e.title.groupKey,
    };
    final StringBuffer out = StringBuffer();
    void say(String s) => out.writeln(s);

    // ── 2. Avant / après ────────────────────────────────────────────────────
    // Coût de la reconstruction (elle tourne sur le thread UI à chaque
    // chargement de liste) : le MEILLEUR de 3 passes chaudes, JIT.
    int best(bool poster) {
      TmdbGroupAliasService.posterPassEnabled = poster;
      return [for (int i = 0; i < 3; i++) _rebuildMs(all)].reduce(min);
    }
    say('reconstruction (meilleur de 3, JIT) : identifiants seuls '
        '${best(false)} ms, avec les affiches ${best(true)} ms');
    TmdbGroupAliasService.posterPassEnabled = false;
    final int msBefore = _rebuildMs(all);
    final Map<String, String> t0 = _snapshot(rawKeys);
    final int aliasBefore = TmdbGroupAliasService.aliasCount;
    final Set<String> favBefore = {
      for (final e in all) FavoritesService.keyFor(e),
    };

    // ── 1. Orphelines (avant les affiches) ─────────────────────────────────
    final Map<String, List<M3uEntry>> groups = {};
    for (final e in all) {
      groups.putIfAbsent('${e.type.name}|${t0[e.title.groupKey]}', () => []).add(e);
    }
    final int orphans = groups.values.where((g) => !g.any(_hasId)).length;
    say('${all.length} entrées films + séries, ${groups.length} vignettes, '
        '$orphans ORPHELINES (aucun identifiant TMDB) = recherches TMDB qu\'un '
        'alias par titre coûterait');

    TmdbGroupAliasService.posterPassEnabled = true;
    final int msAfter = _rebuildMs(all);
    final Map<String, String> t1 = _snapshot(rawKeys);
    say('table : $aliasBefore alias par identifiant → '
        '${TmdbGroupAliasService.aliasCount} avec les affiches '
        '(+${TmdbGroupAliasService.posterAliasCount}) ; reconstruction '
        '$msBefore ms → $msAfter ms (JIT)');

    // ── 3. Échantillon des fusions nouvelles ────────────────────────────────
    final Map<String, List<String>> newClusters = {};
    for (final k in rawKeys) {
      if (t0[k] != t1[k]) {
        (newClusters[t1[k]!] ??= [t1[k]!]).add(k);
      }
    }
    final Map<String, String> sampleTitle = {};
    for (final e in all) {
      sampleTitle.putIfAbsent(e.title.groupKey, () => e.title.rawTitle);
    }
    final List<List<String>> clusters = newClusters.values.toList()
      ..shuffle(Random(20260925));
    say('${clusters.length} grappes nouvelles (vignettes réunies par '
        'l\'affiche), échantillon :');
    for (final c in clusters.take(_all ? clusters.length : 40)) {
      say('   + ${{for (final k in c) sampleTitle[k] ?? k}.join('  //  ')}');
    }

    // ── 3 bis. Garde stricte des FILMS à plus de 3 titres par affiche ───────
    TmdbGroupAliasService.crowdedFilmMax = 3; // l'ancienne garde
    TmdbGroupAliasService.rebuild(all);
    final Map<String, String> strictBefore = _snapshot(rawKeys);
    final int aliasStrictBefore = TmdbGroupAliasService.aliasCount;
    TmdbGroupAliasService.crowdedFilmMax = 8;
    TmdbGroupAliasService.rebuild(all);
    final Map<String, List<String>> gained = {};
    for (final k in rawKeys) {
      if (strictBefore[k] != t1[k]) (gained[t1[k]!] ??= [t1[k]!]).add(k);
    }
    say('garde stricte (films, 4 à 8 titres par affiche) : '
        '$aliasStrictBefore → ${TmdbGroupAliasService.aliasCount} alias '
        '(+${TmdbGroupAliasService.aliasCount - aliasStrictBefore}), '
        '${gained.length} grappes gagnées :');
    for (final c in gained.values) {
      say('   ++ ${{for (final k in c) sampleTitle[k] ?? k}.join('  //  ')}');
    }

    // ── 4. Favoris simulés : un favori sur CHAQUE vignette ──────────────────
    final Set<String> favAfter = {
      for (final e in all) FavoritesService.keyFor(e),
    };
    final int darkWithout =
        favAfter.where((k) => !favBefore.contains(k)).length;
    final Set<String> migrated = {
      ...favBefore,
      ...FavoritesService.aliasClosureAdditions(
          favBefore, TmdbGroupAliasService.aliases),
    };
    final int darkWith = favAfter.where((k) => !migrated.contains(k)).length;
    say('favoris simulés (${favBefore.length}, un par vignette) : '
        '$darkWithout s\'éteindraient SANS la migration (R53), $darkWith '
        'AVEC ; clés stockées en plus : ${migrated.length - favBefore.length}');
    // Un favori SEUL, posé sur chaque vignette dont la clé change : c'est le
    // cas réel (quelques dizaines de favoris), que la simulation « tout est
    // favori » masque — la clé d'arrivée y est déjà favorite.
    final Map<String, String> movedKey = {};
    for (final e in all) {
      if (e.title.groupKey.isEmpty) continue;
      final String t = e.type == M3uContentType.movie ? 'movie' : 'series';
      // La clé que ce favori avait AVANT les affiches, et celle d'après.
      final String stored = '$t|${t0[e.title.groupKey]}|${e.title.year ?? ''}';
      final String after = FavoritesService.keyFor(e);
      if (stored != after) movedKey[stored] = after;
    }
    int lostAlone = 0;
    for (final MapEntry<String, String> m in movedKey.entries) {
      final Set<String> one = {
        m.key,
        ...FavoritesService.aliasClosureAdditions(
            {m.key}, TmdbGroupAliasService.aliases),
      };
      if (!one.contains(m.value)) lostAlone++;
    }
    say('favori SEUL sur une vignette dont la clé change : ${movedKey.length} '
        'cas, tous éteints sans la migration ; $lostAlone éteint(s) avec '
        '(doit être 0)');

    // L'alias disparaît (retour à la table sans les affiches).
    TmdbGroupAliasService.posterPassEnabled = false;
    TmdbGroupAliasService.rebuild(all);
    final Set<String> back = {
      ...migrated,
      ...FavoritesService.aliasClosureAdditions(
          migrated, TmdbGroupAliasService.aliases),
    };
    final int darkBack = {
      for (final e in all) FavoritesService.keyFor(e),
    }.where((k) => !back.contains(k)).length;
    say('… puis l\'alias disparaît : $darkBack favori(s) éteint(s) (doit être 0)');

    // ── 5. R53 aujourd'hui : une liste repart de la mémoire ────────────────
    for (final String gone in byList.keys) {
      final List<M3uEntry> rest = [
        for (final MapEntry<String, List<M3uEntry>> l in byList.entries)
          if (l.key != gone) ...l.value,
      ];
      TmdbGroupAliasService.rebuild(rest);
      final Set<String> restKeys = {
        for (final e in rest)
          if (e.title.groupKey.isNotEmpty) e.title.groupKey,
      };
      final int moved = restKeys.where((k) => t0[k] != TmdbGroupAliasService.canonical(k)).length;
      say('R53 (identifiants seuls) : ${gone.split('.').first} déchargée → '
          '$moved clés de favori bougent sous les vignettes restantes');
    }

    // ── 6. Catégories apprises ──────────────────────────────────────────────
    int noCategory = 0;
    for (final List<String> c in newClusters.values) {
      final Set<String> ks = c.toSet();
      final bool anyCat = all.any((e) =>
          ks.contains(e.title.groupKey) && (e.category?.isNotEmpty ?? false));
      if (!anyCat) noCategory++;
    }
    say('grappes nouvelles sans AUCUNE catégorie fournisseur (les seules qui '
        'dépendent d\'une catégorie apprise) : $noCategory');

    TmdbGroupAliasService.posterPassEnabled = true;
    TmdbGroupAliasService.resetForTest();
    // ignore: avoid_print
    print(out);
    expect(darkWith, 0, reason: 'R53 : aucun favori ne doit s\'éteindre');
    expect(lostAlone, 0, reason: 'un favori seul non plus');
    expect(darkBack, 0, reason: 'ni quand l\'alias disparaît');
  },
      skip: _dumps.any((n) => File('$_dir/$n').existsSync())
          ? false
          : 'dumps absents (lib/iptv_exemple/)',
      timeout: const Timeout(Duration(minutes: 20)));
}
