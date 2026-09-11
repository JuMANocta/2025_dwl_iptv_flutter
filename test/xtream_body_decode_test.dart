import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aetherStream/data/services/xtream_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Revue 2026-09-11, D1A-12 — `decodeXtreamBody` (octets → corps) doit rendre
/// EXACTEMENT ce que rendait l'ancien chemin de `XtreamApiService._fetch` :
/// Dio en `ResponseType.plain`, puis `jsonDecode`, puis le texte tronqué à
/// 500 caractères si ce n'était pas du JSON.
///
/// Relecture lot 8a — La référence ne RECOPIE plus ce que Dio est censé faire
/// (`utf8.decode(…, allowMalformed: true)`) : elle passe les octets par le
/// VRAI transformateur de Dio (`FusedTransformer`, celui que `Dio()` installe
/// par défaut — aucun `transformer`/`responseDecoder` n'est posé dans l'app),
/// avec l'en-tête `application/json` qu'envoient les panels, puis par le code
/// d'origine de `_fetch`. Une recopie aurait prouvé l'équivalence avec une
/// hypothèse, pas avec l'ancien chemin.
///
/// ⚠️ Les octets « tordus » sont écrits en NOMBRES, jamais en séquences
/// d'échappement dans des littéraux (la couche outil les décode).
Future<Object?> legacyDecode(Uint8List bytes) async {
  final Object? plain = await FusedTransformer(
    contentLengthIsolateThreshold: 50 * 1024,
  ).transformResponse(
    RequestOptions(path: '/player_api.php', responseType: ResponseType.plain),
    ResponseBody.fromBytes(bytes, 200, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>['application/json'],
    }),
  );
  // Code d'origine de `_fetch` (base a2a4d07), à l'identique.
  final String raw = (plain as String?) ?? '';
  if (raw.isEmpty) return null;
  try {
    return jsonDecode(raw);
  } catch (_) {
    return raw.length > 500 ? raw.substring(0, 500) : raw;
  }
}

Uint8List b(List<Object> parts) {
  final List<int> out = <int>[];
  for (final Object p in parts) {
    if (p is String) {
      out.addAll(utf8.encode(p));
    } else if (p is int) {
      out.add(p);
    } else if (p is List<int>) {
      out.addAll(p);
    }
  }
  return Uint8List.fromList(out);
}

void main() {
  const int bomA = 0xEF, bomB = 0xBB, bomC = 0xBF;
  final Map<String, Uint8List> cases = <String, Uint8List>{
    'vide': Uint8List(0),
    'BOM seul': b(<Object>[bomA, bomB, bomC]),
    'BOM + espace': b(<Object>[bomA, bomB, bomC, ' ']),
    'BOM + liste': b(<Object>[bomA, bomB, bomC, '[1,"a"]']),
    'null JSON': b(<Object>['null']),
    'liste vide': b(<Object>['[]']),
    'objet vide': b(<Object>['{}']),
    'bloc d\'auth': b(<Object>['{"user_info":{"auth":0}}']),
    'HTML': b(<Object>['<html><body>Too many connections</body></html>']),
    'texte Latin-1': b(<Object>['Tr', 0xE8, 's']),
    'Latin-1 dans une chaîne': b(<Object>['[{"name":"caf', 0xE9, '"}]']),
    'séquence tronquée avant guillemet':
        b(<Object>['["a', 0xC3, '"]']),
    'FF FE dans une chaîne': b(<Object>['["', 0xFF, 0xFE, '"]']),
    'surlong': b(<Object>['["', 0xC0, 0xAF, '"]']),
    'demi-surrogate encodé': b(<Object>['["', 0xED, 0xA0, 0x80, 'x"]']),
    '4 octets tronqués': b(<Object>['["', 0xF0, 0x9F, 0x98, '"]']),
    'continuation orpheline': b(<Object>['["', 0x80, 0x80, '"]']),
    'tronqué en fin': b(<Object>['["a', 0xC3]),
    'invalide hors chaîne': b(<Object>['[1,', 0xFF, '2]']),
    'invalide dans une clé': b(<Object>['{"k', 0xE9, '":1}']),
    'BOM au milieu': b(<Object>['["a', bomA, bomB, bomC, 'b"]']),
    'contrôle C1': b(<Object>['["a', 0xC2, 0x85, '"]']),
    'NUL brut': b(<Object>['["a', 0x00, '"]']),
    'unicode': b(<Object>['["😀 é ß 中 العربية"]']),
    'nombres': b(<Object>['[1.50,-0,1e3,12345678901234567890,0.1,true,false]']),
    'espaces autour': b(<Object>['  ', 10, ' [ ] ', 9, ' ']),
    'déchet final': b(<Object>['[1] x']),
    'texte long (> 500)': b(<Object>['<html>${'x' * 900}</html>']),
  };

  group('decodeXtreamBody ≡ ancien chemin (Dio plain + jsonDecode)', () {
    cases.forEach((String name, Uint8List bytes) {
      test(name, () async {
        final Object? expected = await legacyDecode(bytes);
        expect(decodeXtreamBody(bytes), equals(expected));
        // Et par le chemin de `_fetch` (sur place : ce sont de petits corps).
        expect(await XtreamApiService.decodeBody(bytes), equals(expected));
      });
    });
  });

  test('catalogue synthétique > 50 Ko : identique, aller-retour RÉEL par '
      'l\'isolate', () async {
    final List<Map<String, Object?>> items = <Map<String, Object?>>[
      for (int i = 0; i < 2000; i++)
        <String, Object?>{
          'stream_id': i,
          'name': '|FR| Film n°$i — ${i.isEven ? 'Été' : 'Noël'}',
          'category_id': '${i % 37}',
          'rating': i / 7,
          'stream_icon': i % 3 == 0 ? null : 'http://img.test/$i.jpg',
          'backdrop_path': <String>['a$i', 'b$i'],
        },
    ];
    final Uint8List bytes = Uint8List.fromList(utf8.encode(jsonEncode(items)));
    expect(bytes.length, greaterThan(50 * 1024));
    final String expected = jsonEncode(await legacyDecode(bytes));
    expect(jsonEncode(decodeXtreamBody(bytes)), expected);
    final FutureOr<Object?> viaFetch = XtreamApiService.decodeBody(bytes);
    expect(viaFetch, isA<Future<Object?>>(),
        reason: 'au-delà de 50 Ko, le décodage doit partir dans un isolate');
    expect(jsonEncode(await viaFetch), expected);
  });

  test('corps > 50 Ko qui n\'est PAS du JSON : texte tronqué, par l\'isolate',
      () async {
    final Uint8List bytes =
        b(<Object>['<html>', 'x' * (60 * 1024), 0xFF, '</html>']);
    final Object? expected = await legacyDecode(bytes);
    expect(expected, isA<String>());
    expect((expected as String).length, 500);
    expect(await XtreamApiService.decodeBody(bytes), expected);
  });

  // Les catalogues réels (non versionnés) : un clone frais les saute.
  const String dumps = 'lib/iptv_exemple';
  for (final String name in <String>[
    'PLATINIUM_vod_cache.json',
    'PREMIUM_vod_cache.json',
    'VOD_vod_cache.json',
    'xenoIptv.json',
  ]) {
    final File f = File('$dumps/$name');
    test('dump réel — $name : identique (par l\'isolate)', () async {
      final Uint8List bytes = f.readAsBytesSync();
      final String expected = jsonEncode(await legacyDecode(bytes));
      expect(jsonEncode(await XtreamApiService.decodeBody(bytes)), expected);
    }, skip: f.existsSync() ? false : 'dump absent ($name)');
  }
}
