import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aetherStream/data/models/download_task.dart';
import 'package:aetherStream/data/services/download_manager_service.dart';

/// Revue 2026-09-11 — Le cycle de vie de la liste des téléchargements.
///
/// D3A-05 : tirer la page pour rafraîchir rappelait `init()`, qui basculait
/// TOUTE tâche `downloading` en échec — y compris celles en cours.
/// D3A-14 : une seule entrée illisible faisait repartir la liste à vide.
/// D3A-09 : le message d'échec était le texte BRUT de l'exception.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DownloadManagerService manager;

  DownloadTask task(String id, DownloadStatus status) => DownloadTask(
        id: id,
        url: 'http://test/$id.mp4',
        displayName: id,
        finalPath: '/movies/$id.mp4',
        tempPath: '/movies/.$id.aetherpart.mp4',
        createdAt: DateTime(2026),
        totalSize: 1000,
        // ⚠️ Jamais `queued` ici : le `pump()` de `init()` ferait PARTIR la
        // tâche pour de vrai (réseau).
        status: status,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    manager = DownloadManagerService();
    manager.clearInFlightForTest();
    manager.tasksNotifier.value = [];
    await manager.init();
  });

  tearDown(() {
    manager.clearInFlightForTest();
    manager.resetQueueForTest();
  });

  test('🔴 D3A-05 — un transfert EN VOL survit au rafraîchissement', () async {
    await manager.addTask(task('vol', DownloadStatus.downloading));
    await manager.addTask(task('mort', DownloadStatus.downloading));
    // « vol » tourne vraiment ; « mort » est un reste d'une session tuée.
    manager.markInFlightForTest('vol', Future<void>.value());

    await manager.refreshFromDisk();

    DownloadStatus statusOf(String id) =>
        manager.tasksNotifier.value.firstWhere((t) => t.id == id).status;
    expect(statusOf('vol'), DownloadStatus.downloading,
        reason: 'pas de fausse notification d\'échec sur un geste');
    expect(statusOf('mort'), DownloadStatus.failed,
        reason: 'un transfert interrompu, lui, reste réconcilié');
  });

  test('D3A-05 — rejouer init() ne perd ni ne duplique rien', () async {
    await manager.addTask(task('a', DownloadStatus.completed));
    await manager.init();
    await manager.init();
    expect(manager.tasksNotifier.value.map((t) => t.id), ['a']);
  });

  test('🔴 D3A-14 — une entrée illisible est mise de côté, les autres restent',
      () async {
    final good = task('ok', DownloadStatus.completed).toJson();
    final bad = <String, dynamic>{'id': 'cassé'}; // champs obligatoires absents
    SharedPreferences.setMockInitialValues({
      'download_tasks_list': jsonEncode([good, bad]),
    });
    manager.tasksNotifier.value = [];
    await manager.init();

    expect(manager.tasksNotifier.value.map((t) => t.id), ['ok']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('download_tasks_unreadable'), contains('cassé'),
        reason: 'l\'entrée illisible est gardée, pas écrasée');
  });

  test('D3A-14 — une liste illisible en bloc ne vide rien', () async {
    SharedPreferences.setMockInitialValues({
      'download_tasks_list': '{pas du json',
    });
    manager.tasksNotifier.value = [task('mem', DownloadStatus.completed)];
    await manager.init();
    expect(manager.tasksNotifier.value.map((t) => t.id), ['mem']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('download_tasks_unreadable'), '{pas du json');
  });

  test('🔴 D3A-09 — le message d\'échec est lisible, sans chemin ni anglais',
      () async {
    await manager.addTask(task('disque', DownloadStatus.downloading));
    await manager.failOrRequeueForTest(
      'disque',
      const FileSystemException('writeFrom failed',
          '/storage/emulated/0/Movies/AetherStream/.disque.aetherpart.mp4',
          OSError('No space left on device', 28)),
    );
    final t = manager.tasksNotifier.value.firstWhere((t) => t.id == 'disque');
    expect(t.status, DownloadStatus.failed,
        reason: 'un disque plein n\'est pas une panne de réseau');
    expect(t.errorMessage, isNot(contains('/storage')));
    expect(t.errorMessage, isNot(contains('No space left')));
    expect(t.errorMessage, isNotEmpty);
  });

  test('D3A-07 — annuler pendant la finalisation ne fait rien', () async {
    await manager.addTask(task('fin', DownloadStatus.finalizing));
    await manager.cancelTask('fin');
    expect(manager.tasksNotifier.value.single.status, DownloadStatus.finalizing);
  });
}
