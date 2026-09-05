// §dlOrphans (2026-09-05) — La règle « quel fichier est orphelin », pure.
//
// Le cas mesuré (Galaxy S25, 2026-09-04) : 5 fichiers dans le dossier public,
// 1 tâche « annulée » dans la liste, « Terminés 0 ». Le défaut n'est pas
// théorique, et la règle qui le corrige doit être vérifiable sans appareil.

import 'package:aetherStream/data/models/download_task.dart';
import 'package:aetherStream/data/services/device_library_service.dart';
import 'package:flutter_test/flutter_test.dart';

DeviceVideo _file(String name, {int size = 1}) => DeviceVideo(
      uri: 'content://media/external/video/media/${name.hashCode}',
      name: name,
      path: '/storage/emulated/0/Movies/AetherStream/$name',
      size: size,
      modifiedAt: DateTime(2026, 9, 4),
    );

DownloadTask _task(String fileName, DownloadStatus status) => DownloadTask(
      id: fileName,
      url: 'http://x/$fileName',
      displayName: fileName,
      finalPath: '/storage/emulated/0/Movies/AetherStream/$fileName',
      tempPath: '',
      status: status,
      progress: status == DownloadStatus.completed ? 1 : 0,
      totalSize: 1,
      createdAt: DateTime(2026, 9, 4),
    );

void main() {
  group('§dlOrphans — orphansOf', () {
    test('un fichier issu d\'une tâche TERMINÉE n\'est pas orphelin', () {
      final files = [_file('Heat.mkv'), _file('Alien.mkv')];
      final tasks = [_task('Heat.mkv', DownloadStatus.completed)];
      final orphans = DeviceLibraryService.orphansOf(files, tasks);
      expect(orphans.map((v) => v.name), ['Alien.mkv']);
    });

    test('⚠️ une tâche FAILED/CANCELED ne cache pas son fichier', () {
      // C'est le cas mesuré : la réconciliation avait basculé la tâche en
      // échec alors que le fichier était complet. La tuile de la tâche ne
      // sait pas le lire ; le fichier doit donc remonter.
      final files = [_file('Le Crime du 3e étage.mkv')];
      final orphans = DeviceLibraryService.orphansOf(files, [
        _task('Le Crime du 3e étage.mkv', DownloadStatus.canceled),
        _task('Autre.mkv', DownloadStatus.failed),
      ]);
      expect(orphans.length, 1);
    });

    test('sans aucune tâche, tout le dossier est orphelin', () {
      final files = [_file('a.mkv'), _file('b.mp4'), _file('c.mkv')];
      expect(DeviceLibraryService.orphansOf(files, const []).length, 3);
    });

    test('le rapprochement se fait sur le NOM DE FICHIER, pas le chemin', () {
      // Le chemin de MediaStore et celui de la tâche peuvent différer
      // (/storage/emulated/0 vs /sdcard) : seul le nom compte.
      final files = [_file('Dune.mkv')];
      final task = DownloadTask(
        id: 'd',
        url: 'http://x/d',
        displayName: 'Dune',
        finalPath: '/sdcard/Movies/AetherStream/Dune.mkv',
        tempPath: '',
        status: DownloadStatus.completed,
        progress: 1,
        totalSize: 1,
        createdAt: DateTime(2026, 9, 4),
      );
      expect(DeviceLibraryService.orphansOf(files, [task]), isEmpty);
    });

    test('le titre affiché perd son extension', () {
      expect(_file('Spider-Man _ Brand New Day.mp4').title,
          'Spider-Man _ Brand New Day');
      expect(_file('sans-extension').title, 'sans-extension');
    });

    test('le résultat d\'un balayage additionne les tailles', () {
      final r = DeviceScanResult([_file('a', size: 3), _file('b', size: 4)]);
      expect(r.totalBytes, 7);
      expect(r.permissionDenied, isFalse);
    });

    test('aller-retour JSON (mémorisation entre deux lancements)', () {
      final v = _file('X.mkv', size: 42);
      final back = DeviceVideo.fromJson(v.toJson());
      expect(back.uri, v.uri);
      expect(back.name, v.name);
      expect(back.path, v.path);
      expect(back.size, 42);
      expect(back.modifiedAt, v.modifiedAt);
    });
  });
}
