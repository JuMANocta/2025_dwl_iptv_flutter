import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/models/download_task.dart';
import 'package:aetherStream/data/services/download_notice.dart';

/// §dlNotif — Ce que la notification de téléchargement affiche est décidé
/// par deux fonctions PURES : `downloadNotice` (l'état courant) et
/// `finishedTransitions` (les fins de transfert, ponctuelles). Le service de
/// premier plan (§dlNotif — sans lui la notification mentirait) n'est
/// vérifiable que sur appareil ; ces tests verrouillent la décision.
void main() {
  DownloadTask task({
    required String id,
    String name = 'Film',
    DownloadStatus status = DownloadStatus.downloading,
    double progress = 0.0,
  }) =>
      DownloadTask(
        id: id,
        url: 'https://panel.example/movie/user/pass/1.mkv',
        displayName: name,
        finalPath: '/storage/emulated/0/Movies/AetherStream/$name.mkv',
        tempPath: '/data/user/0/com.juman.aetherstream/cache/dl_tmp/$id',
        status: status,
        progress: progress,
        totalSize: 1000,
        createdAt: DateTime(2026, 1, 1),
      );

  group('downloadNotice', () {
    test('aucune tâche active : rien à annoncer', () {
      final tasks = [
        task(id: '1', status: DownloadStatus.completed),
        task(id: '2', status: DownloadStatus.canceled),
      ];
      expect(downloadNotice(tasks, isTv: false), isNull);
    });

    test('TV : jamais, même avec une tâche active', () {
      final tasks = [task(id: '1')];
      expect(downloadNotice(tasks, isTv: true), isNull);
    });

    test('🔴 §notifAudit P3 — la permission de notification ne décide plus rien',
        () {
      // Elle rendait `null` quand POST_NOTIFICATIONS était refusée : le pont
      // appelait alors `stopOngoing` et le SERVICE de premier plan s'arrêtait
      // — or c'est lui qui garde le processus, donc le transfert, en vie.
      // Refuser la notification doit coûter la notification, pas le
      // téléchargement. La fonction n'a même plus de paramètre `granted`.
      final tasks = [task(id: '1', progress: 0.42)];
      expect(downloadNotice(tasks, isTv: false), isNotNull);
    });

    test('une tâche en téléchargement : titre = nom, pourcentage exact', () {
      final n = downloadNotice(
        [task(id: '1', name: 'Dune', progress: 0.42)],
        isTv: false,
      )!;
      expect(n.title, 'Dune');
      // §notifAudit P7 — « 420 octets sur 1 000 octets » : la taille dit ce
      // qui reste, le pourcentage non (la barre le porte déjà).
      expect(n.text, contains('420'));
      expect(n.text, contains('sur'));
      expect(n.text, isNot(contains('42 %')));
      expect(n.progress, closeTo(0.42, 0.001));
      expect(n.activeCount, 1);
      expect(n.cancelTaskId, '1'); // une seule tâche → bouton Annuler ciblé
    });

    test('en attente / finalisation : barre indéterminée, pas de pourcentage',
        () {
      final queued = downloadNotice(
        [task(id: '1', status: DownloadStatus.queued)],
        isTv: false,
      )!;
      expect(queued.text, 'En attente…');
      expect(queued.progress, isNull);

      final finalizing = downloadNotice(
        [task(id: '1', status: DownloadStatus.finalizing)],
        isTv: false,
      )!;
      expect(finalizing.text, 'Finalisation…');
      expect(finalizing.progress, isNull);
    });

    test('D3A-07 — pas d\'« Annuler » pendant la finalisation', () {
      // Le transfert est fini : l'interrompre laisserait une copie à moitié
      // faite, et la tuile le refusait déjà.
      final finalizing = downloadNotice(
        [task(id: '1', status: DownloadStatus.finalizing)],
        isTv: false,
      )!;
      expect(finalizing.cancelTaskId, isNull);

      final queued = downloadNotice(
        [task(id: '1', status: DownloadStatus.queued)],
        isTv: false,
      )!;
      expect(queued.cancelTaskId, '1');
    });

    test('plusieurs tâches actives : accord pluriel, pas de cible d\'annulation',
        () {
      final n = downloadNotice(
        [
          task(id: '1', progress: 0.2),
          task(id: '2', progress: 0.6),
          task(id: '3', status: DownloadStatus.queued),
        ],
        isTv: false,
      )!;
      expect(n.title, '3 téléchargements');
      expect(n.activeCount, 3);
      expect(n.cancelTaskId, isNull);
      // (0.2 + 0.6 + 0.0) / 3 = 0.2667 → 27 %
      expect(n.text, '27 % en moyenne');
    });

    test('accord singulier : « 1 téléchargement » jamais affiché comme titre '
        'générique — le titre EST le nom du fichier', () {
      final n = downloadNotice(
        [task(id: '1', name: 'Mon Film')],
        isTv: false,
      )!;
      expect(n.title, 'Mon Film');
    });

    test('aucun champ ne contient l\'URL ou des identifiants', () {
      final n = downloadNotice(
        [task(id: '1', name: 'Dune')],
        isTv: false,
      )!;
      for (final s in [n.title, n.text, n.cancelTaskId ?? '']) {
        expect(s, isNot(contains('panel.example')));
        expect(s, isNot(contains('user')));
        expect(s, isNot(contains('pass')));
      }
    });
  });

  group('downloadFinishCard (§notifAudit P6)', () {
    test('succès : pas de « Relancer » — le fichier est là', () {
      final c = downloadFinishCard(
        (task: task(id: '1', name: 'Dune', status: DownloadStatus.completed),
         success: true),
      );
      expect(c.title, 'Dune');
      expect(c.restartTaskId, isNull,
          reason: 'proposer de refaire plusieurs Go sur un fichier déjà '
              'terminé est exactement ce que §dlErgo interdit.');
    });

    test('🔴 échec : la RAISON est dite, et « Relancer » désigne la tâche', () {
      final t = DownloadTask(
        id: 'x9',
        url: 'https://panel.example/movie/user/pass/1.mkv',
        displayName: 'Dune',
        finalPath: '/movies/Dune.mkv',
        tempPath: '/movies/.Dune.aetherpart.mkv',
        status: DownloadStatus.failed,
        errorMessage: 'La connexion a été perdue',
        totalSize: 1000,
        createdAt: DateTime(2026, 1, 1),
      );
      final c = downloadFinishCard((task: t, success: false));
      expect(c.text, 'La connexion a été perdue',
          reason: 'la notification n\'annonçait qu\'« échec », sans dire '
              'pourquoi : la raison est déjà écrite sur la tâche, passée '
              'par describeError (§userError).');
      expect(c.restartTaskId, 'x9',
          reason: 'sans cible, il n\'y a pas de bouton — l\'utilisateur '
              'devait rouvrir l\'app et retrouver la tuile.');
    });

    test('échec sans message : un texte de repli, jamais un vide', () {
      final c = downloadFinishCard(
        (task: task(id: '2', status: DownloadStatus.failed), success: false),
      );
      expect(c.text.trim(), isNotEmpty);
      expect(c.restartTaskId, '2');
    });

    test('aucun champ ne laisse fuir l\'URL ni les identifiants', () {
      final c = downloadFinishCard(
        (task: task(id: '3', name: 'Dune', status: DownloadStatus.failed),
         success: false),
      );
      for (final v in [c.title, c.text, c.restartTaskId ?? '']) {
        expect(v, isNot(contains('panel.example')));
        expect(v, isNot(contains('pass')));
      }
    });
  });

  group('hasActiveDownloads', () {
    test('vrai avec une tâche active, faux sinon', () {
      expect(hasActiveDownloads([task(id: '1')]), isTrue);
      expect(
        hasActiveDownloads([task(id: '1', status: DownloadStatus.completed)]),
        isFalse,
      );
      expect(hasActiveDownloads(const []), isFalse);
    });
  });

  group('finishedTransitions', () {
    test('succès : downloading → completed', () {
      final prev = [task(id: '1', status: DownloadStatus.downloading)];
      final cur = [task(id: '1', status: DownloadStatus.completed)];
      final out = finishedTransitions(prev, cur);
      expect(out, hasLength(1));
      expect(out.first.success, isTrue);
    });

    test('échec : downloading → failed', () {
      final prev = [task(id: '1', status: DownloadStatus.downloading)];
      final cur = [task(id: '1', status: DownloadStatus.failed)];
      expect(finishedTransitions(prev, cur).single.success, isFalse);
    });

    test('annulation : jamais signalée — l\'utilisateur vient de le faire',
        () {
      final prev = [task(id: '1', status: DownloadStatus.downloading)];
      final cur = [task(id: '1', status: DownloadStatus.canceled)];
      expect(finishedTransitions(prev, cur), isEmpty);
    });

    test('déjà terminée au tour précédent : PAS re-signalée', () {
      // ⚠️ Le cœur du correctif : sans cette garde, chaque frappe de
      // progression d'une AUTRE tâche redéclencherait la notification finale
      // de celle-ci.
      final prev = [task(id: '1', status: DownloadStatus.completed)];
      final cur = [task(id: '1', status: DownloadStatus.completed)];
      expect(finishedTransitions(prev, cur), isEmpty);
    });

    test('arrivée déjà terminée (absente de previous, ex. reconciliation au '
        'boot) : PAS signalée', () {
      final cur = [task(id: '1', status: DownloadStatus.failed)];
      expect(finishedTransitions(const [], cur), isEmpty);
    });

    test('plusieurs tâches, une seule finit : une seule notification', () {
      final prev = [
        task(id: '1', status: DownloadStatus.downloading),
        task(id: '2', status: DownloadStatus.downloading),
      ];
      final cur = [
        task(id: '1', status: DownloadStatus.completed),
        task(id: '2', status: DownloadStatus.downloading),
      ];
      final out = finishedTransitions(prev, cur);
      expect(out, hasLength(1));
      expect(out.first.task.id, '1');
    });
  });
}
