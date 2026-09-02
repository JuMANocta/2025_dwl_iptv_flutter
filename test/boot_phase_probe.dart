// §bootPercent — Où partent VRAIMENT les 16 secondes d'« analyse du catalogue » ?
//
// Usage : flutter test test/boot_phase_probe.dart
//
// ⚠️ **Ce n'est PAS un test** — c'est une SONDE DE MESURE, et c'est pour ça que
// le nom ne finit pas par `_test.dart` : `flutter test` ne la ramasse donc pas
// avec la suite. Elle a besoin des dumps réels de `lib/iptv_exemple/`, qui ne
// sont pas versionnés ; sur une machine qui ne les a pas, elle s'annonce et ne
// mesure rien plutôt que d'échouer.
//
// ⚠️ Elle vit sous le harnais de test et non dans `tool/` parce que le parseur
// importe `package:flutter/foundation.dart` (`compute`, `debugPrint`) : sous
// `dart run`, la compilation casse sur les types de `dart:ui`.
//
// ── Ce qu'elle répond ────────────────────────────────────────────────────────
//
// Le pourcentage de boot est un mensonge (0,05 puis 1,0, avec 16 s d'immobilité
// entre les deux) parce que tout le travail vit dans un `compute()` qui ne rend
// rien avant d'avoir fini. Avant de choisir COMMENT le rendre honnête, il faut
// savoir ce qui coûte : la lecture du fichier, le décodage JSON, ou la
// construction des entrées.
//
// Elle compare aussi deux façons de décoder :
//   A. l'actuelle — `readAsBytesSync()` puis `convert()` en un bloc : rapide,
//      mais AUCUNE progression n'est observable et les 64 Mo d'octets restent
//      vivants pendant tout le décodage ;
//   B. la candidate — `openRead()` + `startChunkedConversion` : la progression
//      suit les octets réellement consommés (elle ne peut donc pas mentir), et
//      le tampon d'octets ne dépasse jamais un chunk.
//
// ⚠️ B n'a d'intérêt que si son surcoût est faible. Le décodeur fusionné
// UTF-8+JSON emprunte le parseur Dart dans les DEUX cas (le `_parseJson` natif
// est réservé à l'entrée String) — l'hypothèse est donc qu'ils sont proches,
// mais une hypothèse n'est pas une mesure.
//
// ⚠️ Chaque phase vit dans sa PROPRE fonction et ne renvoie que des nombres :
// garder deux graphes d'objets d'un catalogue de 64 Mo vivants en même temps
// mesurerait la pression du ramasse-miettes, pas le décodage.
//
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/feature/search/xtream_catalog_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Les dumps réels, du plus gros au plus petit. Le premier est celui qui a
/// produit les 16,2 s mesurées sur le téléviseur.
const _candidates = <String>[
  'lib/iptv_exemple/PLATINIUM_vod_cache.json',
  'lib/iptv_exemple/xenoIptv.json',
  'lib/iptv_exemple/VOD_vod_cache.json',
];

void main() {
  test('§bootPercent — répartition du travail de parsing', () async {
    final path = _candidates.firstWhere(
      (p) => File(p).existsSync(),
      orElse: () => '',
    );
    if (path.isEmpty) {
      print('⏭️  Aucun dump dans lib/iptv_exemple/ (non versionnés) — '
          'rien à mesurer.');
      return;
    }

    final file = File(path);
    final int size = file.lengthSync();
    print('\n📦 $path — ${(size / 1024 / 1024).toStringAsFixed(1)} Mo\n');

    final a = _measureOneShot(file);
    print('A. bloc unique  (readAsBytesSync + convert)');
    print('   lecture disque   ${_ms(a.readMs)}');
    print('   décodage JSON    ${_ms(a.decodeMs)}');
    print('   → live=${a.live} vod=${a.vod} series=${a.series} '
        '(total ${a.live + a.vod + a.series})\n');

    final b = await _measureChunked(file, size);
    print('B. chunked  (openRead + startChunkedConversion)');
    print('   lecture+décodage ${_ms(b.totalMs)}');
    print('   paliers de progression observables : ${b.buckets}');
    print('   → live=${b.live} vod=${b.vod} series=${b.series}\n');

    // Garde-fou : une progression observable ne vaut rien si elle décode faux.
    expect(b.live, a.live, reason: 'chunked doit décoder le même contenu');
    expect(b.vod, a.vod, reason: 'chunked doit décoder le même contenu');
    expect(b.series, a.series, reason: 'chunked doit décoder le même contenu');

    final int aTotal = a.readMs + a.decodeMs;
    final double delta = (b.totalMs - aTotal) / aTotal * 100;
    print('   surcoût de B vs A : ${delta >= 0 ? '+' : ''}'
        '${delta.toStringAsFixed(1)} %\n');

    final int full = await _measureParseFile(path);
    print('C. parseFile complet (isolate + transfert du résultat) ${_ms(full)}\n');

    final int build = (full - aTotal).clamp(0, full);
    print('📊 Répartition du travail de l\'isolate :');
    _bar('lecture disque', a.readMs, full);
    _bar('décodage JSON', a.decodeMs, full);
    _bar('construction entrées', build, full);
    print('\n→ Poids pour la barre : lecture+décodage = '
        '${(aTotal / full * 100).toStringAsFixed(0)} %, '
        'construction = ${(build / full * 100).toStringAsFixed(0)} %');
    print('⚠️ « construction » inclut le transfert du résultat hors isolate.\n');
  }, timeout: const Timeout(Duration(minutes: 10)));
}

typedef _OneShot = ({int readMs, int decodeMs, int live, int vod, int series});

/// Mesure A. Ne renvoie que des nombres → le graphe d'objets est collectable
/// dès le retour.
_OneShot _measureOneShot(File file) {
  final swRead = Stopwatch()..start();
  final bytes = file.readAsBytesSync();
  swRead.stop();

  final swDecode = Stopwatch()..start();
  final data = const Utf8Decoder().fuse(const JsonDecoder()).convert(bytes)
      as Map<String, dynamic>;
  swDecode.stop();

  return (
    readMs: swRead.elapsedMilliseconds,
    decodeMs: swDecode.elapsedMilliseconds,
    live: (data['live'] as List? ?? const []).length,
    vod: (data['vod'] as List? ?? const []).length,
    series: (data['series'] as List? ?? const []).length,
  );
}

typedef _Chunked = ({int totalMs, int buckets, int live, int vod, int series});

/// Mesure B — c'est le chemin candidat pour §bootPercent : la progression est
/// dérivée des octets réellement consommés, donc elle ne peut pas mentir.
Future<_Chunked> _measureChunked(File file, int size) async {
  final sw = Stopwatch()..start();
  Object? decoded;
  final outSink = ChunkedConversionSink<Object?>.withCallback(
    (chunks) => decoded = chunks.single,
  );
  final byteSink = const Utf8Decoder()
      .fuse(const JsonDecoder())
      .startChunkedConversion(outSink);

  int read = 0;
  int buckets = 0;
  int lastBucket = -1;
  await for (final chunk in file.openRead()) {
    byteSink.add(chunk);
    read += chunk.length;
    final bucket = (read / size * 100).round();
    if (bucket != lastBucket) {
      lastBucket = bucket;
      buckets++;
    }
  }
  byteSink.close();
  sw.stop();

  final data = decoded as Map<String, dynamic>;
  return (
    totalMs: sw.elapsedMilliseconds,
    buckets: buckets,
    live: (data['live'] as List? ?? const []).length,
    vod: (data['vod'] as List? ?? const []).length,
    series: (data['series'] as List? ?? const []).length,
  );
}

/// Mesure C — le parseur réel, isolate compris, pour connaître le total.
Future<int> _measureParseFile(String path) async {
  final films = <M3uEntry>[];
  final series = <M3uEntry>[];
  final tv = <M3uEntry>[];
  final sw = Stopwatch()..start();
  await XtreamCatalogParser.parseFile(
    path,
    films,
    series,
    tv,
    accountId: 'probe',
  );
  sw.stop();
  return sw.elapsedMilliseconds;
}

String _ms(int ms) => '${ms.toString().padLeft(6)} ms';

void _bar(String label, int ms, int total) {
  final pct = total == 0 ? 0.0 : ms / total * 100;
  final filled = (pct / 2.5).round().clamp(0, 40);
  print('   ${label.padRight(22)} ${'█' * filled}${'·' * (40 - filled)} '
      '${pct.toStringAsFixed(1).padLeft(5)} %  ($ms ms)');
}
