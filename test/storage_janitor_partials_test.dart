// §dlPartSweep — Le balayage des partiels, branché sur de VRAIS fichiers.
//
// Le contrat pur est vérifié par `download_partial_sweep_test.dart`. Ici, on
// vérifie ce qu'aucune fonction pure ne peut tenir :
//
//   1. **Le refus sur liste de tâches vide.** Si les préférences hoquettent,
//      `liveTempPaths` arrive vide et TOUT devient orphelin — y compris un
//      transfert de plusieurs gigaoctets en attente de reprise. Même leçon,
//      même garde-fou que pour les comptes (§acctPurge).
//   2. **L'accord sur le nom du dossier.** Le balayeur cherche dans
//      `<cache externe>/dl_tmp` ; c'est `download_initiator` qui y écrit. Si
//      l'un des deux change, c'est CE test qui prévient — pas un utilisateur
//      dont le disque se remplit en silence.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/services/storage_janitor.dart';
import 'package:aetherStream/feature/downloads/logic/partial_sweep.dart';

late Directory _root;
late Directory _cache;
late Directory _movies;

File _touch(Directory dir, String name, {int bytes = 16, Duration? age}) {
  final f = File('${dir.path}/$name')..writeAsBytesSync(List.filled(bytes, 0));
  f.setLastModifiedSync(DateTime.now().subtract(age ?? const Duration(days: 1)));
  return f;
}

String _slash(String p) => p.replaceAll(String.fromCharCode(92), '/');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _root = Directory.systemTemp.createTempSync('partials');
    _cache = Directory('${_root.path}/cache/$kDownloadTmpDirName')
      ..createSync(recursive: true);
    _movies = Directory('${_root.path}/Movies/AetherStream')
      ..createSync(recursive: true);
  });

  tearDown(() => _root.deleteSync(recursive: true));

  group('🛑 Le garde-fou — aucune tâche connue', () {
    test('REFUSE de balayer, et ne touche à RIEN', () async {
      _touch(_cache, 'Film.mkv', bytes: 500);
      final res = await StorageJanitor.sweepDownloadPartials(
        tmpDirectory: _cache,
        publicDirectory: _movies,
        liveTempPaths: const <String>{},
      );
      expect(res.refused, isTrue);
      expect(res.fileCount, 0);
      expect(File('${_cache.path}/Film.mkv').existsSync(), isTrue,
          reason: 'un partiel reprenable a été détruit sur une liste vide');
    });

    test("mais l'action EXPLICITE de l'utilisateur passe outre", () async {
      _touch(_cache, 'Film.mkv', bytes: 500);
      final res = await StorageJanitor.sweepDownloadPartials(
        tmpDirectory: _cache,
        publicDirectory: _movies,
        liveTempPaths: const <String>{},
        allowEmptyTaskList: true,
      );
      expect(res.refused, isFalse);
      expect(res.fileCount, 1);
      expect(res.bytes, 500);
      expect(File('${_cache.path}/Film.mkv').existsSync(), isFalse);
    });
  });

  group('Balayage nominal', () {
    test('épargne le partiel VIVANT, emporte l\'abandonné', () async {
      final vivant = _touch(_cache, 'EnCours.mkv', bytes: 300);
      final mort = _touch(_cache, 'Abandonne.mkv', bytes: 700);

      final res = await StorageJanitor.sweepDownloadPartials(
        tmpDirectory: _cache,
        publicDirectory: _movies,
        liveTempPaths: <String>{_slash(vivant.path)},
      );

      expect(res.fileCount, 1);
      expect(res.bytes, 700);
      expect(vivant.existsSync(), isTrue);
      expect(mort.existsSync(), isFalse);
    });

    test('dans le dossier public : le partiel part, le FILM reste', () async {
      final film = _touch(_movies, 'Heroes S03 E01.mkv', bytes: 9000);
      final part = _touch(_movies, '.Heroes S03 E02.mkv.part', bytes: 400);

      final res = await StorageJanitor.sweepDownloadPartials(
        tmpDirectory: _cache,
        publicDirectory: _movies,
        liveTempPaths: <String>{'/un/chemin/qui/existe.mkv'},
      );

      expect(res.fileCount, 1);
      expect(res.bytes, 400);
      expect(film.existsSync(), isTrue,
          reason: 'le dossier public appartient à l\'utilisateur');
      expect(part.existsSync(), isFalse);
    });

    test('preview : annonce le total sans rien supprimer', () async {
      final mort = _touch(_cache, 'Abandonne.mkv', bytes: 700);
      final res = await StorageJanitor.sweepDownloadPartials(
        tmpDirectory: _cache,
        publicDirectory: _movies,
        liveTempPaths: const <String>{},
        allowEmptyTaskList: true,
        dryRun: true,
      );
      expect(res.fileCount, 1);
      expect(res.bytes, 700);
      expect(mort.existsSync(), isTrue);
    });

    test('un partiel RÉCENT est épargné, même inconnu', () async {
      final jeune = _touch(_cache, 'Jeune.mkv', age: const Duration(seconds: 5));
      final res = await StorageJanitor.sweepDownloadPartials(
        tmpDirectory: _cache,
        publicDirectory: _movies,
        liveTempPaths: const <String>{},
        allowEmptyTaskList: true,
      );
      expect(res.fileCount, 0);
      expect(jeune.existsSync(), isTrue);
    });

    test('deux balayages d\'affilée : le second ne trouve plus rien', () async {
      _touch(_cache, 'Abandonne.mkv', bytes: 700);
      await StorageJanitor.sweepDownloadPartials(
        tmpDirectory: _cache,
        publicDirectory: _movies,
        liveTempPaths: const <String>{},
        allowEmptyTaskList: true,
      );
      final second = await StorageJanitor.sweepDownloadPartials(
        tmpDirectory: _cache,
        publicDirectory: _movies,
        liveTempPaths: const <String>{},
        allowEmptyTaskList: true,
      );
      expect(second.isEmpty, isTrue);
    });

    test('un dossier absent ne fait pas échouer le balayage', () async {
      _cache.deleteSync(recursive: true);
      _movies.deleteSync(recursive: true);
      final res = await StorageJanitor.sweepDownloadPartials(
        tmpDirectory: _cache,
        publicDirectory: _movies,
        liveTempPaths: const <String>{},
        allowEmptyTaskList: true,
      );
      expect(res.refused, isFalse);
      expect(res.fileCount, 0);
    });
  });

  group("⚠️ L'accord avec celui qui écrit les partiels", () {
    test("le dossier balayé est composé par la MÊME fonction que l'écriture",
        () async {
      // `download_initiator._getTempDirectory` et `StorageJanitor` appellent
      // tous deux `downloadTmpPath`. Si l'un des deux compose son chemin
      // autrement, le balayeur cherche là où personne n'écrit — et rien ne le
      // dirait.
      expect(downloadTmpPath('/base'), '/base/$kDownloadTmpDirName');
      expect(_slash(_cache.path), endsWith(downloadTmpPath('/cache')
          .substring('/cache'.length)));

      _touch(_cache, 'Preuve.mkv', bytes: 42);
      final res = await StorageJanitor.sweepDownloadPartials(
        tmpDirectory: _cache,
        publicDirectory: _movies,
        liveTempPaths: const <String>{},
        allowEmptyTaskList: true,
      );
      expect(res.fileCount, 1);
    });
  });
}
