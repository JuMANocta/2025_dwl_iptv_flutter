// §dlQueueFix — Le délai de remise en file (§dlQueue) ne doit ni brûler les
// crédits de kMaxNetworkRequeues en martelant la source, ni figer une tâche
// « au chaud » comme si elle occupait une place. Cf. l'en-tête de
// lib/feature/downloads/logic/download_scheduler.dart.

import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/data/models/download_task.dart';
import 'package:aetherStream/feature/downloads/logic/download_scheduler.dart';

DownloadTask _task(
  String id,
  String url, {
  required int order,
  DownloadStatus status = DownloadStatus.queued,
}) => DownloadTask(
  id: id,
  url: url,
  displayName: id,
  finalPath: '/x/$id.mkv',
  tempPath: '/x/$id.part',
  totalSize: 0,
  status: status,
  createdAt: DateTime(2026, 9, 16, 12, order),
);

List<String> _ids(List<DownloadTask> l) => l.map((t) => t.id).toList();

void main() {
  group('requeueBackoffFor', () {
    test('0 → zéro, 1/2/3 → paliers croissants, au-delà → dernier palier', () {
      expect(
        requeueBackoffFor(0),
        Duration.zero,
        reason: 'la première tentative ne doit jamais attendre.',
      );
      expect(requeueBackoffFor(1), const Duration(seconds: 5));
      expect(requeueBackoffFor(2), const Duration(seconds: 15));
      expect(requeueBackoffFor(3), const Duration(seconds: 45));
      expect(
        requeueBackoffFor(4),
        const Duration(seconds: 45),
        reason: 'au-delà du dernier palier défini, c\'est ce dernier palier '
            'qui continue de s\'appliquer.',
      );
      expect(requeueBackoffFor(10), const Duration(seconds: 45));
    });

    test('kRequeueBackoff est strictement croissant', () {
      expect(
        kRequeueBackoff.length,
        greaterThanOrEqualTo(2),
        reason: 'une suite à un seul palier ne prouve rien sur la '
            'croissance.',
      );
      for (var i = 1; i < kRequeueBackoff.length; i++) {
        expect(
          kRequeueBackoff[i] > kRequeueBackoff[i - 1],
          isTrue,
          reason: 'un palier qui n\'augmente pas laisserait une source '
              'morte être martelée au même rythme qu\'une simple coupure '
              'brève.',
        );
      }
    });
  });

  test('showParallelDownloadsSetting : muet en dessous de 2 abonnements', () {
    expect(showParallelDownloadsSetting(0), isFalse);
    expect(
      showParallelDownloadsSetting(1),
      isFalse,
      reason: 'avec un seul abonnement, la file n\'autorise qu\'UN '
          'transfert par hôte (§dlQueue, §hostGate) : le curseur ne '
          'changerait rien — un réglage qui ne fait rien ment à qui le '
          'tourne.',
    );
    expect(showParallelDownloadsSetting(2), isTrue);
    expect(showParallelDownloadsSetting(5), isTrue);
  });

  group('pickStartable — notBefore / now (§dlQueueFix)', () {
    test('notBefore dans le futur : la tâche n\'est pas élue', () {
      final now = DateTime(2026, 9, 16, 12, 30);
      final future = now.add(const Duration(minutes: 5));
      final a = _task('a', 'http://a.test/1.mkv', order: 0); // la plus ancienne
      final b = _task('b', 'http://b.test/2.mkv', order: 1);

      final picks = pickStartable(
        tasks: [a, b],
        inFlightIds: {},
        maxParallel: 2,
        notBefore: {'a': future},
        now: now,
      );

      expect(
        _ids(picks),
        ['b'],
        reason: '§dlQueueFix : a est encore au chaud après une remise en '
            'file — la relancer immédiatement brûlerait les crédits de '
            'kMaxNetworkRequeues en moins d\'une seconde.',
      );
    });

    test('l\'échéance passée, la même tâche redevient éligible', () {
      final deadline = DateTime(2026, 9, 16, 12, 30);
      final after = deadline.add(const Duration(seconds: 1));
      final a = _task('a', 'http://a.test/1.mkv', order: 0);
      final b = _task('b', 'http://b.test/2.mkv', order: 1);

      final picks = pickStartable(
        tasks: [a, b],
        inFlightIds: {},
        maxParallel: 2,
        notBefore: {'a': deadline},
        now: after,
      );

      expect(
        _ids(picks),
        ['a', 'b'],
        reason: 'le sondage doit reprendre a dès que son échéance est '
            'passée, sans geste manuel.',
      );
    });

    test('une tâche au chaud ne consomme PAS de place (maxParallel: 1)', () {
      final now = DateTime(2026, 9, 16, 12, 30);
      final future = now.add(const Duration(minutes: 5));
      // a est la plus ancienne mais au chaud ; b, sur un autre hôte, ne l'est
      // pas.
      final a = _task('a', 'http://a.test/1.mkv', order: 0);
      final b = _task('b', 'http://b.test/2.mkv', order: 1);

      final picks = pickStartable(
        tasks: [a, b],
        inFlightIds: {},
        maxParallel: 1,
        notBefore: {'a': future},
        now: now,
      );

      expect(
        _ids(picks),
        ['b'],
        reason: 'si sauter a consommait quand même sa place, b resterait '
            'bloquée par maxParallel:1 alors qu\'aucun transfert n\'est '
            'réellement en vol — le sondage reviendrait bredouille pour '
            'rien.',
      );
    });

    test('sans notBefore, le comportement est inchangé', () {
      final a = _task('a', 'http://a.test/1.mkv', order: 0);
      final b = _task('b', 'http://b.test/2.mkv', order: 1);

      final picks = pickStartable(
        tasks: [a, b],
        inFlightIds: {},
        maxParallel: 2,
      );

      expect(
        _ids(picks),
        ['a', 'b'],
        reason: 'le paramètre notBefore est optionnel : son absence ne doit '
            'filtrer personne.',
      );
    });
  });
}
