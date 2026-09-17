// §dlQueueFix — Ce que la réconciliation au DÉMARRAGE doit décider pour une
// tâche retrouvée `downloading` ou `finalizing` après un arrêt de l'app
// (balayage dans les Récents, processus tué par Android). Avant le correctif,
// TOUT basculait en `failed` alors que le fichier partiel — et la reprise
// `Range` — étaient toujours là. Cf. l'en-tête de
// lib/data/services/download_retry_policy.dart.

import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/data/models/download_task.dart';
import 'package:aetherStream/data/services/download_retry_policy.dart';

void main() {
  group('startupReconcileVerdict — downloading', () {
    test('partiel présent → requeue (la reprise Range existe)', () {
      final verdict = startupReconcileVerdict(
        status: DownloadStatus.downloading,
        partialExists: true,
        finalSizeOk: false,
      );
      expect(
        verdict,
        StartupReconcileVerdict.requeue,
        reason: '§dlQueueFix : le défaut payé faisait tout basculer en '
            'failed alors que le .part sur le disque permet à la reprise '
            'Range de repartir exactement au bon octet.',
      );
    });

    test('pas de partiel → fail', () {
      final verdict = startupReconcileVerdict(
        status: DownloadStatus.downloading,
        partialExists: false,
        finalSizeOk: false,
      );
      expect(
        verdict,
        StartupReconcileVerdict.fail,
        reason: 'sans .part, aucune reprise Range possible : rien à '
            'remettre en file, l\'utilisateur doit relancer.',
      );
    });

    test(
      'pas de partiel mais finalSizeOk → fail quand même (nom réservé, §dlEpisode)',
      () {
        final verdict = startupReconcileVerdict(
          status: DownloadStatus.downloading,
          partialExists: false,
          finalSizeOk: true,
        );
        expect(
          verdict,
          StartupReconcileVerdict.fail,
          reason:
              '§dlEpisode : downloading ne doit JAMAIS regarder le fichier '
              'final — son nom n\'est qu\'un nom RÉSERVÉ, un homonyme '
              'déposé par l\'utilisateur ne doit pas faire passer pour '
              'terminé un transfert qui n\'a rien écrit.',
        );
      },
    );
  });

  group('startupReconcileVerdict — finalizing', () {
    test('partiel présent → refinalize (le renommage n\'a pas eu lieu)', () {
      final verdict = startupReconcileVerdict(
        status: DownloadStatus.finalizing,
        partialExists: true,
        finalSizeOk: false,
      );
      expect(
        verdict,
        StartupReconcileVerdict.refinalize,
        reason: 'le flux était fini mais le déplacement/MediaStore a été '
            'interrompu : le .part encore présent le prouve, on rejoue la '
            'finalisation au lieu de perdre le fichier.',
      );
    });

    test(
      'pas de partiel + finalSizeOk → complete (le renommage avait réussi)',
      () {
        final verdict = startupReconcileVerdict(
          status: DownloadStatus.finalizing,
          partialExists: false,
          finalSizeOk: true,
        );
        expect(
          verdict,
          StartupReconcileVerdict.complete,
          reason: 'le fichier final existe et n\'est pas tronqué : seul le '
              'statut n\'a pas eu le temps d\'être écrit avant l\'arrêt, ce '
              'n\'est pas un échec.',
        );
      },
    );

    test('rien des deux → fail', () {
      final verdict = startupReconcileVerdict(
        status: DownloadStatus.finalizing,
        partialExists: false,
        finalSizeOk: false,
      );
      expect(
        verdict,
        StartupReconcileVerdict.fail,
        reason: 'ni le partiel ni un final crédible : rien à reprendre.',
      );
    });
  });

  test('tous les autres statuts → keep, quelles que soient les deux booléennes', () {
    final autres = DownloadStatus.values.where(
      (s) => s != DownloadStatus.downloading && s != DownloadStatus.finalizing,
    );
    // queued, paused, completed, failed, canceled — les 5 valeurs restantes
    // de l'enum (7 au total, cf. download_task.dart).
    expect(autres.length, 5);

    for (final status in autres) {
      for (final partialExists in [false, true]) {
        for (final finalSizeOk in [false, true]) {
          final verdict = startupReconcileVerdict(
            status: status,
            partialExists: partialExists,
            finalSizeOk: finalSizeOk,
          );
          expect(
            verdict,
            StartupReconcileVerdict.keep,
            reason: '$status (partialExists=$partialExists, '
                'finalSizeOk=$finalSizeOk) ne doit rien changer : seuls '
                'downloading et finalizing sont réconciliés au démarrage.',
          );
        }
      }
    }
  });
}
