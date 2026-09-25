// §notifAudit P5 (second volet) — « Appuyer pour ouvrir » sur la notification
// de fin de téléchargement retombait sur l'accueil : l'extra posé par le natif
// n'était lu par personne. Ces tests tiennent le chemin côté Dart : la route
// relayée par `MainActivity` (démarrage à froid ET app ouverte), la demande
// d'onglet, la tâche à mettre en vue, et la garde « on ne coupe pas un film ».
//
// Sincérité : retirer la garde du lecteur fait tomber « pendant un film » ;
// ne pas demander `takeOpenRoute` à l'attache fait tomber « démarrage à
// froid » ; un compteur sans consommation ferait tomber « une seule bascule ».

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/core/utils/notification_permission.dart';
import 'package:aetherStream/data/services/download_manager_service.dart';
import 'package:aetherStream/data/services/transfer_notification_bridge.dart';
import 'package:aetherStream/feature/downloads/logic/downloads_open_request.dart';
import 'package:aetherStream/feature/player/player_presence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(DownloadsOpenRequest.resetForTest);

  group('downloadsRouteFrom — ce que relaie MainActivity', () {
    test('la route des téléchargements, avec sa tâche', () {
      expect(downloadsRouteFrom({'route': 'downloads', 'taskId': 't1'}),
          (taskId: 't1'));
    });

    test('sans tâche (notification de progression) : l\'onglet seul', () {
      expect(downloadsRouteFrom({'route': 'downloads'}), (taskId: null));
      expect(downloadsRouteFrom({'route': 'downloads', 'taskId': ''}),
          (taskId: null));
    });

    test('rien, une autre route ou une forme inattendue : rien à faire', () {
      expect(downloadsRouteFrom(null), isNull);
      expect(downloadsRouteFrom({'route': 'player'}), isNull);
      expect(downloadsRouteFrom('downloads'), isNull);
    });
  });

  group('DownloadsOpenRequest', () {
    test('une demande = UNE bascule d\'onglet', () {
      expect(DownloadsOpenRequest.takeTabRequest(), isFalse);
      DownloadsOpenRequest.request(taskId: 't1');
      expect(DownloadsOpenRequest.takeTabRequest(), isTrue);
      expect(DownloadsOpenRequest.takeTabRequest(), isFalse);
    });

    test('deux demandes avant l\'écran principal (démarrage à froid) : une '
        'bascule, la DERNIÈRE tâche', () {
      DownloadsOpenRequest.request(taskId: 't1');
      DownloadsOpenRequest.request(taskId: 't2');
      expect(DownloadsOpenRequest.takeTabRequest(), isTrue);
      expect(DownloadsOpenRequest.takeTabRequest(), isFalse);
      expect(DownloadsOpenRequest.takeFocusTask(), 't2');
      expect(DownloadsOpenRequest.takeFocusTask(), isNull);
    });

    test('une demande sans tâche ne réveille pas une ancienne', () {
      DownloadsOpenRequest.request();
      expect(DownloadsOpenRequest.takeFocusTask(), isNull);
    });
  });

  test('⛔ pendant un film, pas de navigation', () {
    expect(shouldOpenDownloads(playerOpen: true), isFalse);
    expect(shouldOpenDownloads(playerOpen: false), isTrue);
  });

  test('index dans la liste : la section « Sur l\'appareil » passe devant', () {
    expect(downloadsListIndexOf(['a', 'b', 'c'], 'b', hasDeviceSection: false),
        1);
    expect(downloadsListIndexOf(['a', 'b', 'c'], 'b', hasDeviceSection: true),
        2);
    expect(downloadsListIndexOf(['a'], 'z', hasDeviceSection: true), -1);
  });

  group('TransferNotificationBridge — la route arrive jusqu\'à la demande', () {
    const notif = MethodChannel('aetherstream/transfer_notif');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    Object? launchRoute;

    Future<void> settle() async {
      for (int i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    /// Le natif appelle Dart (`openRoute`), comme `MainActivity.onNewIntent`.
    Future<void> nativeCalls(String method, Object? args) async {
      await messenger.handlePlatformMessage(
        notif.name,
        notif.codec.encodeMethodCall(MethodCall(method, args)),
        (_) {},
      );
      await settle();
    }

    setUp(() {
      launchRoute = null;
      TransferNotificationBridge.resetForTest();
      resetNotificationPermissionForTest();
      DownloadManagerService().tasksNotifier.value = [];
      messenger.setMockMethodCallHandler(notif, (call) async {
        if (call.method == 'takeOpenRoute') return launchRoute;
        return null;
      });
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(notif, null);
      while (PlayerPresence.isOpen) {
        PlayerPresence.leave();
      }
    });

    test('démarrage à froid : la route du lancement est demandée à l\'attache',
        () async {
      launchRoute = {'route': 'downloads', 'taskId': 't9'};
      TransferNotificationBridge.attach();
      await settle();
      expect(DownloadsOpenRequest.takeTabRequest(), isTrue);
      expect(DownloadsOpenRequest.takeFocusTask(), 't9');
    });

    test('app ouverte : `openRoute` du natif bascule sur l\'onglet', () async {
      TransferNotificationBridge.attach();
      await settle();
      expect(DownloadsOpenRequest.takeTabRequest(), isFalse);
      await nativeCalls('openRoute', {'route': 'downloads', 'taskId': 't3'});
      expect(DownloadsOpenRequest.takeTabRequest(), isTrue);
      expect(DownloadsOpenRequest.takeFocusTask(), 't3');
    });

    test('⛔ pendant un film : la notification ne le coupe pas', () async {
      TransferNotificationBridge.attach();
      await settle();
      PlayerPresence.enter();
      await nativeCalls('openRoute', {'route': 'downloads', 'taskId': 't3'});
      expect(DownloadsOpenRequest.takeTabRequest(), isFalse);
      expect(DownloadsOpenRequest.takeFocusTask(), isNull);
    });
  });
}
