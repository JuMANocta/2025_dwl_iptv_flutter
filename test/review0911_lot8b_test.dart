// Revue 2026-09-11, lot 8b — deux équivalences qui justifient le lot.
//
// Le lot ne garde un changement de performance que s'il rend EXACTEMENT la
// même chose que le code d'avant. Deux d'entre eux vivent dans des services
// (l'accueil et les pages n'ont pas de test, §homeMeter fait foi) :
//
//   - D4B-12 : la feuille « Chercher dans mes listes » itère
//     `entriesOfType(type)` au lieu de `entries` filtré sur le type. Mêmes
//     entrées, MÊME ORDRE — l'ordre décide des groupes et de la troncature
//     à 40.
//   - D4B-10 : la carte d'un compte reprend la requête lancée par
//     `ExpirationAlertService.fetchAll` au lieu d'en relancer une.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/models/parsed_playlist.dart';
import 'package:aetherStream/data/models/stream_account.dart';
import 'package:aetherStream/data/services/expiration_alert_service.dart';
import 'package:aetherStream/data/services/parsed_playlist_service.dart';

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

M3uEntry _entry(String account, int i, M3uContentType type) => M3uEntry(
      url: 'http://exemple.test/$account/${type.name}/$i',
      type: type,
      title: TitleMetadata.parse('Titre $i (2020) FHD'),
      accountId: account,
    );

/// Types ENTRELACÉS : un filtre qui perdrait l'ordre d'origine se verrait.
ParsedPlaylist _playlist(String accountId, int n) => ParsedPlaylist(
      accountId: accountId,
      schema: ParsedPlaylist.schemaVersion,
      m3uModifiedAt: DateTime.now(),
      entries: [
        for (var i = 0; i < n; i++)
          _entry(accountId, i, M3uContentType.values[i % 3]),
      ],
    );

File _source(String accountId) =>
    File('${_docs.path}/playlist_$accountId.json')
      ..writeAsStringSync('{"v":1}');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('D4B-12 — entriesOfType', () {
    setUp(() async {
      _root = await Directory.systemTemp.createTemp('aether_lot8b');
      _docs = Directory('${_root.path}/docs')..createSync(recursive: true);
      _support = Directory('${_root.path}/support')
        ..createSync(recursive: true);
      _mockPathProvider();
      ParsedPlaylistService.clear();
    });

    tearDown(() {
      ParsedPlaylistService.clear();
      if (_root.existsSync()) _root.deleteSync(recursive: true);
    });

    test('mêmes entrées, même ordre que entries.where(type) — deux listes',
        () async {
      await ParsedPlaylistService.saveToDiskForTest(
          'compte1', _playlist('compte1', 11));
      await ParsedPlaylistService.saveToDiskForTest(
          'compte2', _playlist('compte2', 7));
      await ParsedPlaylistService.loadActive(
          'compte1', 'Compte 1', _source('compte1').path);
      await ParsedPlaylistService.loadSecondary(
          'compte2', 'Compte 2', _source('compte2').path);
      expect(ParsedPlaylistService.entriesCountOf('compte1'), 11);
      expect(ParsedPlaylistService.entriesCountOf('compte2'), 7);

      for (final type in M3uContentType.values) {
        final expected = ParsedPlaylistService.entries
            .where((e) => e.type == type)
            .map((e) => e.url)
            .toList();
        final actual = ParsedPlaylistService.entriesOfType(type)
            .map((e) => e.url)
            .toList();
        expect(actual, expected,
            reason: 'l\'ordre décide des groupes ET de la troncature à 40 : '
                'un ordre différent, c\'est une autre liste de résultats');
        expect(actual, isNotEmpty);
      }
    });

    test('mémoire vide → rien', () {
      expect(ParsedPlaylistService.entriesOfType(M3uContentType.movie),
          isEmpty);
    });
  });

  group('D4B-10 — la carte reprend la requête de fetchAll', () {
    // Une URL complète qui n'est PAS du Xtream déguisé : `fetchAccountInfo`
    // rend `null` sans toucher le réseau.
    StreamAccount account(String id) => StreamAccount(
          id: id,
          label: 'Liste $id',
          mode: StreamAuthMode.completeUrl,
          completeUrl: 'http://exemple.test/listes/$id.m3u',
        );

    test('un compte jamais demandé n\'a pas de requête en cours', () {
      expect(ExpirationAlertService.pendingFor('jamais_vu_lot8b'), isNull);
    });

    test('pendingFor rend LA requête EN COURS, une par compte, puis la lâche',
        () async {
      final a = account('lot8b_a');
      final b = account('lot8b_b');
      final all = ExpirationAlertService.fetchAll([a, b]);

      // Disponible dès le retour de fetchAll (avant son premier await) :
      // les cartes se montent pendant que les requêtes sont en vol.
      final fa = ExpirationAlertService.pendingFor(a.id);
      final fb = ExpirationAlertService.pendingFor(b.id);
      expect(fa, isNotNull);
      expect(fb, isNotNull);
      expect(identical(fa, fb), isFalse);
      // La même requête à chaque lecture : la carte ne la relance pas.
      expect(identical(ExpirationAlertService.pendingFor(a.id), fa), isTrue);

      await all;
      expect(await fa, isNull, reason: 'compte non Xtream');
      expect(ExpirationAlertService.infos.value.containsKey(a.id), isTrue,
          reason: 'les puces d\'expiration voient toujours le résultat');
      expect(ExpirationAlertService.infos.value[a.id], isNull);

      // Trouvé à la relecture : la liste des comptes est un
      // `ListView.builder`, une carte sortie de l'écran est DÉTRUITE puis
      // remontée au retour. Une requête TERMINÉE ne doit plus lui être
      // rendue : elle afficherait les chiffres de l'ouverture de la page
      // (connexions actives comprises) au lieu de refaire sa requête, comme
      // avant le lot.
      expect(ExpirationAlertService.pendingFor(a.id), isNull);
      expect(ExpirationAlertService.pendingFor(b.id), isNull);
    });

    test('un nouveau fetchAll remplace la requête en cours', () async {
      final a = account('lot8b_c');
      final first = ExpirationAlertService.fetchAll([a]);
      final f1 = ExpirationAlertService.pendingFor(a.id);
      final second = ExpirationAlertService.fetchAll([a]);
      final f2 = ExpirationAlertService.pendingFor(a.id);
      expect(f1, isNotNull);
      expect(f2, isNotNull);
      expect(identical(f1, f2), isFalse);
      await Future.wait([first, second]);
      expect(ExpirationAlertService.pendingFor(a.id), isNull);
    });
  });
}
