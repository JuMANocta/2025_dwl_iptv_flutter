// §acctPurge — Verrous du ménage de stockage.
//
// Ce que ces tests protègent :
//
//   1. **Le garde-fou.** `sweepOrphans` supprime tout fichier dont le compte
//      n'est pas dans la liste fournie. Si cette liste arrive vide parce que
//      `FlutterSecureStorage` a hoqueté, le balayage effacerait TOUTES les
//      playlists — un incident bien pire que les 290 Mo qu'il répare. Le refus
//      sur liste vide est donc la ligne la plus importante du fichier.
//   2. **L'accord des noms.** Le balayeur travaille sur des motifs de noms de
//      fichiers, pas sur des chemins par compte : il duplique donc la
//      convention de nommage de `PlaylistService` et `ParsedPlaylistService`.
//      Si un service renomme ses fichiers, il faut que ce soit CE test qui
//      prévienne — pas un utilisateur dont la liste a disparu.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/services/storage_janitor.dart';

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

File _touch(Directory dir, String name, {int bytes = 16}) {
  final f = File('${dir.path}/$name')..writeAsBytesSync(List.filled(bytes, 0));
  return f;
}

/// L'état de départ : deux comptes vivants, un compte supprimé, du bruit.
void _seed() {
  _touch(_docs, 'playlist_vivant1.json', bytes: 100);
  _touch(_docs, 'playlist_vivant2.m3u', bytes: 100);
  _touch(_docs, 'playlist_mort.json', bytes: 500);
  _touch(_support, 'parsed_playlist_vivant1.json.gz', bytes: 50);
  _touch(_support, 'parsed_playlist_mort.json.gz', bytes: 300);
  // Bruit : rien de tout ça n'appartient à un compte.
  _touch(_support, 'com.alexmercerind.media_kit.NativeReferenceHolder.10041');
  _touch(_support, 'aether_img_tmdb.db', bytes: 999);
  _touch(_support, 'SourceCodePro_700_abc.ttf', bytes: 999);
  _touch(_docs, 'res_timestamp-125-1788376444365');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _root = Directory.systemTemp.createTempSync('janitor');
    _docs = Directory('${_root.path}/app_flutter')..createSync();
    _support = Directory('${_root.path}/files')..createSync();
    _mockPathProvider();
    _seed();
  });

  tearDown(() => _root.deleteSync(recursive: true));

  group('🛑 Le garde-fou — liste de comptes vide', () {
    test('REFUSE de balayer, et ne touche à RIEN', () async {
      final res = await StorageJanitor.sweepOrphans(knownAccountIds: {});

      expect(res.refused, isTrue,
          reason: 'un stockage sécurisé qui hoquette ne doit pas effacer les '
              'playlists de l\'utilisateur');
      expect(res.bytes, 0);
      // Le point qui compte : les fichiers sont TOUJOURS là.
      expect(File('${_docs.path}/playlist_vivant1.json').existsSync(), isTrue);
      expect(File('${_docs.path}/playlist_mort.json').existsSync(), isTrue);
      expect(
          File('${_support.path}/parsed_playlist_vivant1.json.gz').existsSync(),
          isTrue);
    });

    test('mais l\'action EXPLICITE de l\'utilisateur passe outre', () async {
      // L'utilisateur a la page Optimisation sous les yeux : n'avoir aucun
      // compte est un fait qu'il constate, pas une panne de lecture.
      final res = await StorageJanitor.sweepOrphans(
          knownAccountIds: {}, allowEmptyAccountList: true);

      expect(res.refused, isFalse);
      expect(File('${_docs.path}/playlist_vivant1.json').existsSync(), isFalse);
      // Le bruit qui n'appartient à aucun compte reste intact.
      expect(File('${_support.path}/aether_img_tmdb.db').existsSync(), isTrue);
    });
  });

  group('Balayage nominal', () {
    test('supprime le compte mort, épargne les vivants et le bruit', () async {
      final res = await StorageJanitor.sweepOrphans(
          knownAccountIds: {'vivant1', 'vivant2'});

      expect(res.refused, isFalse);
      // 500 (json mort) + 300 (parsed mort) + 16 (reliquat media_kit)
      expect(res.bytes, 816);
      expect(res.fileCount, 3);

      // Parti :
      expect(File('${_docs.path}/playlist_mort.json').existsSync(), isFalse);
      expect(File('${_support.path}/parsed_playlist_mort.json.gz').existsSync(),
          isFalse);
      expect(
          File('${_support.path}/com.alexmercerind.media_kit'
                  '.NativeReferenceHolder.10041')
              .existsSync(),
          isFalse,
          reason: '§engineVendor — media_kit n\'existe plus, plus rien ne les '
              'crée ni ne les relit');

      // Intact — c\'est ce qui compte le plus :
      expect(File('${_docs.path}/playlist_vivant1.json').existsSync(), isTrue);
      expect(File('${_docs.path}/playlist_vivant2.m3u').existsSync(), isTrue);
      expect(
          File('${_support.path}/parsed_playlist_vivant1.json.gz').existsSync(),
          isTrue);
      expect(File('${_support.path}/aether_img_tmdb.db').existsSync(), isTrue);
      expect(
          File('${_support.path}/SourceCodePro_700_abc.ttf').existsSync(), isTrue);
      expect(File('${_docs.path}/res_timestamp-125-1788376444365').existsSync(),
          isTrue);
    });

    test('preview annonce le même total sans rien supprimer', () async {
      final vu = await StorageJanitor.preview(
          knownAccountIds: {'vivant1', 'vivant2'});
      expect(vu.bytes, 816);
      expect(File('${_docs.path}/playlist_mort.json').existsSync(), isTrue,
          reason: 'preview ne doit RIEN supprimer');

      final fait = await StorageJanitor.sweepOrphans(
          knownAccountIds: {'vivant1', 'vivant2'});
      expect(fait.bytes, vu.bytes, reason: 'le bouton doit tenir sa promesse');
    });

    test('deux balayages d\'affilée : le second ne trouve plus rien', () async {
      await StorageJanitor.sweepOrphans(knownAccountIds: {'vivant1', 'vivant2'});
      final second = await StorageJanitor.sweepOrphans(
          knownAccountIds: {'vivant1', 'vivant2'});
      expect(second.isEmpty, isTrue);
    });
  });

  group('Suppression d\'un compte (le correctif de source)', () {
    test('purgeAccount emporte les deux fichiers du compte, et eux seuls',
        () async {
      final freed = await StorageJanitor.purgeAccount('vivant1');

      expect(freed, 150); // 100 (json) + 50 (parsed)
      expect(File('${_docs.path}/playlist_vivant1.json').existsSync(), isFalse);
      expect(
          File('${_support.path}/parsed_playlist_vivant1.json.gz').existsSync(),
          isFalse);
      expect(File('${_docs.path}/playlist_vivant2.m3u').existsSync(), isTrue);
      expect(File('${_docs.path}/playlist_mort.json').existsSync(), isTrue);
    });

    test('un compte sans fichier ne lève pas', () async {
      expect(await StorageJanitor.purgeAccount('jamais_telecharge'), 0);
    });
  });

  group('Reconnaissance des noms (l\'accord avec les services)', () {
    test('les formes réelles sont reconnues', () {
      expect(StorageJanitor.accountIdOf('playlist_acc_1779351247713.json'),
          'acc_1779351247713');
      expect(StorageJanitor.accountIdOf('playlist_acc_1779605438806.m3u'),
          'acc_1779605438806');
      expect(
          StorageJanitor.accountIdOf(
              'parsed_playlist_acc_1780568968883.json.gz'),
          'acc_1780568968883');
    });

    test('⚠️ `parsed_playlist_X.json.gz` n\'est PAS lu comme un `playlist_`',
        () {
      // Le piège : `parsed_playlist_…` contient `playlist_`. Un test de préfixe
      // mal ordonné rendrait l'identifiant tronqué et le fichier serait pris
      // pour un orphelin — donc supprimé alors qu'il appartient à un compte.
      const name = 'parsed_playlist_vivant1.json.gz';
      expect(StorageJanitor.accountIdOf(name), 'vivant1');
      expect(StorageJanitor.accountIdOf(name), isNot(contains('playlist')));
    });

    test('ce qui n\'appartient à personne renvoie null', () {
      for (final n in const [
        'aether_img_tmdb.db',
        'SourceCodePro_700_abc.ttf',
        'res_timestamp-125-1788376444365',
        'flutter_assets',
        'playlist_.json', // identifiant vide
        'playlist_x.txt', // extension inconnue
        'parsed_playlist_x.json', // pas gzippé
        'monplaylist_x.json', // ne commence pas par le préfixe
      ]) {
        expect(StorageJanitor.accountIdOf(n), isNull, reason: n);
      }
    });
  });
}
