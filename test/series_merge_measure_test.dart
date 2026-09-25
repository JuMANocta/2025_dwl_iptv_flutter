// §22.1 + §seasonMerge (2026-09-25) — MESURE sur les listes réelles de
// `lib/iptv_exemple/` (non versionnées : le test se saute si elles manquent).
//
// Trois questions, posées au VRAI moteur (parseurs, `contentGroupKey`,
// `TmdbGroupAliasService`, `entriesOfTitle`, `seriesStubsToFetch`) :
//
// 1. §22.1 — Combien de titres de série portent PLUSIEURS stubs d'une même
//    liste, et que devient chacun sous la règle de la fiche (un stub par liste
//    avant, `seriesStubsToFetch` maintenant) ?
// 2. §22.1 — Combien de titres mélangent stubs d'API et épisodes M3U quand
//    toutes les listes sont chargées ensemble (le cas R45) ?
// 3. §seasonMerge — Combien de séries sont ÉCLATÉES par saison (« Titre S02 »,
//    « Titre Saison 2 ») ? Diagnostic SEULEMENT : aucune règle ne change ici.
//
// Les titres imprimés ne sont pas des secrets ; aucune URL ni identifiant ne
// l'est (les dumps n'en portent d'ailleurs pas : `host`/`user`/`pass` absents).
//
// Lancer : flutter test test/series_merge_measure_test.dart
@Tags(['bench'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/services/tmdb_group_alias_service.dart';
import 'package:aetherStream/feature/search/details_versions.dart';
import 'package:aetherStream/feature/search/m3u_filter.dart';
import 'package:aetherStream/feature/search/m3u_parser.dart';
import 'package:aetherStream/feature/search/series_stub.dart';
import 'package:aetherStream/feature/search/xtream_catalog_parser.dart';

const String _dir = 'lib/iptv_exemple';
const List<String> _json = [
  'PLATINIUM_vod_cache.json',
  'PREMIUM_vod_cache.json',
  'VOD_vod_cache.json',
  'xenoIptv.json',
];
const List<String> _m3u = ['playlist_racine_2025-12.m3u', 'VOD_get.m3u'];

final String _nl = String.fromCharCode(10);

/// Les séries d'un dump, sous un `accountId` = nom du dump. Les stubs des
/// dumps n'ont ni hôte ni identifiants (`/series///<id>`) : on les préfixe du
/// nom du dump pour que deux listes ne partagent jamais une URL.
Future<List<M3uEntry>> _seriesOf(String name) async {
  final films = <M3uEntry>[], series = <M3uEntry>[], tv = <M3uEntry>[];
  final String path = '$_dir/$name';
  if (name.endsWith('.json')) {
    await XtreamCatalogParser.parseFile(path, films, series, tv,
        accountId: name);
  } else {
    await M3uParser.parseFile(path, films, series, tv, accountId: name);
  }
  return [
    for (final M3uEntry e in series)
      M3uEntry(
        url: 'http://$name${e.url}',
        type: e.type,
        title: e.title,
        accountId: e.accountId,
        tmdbId: e.tmdbId,
      ),
  ];
}

/// Les groupes de l'accueil, par clé (alias TMDB compris), puis le filtre
/// d'année de la fiche appliqué depuis la TÊTE (ce que reçoit `DetailsPage`).
List<List<M3uEntry>> _fiches(Iterable<M3uEntry> series) {
  final Map<String, List<M3uEntry>> byKey = {};
  for (final M3uEntry e in series) {
    byKey.putIfAbsent(contentGroupKey(e), () => []).add(e);
  }
  return [for (final List<M3uEntry> g in byKey.values) entriesOfTitle(g, g.first)];
}

String _titles(Iterable<M3uEntry> es) =>
    es.map((e) => e.title.rawTitle).take(5).join('  //  ');

/// §seasonMerge — un marqueur de saison dans un NOM de série (pas `SxxExx`,
/// que le parseur sait déjà lire comme un épisode).
final RegExp _seasonWord = RegExp(
  r'(^|[^\p{L}])(s|saison|saisons|season|seasons|temporada|staffel|stagione|seizoen)\s*0*\d{1,2}([^\p{L}\p{N}]|$)',
  caseSensitive: false,
  unicode: true,
);

/// `AS_MEASURE_ALL=1` : tous les exemples au lieu des huit premiers.
final int _ex = Platform.environment['AS_MEASURE_ALL'] == '1' ? 1 << 20 : 8;

bool get _anyDump =>
    [..._json, ..._m3u].any((n) => File('$_dir/$n').existsSync());

void main() {
  test('§22.1 + §seasonMerge — mesure sur les dumps réels', () async {
    final Map<String, List<M3uEntry>> perDump = {};
    for (final String n in [..._json, ..._m3u]) {
      if (!File('$_dir/$n').existsSync()) continue;
      perDump[n] = await _seriesOf(n);
    }
    final StringBuffer out = StringBuffer();
    void say(String s) => out.writeln(s);

    // ── 1. Plusieurs stubs d'une même liste ────────────────────────────────
    say('── §22.1 : plusieurs stubs d\'une MÊME liste pour un titre ──');
    for (final String n in _json) {
      final List<M3uEntry>? series = perDump[n];
      if (series == null) continue;
      TmdbGroupAliasService.rebuild(series); // une liste seule chargée
      final List<List<M3uEntry>> fiches = _fiches(series);
      int multi = 0, before = 0, after = 0, max = 0;
      int bySig = 0, byTmdb = 0, byCap = 0, sameSigSameTmdb = 0;
      final List<String> gained = [], skippedSig = [], skippedTmdb = [];
      final List<String> seasonSplitCandidates = [];
      final Map<int, int> sizes = {};
      final Map<String, int> shapes = {};
      final Map<String, List<String>> shapeEx = {};
      for (final List<M3uEntry> f in fiches) {
        final List<M3uEntry> stubs = f.where(isSeriesStubEntry).toList();
        if (stubs.length < 2) continue;
        multi++;
        before += 1; // une seule liste : un stub interrogé
        final List<M3uEntry> fetched = seriesStubsToFetch(f);
        final List<M3uEntry> uncapped =
            seriesStubsToFetch(f, maxPerAccount: 1 << 20);
        after += fetched.length;
        byCap += uncapped.length - fetched.length;
        sizes.update(uncapped.length, (v) => v + 1, ifAbsent: () => 1);
        if (uncapped.length > max) max = uncapped.length;
        if (fetched.length > 1 && gained.length < _ex) {
          gained.add(fetched
              .map((e) => '${e.title.rawTitle} [tmdb ${e.tmdbId ?? '-'}]')
              .join('  //  '));
        }
        for (final M3uEntry x in fetched.skip(1)) {
          final M3uEntry p = fetched.first;
          final String shape = x.title.groupKey != p.title.groupKey
              ? 'autre nom (alias TMDB)'
              : x.title.year == p.title.year
                  ? 'même nom, même année'
                  : (x.title.year == null || p.title.year == null)
                      ? 'même nom, une année absente'
                      : 'même nom, années différentes';
          shapes.update(shape, (v) => v + 1, ifAbsent: () => 1);
          if (shape != 'même nom, même année' &&
              (shapeEx[shape] ??= []).length < _ex) {
            shapeEx[shape]!.add('${p.title.rawTitle}  +  ${x.title.rawTitle}');
          }
        }
        final Set<String> kept = fetched.map((e) => e.url).toSet();
        final String sig0 = versionSignature(fetched.first.title);
        final String? t0 = fetched.first.tmdbId;
        for (final M3uEntry s in stubs) {
          if (kept.contains(s.url)) continue;
          final bool sameSig = fetched.any(
              (k) => versionSignature(k.title) == versionSignature(s.title));
          if (sameSig) {
            bySig++;
            if (skippedSig.length < _ex) {
              skippedSig.add('${_titles([fetched.first])}  ≡  ${s.title.rawTitle}');
            }
            if (t0 != null && t0 == s.tmdbId && sig0 == versionSignature(s.title)) {
              sameSigSameTmdb++;
              if (seasonSplitCandidates.length < _ex) {
                seasonSplitCandidates
                    .add('${fetched.first.title.rawTitle}  ≡  ${s.title.rawTitle}');
              }
            }
          } else if (!uncapped.any((u) => u.url == s.url)) {
            byTmdb++;
            if (skippedTmdb.length < _ex) {
              skippedTmdb.add('${_titles([fetched.first])}  ≠  ${s.title.rawTitle}');
            }
          }
        }
      }
      say('$n : ${fiches.length} titres de série, $multi avec ≥ 2 stubs '
          '(${(100 * multi / (fiches.isEmpty ? 1 : fiches.length)).toStringAsFixed(1)} %)');
      say('   stubs interrogés : avant $before, maintenant $after '
          '(+${after - before}) ; écartés : signature déjà vue $bySig '
          '(dont même TMDB $sameSigSameTmdb), autre série probable (année, nom ou '
          'TMDB) $byTmdb, '
          'plafond $byCap ; stubs utiles par titre ${Map.fromEntries(sizes.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))}, max $max');
      say('   stubs AJOUTÉS, par forme : $shapes');
      for (final MapEntry<String, List<String>> e in shapeEx.entries) {
        for (final String g in e.value) {
          say('   ${e.key} : $g');
        }
      }
      for (final String g in gained) {
        say('   + $g');
      }
      for (final String g in skippedSig) {
        say('   = $g');
      }
      for (final String g in skippedTmdb) {
        say('   ≠ $g');
      }
      for (final String g in seasonSplitCandidates) {
        say('   ? même nom, même TMDB : $g');
      }
    }

    // ── 2. Titres mixtes, toutes listes chargées ───────────────────────────
    say('── §22.1 : toutes les listes ensemble (le cas R45) ──');
    final List<M3uEntry> all = [for (final l in perDump.values) ...l];
    TmdbGroupAliasService.rebuild(all);
    final List<List<M3uEntry>> fiches = _fiches(all);
    int mixed = 0, multiAccountStubs = 0, m3uOnly = 0, stubOnly = 0;
    final List<String> mixedEx = [];
    for (final List<M3uEntry> f in fiches) {
      final bool hasStub = f.any(isSeriesStubEntry);
      final bool hasEp = f.any((e) => e.title.isSeriesEpisode);
      if (hasStub && hasEp) {
        mixed++;
        if (mixedEx.length < 6) {
          mixedEx.add('${f.first.title.baseTitle} — '
              '${f.map((e) => e.accountId).toSet().join(', ')}');
        }
      } else if (hasStub) {
        stubOnly++;
      } else if (hasEp) {
        m3uOnly++;
      }
      final Set<String> stubAccounts =
          f.where(isSeriesStubEntry).map((e) => e.accountId).toSet();
      if (stubAccounts.length >= 2) multiAccountStubs++;
    }
    say('${fiches.length} titres : mixtes (stubs + épisodes M3U) $mixed, '
        'stubs seuls $stubOnly, épisodes M3U seuls $m3uOnly ; '
        'stubs de ≥ 2 listes $multiAccountStubs');
    for (final String g in mixedEx) {
      say('   ~ $g');
    }

    // ── 3. §seasonMerge — séries éclatées par saison ───────────────────────
    say('── §seasonMerge : un marqueur de saison dans le NOM de la série ──');
    for (final MapEntry<String, List<M3uEntry>> d in perDump.entries) {
      final Map<String, M3uEntry> hits = {};
      for (final M3uEntry e in d.value) {
        if (_seasonWord.hasMatch(e.title.baseTitle)) {
          hits.putIfAbsent(e.title.groupKey, () => e);
        }
      }
      final Set<String> keys = d.value.map((e) => e.title.groupKey).toSet();
      say('${d.key} : ${keys.length} clés de série, ${hits.length} avec un '
          'marqueur de saison dans le nom');
      for (final M3uEntry e in hits.values.take(12)) {
        say('   s ${e.title.rawTitle}  →  « ${e.title.baseTitle} »');
      }
    }
    // Même identifiant TMDB sous des clés différentes d'une même liste : la
    // forme que prend une série éclatée par saison SOUS UN AUTRE NOM
    // (« Koh-Lanta Fidji », « Koh-Lanta Cambodge »…). §tmdbMerge les réunit à
    // l'accueil — SAUF si leurs années divergent (garde-fou d'un identifiant
    // douteux) : ce sont celles-là qui restent éclatées.
    for (final String n in _json) {
      final List<M3uEntry>? series = perDump[n];
      if (series == null) continue;
      final Map<String, Set<String>> keysByTmdb = {};
      final Map<String, Set<String>> yearsByTmdb = {};
      final Map<String, String> sample = {};
      for (final M3uEntry e in series) {
        final String? id = e.tmdbId;
        if (id == null || id.isEmpty || id == '0') continue;
        keysByTmdb.putIfAbsent(id, () => {}).add(e.title.groupKey);
        final String? y = e.title.year;
        if (y != null) yearsByTmdb.putIfAbsent(id, () => {}).add(y);
        sample.putIfAbsent('$id|${e.title.groupKey}', () => e.title.rawTitle);
      }
      final List<MapEntry<String, Set<String>>> split =
          keysByTmdb.entries.where((e) => e.value.length >= 2).toList();
      final List<MapEntry<String, Set<String>>> apart = split
          .where((e) => (yearsByTmdb[e.key]?.length ?? 0) > 1)
          .toList();
      say('$n : ${keysByTmdb.length} identifiants TMDB de série, '
          '${split.length} portés par ≥ 2 noms différents, dont '
          '${apart.length} aux années divergentes (restent ÉCLATÉS sur l’accueil)');
      for (final MapEntry<String, Set<String>> e in split.take(_ex)) {
        say('   t ${e.value.map((k) => sample['${e.key}|$k']).join('  //  ')}');
      }
      for (final MapEntry<String, Set<String>> e in apart.take(_ex)) {
        say('   T ${e.value.map((k) => sample['${e.key}|$k']).join('  //  ')}');
      }
    }
    // Les saisons annoncées par xenoIptv (champ `seasons`, le seul dump qui
    // le porte) pour les stubs d'un même titre : des saisons DISJOINTES
    // seraient une série éclatée sous un même nom.
    final File xeno = File('$_dir/xenoIptv.json');
    final List<M3uEntry>? xenoSeries = perDump['xenoIptv.json'];
    if (xeno.existsSync() && xenoSeries != null) {
      final Map<String, dynamic> raw =
          jsonDecode(xeno.readAsStringSync()) as Map<String, dynamic>;
      final Map<int, Set<int>> seasonsOf = {};
      for (final Object? it in raw['series'] as List? ?? const []) {
        if (it is! Map) continue;
        final int? id = int.tryParse('${it['series_id']}');
        if (id == null) continue;
        final Object? s = it['seasons'];
        seasonsOf[id] = {
          if (s is List)
            for (final Object? x in s)
              if (x is Map && x['season_number'] is int) x['season_number'] as int,
          if (s is Map)
            for (final Object? k in s.keys)
              if (int.tryParse('$k') != null) int.parse('$k'),
        };
      }
      TmdbGroupAliasService.rebuild(xenoSeries);
      int same = 0, disjoint = 0, partial = 0, emptySide = 0;
      final List<String> disjointEx = [];
      for (final List<M3uEntry> f in _fiches(xenoSeries)) {
        final List<M3uEntry> stubs = f.where(isSeriesStubEntry).toList();
        if (stubs.length < 2) continue;
        final List<Set<int>> sets = [
          for (final M3uEntry s in stubs) seasonsOf[seriesIdFromUrl(s.url)] ?? <int>{},
        ];
        if (sets.any((s) => s.isEmpty)) {
          emptySide++;
        } else if (sets.every((s) => s.length == sets.first.length && s.containsAll(sets.first))) {
          same++;
        } else {
          bool anyOverlap = false;
          for (int i = 0; i < sets.length; i++) {
            for (int j = i + 1; j < sets.length; j++) {
              if (sets[i].intersection(sets[j]).isNotEmpty) anyOverlap = true;
            }
          }
          if (anyOverlap) {
            partial++;
          } else {
            disjoint++;
            if (disjointEx.length < _ex) {
              disjointEx.add([
                for (int i = 0; i < stubs.length; i++)
                  '${stubs[i].title.rawTitle} ${sets[i].toList()..sort()}',
              ].join('  //  '));
            }
          }
        }
      }
      say('xenoIptv.json, saisons annoncées des titres à ≥ 2 stubs : mêmes '
          'saisons $same, chevauchement partiel $partial, DISJOINTES $disjoint, '
          'un stub sans saison $emptySide');
      for (final String g in disjointEx) {
        say('   d $g');
      }
    }

    TmdbGroupAliasService.resetForTest();
    // ignore: avoid_print
    print(out.toString().split(_nl).join(_nl));
    expect(perDump, isNotEmpty);
  },
      skip: _anyDump ? false : 'dumps absents (lib/iptv_exemple/)',
      timeout: const Timeout(Duration(minutes: 15)));
}
