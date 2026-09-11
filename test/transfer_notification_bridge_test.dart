import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/core/utils/notification_permission.dart';
import 'package:aetherStream/data/models/download_task.dart';
import 'package:aetherStream/data/services/download_manager_service.dart';
import 'package:aetherStream/data/services/transfer_notification_bridge.dart';

/// Revue 2026-09-11 — Le pont de notification des téléchargements (§dlNotif).
///
/// D3A-08 : un appel resté suspendu sur la boîte de permission reposait, après
/// coup, une notification PÉRIMÉE — après le `stopOngoing` — et plus rien ne
/// venait la retirer (notification et service de premier plan plantés).
/// D3A-18 : le throttle avalait `downloading → finalizing` : la notification
/// restait figée à « 99 % » pendant toute la finalisation.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const notif = MethodChannel('aetherstream/transfer_notif');
  const perms = MethodChannel('flutter.baseflow.com/permissions/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;

  DownloadTask task(DownloadStatus s, {double progress = 0.5}) => DownloadTask(
        id: 't1',
        url: 'http://h/1.mkv',
        displayName: 'Heat',
        finalPath: '/m/Heat.mkv',
        tempPath: '/m/.Heat.aetherpart.mkv',
        createdAt: DateTime(2026),
        status: s,
        progress: progress,
        totalSize: 1000,
      );

  Future<void> settle() async {
    for (int i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() {
    calls = [];
    TransferNotificationBridge.resetForTest();
    resetNotificationPermissionForTest();
    DownloadManagerService().tasksNotifier.value = [];
    messenger.setMockMethodCallHandler(notif, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(notif, null);
    messenger.setMockMethodCallHandler(perms, null);
  });

  test('🔴 D3A-08 — une réponse de permission tardive ne repose rien après '
      'l\'arrêt', () async {
    final answer = Completer<Map<int, int>>();
    messenger.setMockMethodCallHandler(perms, (call) async {
      if (call.method == 'checkPermissionStatus') return 0; // denied
      if (call.method == 'requestPermissions') {
        final ids = (call.arguments as List).cast<int>();
        final granted = await answer.future;
        return {for (final id in ids) id: granted.values.first};
      }
      return null;
    });

    TransferNotificationBridge.attach();
    final n = DownloadManagerService().tasksNotifier;
    n.value = [task(DownloadStatus.downloading)]; // la boîte système s'ouvre
    await settle();
    n.value = [task(DownloadStatus.completed, progress: 1)]; // fini entre-temps
    await settle();
    answer.complete({0: 1}); // l'utilisateur accepte, APRÈS
    await settle();

    final methods = calls.map((c) => c.method).toList();
    expect(methods, contains('stopOngoing'));
    expect(methods.lastIndexOf('startOrUpdate'),
        lessThan(methods.lastIndexOf('stopOngoing')),
        reason: 'rien ne doit être reposé après l\'arrêt : $methods');
  });

  test('🔴 D3A-18 — la finalisation passe même dans la fenêtre du throttle',
      () async {
    messenger.setMockMethodCallHandler(perms, (call) async {
      if (call.method == 'checkPermissionStatus') return 1; // granted
      return null;
    });

    TransferNotificationBridge.attach();
    final n = DownloadManagerService().tasksNotifier;
    n.value = [task(DownloadStatus.downloading, progress: 0.99)];
    await settle();
    // Moins d'une seconde plus tard : ce n'est plus une progression.
    n.value = [task(DownloadStatus.finalizing, progress: 1)];
    await settle();

    final updates = calls.where((c) => c.method == 'startOrUpdate').toList();
    expect(updates, hasLength(2));
    expect((updates.last.arguments as Map)['indeterminate'], isTrue);
  });

  test('une simple progression dans la seconde reste throttlée', () async {
    messenger.setMockMethodCallHandler(perms, (call) async {
      if (call.method == 'checkPermissionStatus') return 1;
      return null;
    });

    TransferNotificationBridge.attach();
    final n = DownloadManagerService().tasksNotifier;
    n.value = [task(DownloadStatus.downloading, progress: 0.40)];
    await settle();
    n.value = [task(DownloadStatus.downloading, progress: 0.41)];
    await settle();

    expect(calls.where((c) => c.method == 'startOrUpdate'), hasLength(1));
  });
}
