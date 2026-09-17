import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/utils/notification_permission.dart';
import '../../core/utils/platform_tv.dart';
import '../../l10n/l10n_ext.dart';
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

  /// D3A-18 — Forme de la dernière notification poussée (barre indéterminée,
  /// nombre de tâches). Un changement de forme est une transition : sans ça,
  /// `downloading → finalizing` tombait dans le throttle et la notification
  /// restait figée à « 99 % » pendant toute la finalisation.
  static bool _wasIndeterminate = false;
  static int _lastCount = 0;

  /// D3A-08 — Numéro du dernier appel. Un appel resté suspendu sur la boîte
  /// de permission ne doit pas reposer, après coup, un état PÉRIMÉ (celui
  /// d'avant le `stopOngoing`, qui aurait laissé la notification et le
  /// service de premier plan plantés pour de bon).
  static int _seq = 0;

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
    // §notifAudit P4 — Pas de notification de fin sur un téléviseur : personne
    // n'y déroule un tiroir, et le tiroir d'Android TV ne la montre même pas
    // (même porte que §nowPlaying et §pipPhone).
    if (!PlatformTv.isTv) {
      for (final f in finishedTransitions(_previous, current)) {
        unawaited(_postFinished(f));
      }
    }
    _previous = current;
    final int seq = ++_seq;

    // ⚠️ La permission n'est jamais demandée s'il n'y a rien à montrer : un
    // appel à `ensureNotificationPermission()` avant même de savoir si une
    // notification est utile ferait apparaître la boîte système au premier
    // téléchargement même minuscule ET au premier lancement (liste vide).
    //
    // §notifAudit P3 — ⚠️ On DEMANDE, on n'ATTEND PLUS la réponse : un refus
    // ne doit plus rien décider. Il arrêtait le service de premier plan (via
    // `downloadNotice`, qui rendait `null`), donc le transfert perdait ce qui
    // le gardait en vie. La boîte système reste proposée une fois ; qu'on dise
    // oui ou non, le service tourne.
    if (hasActiveDownloads(current)) {
      unawaited(ensureNotificationPermission());
    }
    // D3A-08 — Un appel plus récent est passé pendant l'attente : c'est lui
    // qui a le dernier mot.
    if (seq != _seq) return;

    final notice = downloadNotice(current, isTv: PlatformTv.isTv);

    // ⚠️ **Les TRANSITIONS ne sont JAMAIS throttlées.** Bug constaté sur
    // appareil : annuler un téléchargement juste après une mise à jour de
    // progression tombait dans la fenêtre de throttle — le `stopOngoing` était
    // avalé, et comme plus AUCUN événement ultérieur ne survient sur une tâche
    // qui vient de s'arrêter, la notification et le service de premier plan
    // restaient plantés indéfiniment. Seules les répétitions d'un MÊME état
    // (progression qui avance) sont throttlées ; apparition et disparition de
    // la notification passent toujours.
    final bool indeterminate = notice != null && notice.progress == null;
    final int count = notice?.activeCount ?? 0;
    final bool isEdge = _wasShowing != (notice != null) ||
        (notice != null &&
            (indeterminate != _wasIndeterminate || count != _lastCount));
    _wasShowing = notice != null;
    _wasIndeterminate = indeterminate;
    _lastCount = count;
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
          // Revue 2026-09-11, D3L-02 — le libellé du bouton vient de Dart,
          // dans la langue de l'écran ; le natif n'a plus qu'un REPLI.
          'cancelLabel': L10n.current.commonCancel,
        });
      }
    } catch (e) {
      debugPrint('⚠️ TransferNotificationBridge : $e');
    }
  }

  static Future<void> _postFinished(DownloadFinishNotice f) async {
    // §notifAudit P6 — Titre, raison de l'échec et bouton « Relancer » sont
    // décidés par une fonction PURE, testée (`downloadFinishCard`).
    final DownloadFinishCard card = downloadFinishCard(f);
    try {
      await _channel.invokeMethod('postFinished', {
        // Un hash de chaîne, jamais l'id fixe de l'agrégat (côté natif,
        // `AetherDownloadService`) : un chevauchement resterait sans
        // conséquence — au pire une notification de fin en écrase une autre.
        'id': f.task.id.hashCode,
        'title': card.title,
        'success': f.success,
        // D3L-02 — texte de la notification de fin, traduit ici.
        'text': card.text,
        'restartTaskId': card.restartTaskId,
        'restartLabel': L10n.current.dlActionRestart,
        // §notifAudit P5 — Nom du canal « terminés » : traduit ici, comme le
        // reste. Android met à jour le nom d'un canal existant, il suit donc
        // la langue de l'appareil (D2B-17).
        'doneChannelName': L10n.current.dlNotifChannelDone,
      });
    } catch (e) {
      debugPrint('⚠️ TransferNotificationBridge.postFinished : $e');
    }
  }

  static Future<void> _onNativeCall(MethodCall call) async {
    if (call.method != 'onDownloadAction') return;
    final args = (call.arguments as Map?) ?? const {};
    final String? id = args['taskId'] as String?;
    if (id == null) return;
    switch (args['action']) {
      case 'cancel':
        await DownloadManagerService().cancelTask(id);
      case 'restart':
        // §notifAudit P6 — « Relancer » depuis la notification d'échec :
        // par la FILE (§dlQueue), jamais en direct — sinon on ouvrirait une
        // seconde connexion sur l'abonnement.
        final DownloadTask? t = DownloadManagerService()
            .tasksNotifier
            .value
            .where((x) => x.id == id)
            .firstOrNull;
        if (t == null) {
          debugPrint('⚠️ §notifAudit — relance demandée pour une tâche inconnue : $id');
          return;
        }
        debugPrint('🔁 §notifAudit — relance demandée depuis la notification : $id');
        await DownloadManagerService().enqueue(t);
    }
  }

  /// Tests uniquement.
  @visibleForTesting
  static void resetForTest() {
    _wired = false;
    _previous = const [];
    _lastPush = DateTime.fromMillisecondsSinceEpoch(0);
    _wasShowing = false;
    _wasIndeterminate = false;
    _lastCount = 0;
    _seq = 0;
  }
}
