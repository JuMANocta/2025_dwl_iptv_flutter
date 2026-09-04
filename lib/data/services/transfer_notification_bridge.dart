import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/utils/notification_permission.dart';
import '../../core/utils/platform_tv.dart';
import '../models/download_task.dart';
import 'download_manager_service.dart';
import 'download_notice.dart';

/// §dlNotif — Pont entre `DownloadManagerService.tasksNotifier` (le SEUL
/// canal d'état des téléchargements, `download_manager_service.dart:23`) et
/// le canal natif `aetherstream/transfer_notif`.
///
/// ⚠️ **N'introduit PAS de second état** : ce pont ne fait que LIRE
/// `tasksNotifier` et traduire ce qu'il voit. `downloadTileActions` et le
/// reste de l'UI restent la seule vérité sur une tâche.
abstract final class TransferNotificationBridge {
  static const MethodChannel _channel =
      MethodChannel('aetherstream/transfer_notif');

  static bool _wired = false;
  static List<DownloadTask> _previous = const [];

  /// Throttle propre au pont — distinct de `progressNotifyInterval` (250 ms,
  /// pour l'UI) : `startForegroundService` a un coût réel, une notification
  /// système ne doit pas être reposée 4×/s.
  static DateTime _lastPush = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _minInterval = Duration(seconds: 1);

  /// `true` si la dernière décision montrait quelque chose. Sert à détecter
  /// les TRANSITIONS (apparition/disparition) pour ne jamais les throttler —
  /// voir le commentaire dans [_onTasksChanged].
  static bool _wasShowing = false;

  /// Appelé une fois depuis `main.dart`, après
  /// `DownloadManagerService().init()`.
  static void attach() {
    if (_wired) return;
    _wired = true;
    _channel.setMethodCallHandler(_onNativeCall);
    final notifier = DownloadManagerService().tasksNotifier;
    // ⚠️ La liste courante (déjà réconciliée au boot — §dlWatchdog bascule
    // les tâches interrompues en `failed`) sert de LIGNE DE BASE : sans ça,
    // `finishedTransitions` comparerait à une liste vide et annoncerait
    // « échec » pour chaque téléchargement interrompu lors d'une session
    // précédente, à chaque redémarrage de l'app.
    _previous = notifier.value;
    notifier.addListener(() => _onTasksChanged(notifier.value));
  }

  static Future<void> _onTasksChanged(List<DownloadTask> current) async {
    for (final f in finishedTransitions(_previous, current)) {
      unawaited(_postFinished(f));
    }
    _previous = current;

    // ⚠️ La permission n'est jamais demandée s'il n'y a rien à montrer : un
    // appel à `ensureNotificationPermission()` avant même de savoir si une
    // notification est utile ferait apparaître la boîte système au premier
    // téléchargement même minuscule ET au premier lancement (liste vide).
    final bool granted = hasActiveDownloads(current)
        ? await ensureNotificationPermission()
        : false;

    final notice =
        downloadNotice(current, isTv: PlatformTv.isTv, granted: granted);

    // ⚠️ **Les TRANSITIONS ne sont JAMAIS throttlées.** Bug constaté sur
    // appareil : annuler un téléchargement juste après une mise à jour de
    // progression tombait dans la fenêtre de throttle — le `stopOngoing` était
    // avalé, et comme plus AUCUN événement ultérieur ne survient sur une tâche
    // qui vient de s'arrêter, la notification et le service de premier plan
    // restaient plantés indéfiniment. Seules les répétitions d'un MÊME état
    // (progression qui avance) sont throttlées ; apparition et disparition de
    // la notification passent toujours.
    final bool isEdge = _wasShowing != (notice != null);
    _wasShowing = notice != null;
    final now = DateTime.now();
    if (!isEdge && now.difference(_lastPush) < _minInterval) return;
    _lastPush = now;

    try {
      if (notice == null) {
        await _channel.invokeMethod('stopOngoing');
      } else {
        await _channel.invokeMethod('startOrUpdate', {
          'title': notice.title,
          'text': notice.text,
          'progress':
              notice.progress == null ? -1 : (notice.progress! * 100).round(),
          'indeterminate': notice.progress == null,
          'cancelTaskId': notice.cancelTaskId,
        });
      }
    } catch (e) {
      debugPrint('⚠️ TransferNotificationBridge : $e');
    }
  }

  static Future<void> _postFinished(DownloadFinishNotice f) async {
    try {
      await _channel.invokeMethod('postFinished', {
        // Un hash de chaîne, jamais l'id fixe de l'agrégat (côté natif,
        // `AetherDownloadService`) : un chevauchement resterait sans
        // conséquence — au pire une notification de fin en écrase une autre.
        'id': f.task.id.hashCode,
        'title': f.task.displayName,
        'success': f.success,
      });
    } catch (e) {
      debugPrint('⚠️ TransferNotificationBridge.postFinished : $e');
    }
  }

  static Future<void> _onNativeCall(MethodCall call) async {
    if (call.method != 'onDownloadAction') return;
    final args = (call.arguments as Map?) ?? const {};
    if (args['action'] == 'cancel') {
      final id = args['taskId'] as String?;
      if (id != null) await DownloadManagerService().cancelTask(id);
    }
  }

  /// Tests uniquement.
  @visibleForTesting
  static void resetForTest() {
    _wired = false;
    _previous = const [];
    _lastPush = DateTime.fromMillisecondsSinceEpoch(0);
    _wasShowing = false;
  }
}
