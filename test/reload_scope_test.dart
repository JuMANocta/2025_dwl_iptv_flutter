// §reloadScope — Ce qui casse « la vue des qualités » d'une fiche, et le
// bouton qui ne rechargeait qu'une liste.
//
// Trois défauts, mesurés sur l'émulateur téléphone le 2026-09-05 avec les
// trois listes réelles :
//
//   1. Le ↻ de l'accueil ne rechargeait que la liste PRINCIPALE (la question
//      de confirmation ne nommait qu'un compte), donc aucune liste absente de
//      la mémoire ne pouvait revenir depuis l'accueil.
//   2. La fiche décidait « ai-je plusieurs listes ? » à partir du CONTENU DE
//      LA MÉMOIRE. Dès qu'il n'en restait qu'une, deux versions de même
//      libellé venues de deux listes fusionnaient : une pastille disparaissait
//      (constaté : « MULTI VOD » perdu, 5 boutons au lieu de 6).
//   3. `markStale` jetait la copie en mémoire avant le re-parse : la liste
//      active disparaissait de l'accueil pendant toute l'analyse.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/models/parsed_playlist.dart';
import 'package:aetherStream/data/services/parsed_playlist_service.dart';
import 'package:aetherStream/feature/search/version_dedup.dart';

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

M3uEntry _entry(String id, String titre, {String account = 'compte1'}) =>
    M3uEntry(
      url: 'http://exemple.test/$account/$id',
      type: M3uContentType.movie,
      title: TitleMetadata.parse(titre),
      accountId: account,
    );

ParsedPlaylist _playlist(String accountId, int films) => ParsedPlaylist(
      accountId: accountId,
      schema: ParsedPlaylist.schemaVersion,
      m3uModifiedAt: DateTime.now(),
      entries: [
        for (var i = 0; i < films; i++)
          _entry('f$i', 'Film $i (2020) FHD', account: accountId),
      ],
    );

File _source(String accountId) =>
    File('${_docs.path}/playlist_$accountId.json')
      ..writeAsStringSync('{"v":1}');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('§reloadScope — dédoublonnage des versions d\'une fiche', () {
    // La règle : la LISTE D'ORIGINE fait toujours partie de la clé. Avant, elle
    // n'y entrait que si plusieurs listes étaient chargées en mémoire.
    String label(M3uEntry e, int i) => e.title.quality ?? 'Flux ${i + 1}';

    test('deux listes, même libellé : les DEUX versions restent', () {
      final versions = [
        _entry('a', 'Film FHD', account: 'platinium'),
        _entry('b', 'Film FHD', account: 'vod'),
      ];
      expect(dedupeVersions(versions, label).length, 2,
          reason: 'perdre une source, c\'est retirer un choix à '
              'l\'utilisateur sans le lui dire');
    });

    test('même liste, même libellé : une seule version', () {
      final versions = [
        _entry('a', 'Film FHD', account: 'platinium'),
        _entry('b', 'Film FHD', account: 'platinium'),
      ];
      expect(dedupeVersions(versions, label).length, 1);
    });

    test('l\'ordre d\'entrée est conservé (la priorité de l\'appelant)', () {
      final versions = [
        _entry('a', 'Film 4K', account: 'vod'),
        _entry('b', 'Film FHD', account: 'platinium'),
        _entry('c', 'Film 4K', account: 'vod'),
      ];
      final out = dedupeVersions(versions, label);
      expect(out.map((e) => e.url).toList(),
          [versions[0].url, versions[1].url]);
    });
  });

  group('§reloadScope — « plusieurs listes ? » ne se lit pas dans la mémoire',
      () {
    setUp(() {
      ParsedPlaylistService.clear();
      ParsedPlaylistService.reportConfiguredAccounts(0);
    });

    test('deux listes configurées, mémoire VIDE → multi-comptes quand même',
        () {
      ParsedPlaylistService.reportConfiguredAccounts(2);
      expect(ParsedPlaylistService.isMultiAccount, isTrue,
          reason: 'c\'est le cas exact du bug : pendant un rechargement ou '
              'tant qu\'une liste n\'est pas revenue, la fiche annonçait '
              '« une seule liste »');
    });

    test('une seule liste configurée → mono-compte', () {
      ParsedPlaylistService.reportConfiguredAccounts(1);
      expect(ParsedPlaylistService.isMultiAccount, isFalse);
    });
  });

  group('§reloadScope — markStale garde la liste affichable', () {
    setUp(() async {
      _root = await Directory.systemTemp.createTemp('aether_reload_scope');
      _docs = Directory('${_root.path}/docs')..createSync(recursive: true);
      _support = Directory('${_root.path}/support')..createSync(recursive: true);
      _mockPathProvider();
      ParsedPlaylistService.clear();
    });

    tearDown(() {
      ParsedPlaylistService.clear();
      if (_root.existsSync()) _root.deleteSync(recursive: true);
    });

    test('la copie reste en mémoire, mais elle est marquée périmée', () async {
      final src = _source('compte1');
      await ParsedPlaylistService.saveToDiskForTest('compte1', _playlist('compte1', 3));
      await ParsedPlaylistService.loadActive('compte1', 'Compte 1', src.path);
      expect(ParsedPlaylistService.entriesCountOf('compte1'), 3);

      ParsedPlaylistService.markStale('compte1');

      expect(ParsedPlaylistService.entriesCountOf('compte1'), 3,
          reason: 'jeter la copie ici, c\'était faire disparaître la liste de '
              'l\'accueil et des fiches pendant tout le re-parse');
      expect(ParsedPlaylistService.isStale('compte1'), isTrue);
    });

    test('une copie périmée est RÉ-ANALYSÉE au chargement suivant', () async {
      final src = _source('compte1');
      await ParsedPlaylistService.saveToDiskForTest('compte1', _playlist('compte1', 3));
      await ParsedPlaylistService.loadActive('compte1', 'Compte 1', src.path);
      expect(ParsedPlaylistService.entriesCountOf('compte1'), 3);

      // La source a changé : le cache disque porte désormais 5 films.
      await ParsedPlaylistService.saveToDiskForTest('compte1', _playlist('compte1', 5));
      ParsedPlaylistService.markStale('compte1');

      await ParsedPlaylistService.loadActive('compte1', 'Compte 1', src.path);
      expect(ParsedPlaylistService.entriesCountOf('compte1'), 5,
          reason: 'sans le drapeau, `loadActive` rendrait la copie en mémoire '
              'et la nouvelle source ne serait jamais lue');
      expect(ParsedPlaylistService.isStale('compte1'), isFalse,
          reason: 'un chargement réussi lève le drapeau');
    });

    test('forget et unloadSecondary emportent le drapeau', () async {
      final src = _source('compte1');
      await ParsedPlaylistService.saveToDiskForTest('compte1', _playlist('compte1', 3));
      await ParsedPlaylistService.loadActive('compte1', 'Compte 1', src.path);

      ParsedPlaylistService.markStale('compte1');
      ParsedPlaylistService.unloadSecondary('compte1');
      expect(ParsedPlaylistService.isStale('compte1'), isFalse);

      await ParsedPlaylistService.loadActive('compte1', 'Compte 1', src.path);
      ParsedPlaylistService.markStale('compte1');
      ParsedPlaylistService.forget('compte1');
      expect(ParsedPlaylistService.isStale('compte1'), isFalse);
    });
  });
}
