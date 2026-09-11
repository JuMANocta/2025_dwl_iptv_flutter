// revue 2026-09-11 — D1A-01 (repli get.php motivé et validé), D1A-02 (un
// téléchargement de liste à la fois par compte), D1A-19 (le principal soumis
// au plancher §cacheKeep).
//
// Ces tests passent par les VRAIS téléchargeurs de `PlaylistService` : seuls
// le réseau (catalogue JSON, get.php) est remplacé par les deux crochets de
// test. Verrou, plancher, validation, renommage et suppression de l'autre
// format sont ceux de la production.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aetherStream/data/models/stream_account.dart';
import 'package:aetherStream/data/services/load_failure.dart';
import 'package:aetherStream/data/services/parsed_playlist_service.dart';
import 'package:aetherStream/data/services/playlist_fleet_service.dart';
import 'package:aetherStream/data/services/playlist_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

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

StreamAccount _acc(String id) => StreamAccount(
      id: id,
      label: 'Liste $id',
      mode: StreamAuthMode.separate,
      baseUrl: 'http://panel.test',
      username: 'u',
      password: 'p',
    );

File _json(String id) => File('${_docs.path}/playlist_$id.json');
File _m3u(String id) => File('${_docs.path}/playlist_$id.m3u');

/// Un catalogue JSON crédible (au-dessus du plancher de 4 Ko).
String _catalogBody() => '{"v":1,"pad":"${'x' * 5000}"}';

/// Une vraie liste M3U, au-dessus du plancher.
String _m3uBody([int n = 120]) => <String>[
      '#EXTM3U',
      for (var i = 0; i < n; i++) ...<String>[
        '#EXTINF:-1 group-title="Films",Film $i (2020)',
        'http://panel.test/movie/u/p/$i.mkv',
      ],
    ].join('\n');

const String _pageErreur =
    '<!DOCTYPE html><html><body><h1>503 Service Unavailable</h1></body></html>';

CatalogResult _written() => (written: true, failure: null, detail: null);
CatalogResult _refused(LoadFailureKind k) =>
    (written: false, failure: k, detail: 'test');

typedef CatalogResult = ({bool written, LoadFailureKind? failure, String? detail});

void _setCurrent(StreamAccount a) {
  FlutterSecureStorage.setMockInitialValues(<String, String>{
    'accounts_index': jsonEncode(<String>[a.id]),
    'account:${a.id}': jsonEncode(a.toJson()),
    'current_account_id': a.id,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _root = Directory.systemTemp.createTempSync('aether_dl_exclusive');
    _docs = Directory('${_root.path}/docs')..createSync();
    _support = Directory('${_root.path}/support')..createSync();
    _mockPathProvider();
    ParsedPlaylistService.clear();
    PlaylistService.catalogDownloaderForTest = null;
    PlaylistService.getPhpDownloaderForTest = null;
  });

  tearDown(() {
    PlaylistService.catalogDownloaderForTest = null;
    PlaylistService.getPhpDownloaderForTest = null;
    ParsedPlaylistService.clear();
    if (_root.existsSync()) _root.deleteSync(recursive: true);
  });

  group('D1A-01 — le repli get.php ne détruit plus un catalogue sain', () {
    test('panel saturé + catalogue JSON sain → pas de repli, JSON intact',
        () async {
      _json('a').writeAsStringSync(_catalogBody());
      var getPhp = 0;
      PlaylistService.catalogDownloaderForTest =
          (_, __) async => _refused(LoadFailureKind.busy);
      PlaylistService.getPhpDownloaderForTest = (_, tmp) async {
        getPhp++;
        File(tmp).writeAsStringSync(_pageErreur);
      };

      final r = await PlaylistService.ensureDownloadedForAccount(_acc('a'),
          force: true);

      expect(getPhp, 0, reason: 'un refus motivé ne va pas chercher get.php');
      expect(r.downloaded, isFalse);
      expect(r.path, _json('a').path);
      expect(_json('a').readAsStringSync(), _catalogBody());
      expect(_m3u('a').existsSync(), isFalse);
    });

    test('chute à zéro (amputated) + JSON sain → le JSON reste la source',
        () async {
      _json('a').writeAsStringSync(_catalogBody());
      PlaylistService.catalogDownloaderForTest =
          (_, __) async => _refused(LoadFailureKind.amputated);
      PlaylistService.getPhpDownloaderForTest =
          (_, tmp) async => File(tmp).writeAsStringSync(_m3uBody());

      final r = await PlaylistService.ensureDownloadedForAccount(_acc('a'),
          force: true);
      expect(r.downloaded, isFalse);
      expect(_json('a').existsSync(), isTrue);
      expect(_m3u('a').existsSync(), isFalse);
    });

    test('premier téléchargement (aucun JSON) → repli autorisé, liste publiée',
        () async {
      PlaylistService.catalogDownloaderForTest =
          (_, __) async => _refused(LoadFailureKind.noSource);
      PlaylistService.getPhpDownloaderForTest =
          (_, tmp) async => File(tmp).writeAsStringSync(_m3uBody());

      final r = await PlaylistService.ensureDownloadedForAccount(_acc('a'));
      expect(r.downloaded, isTrue);
      expect(r.path, _m3u('a').path);
      expect(_m3u('a').existsSync(), isTrue);
      expect(File('${_m3u('a').path}.part').existsSync(), isFalse);
    });

    test('repli qui rend une page d\'erreur → rien n\'est publié, l\'ancienne '
        'liste reste', () async {
      _m3u('a').writeAsStringSync(_m3uBody());
      final String avant = _m3u('a').readAsStringSync();
      PlaylistService.catalogDownloaderForTest =
          (_, __) async => _refused(LoadFailureKind.badAccount);
      PlaylistService.getPhpDownloaderForTest =
          (_, tmp) async => File(tmp).writeAsStringSync(_pageErreur);

      final r = await PlaylistService.ensureDownloadedForAccount(_acc('a'),
          force: true);
      expect(r.downloaded, isFalse);
      expect(r.path, _m3u('a').path, reason: 'la liste d\'hier reste servie');
      expect(_m3u('a').readAsStringSync(), avant);
      expect(File('${_m3u('a').path}.part').existsSync(), isFalse);
    });

    test('compte sans identifiants Xtream + JSON : repli autorisé, et le JSON '
        'n\'est supprimé qu\'APRÈS la publication de la liste', () async {
      _json('a').writeAsStringSync(_catalogBody());
      PlaylistService.catalogDownloaderForTest =
          (_, __) async => _refused(LoadFailureKind.badAccount);
      PlaylistService.getPhpDownloaderForTest =
          (_, tmp) async => File(tmp).writeAsStringSync(_m3uBody());

      final r = await PlaylistService.ensureDownloadedForAccount(_acc('a'),
          force: true);
      expect(r.downloaded, isTrue);
      expect(_m3u('a').existsSync(), isTrue);
      expect(_json('a').existsSync(), isFalse);
    });

    test('principal : refus motivé + JSON sain → chemin existant, rien de neuf '
        '(un rechargement ne s\'annoncera pas « réussi »)', () async {
      _setCurrent(_acc('a'));
      _json('a').writeAsStringSync(_catalogBody());
      var getPhp = 0;
      PlaylistService.catalogDownloaderForTest =
          (_, __) async => _refused(LoadFailureKind.busy);
      PlaylistService.getPhpDownloaderForTest = (_, __) async => getPhp++;

      final r = await PlaylistService.downloadCurrentM3UResult();
      expect(r.path, _json('a').path);
      expect(r.downloaded, isFalse);
      expect(getPhp, 0);
    });

    test('principal : repli qui rend une page d\'erreur → erreur, JSON jamais '
        'supprimé', () async {
      _setCurrent(_acc('a'));
      PlaylistService.catalogDownloaderForTest =
          (_, __) async => _refused(LoadFailureKind.noSource);
      PlaylistService.getPhpDownloaderForTest =
          (_, tmp) async => File(tmp).writeAsStringSync(_pageErreur);

      await expectLater(PlaylistService.downloadCurrentM3UResult(),
          throwsA(isA<HttpException>()));
      expect(_m3u('a').existsSync(), isFalse);
      expect(File('${_m3u('a').path}.part').existsSync(), isFalse,
          reason: 'la page refusée ne doit pas traîner sur le disque');
    });
  });

  group('D1A-02 — un téléchargement de liste à la fois par compte', () {
    test('deux contrôles simultanés du même compte → UN téléchargement, deux '
        'futurs résolus', () async {
      var calls = 0;
      PlaylistService.catalogDownloaderForTest = (_, path) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        File(path).writeAsStringSync(_catalogBody());
        return _written();
      };

      final res = await Future.wait(<Future<({String? path, bool downloaded})>>[
        PlaylistService.ensureDownloadedForAccount(_acc('a')),
        PlaylistService.ensureDownloadedForAccount(_acc('a')),
      ]);

      expect(calls, 1, reason: 'le second a trouvé le fichier neuf du premier');
      expect(res[0].downloaded, isTrue);
      expect(res[1].downloaded, isFalse);
      expect(res[1].path, _json('a').path);
    });

    test('un rechargement FORCÉ arrivé pendant un contrôle attend la fin, puis '
        'retélécharge — jamais en même temps', () async {
      var enCours = 0;
      var pic = 0;
      var calls = 0;
      PlaylistService.catalogDownloaderForTest = (_, path) async {
        calls++;
        enCours++;
        if (enCours > pic) pic = enCours;
        await Future<void>.delayed(const Duration(milliseconds: 15));
        File(path).writeAsStringSync(_catalogBody());
        enCours--;
        return _written();
      };

      await Future.wait(<Future<Object?>>[
        PlaylistService.ensureDownloadedForAccount(_acc('a')),
        PlaylistService.ensureDownloadedForAccount(_acc('a'), force: true),
      ]);

      expect(calls, 2);
      expect(pic, 1, reason: 'deux écritures du même `.part` : interdit');
    });

    test('deux comptes différents ne s\'attendent pas', () async {
      final Completer<void> gate = Completer<void>();
      final List<String> debuts = <String>[];
      PlaylistService.catalogDownloaderForTest = (acc, path) async {
        debuts.add(acc.id);
        if (acc.id == 'a') await gate.future;
        File(path).writeAsStringSync(_catalogBody());
        return _written();
      };

      final fa = PlaylistService.ensureDownloadedForAccount(_acc('a'));
      await PlaylistService.ensureDownloadedForAccount(_acc('b'));
      expect(debuts, containsAll(<String>['a', 'b']));
      gate.complete();
      await fa;
    });
  });

  group('D1A-19 — le compte principal soumis au plancher de 4 Ko', () {
    test('une source de moins de 4 Ko est retéléchargée', () async {
      _setCurrent(_acc('a'));
      _json('a').writeAsStringSync('{"user_info":{"auth":0}}');
      var started = 0;
      PlaylistService.catalogDownloaderForTest = (_, path) async {
        File(path).writeAsStringSync(_catalogBody());
        return _written();
      };

      final String path = await PlaylistService.getOrDownloadPlaylist(
        onDownloadStart: () => started++,
      );

      expect(started, 1,
          reason: 'une page d\'erreur de quelques octets n\'est pas un cache');
      expect(path, _json('a').path);
      expect(_json('a').lengthSync(), greaterThan(PlaylistService.minPlaylistBytes));
    });

    test('une source fraîche et crédible → aucun téléchargement', () async {
      _setCurrent(_acc('a'));
      _json('a').writeAsStringSync(_catalogBody());
      var calls = 0;
      PlaylistService.catalogDownloaderForTest = (_, __) async {
        calls++;
        return _written();
      };

      final String path = await PlaylistService.getOrDownloadPlaylist();
      expect(path, _json('a').path);
      expect(calls, 0);
    });

    // Relecture : le plancher ne doit pas coûter une liste qui MARCHAIT.
    test('petite liste M3U fraîche + réseau coupé → elle reste servie, comme '
        'avant le plancher', () async {
      _setCurrent(_acc('a'));
      _m3u('a').writeAsStringSync('#EXTM3U\n#EXTINF:-1,TF1\nhttp://h/1.ts\n');
      PlaylistService.catalogDownloaderForTest =
          (_, __) async => throw const SocketException('hors ligne');
      PlaylistService.getPhpDownloaderForTest =
          (_, __) async => throw const SocketException('hors ligne');

      final String path = await PlaylistService.getOrDownloadPlaylist();
      expect(path, _m3u('a').path);
    });

    test('page d\'erreur en cache + réseau coupé → l\'erreur remonte (la page '
        'n\'est pas servie comme une liste)', () async {
      _setCurrent(_acc('a'));
      _m3u('a').writeAsStringSync(_pageErreur);
      PlaylistService.catalogDownloaderForTest =
          (_, __) async => throw const SocketException('hors ligne');
      PlaylistService.getPhpDownloaderForTest =
          (_, __) async => throw const SocketException('hors ligne');

      await expectLater(PlaylistService.getOrDownloadPlaylist(),
          throwsA(isA<HttpException>()));
    });
  });

  group('D3B-02 + D1A-02 — le réconciliateur ne double pas un téléchargement '
      'en cours', () {
    test('liste périmée en cours de téléchargement (entrée « sans attendre ») '
        '→ le réconciliateur attend et ne retélécharge PAS', () async {
      _setCurrent(_acc('a'));
      _json('a')
        ..writeAsStringSync(_catalogBody())
        ..setLastModifiedSync(
            DateTime.now().subtract(const Duration(hours: 30)));
      final Completer<void> started = Completer<void>();
      final Completer<void> gate = Completer<void>();
      var calls = 0;
      PlaylistService.catalogDownloaderForTest = (_, path) async {
        calls++;
        if (calls == 1) {
          started.complete();
          await gate.future;
        }
        File(path).writeAsStringSync(_catalogBody());
        return _written();
      };

      // Le démarrage télécharge la liste périmée, et tourne encore…
      final Future<String> boot = PlaylistService.getOrDownloadPlaylist();
      await started.future;
      expect(PlaylistService.isDownloadInProgress('a'), isTrue);

      // …quand le réconciliateur passe. `onDetail` est appelé juste avant la
      // décision de télécharger : une fois vu, la décision est prise.
      final Completer<void> decided = Completer<void>();
      final Future<Object?> fleet = PlaylistFleetService.ensureAllLoaded(
        reason: 'test',
        onDetail: (_) {
          if (!decided.isCompleted) decided.complete();
        },
      );
      await decided.future;
      gate.complete();
      await boot;
      await fleet;

      expect(calls, 1,
          reason: 'forcé sur des faits relevés AVANT le verrou, il en refaisait '
              'un second, complet, derrière celui du démarrage');
    });
  });
}
