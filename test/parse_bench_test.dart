// §parseSpeed (2026-09-06) — Banc de mesure des DEUX parseurs sur TOUTES les
// listes réelles de `lib/iptv_exemple/` (non versionnées : chaque cas se saute
// si son dump manque). Sous `flutter test` le Dart est JIT — les valeurs
// absolues ne sont pas celles du release, la RÉPARTITION l'est.
//
//   - M3U standard (#EXTINF)  : playlist_racine_2025-12.m3u
//   - M3U « Ultimate » (#Name:) : VOD_get.m3u
//   - catalogues JSON Xtream   : PLATINIUM / PREMIUM / VOD _vod_cache.json, xenoIptv.json
//
// Lancer : flutter test test/parse_bench_test.dart
@Tags(['bench'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/core/utils/string_pool.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/feature/search/m3u_filter.dart';
import 'package:aetherStream/feature/search/m3u_parser.dart';
import 'package:aetherStream/feature/search/xtream_catalog_parser.dart';

const String _dir = 'lib/iptv_exemple';
const List<String> _m3u = ['playlist_racine_2025-12.m3u', 'VOD_get.m3u'];
const List<String> _json = [
  'PLATINIUM_vod_cache.json',
  'PREMIUM_vod_cache.json',
  'VOD_vod_cache.json',
  'xenoIptv.json',
];

void main() {
  for (final String name in _m3u) {
    final String path = '$_dir/$name';
    test('bench M3U — $name', () async {
      final films = <M3uEntry>[], series = <M3uEntry>[], tv = <M3uEntry>[];
      final sw = Stopwatch()..start();
      await M3uParser.parseFile(path, films, series, tv, accountId: 'bench');
      final int total = sw.elapsedMilliseconds;
      final int n = films.length + series.length + tv.length;

      // Les titres seuls, pour isoler `TitleMetadata.parse`.
      sw.reset();
      final List<String> titles = [];
      String? pending;
      for (final line in File(path).readAsLinesSync()) {
        final t = line.trim();
        if (t.startsWith('#EXTINF')) {
          pending = t;
        } else if (t.startsWith('http')) {
          if (pending != null) {
            final i = pending.lastIndexOf(',');
            if (i != -1) titles.add(pending.substring(i + 1).trim());
            pending = null;
          } else {
            final parts = t.split('#Name:');
            if (parts.length > 1) titles.add(parts[1].trim());
          }
        }
      }
      final int tRead = sw.elapsedMilliseconds;

      sw.reset();
      final pool = StringPool();
      int keep = 0;
      TitleMetadata.stageUs.clear();
      TitleMetadata.profileStages = true;
      for (final t in titles) {
        keep += TitleMetadata.parse(t, pool).groupKey.length;
      }
      TitleMetadata.profileStages = false;
      final int tTitle = sw.elapsedMilliseconds;
      final stages = (TitleMetadata.stageUs.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
          .map((e) => '    ${e.key.padRight(26)} ${(e.value / 1000).round()} ms')
          .join(String.fromCharCode(10));

      sw.reset();
      int hiddenCount = 0;
      for (final t in titles) {
        if (isRegionHidden(name: t, groupTitle: null, hidden: const {})) {
          hiddenCount++;
        }
      }
      final int tRegion = sw.elapsedMilliseconds;

      // ignore: avoid_print
      print('''
§parseSpeed M3U — $name : $n entrées (JIT)
  parseFile complet        : $total ms  (${(n / (total / 1000)).round()} entrées/s)
  lecture + découpe lignes : $tRead ms
  TitleMetadata.parse      : $tTitle ms  (${(tTitle * 1000 / titles.length).toStringAsFixed(0)} µs/titre, ${titles.length} titres)
  isRegionHidden           : $tRegion ms
  (keep=$keep hidden=$hiddenCount)
  etapes de TitleMetadata.parse :
$stages''');
      expect(n, greaterThan(1000));
    },
        skip: File(path).existsSync() ? false : 'dump absent ($name)',
        timeout: const Timeout(Duration(minutes: 10)));
  }

  // §parseSpeed — FILET : la sortie du parseur sur chaque titre réel est
  // figée dans build/parse_snapshot_<dump>.tsv au premier passage ; tout
  // passage suivant doit rendre EXACTEMENT la même (base, clé, année,
  // saison/épisode, qualité, langues, libellé de version, marqueur).
  // Supprimer le fichier pour re-figer après un changement VOULU du parsing.
  for (final String name in [..._m3u, ..._json]) {
    final String path = '$_dir/$name';
    test('snapshot — $name', () async {
      final films = <M3uEntry>[], series = <M3uEntry>[], tv = <M3uEntry>[];
      if (name.endsWith('.json')) {
        await XtreamCatalogParser.parseFile(path, films, series, tv,
            accountId: 'snap');
      } else {
        await M3uParser.parseFile(path, films, series, tv, accountId: 'snap');
      }
      final List<M3uEntry> all = [...films, ...series, ...tv];
      String line(M3uEntry e) {
        final t = e.title;
        return [
          t.rawTitle,
          t.baseTitle,
          t.groupKey,
          t.year ?? '',
          '${t.seasonNumber ?? ''}',
          '${t.episodeNumber ?? ''}',
          t.quality ?? '',
          t.languages.join('+'),
          t.versionLabel ?? '',
          t.providerTag ?? '',
          e.type.name,
          e.category ?? '',
        ].join('	');
      }
      final snapFile = File('build/parse_snapshot_$name.tsv');
      final List<String> now = all.map(line).toList();
      if (!snapFile.existsSync()) {
        snapFile.parent.createSync(recursive: true);
        snapFile.writeAsStringSync(now.join(String.fromCharCode(10)));
        // ignore: avoid_print
        print('§parseSpeed — instantané figé : ${snapFile.path} (${now.length} lignes)');
        return;
      }
      final List<String> before = snapFile.readAsStringSync().split(String.fromCharCode(10));
      final diffs = <String>[];
      final int len = now.length < before.length ? now.length : before.length;
      for (var i = 0; i < len && diffs.length < 20; i++) {
        if (now[i] != before[i]) diffs.add('#$i' + String.fromCharCode(10) + '  avant: ${before[i]}' + String.fromCharCode(10) + '  apres: ${now[i]}');
      }
      expect(now.length, before.length, reason: 'nombre d entrées différent');
      expect(diffs, isEmpty, reason: 'sortie du parseur changée :' + String.fromCharCode(10) + diffs.join(String.fromCharCode(10)));
    },
        skip: File(path).existsSync() ? false : 'dump absent ($name)',
        timeout: const Timeout(Duration(minutes: 10)));
  }

  for (final String name in _json) {
    final String path = '$_dir/$name';
    test('bench JSON — $name', () async {
      final films = <M3uEntry>[], series = <M3uEntry>[], tv = <M3uEntry>[];
      final sw = Stopwatch()..start();
      await XtreamCatalogParser.parseFile(path, films, series, tv,
          accountId: 'bench');
      final int total = sw.elapsedMilliseconds;
      final int n = films.length + series.length + tv.length;
      // ignore: avoid_print
      print('''
§parseSpeed JSON — $name : $n entrées (JIT, isolate)
  parseFile complet        : $total ms  (${n == 0 ? 0 : (n / (total / 1000)).round()} entrées/s)''');
      expect(n, greaterThan(0));
    },
        skip: File(path).existsSync() ? false : 'dump absent ($name)',
        timeout: const Timeout(Duration(minutes: 10)));
  }
}
