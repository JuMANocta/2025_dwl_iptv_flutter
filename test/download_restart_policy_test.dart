import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aetherStream/data/models/download_task.dart';
import 'package:aetherStream/data/services/download_manager_service.dart';
import 'package:aetherStream/data/services/download_stall_policy.dart';

/// §dlLoop (2026-09-08) — « si on sort de l'application la relance se lance en
/// boucle ».
///
/// La règle `shouldAutoRestart` était CORRECTE et déjà testée
/// (`download_stall_policy_test.dart`) : elle refuse une relance à moins de
/// 30 s de la précédente, ou si celle-ci n'a pas rapporté 1 Mo. Le défaut était
/// ailleurs — ses deux ENTRÉES (`_lastAutoRestart`, `_bytesAtLastAutoRestart`)
/// étaient effacées par `_clearProgressThrottle`, appelée dans le `finally` du
/// transfert que la relance venait justement d'interrompre. Au tour suivant les
/// deux valeurs étaient `null`, donc `shouldAutoRestart(null, null) == true` :
/// ni le délai ni le gain minimal ne s'appliquaient jamais.
///
/// Ces tests verrouillent la DURÉE DE VIE de ces compteurs, pas la règle.
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
        totalSize: 4000000000,
        // ⚠️ PAS `queued` : le service est un SINGLETON et garde ses tâches
        // d'un test à l'autre. Le `pump()` du prochain `init()` ferait alors
        // PARTIR ce transfert pour de vrai (canal réseau, test qui échoue après
        // s'être terminé). `pickStartable` n'élit que les `queued`.
        status: DownloadStatus.downloading,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    manager = DownloadManagerService();
    // Vider AVANT l'init : `_loadTasksFromDisk` n'écrase la liste que s'il
    // trouve quelque chose sur le disque, donc sans ça le singleton entre dans
    // `init()` avec les tâches du test précédent.
    manager.tasksNotifier.value = [];
    await manager.init();
    manager.resetProgressThrottle('film');
    await manager.addTask(task('film'));
  });

  test('une relance automatique laisse une trace', () {
    expect(manager.restartPolicyStateForTest('film').at, isNull);
    manager.noteAutoRestartForTest('film', DateTime(2026, 1, 1, 12), 1000);
    final s = manager.restartPolicyStateForTest('film');
    expect(s.at, DateTime(2026, 1, 1, 12));
    expect(s.bytes, 1000);
  });

  test('🔴 la trace SURVIT à la fin du transfert que la relance a coupé', () {
    manager.noteAutoRestartForTest('film', DateTime(2026, 1, 1, 12), 1000);

    // C'est exactement ce que fait le `finally` de `_runDownload` quand le flux
    // coupé par `restartTask` se termine — donc AVANT que le nouveau transfert
    // ne démarre.
    manager.endOfTransferCleanupForTest('film');

    final s = manager.restartPolicyStateForTest('film');
    expect(s.at, isNotNull,
        reason: 'sans ça, le cooldown de 30 s ne peut jamais s\'appliquer');
    expect(s.bytes, 1000,
        reason: 'sans ça, le gain minimal de 1 Mo ne peut jamais s\'appliquer');
  });

  test('🔴 la boucle : deux décrochages rapprochés, la 2e relance est REFUSÉE',
      () {
    // Reconstitution du scénario signalé, avec la vraie règle.
    final t0 = DateTime(2026, 1, 1, 12, 0, 0);
    manager.noteAutoRestartForTest('film', t0, 10 * 1024 * 1024);
    manager.endOfTransferCleanupForTest('film'); // le flux coupé se termine

    // 5 s plus tard, l'arrière-plan fait re-décrocher le débit.
    final t1 = t0.add(const Duration(seconds: 5));
    final s = manager.restartPolicyStateForTest('film');
    final bool autorisee = shouldAutoRestart(
      sinceLastRestart: s.at == null ? null : t1.difference(s.at!),
      gainSinceLastRestart:
          s.bytes == null ? null : (10 * 1024 * 1024 + 4096) - s.bytes!,
    );

    expect(autorisee, isFalse,
        reason: 'moins de 30 s ET moins de 1 Mo gagné : c\'est la boucle');
  });

  test('un vrai bridage, lui, est toujours relancé (la règle reste utile)', () {
    final t0 = DateTime(2026, 1, 1, 12, 0, 0);
    manager.noteAutoRestartForTest('film', t0, 10 * 1024 * 1024);
    manager.endOfTransferCleanupForTest('film');

    // 2 min plus tard, 40 Mo de plus : la reconnexion précédente a servi.
    final t1 = t0.add(const Duration(minutes: 2));
    final s = manager.restartPolicyStateForTest('film');
    expect(
      shouldAutoRestart(
        sinceLastRestart: t1.difference(s.at!),
        gainSinceLastRestart: (50 * 1024 * 1024) - s.bytes!,
      ),
      isTrue,
    );
  });

  test('une tâche TERMINÉE oublie son historique', () async {
    manager.noteAutoRestartForTest('film', DateTime(2026), 1000);
    await manager.updateTask('film',
        status: DownloadStatus.completed, progress: 1.0);
    expect(manager.restartPolicyStateForTest('film').at, isNull);
  });

  test('⚠️ une ANNULATION ne l\'oublie pas — une relance passe par là', () async {
    // `restartTask` coupe le flux via `cancelTask`, qui publie `canceled` :
    // effacer l'historique sur cet état remettrait la boucle en place.
    manager.noteAutoRestartForTest('film', DateTime(2026), 1000);
    await manager.updateTask('film', status: DownloadStatus.canceled);
    expect(manager.restartPolicyStateForTest('film').at, isNotNull);
  });

  test('une tâche SUPPRIMÉE oublie son historique', () async {
    manager.noteAutoRestartForTest('film', DateTime(2026), 1000);
    await manager.removeTask('film');
    expect(manager.restartPolicyStateForTest('film').at, isNull);
  });
}
