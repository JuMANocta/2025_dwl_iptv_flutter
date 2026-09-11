import 'dart:convert';
import 'dart:io';

import 'package:aetherStream/data/services/xtream_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Revue 2026-09-11, D1A-12 — `writeJsonMapChunked` doit écrire, octet pour
/// octet, ce qu'écrivait `writeAsString(jsonEncode(payload), flush: true)` :
/// le fichier catalogue est relu par `XtreamCatalogParser`, et son contenu
/// ne doit pas bouger d'un octet.
///
/// ⚠️ Caractères spéciaux construits par `String.fromCharCode`, jamais par
/// séquence d'échappement (la couche outil les décode).
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('catalog_writer_');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> expectSameBytes(Map<String, Object?> payload) async {
    final String path = '${dir.path}/playlist.json.part';
    await writeJsonMapChunked(path, payload);
    final List<int> written = File(path).readAsBytesSync();
    final List<int> expected = utf8.encode(jsonEncode(payload));
    expect(written.length, expected.length);
    expect(written, equals(expected));
  }

  final String quote = String.fromCharCode(34);
  final String backslash = String.fromCharCode(92);
  final String newline = String.fromCharCode(10);
  final String tab = String.fromCharCode(9);
  final String ctrl = String.fromCharCode(1);

  Map<String, Object?> item(int i) => <String, Object?>{
        'num': i,
        'name': 'Film $i ${quote}cité$quote $backslash chemin',
        'stream_type': 'movie',
        'stream_id': i * 3,
        'stream_icon': i % 4 == 0 ? null : 'https://image.tmdb.org/t/p/w600/$i.jpg',
        'rating': i % 5 == 0 ? 0 : 7.357,
        'rating_5based': 3.7,
        'added': '${1700000000 + i}',
        'category_id': '${i % 50}',
        'container_extension': 'mkv',
        'plot': 'Ligne 1${newline}Ligne 2${tab}tab $ctrl — été 😀 中文 العربية',
        'backdrop_path': <Object?>['https://img/$i-a.jpg', null, i],
        'nested': <String, Object?>{'a': true, 'b': false, 'c': <Object?>[]},
        '_cat': 'Films | Action ( NETFLIX| PRIME )',
      };

  test('petit catalogue : mêmes octets que jsonEncode', () async {
    await expectSameBytes(<String, Object?>{
      'v': 1,
      'host': 'http://panel.test:8080',
      'user': 'user${quote}x',
      'pass': 'p${backslash}a/ss',
      'live': <Map<String, Object?>>[item(1), item(2)],
      'vod': <Map<String, Object?>>[item(3)],
      'series': <Map<String, Object?>>[],
    });
  });

  test('gros catalogue (plusieurs tranches) : mêmes octets', () async {
    await expectSameBytes(<String, Object?>{
      'v': 1,
      'host': 'http://panel.test',
      'user': 'u',
      'pass': 'p',
      'live': <Map<String, Object?>>[for (int i = 0; i < 1500; i++) item(i)],
      'vod': <Map<String, Object?>>[for (int i = 0; i < 3000; i++) item(i)],
      'series': <Map<String, Object?>>[for (int i = 0; i < 700; i++) item(i)],
    });
  });

  test('objet vide, valeurs non-listes, listes vides', () async {
    await expectSameBytes(<String, Object?>{});
    await expectSameBytes(<String, Object?>{
      'a': null,
      'b': 2.5,
      'c': 'x',
      'd': <Object?>[],
      'e': <String, Object?>{'k': <Object?>[1, 2]},
    });
  });

  test('un fichier plus long est bien TRONQUÉ (mode écriture)', () async {
    final String path = '${dir.path}/playlist.json.part';
    File(path).writeAsStringSync('z' * 100000);
    final Map<String, Object?> payload = <String, Object?>{
      'v': 1,
      'live': <Object?>[1],
    };
    await writeJsonMapChunked(path, payload);
    expect(File(path).readAsStringSync(), jsonEncode(payload));
  });

  // Relecture lot 8a — Les DEMI-SURROGATES. Un panel qui écrit `\ud83d`
  // sans sa moitié (troncature PHP d'un emoji) donne, une fois décodé, une
  // chaîne Dart qui contient un demi-surrogate isolé. `jsonEncode` le rend
  // par la séquence d'échappement `\udXXX` ; `JsonUtf8Encoder` doit faire
  // exactement pareil, et non le remplacer par U+FFFD comme le ferait un
  // encodage UTF-8 direct. C'était le seul cas où les deux encodeurs
  // POUVAIENT diverger.
  test('demi-surrogates isolés, paires valides, bords de chaîne : mêmes '
      'octets', () async {
    final String lead = String.fromCharCode(0xD83D);
    final String trail = String.fromCharCode(0xDE00);
    final String pair = String.fromCharCodes(<int>[0xD83D, 0xDE00]);
    await expectSameBytes(<String, Object?>{
      'v': 1,
      'k$lead': 'clé avec un demi-surrogate',
      'live': <Object?>[
        '${lead}début',
        'fin$lead',
        '${trail}début',
        'fin$trail',
        'milieu${lead}x${trail}y',
        'inversés$trail$lead',
        'paire$pair',
        <String, Object?>{'name': 'Film $lead', 'plot': '$trail$pair$lead'},
        lead,
        trail,
      ],
    });
  });
}
