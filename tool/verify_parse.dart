// Script de vérification non-régression du parsing M3U (§Ultimate).
// Outil CLI de dev → print() est volontaire (pas de framework de log ici).
// ignore_for_file: avoid_print
// Lance : dart run tool/verify_parse.dart
//
// Pour chaque playlist d'exemple : reproduit EXACTEMENT la classification de
// `m3u_parser._addEntry` (URL /movie/ /series/, sinon SxxExx strict, sinon TV)
// et appelle le vrai `TitleMetadata.parse`. Rapporte :
//   - répartition film / série / TV
//   - nb de séries avec saison+épisode extraits (le gain §Ultimate)
//   - ensemble « à risque » : entrées NON-série contenant un motif NNxNN, avec
//     leur baseTitle résultant (pour vérifier qu'aucun titre film/TV n'est
//     mal classé en série ni son titre mutilé).
import 'dart:convert';
import 'dart:io';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/feature/search/m3u_filter.dart';

final _reGroup = RegExp(r'group-title="([^"]*)"');

// Mêmes patterns que m3u_parser pour la classification.
final _reSerie = RegExp(r'S\s*(\d{1,2})\s*E\s*(\d{1,2})', caseSensitive: false);
final _reNNxNN = RegExp(r'(?<!\d)(\d{1,2})\s*x\s*(\d{1,2})(?!\d)', caseSensitive: false);

int _sepComma(String meta) {
  bool inQuotes = false;
  for (int i = 0; i < meta.length; i++) {
    final c = meta[i];
    if (c == '"') {
      inQuotes = !inQuotes;
    } else if (c == ',' && !inQuotes) {
      return i;
    }
  }
  return -1;
}

Future<void> _analyze(String path) async {
  final name = path.split(RegExp(r'[\\/]')).last;
  int movies = 0, series = 0, tv = 0;
  int seriesWithNums = 0;
  int vodNullCat = 0; // films+séries sans catégorie (→ "Autres")
  final nullCatGroups = <String>{}; // group-titles distincts → null
  final foreignTally = <String, int>{}; // région étrangère → nb d'entrées
  final atRisk = <String>[]; // non-série avec NNxNN → baseTitle
  String? pending;

  final lines = File(path)
      .openRead()
      .transform(utf8.decoder)
      .transform(const LineSplitter());

  await for (final line in lines) {
    final t = line.trim();
    if (t.isEmpty) continue;
    if (t.startsWith('#EXTINF')) {
      pending = t;
    } else if (t.startsWith('http')) {
      if (pending == null) continue;
      final ci = _sepComma(pending);
      final meta = pending;
      pending = null;
      if (ci == -1) continue;
      final rawTitle = meta.substring(ci + 1).trim();
      if (rawTitle.isEmpty) continue;
      final lower = t.toLowerCase();

      // Classification — identique à m3u_parser._addEntry (version corrigée).
      M3uContentType type;
      if (lower.contains('/movie/')) {
        type = M3uContentType.movie;
      } else if (lower.contains('/series/')) {
        type = M3uContentType.series;
      } else if (_reSerie.firstMatch(rawTitle) != null) {
        type = M3uContentType.series;
      } else {
        type = M3uContentType.tv;
      }

      // Catégorisation (films + séries) — null → "Autres" sur la home.
      if (type != M3uContentType.tv) {
        final gt = _reGroup.firstMatch(meta)?.group(1);
        final cat = contentCategoryLabel(gt);
        if (cat == null) {
          vodNullCat++;
          if (gt != null && nullCatGroups.length < 20) nullCatGroups.add(gt);
        } else if (kForeignRegionLabels.contains(cat)) {
          foreignTally[cat] = (foreignTally[cat] ?? 0) + 1;
        }
      }

      if (type == M3uContentType.series) {
        series++;
        final m = TitleMetadata.parse(rawTitle);
        if (m.isSeriesEpisode) seriesWithNums++;
      } else if (type == M3uContentType.movie) {
        movies++;
        if (_reSerie.firstMatch(rawTitle) == null &&
            _reNNxNN.firstMatch(rawTitle) != null &&
            atRisk.length < 40) {
          atRisk.add('[MOVIE] "$rawTitle" → base="${TitleMetadata.parse(rawTitle).baseTitle}"');
        }
      } else {
        tv++;
        if (_reSerie.firstMatch(rawTitle) == null &&
            _reNNxNN.firstMatch(rawTitle) != null &&
            atRisk.length < 40) {
          atRisk.add('[TV]    "$rawTitle" → base="${TitleMetadata.parse(rawTitle).baseTitle}"');
        }
      }
    }
  }

  final total = movies + series + tv;
  final pct = series == 0 ? 0 : (seriesWithNums * 100 / series);
  print('===== $name =====');
  print('  total=$total | films=$movies | séries=$series | TV=$tv');
  print('  séries avec saison+épisode = $seriesWithNums '
      '(${pct.toStringAsFixed(1)}%)');
  final vodTotal = movies + series;
  final catPct = vodTotal == 0 ? 0 : (vodNullCat * 100 / vodTotal);
  print('  films+séries SANS catégorie (→ Autres) = $vodNullCat '
      '(${catPct.toStringAsFixed(1)}%)');
  if (nullCatGroups.isNotEmpty) {
    print('    group-titles non catégorisés (échantillon) :');
    for (final g in nullCatGroups) {
      print('      "$g"');
    }
  }
  if (foreignTally.isNotEmpty) {
    final sorted = foreignTally.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final tot = foreignTally.values.fold(0, (a, b) => a + b);
    print('  films+séries en catégorie RÉGION étrangère (reléguée) = $tot :');
    for (final e in sorted.take(12)) {
      print('      ${e.key} : ${e.value}');
    }
  }
  print('  ── non-série contenant NNxNN (à risque, doivent rester film/TV, '
      'base propre) : ${atRisk.length} ──');
  for (final r in atRisk) {
    print('    $r');
  }
  print('');
}

Future<void> main() async {
  const dir = 'lib/iptv_exemple';
  for (final f in ['Premium_playlist', 'VOD_playlist', 'Ultimate_playlist']) {
    final p = '$dir/$f.m3u';
    if (File(p).existsSync()) {
      await _analyze(p);
    } else {
      print('⚠️  introuvable: $p');
    }
  }
}
