// revue 2026-09-11 — Les chargements concurrents d'une MÊME liste.
//
//   - D1L-02 : `loadActive` était hors du verrou §fleetSingle — deux analyses
//     complètes du même catalogue pouvaient tourner en parallèle ;
//   - D1A-03 : un rechargement qui rejoignait un chargement en vol recevait
//     `null` (faux « l'analyse a échoué ») sans jamais lire la NOUVELLE
//     source, et une charge démarrée avant `markStale` levait le drapeau ;
//   - D1A-18 : `reloadFromDisk` ne reconstruisait pas la table de fusion
//     TMDB, et chaque chargement repoussait le déchargement de TOUTES les
//     listes secondaires ;
//   - D1A-19 : une analyse à zéro entrée était acceptée comme « chargée » ;
//   - D1A-04 : deux sauvegardes du cache analysé partageaient le même `.part`.
//
// Les sources passent par les VRAIS parseurs (M3U, catalogue JSON).
import 'dart:convert';
import 'dart:io';

import 'package:aetherStream/core/utils/user_error.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/models/parsed_playlist.dart';
import 'package:aetherStream/data/services/load_failure.dart';
import 'package:aetherStream/data/services/parsed_playlist_service.dart';
import 'package:aetherStream/data/services/tmdb_group_alias_service.dart';
import 'package:aetherStream/data/services/hidden_regions_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

late Directory _root;
late Directory _docs;
late Directory _support;

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

/// Une source M3U de [n] films, lue par le vrai parseur.
File _m3uSource(String id, int n) =>
    File('${_docs.path}/playlist_$id.m3u')
      ..writeAsStringSync(<String>[
        '#EXTM3U',
        for (var i = 0; i < n; i++) ...<String>[
          '#EXTINF:-1 group-title="Films",Film $i (2020)',
          'http://h.test/movie/u/p/$id$i.mkv',
        ],
      ].join('\n'));

M3uEntry _entry(String account, int i) => M3uEntry(
      url: 'http://h.test/$account/$i',
      type: M3uContentType.movie,
      title: TitleMetadata.parse('Film $i (2020) FHD'),
      accountId: account,
    );

ParsedPlaylist _playlist(String id, int n) => ParsedPlaylist(
      accountId: id,
      schema: ParsedPlaylist.schemaVersion,
      m3uModifiedAt: DateTime.now(),
      entries: <M3uEntry>[for (var i = 0; i < n; i++) _entry(id, i)],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _root = Directory.systemTemp.createTempSync('aether_inflight');
    _docs = Directory('${_root.path}/docs')..createSync();
    _support = Directory('${_root.path}/support')..createSync();
    _mockPathProvider();
    ParsedPlaylistService.clear();
    ParsedPlaylistService.loadStartsForTest = 0;
    TmdbGroupAliasService.resetForTest();
  });

  tearDown(() async {
    ParsedPlaylistService.saveSliceForTest = const Duration(milliseconds: 8);
    ParsedPlaylistService.clear();
    // Laisse les sauvegardes « fire & forget » se poser avant d'effacer.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (_root.existsSync()) _root.deleteSync(recursive: true);
  });

  group('D1L-02 — loadActive sous le verrou §fleetSingle', () {
    test('deux loadActive concurrents → UNE analyse, le même résultat',
        () async {
      final File src = _m3uSource('c', 4);
      final List<ParsedPlaylist> res = await Future.wait(<Future<ParsedPlaylist>>[
        ParsedPlaylistService.loadActive('c', 'C', src.path),
        ParsedPlaylistService.loadActive('c', 'C', src.path),
      ]);
      expect(ParsedPlaylistService.loadStartsForTest, 1,
          reason: 'le second devait attendre le premier, pas relancer');
      expect(res[0].entries, hasLength(4));
      expect(identical(res[0], res[1]), isTrue);
    });

    test('loadActive + reloadFromDisk simultanés → une seule analyse',
        () async {
      final File src = _m3uSource('c', 4);
      final Future<ParsedPlaylist> a =
          ParsedPlaylistService.loadActive('c', 'C', src.path);
      final Future<ParsedPlaylist?> b =
          ParsedPlaylistService.reloadFromDisk('c', 'C', src.path);
      await a;
      final ParsedPlaylist? rb = await b;
      expect(ParsedPlaylistService.loadStartsForTest, 1);
      expect(rb, isNotNull);
      expect(rb!.entries, hasLength(4));
    });
  });

  group('D1A-03 — un chargement en vol ne « mange » plus un markStale', () {
    test('un rechargement qui rejoint un vol lit la NOUVELLE source (plus de '
        'faux échec)', () async {
      final File src = _m3uSource('c', 3);
      await ParsedPlaylistService.saveToDiskForTest('c', _playlist('c', 3));

      // Vol en cours : la liste se charge depuis son cache (3 entrées)…
      final Future<void> vol =
          ParsedPlaylistService.loadSecondary('c', 'C', src.path);
      // …pendant que la source est renouvelée et marquée périmée.
      _m3uSource('c', 5);
      ParsedPlaylistService.markStale('c');
      final ParsedPlaylist? res =
          await ParsedPlaylistService.reloadFromDisk('c', 'C', src.path);
      await vol;

      expect(res, isNotNull,
          reason: 'avant : `null` → « L\'analyse de la liste a échoué »');
      expect(res!.entries, hasLength(5));
      expect(ParsedPlaylistService.entriesCountOf('c'), 5);
      expect(ParsedPlaylistService.isStale('c'), isFalse);
    });

    test('une charge démarrée AVANT markStale ne lève pas le drapeau', () async {
      final File src = _m3uSource('c', 3);
      await ParsedPlaylistService.saveToDiskForTest('c', _playlist('c', 3));

      final Future<void> vol =
          ParsedPlaylistService.loadSecondary('c', 'C', src.path);
      ParsedPlaylistService.markStale('c');
      await vol;

      expect(ParsedPlaylistService.entriesCountOf('c'), 3,
          reason: 'la copie reste affichable');
      expect(ParsedPlaylistService.isStale('c'), isTrue,
          reason: 'elle décrit l\'ANCIENNE source : la prochaine passe doit '
              'la ré-analyser, pas la croire à jour 24 h');
    });
  });

  group('D1A-18 — table de fusion TMDB et déchargement', () {
    test('reloadFromDisk reconstruit la table de fusion TMDB', () async {
      final File src = File('${_docs.path}/playlist_t.json')
        ..writeAsStringSync(jsonEncode(<String, dynamic>{
          'v': 1,
          'host': 'http://h.test',
          'user': 'u',
          'pass': 'p',
          'live': <Object>[],
          'vod': <Map<String, dynamic>>[
            <String, dynamic>{'stream_id': 1, 'name': 'Alpha', 'tmdb': '424242', '_cat': 'Action'},
            <String, dynamic>{'stream_id': 2, 'name': 'Omega', 'tmdb': '424242', '_cat': 'Action'},
          ],
          'series': <Object>[],
        }));

      final ParsedPlaylist? res =
          await ParsedPlaylistService.reloadFromDisk('t', 'T', src.path);

      expect(res, isNotNull);
      expect(TmdbGroupAliasService.aliasCount, greaterThan(0),
          reason: 'les nouveaux identifiants TMDB doivent fusionner dès le '
              'rechargement, pas au lancement suivant');
    });

    test('charger une liste ne repousse plus le déchargement des autres',
        () async {
      for (final String id in <String>['a', 'b', 'c']) {
        _m3uSource(id, 2);
        await ParsedPlaylistService.saveToDiskForTest(id, _playlist(id, 2));
      }
      final String path = '${_docs.path}/playlist_';
      await ParsedPlaylistService.loadActive('a', 'A', '${path}a.m3u');
      await ParsedPlaylistService.loadSecondary('b', 'B', '${path}b.m3u');
      // Premier passage : « b » reçoit sa période de grâce (horodatée ici).
      ParsedPlaylistService.unloadIdleSecondaries(
          activeAccountId: 'a', idle: const Duration(milliseconds: 60));
      await Future<void>.delayed(const Duration(milliseconds: 120));

      // Une AUTRE liste se charge : elle ne doit pas rajeunir « b ».
      await ParsedPlaylistService.loadSecondary('c', 'C', '${path}c.m3u');
      ParsedPlaylistService.unloadIdleSecondaries(
          activeAccountId: 'a', idle: const Duration(milliseconds: 60));

      expect(ParsedPlaylistService.entriesCountOf('b'), 0,
          reason: '« b » n\'a pas été consultée depuis 120 ms : déchargée');
      expect(ParsedPlaylistService.entriesCountOf('a'), 2,
          reason: 'la liste active n\'est jamais déchargée');
    });
  });

  group('D1A-19 — zéro entrée n\'est pas un chargement', () {
    test('loadActive : échec nommé, rien en mémoire, rien en cache', () async {
      final File src = File('${_docs.path}/playlist_z.m3u')
        ..writeAsStringSync('#EXTM3U\n');

      await expectLater(
        ParsedPlaylistService.loadActive('z', 'Z', src.path),
        throwsA(isA<UserFacingException>()),
      );
      expect(ParsedPlaylistService.stateOf('z'), AccountLoadState.error);
      expect(ParsedPlaylistService.failureOf('z')?.kind,
          LoadFailureKind.amputated);
      expect(ParsedPlaylistService.entriesCountOf('z'), 0);
      expect(
        File(await ParsedPlaylistService.diskCachePathForTest('z'))
            .existsSync(),
        isFalse,
      );
    });

    test('loadSecondary : même règle, sans lever', () async {
      final File src = File('${_docs.path}/playlist_z.m3u')
        ..writeAsStringSync('#EXTM3U\n');
      await ParsedPlaylistService.loadSecondary('z', 'Z', src.path);
      expect(ParsedPlaylistService.stateOf('z'), AccountLoadState.error);
      expect(ParsedPlaylistService.getAccount('z'), isNull);
    });

    // Intégration du lot 2 — un filtre de régions qui masque TOUT n'est pas
    // une panne : la liste se charge vide, comme avant D1A-19 (sinon la
    // liste principale menait à l'écran d'erreur du démarrage).
    test('emptyBecauseFiltered : vide ET filtre actif seulement', () {
      expect(ParsedPlaylistService.emptyBecauseFiltered(const [],
          filterActive: true), isTrue);
      expect(ParsedPlaylistService.emptyBecauseFiltered(const [],
          filterActive: false), isFalse);
      expect(
          ParsedPlaylistService.emptyBecauseFiltered([_entry('a', 1)],
              filterActive: true),
          isFalse);
    });

    test('🔴 filtre de régions actif : loadActive charge la liste VIDE, sans '
        'échec', () async {
      SharedPreferences.setMockInitialValues({});
      await HiddenRegionsService.setHidden({'UK'});
      addTearDown(() => HiddenRegionsService.setHidden({}));
      final File src = File('${_docs.path}/playlist_f.m3u')
        ..writeAsStringSync('#EXTM3U\n');

      await ParsedPlaylistService.loadActive('f', 'F', src.path);

      expect(ParsedPlaylistService.stateOf('f'), AccountLoadState.loaded);
      expect(ParsedPlaylistService.entriesCountOf('f'), 0);
    });
  });

  group('D1A-04 — sauvegardes du cache analysé', () {
    File source() =>
        File('${_docs.path}/playlist_c.json')..writeAsStringSync('{"v":1}');

    test('deux sauvegardes concurrentes du même compte → un cache VALIDE, la '
        'plus récente gagne, aucun .part', () async {
      final File src = source();
      await Future.wait(<Future<void>>[
        ParsedPlaylistService.saveToDiskForTest('c', _playlist('c', 3)),
        ParsedPlaylistService.saveToDiskForTest('c', _playlist('c', 30)),
      ]);

      final ParsedPlaylist? relu =
          await ParsedPlaylistService.loadFromDiskForTest('c', src.path);
      expect(relu, isNotNull);
      expect(relu!.entries, hasLength(30));
      final String cache =
          await ParsedPlaylistService.diskCachePathForTest('c');
      expect(File('$cache.part').existsSync(), isFalse);
    });

    test('rendre la main pendant l\'écriture ne corrompt pas le flux gzip',
        () async {
      final File src = source();
      // Rendre la main à CHAQUE entrée : le pire cas pour le flux compressé.
      ParsedPlaylistService.saveSliceForTest = Duration.zero;
      await ParsedPlaylistService.saveToDiskForTest('c', _playlist('c', 300));

      final ParsedPlaylist? relu =
          await ParsedPlaylistService.loadFromDiskForTest('c', src.path);
      expect(relu, isNotNull);
      expect(relu!.entries, hasLength(300));
    });
  });
}
