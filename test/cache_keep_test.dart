// §cacheKeep — Verrous du cache analysé (`parsed_playlist_<id>.json.gz`).
//
// Le défaut réparé, constaté sur les données réelles du téléphone : trois
// catalogues bruts sains sur disque, mais **deux caches analysés seulement**.
// Une liste absente de la mémoire est totalement invisible de l'accueil ET de
// la recherche — sans erreur, sans chip rouge, sans une ligne de journal.
//
// Quatre mécanismes s'y mettaient. Ce fichier verrouille les deux qui vivent
// dans `ParsedPlaylistService` :
//
//   1. **L'écriture n'était pas atomique.** `File(path).openWrite()` écrivait
//      directement sur la destination : une interruption y laissait un `.gz`
//      tronqué, c'est-à-dire un cache qui existe, qu'on relit sans erreur, et
//      qui rend une liste VIDE.
//   2. **Un échec d'analyse ne devait jamais coûter le cache précédent.** Mieux
//      vaut une liste périmée qu'aucune liste.
//
// ⚠️ Le test le plus important du fichier est celui de non-régression : après
// une analyse ratée, le `.json.gz` doit être TOUJOURS LÀ.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/models/parsed_playlist.dart';
import 'package:aetherStream/data/services/parsed_playlist_service.dart';

late Directory _root;
late Directory _docs;
late Directory _support;

/// Fait répondre `path_provider` avec des dossiers temporaires.
void _mockPathProvider() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => switch (call.method) {
      'getApplicationDocumentsDirectory' => _docs.path,
      'getApplicationSupportDirectory' => _support.path,
      _ => null,
    },
  );
}

/// Le fichier SOURCE (`playlist_<id>.json`) : sa date de modification est le
/// juge de fraîcheur du cache, donc il doit exister pour toute relecture.
File _source(String accountId) =>
    File('${_docs.path}/playlist_$accountId.json')
      ..writeAsStringSync('{"v":1}');

M3uEntry _entry(String id, String titre, M3uContentType type) => M3uEntry(
      url: 'http://exemple.test/$id',
      type: type,
      title: TitleMetadata.parse(titre),
      accountId: 'compte1',
    );

ParsedPlaylist _playlist({int films = 3, int series = 2, int tv = 4}) {
  final entries = <M3uEntry>[
    for (var i = 0; i < films; i++)
      _entry('f$i', 'Film $i (2020) FHD', M3uContentType.movie),
    for (var i = 0; i < series; i++)
      _entry('s$i', 'Serie $i S01E0$i', M3uContentType.series),
    for (var i = 0; i < tv; i++) _entry('t$i', 'Chaine $i HD', M3uContentType.tv),
  ];
  return ParsedPlaylist(
    accountId: 'compte1',
    schema: ParsedPlaylist.schemaVersion,
    m3uModifiedAt: DateTime.now(),
    entries: entries,
  );
}

Future<File> _cacheFile(String accountId) async =>
    File(await ParsedPlaylistService.diskCachePathForTest(accountId));

/// Écrit un cache dont l'EN-TÊTE est celui qu'on veut, et le corps celui qu'on
/// veut : c'est le seul moyen de fabriquer un cache tronqué sans dépendre du
/// hasard d'une coupure.
Future<void> _writeRawCache(
  String accountId, {
  required Map<String, dynamic> header,
  List<Map<String, dynamic>> body = const [],
}) async {
  final path = await ParsedPlaylistService.diskCachePathForTest(accountId);
  final buffer = StringBuffer()..writeln(jsonEncode(header));
  for (final line in body) {
    buffer.writeln(jsonEncode(line));
  }
  File(path).writeAsBytesSync(gzip.encode(utf8.encode(buffer.toString())));
}

Map<String, dynamic> _headerOf(ParsedPlaylist p, {int? count}) => {
      'schema': p.schema,
      'accountId': p.accountId,
      'm3uModAt': p.m3uModifiedAt.toIso8601String(),
      'count': count ?? p.entries.length,
      'nFilms': p.films.length,
      'nSeries': p.series.length,
      'nTv': p.tv.length,
      'filterSig': '',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _root = Directory.systemTemp.createTempSync('cachekeep');
    _docs = Directory('${_root.path}/app_flutter')..createSync();
    _support = Directory('${_root.path}/files')..createSync();
    _mockPathProvider();
    ParsedPlaylistService.clear();
  });

  tearDown(() {
    ParsedPlaylistService.clear();
    _root.deleteSync(recursive: true);
  });

  group('Aller-retour écriture → relecture', () {
    test('ce qui est écrit est relu, et le `.part` ne survit pas', () async {
      final src = _source('compte1');
      final p = _playlist();
      await ParsedPlaylistService.saveToDiskForTest('compte1', p);

      final cache = await _cacheFile('compte1');
      expect(cache.existsSync(), isTrue, reason: 'le cache doit être publié');
      expect(File('${cache.path}.part').existsSync(), isFalse,
          reason: 'le fichier temporaire doit avoir été renommé, pas laissé');

      final relu = await ParsedPlaylistService.loadFromDiskForTest(
          'compte1', src.path);
      expect(relu, isNotNull);
      expect(relu!.entries.length, p.entries.length);
      expect(relu.films.length, 3);
      expect(relu.series.length, 2);
      expect(relu.tv.length, 4);
    });

    test('l\'en-tête porte nFilms / nSeries / nTv (§secondaryCounts)', () async {
      _source('compte1');
      await ParsedPlaylistService.saveToDiskForTest('compte1', _playlist());

      final cache = await _cacheFile('compte1');
      final premiere = utf8
          .decode(gzip.decode(cache.readAsBytesSync()))
          .split('\n')
          .first;
      final header = jsonDecode(premiere) as Map<String, dynamic>;

      expect(header['nFilms'], 3);
      expect(header['nSeries'], 2);
      expect(header['nTv'], 4);
      expect(header['count'], 9);
      expect(header['schema'], ParsedPlaylist.schemaVersion);
    });

    test('une réécriture remplace le cache sans passer par un état absent',
        () async {
      final src = _source('compte1');
      await ParsedPlaylistService.saveToDiskForTest('compte1', _playlist());
      final cache = await _cacheFile('compte1');
      final avant = cache.lengthSync();

      await ParsedPlaylistService.saveToDiskForTest(
          'compte1', _playlist(films: 30, series: 20, tv: 40));

      expect(cache.existsSync(), isTrue);
      expect(cache.lengthSync(), greaterThan(avant));
      expect(File('${cache.path}.part').existsSync(), isFalse);

      final relu = await ParsedPlaylistService.loadFromDiskForTest(
          'compte1', src.path);
      expect(relu!.entries.length, 90);
    });
  });

  group('🛑 Non-régression — une analyse ratée ne coûte PAS le cache', () {
    test('le `.json.gz` est toujours là après un échec de rechargement',
        () async {
      final src = _source('compte1');
      await ParsedPlaylistService.saveToDiskForTest('compte1', _playlist());
      final cache = await _cacheFile('compte1');
      final tailleAvant = cache.lengthSync();

      // L'analyse échoue : le fichier source est un JSON que le parseur de
      // catalogue ne sait pas lire. `reloadFromDisk` doit rendre `null`…
      src.writeAsStringSync('ceci n\'est pas un catalogue');
      final res = await ParsedPlaylistService.reloadFromDisk(
          'compte1', 'Compte 1', src.path);
      expect(res, isNull, reason: 'l\'analyse doit échouer pour ce test');

      // …ET LAISSER LE CACHE EN PLACE. C'est le cœur de §cacheKeep : avant,
      // `reloadFromDisk` supprimait le cache AVANT de sauvegarder, donc un
      // échec le faisait disparaître pour de bon.
      expect(cache.existsSync(), isTrue,
          reason: 'une analyse ratée ne doit jamais détruire le cache existant');
      expect(cache.lengthSync(), tailleAvant);

      // Et il reste exploitable : la liste n'est pas perdue.
      final relu = await ParsedPlaylistService.loadFromDiskForTest(
          'compte1', src.path);
      expect(relu, isNotNull);
      expect(relu!.entries.length, 9);
    });

    test('markStale vide la mémoire mais CONSERVE le fichier', () async {
      final src = _source('compte1');
      await ParsedPlaylistService.saveToDiskForTest('compte1', _playlist());
      final cache = await _cacheFile('compte1');

      ParsedPlaylistService.markStale('compte1');

      expect(cache.existsSync(), isTrue,
          reason: 'un téléchargeur produit un fichier, il ne décide pas du '
              'cycle de vie du cache analysé');
      expect(ParsedPlaylistService.entriesCountOf('compte1'), 0);
      final relu = await ParsedPlaylistService.loadFromDiskForTest(
          'compte1', src.path);
      expect(relu, isNotNull);
    });

    test('forget, lui, emporte bien le fichier (suppression de compte)',
        () async {
      _source('compte1');
      await ParsedPlaylistService.saveToDiskForTest('compte1', _playlist());
      final cache = await _cacheFile('compte1');

      ParsedPlaylistService.forget('compte1');
      // `forget` n'attend pas `_deleteDiskCache` (fire & forget, et il passe
      // par `path_provider` donc par le canal de plateforme) : on laisse la
      // boucle d'événements aboutir, avec une borne.
      for (var i = 0; i < 100 && cache.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(cache.existsSync(), isFalse);
    });
  });

  group('Caches malades — détectés au lieu d\'être servis', () {
    test('un `.gz` tronqué est détecté, supprimé, et rend null', () async {
      final src = _source('compte1');
      await ParsedPlaylistService.saveToDiskForTest('compte1', _playlist());
      final cache = await _cacheFile('compte1');

      // Coupure au milieu du flux gzip : exactement ce que laissait l'ancienne
      // écriture directe quand l'application était tuée.
      final octets = cache.readAsBytesSync();
      cache.writeAsBytesSync(octets.sublist(0, octets.length ~/ 2));

      final relu = await ParsedPlaylistService.loadFromDiskForTest(
          'compte1', src.path);
      expect(relu, isNull);
      expect(cache.existsSync(), isFalse,
          reason: 'un cache illisible doit être retiré, pas resservi');
    });

    test('en-tête crédible mais corps vide → tronqué → supprimé', () async {
      // Le cas VRAIMENT sournois : le gunzip réussit, la lecture « réussit »,
      // et on rend une playlist à zéro entrée que `loadActive` accepte comme
      // `loaded`. Le compte devient invisible sans la moindre erreur.
      final src = _source('compte1');
      final p = _playlist();
      await _writeRawCache('compte1', header: _headerOf(p), body: const []);
      final cache = await _cacheFile('compte1');

      final relu = await ParsedPlaylistService.loadFromDiskForTest(
          'compte1', src.path);
      expect(relu, isNull);
      expect(cache.existsSync(), isFalse);
    });

    test('un cache annonçant count: 0 n\'est PAS accepté', () async {
      final src = _source('compte1');
      final p = _playlist();
      await _writeRawCache('compte1',
          header: _headerOf(p, count: 0), body: const []);

      final relu = await ParsedPlaylistService.loadFromDiskForTest(
          'compte1', src.path);
      expect(relu, isNull,
          reason: 'une liste à zéro entrée n\'est jamais un chargement réussi');
    });

    test('schéma obsolète → cache supprimé, null', () async {
      final src = _source('compte1');
      final p = _playlist();
      final header = _headerOf(p)..['schema'] = ParsedPlaylist.schemaVersion - 1;
      await _writeRawCache('compte1',
          header: header, body: [for (final e in p.entries) e.toJson()]);
      final cache = await _cacheFile('compte1');

      final relu = await ParsedPlaylistService.loadFromDiskForTest(
          'compte1', src.path);
      expect(relu, isNull);
      expect(cache.existsSync(), isFalse);
    });

    test('cache absent → null, sans lever', () async {
      final src = _source('compte1');
      expect(
        await ParsedPlaylistService.loadFromDiskForTest('compte1', src.path),
        isNull,
      );
    });
  });
}
