import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aetherStream/data/models/download_task.dart';
import 'package:aetherStream/data/services/download_manager_service.dart';

/// §dlProgress — Verrouille le throttle de progression des téléchargements.
///
/// Avant correctif, `startDownloadTask` appelait `updateTask` **à chaque chunk
/// réseau** (8–64 Ko), et chaque appel réécrivait TOUTE la liste des tâches en
/// JSON dans SharedPreferences en plus de notifier l'UI. Sur un film de 4 Go
/// cela faisait des dizaines de milliers de sérialisations + écritures disque
/// pendant toute la durée du téléchargement — l'une des causes du « ça consomme
/// trop », indépendante de la copie finale.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DownloadManagerService manager;

  DownloadTask task(String id) => DownloadTask(
        id: id,
        url: 'http://test/$id.mp4',
        displayName: id,
        finalPath: '/movies/$id.mp4',
        tempPath: '/movies/.$id.mp4.part',
        createdAt: DateTime(2026),
        totalSize: 4000000000, // 4 Go
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DownloadManagerService.progressNotifyInterval =
        const Duration(milliseconds: 250);
    manager = DownloadManagerService();
    await manager.init();
    manager.tasksNotifier.value = [];
    // Le service est un SINGLETON : sans ce reset, le palier de complétion
    // posé par le test précédent ferait échouer le suivant.
    manager.resetProgressThrottle('film');
    await manager.addTask(task('film'));
  });

  test('100 000 chunks en rafale → notifications bornées par le TEMPS', () async {
    var notifications = 0;
    void listener() => notifications++;
    manager.tasksNotifier.addListener(listener);
    addTearDown(() => manager.tasksNotifier.removeListener(listener));

    for (var i = 0; i <= 100000; i++) {
      manager.reportProgress(
        'film',
        progress: i / 100000,
        totalSize: 4000000000,
      );
    }

    // La boucle s'exécute en bien moins de 250 ms : quelques notifications
    // seulement, au lieu d'une par chunk.
    expect(notifications, lessThan(20));
  });

  test('le throttle est TEMPOREL, pas par pourcentage', () async {
    // Garde-fou de régression : caler les notifications sur le pourcentage
    // entier figeait la vitesse et l'ETA du moniteur (recalculés à chaque
    // notification) — sur un gros fichier, 1 % dure plusieurs secondes.
    DownloadManagerService.progressNotifyInterval = Duration.zero;
    var notifications = 0;
    void listener() => notifications++;
    manager.tasksNotifier.addListener(listener);
    addTearDown(() => manager.tasksNotifier.removeListener(listener));

    // 5 chunks tous dans le MÊME pourcentage entier (50 %).
    for (var i = 0; i < 5; i++) {
      manager.reportProgress(
        'film',
        progress: 0.5 + i * 0.00001,
        totalSize: 4000000000,
      );
    }
    expect(notifications, 5);
  });

  test('la progression finale est bien celle du dernier chunk', () async {
    for (var i = 0; i <= 1000; i++) {
      manager.reportProgress('film', progress: i / 1000, totalSize: 4000000000);
    }
    final t = manager.tasksNotifier.value.firstWhere((t) => t.id == 'film');
    expect(t.progress, 1.0);
    expect(t.status, DownloadStatus.downloading);
  });

  test('deux chunks dans le même intervalle → une seule notification', () {
    DownloadManagerService.progressNotifyInterval = const Duration(hours: 1);
    manager.reportProgress('film', progress: 0.1, totalSize: 4000000000);
    var notifications = 0;
    void listener() => notifications++;
    manager.tasksNotifier.addListener(listener);
    addTearDown(() => manager.tasksNotifier.removeListener(listener));

    manager.reportProgress('film', progress: 0.2, totalSize: 4000000000);
    manager.reportProgress('film', progress: 0.9, totalSize: 4000000000);
    expect(notifications, 0, reason: 'intervalle non écoulé');

    // La complétion échappe TOUJOURS au throttle, sinon la barre resterait
    // figée juste avant la fin.
    manager.reportProgress('film', progress: 1.0, totalSize: 4000000000);
    expect(notifications, 1);
  });

  test('tâche inconnue → aucun plantage, aucune notification', () {
    var notifications = 0;
    void listener() => notifications++;
    manager.tasksNotifier.addListener(listener);
    addTearDown(() => manager.tasksNotifier.removeListener(listener));

    manager.reportProgress('inexistante', progress: 0.5, totalSize: 100);
    expect(notifications, 0);
  });

  test('le throttle est réarmé après suppression de la tâche', () async {
    DownloadManagerService.progressNotifyInterval = const Duration(hours: 1);
    manager.reportProgress('film', progress: 0.5, totalSize: 4000000000);
    await manager.removeTask('film');
    await manager.addTask(task('film'));

    var notifications = 0;
    void listener() => notifications++;
    manager.tasksNotifier.addListener(listener);
    addTearDown(() => manager.tasksNotifier.removeListener(listener));

    // Sans réarmement, l'intervalle d'une heure de la tâche précédente
    // bloquerait la nouvelle.
    manager.reportProgress('film', progress: 0.5, totalSize: 4000000000);
    expect(notifications, 1);
  });
}
