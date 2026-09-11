import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aetherStream/core/settings/perf_config.dart';
import 'package:aetherStream/core/settings/performance_settings_service.dart';
import 'package:aetherStream/core/utils/network_kind.dart';
import 'package:aetherStream/data/models/download_task.dart';
import 'package:aetherStream/data/services/download_manager_service.dart';

/// Revue 2026-09-11 (D3L-01) — Au démarrage, « Wi-Fi seulement » doit retenir
/// les téléchargements repris AVANT qu'un seul ne parte.
///
/// Le défaut : `DownloadManagerService().init()` et
/// `PerformanceSettingsService.load()` partaient dans le même `Future.wait` ;
/// le premier `pump()` lisait les réglages AVANT leur chargement (ordre des
/// microtâches), donc les valeurs par défaut — « Wi-Fi seulement » éteint —
/// et les tâches en attente partaient sur les données mobiles.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const device = MethodChannel('aetherstream/device');

  final queued = DownloadTask(
    id: 'ep1',
    url: 'http://test/ep1.mkv',
    displayName: 'Épisode 1',
    finalPath: '/movies/ep1.mkv',
    tempPath: '/movies/.ep1.aetherpart.mkv',
    createdAt: DateTime(2026),
    status: DownloadStatus.queued,
  );

  // Tous les statuts vus passer : un départ, même aussitôt remis en file par
  // un échec réseau, laisserait sa trace ici.
  final Set<DownloadStatus> seen = {};
  void record() => seen.addAll(
      DownloadManagerService().tasksNotifier.value.map((t) => t.status));

  setUp(() {
    // Données mobiles, facturées.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(device, (call) async {
      if (call.method == 'network') {
        return {'transport': 'cellular', 'metered': true};
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({
      'aether_perf_v1': jsonEncode({'dwo': true}),
      'download_tasks_list': jsonEncode([queued.toJson()]),
    });
    // Les réglages en mémoire repartent des valeurs par défaut, comme au
    // lancement du processus : sans ça le test précédent les aurait déjà
    // chargés et le second passerait sans rien prouver.
    PerformanceSettingsService.config.value = PerfConfig.defaults;
    DownloadManagerService().tasksNotifier.value = [];
    seen.clear();
    DownloadManagerService().tasksNotifier.addListener(record);
  });

  tearDown(() {
    DownloadManagerService().tasksNotifier.removeListener(record);
    DownloadManagerService().resetQueueForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(device, null);
  });

  Future<void> settle() async {
    for (int i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  void expectHeld() {
    final m = DownloadManagerService();
    expect(m.tasksNotifier.value.single.status, DownloadStatus.queued,
        reason: 'aucune tâche ne doit partir sur un réseau facturé');
    expect(m.hold.value, DownloadHold.wifi);
    expect(seen, isNot(contains(DownloadStatus.downloading)),
        reason: 'la tâche n\'a jamais dû partir, même un instant');
  }

  test('ordre du démarrage : réglages chargés AVANT les téléchargements',
      () async {
    await PerformanceSettingsService.load();
    await DownloadManagerService().init();
    await settle();
    expectHeld();
  });

  test('🔴 même chargés EN PARALLÈLE, la file lit les réglages à jour', () async {
    // L'ancien ordre de `_initServices` : la file doit relire les réglages
    // APRÈS avoir sondé le réseau, pas avant.
    await Future.wait([
      DownloadManagerService().init(),
      PerformanceSettingsService.load(),
    ]);
    await settle();
    expectHeld();
  });
}
