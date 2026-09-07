// §dlQueue (2026-09-06, lot 6) — La file d'attente des téléchargements décide
// PAR HÔTE : un transfert à la fois par abonnement (les panels n'acceptent
// qu'une connexion), un plafond global entre abonnements différents.

import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/data/models/download_task.dart';
import 'package:aetherStream/feature/downloads/logic/download_scheduler.dart';

DownloadTask _t(String id, String host, {int order = 0,
        DownloadStatus status = DownloadStatus.queued}) =>
    DownloadTask(
      id: id,
      url: 'http://$host/movie/u/p/$id.mkv',
      displayName: id,
      finalPath: '/x/$id.mkv',
      tempPath: '/x/$id.part',
      totalSize: 0,
      status: status,
      createdAt: DateTime(2026, 9, 6, 12, order),
    );

List<String> _ids(List<DownloadTask> l) => l.map((t) => t.id).toList();

void main() {
  test('hôte = serveur:port, vide si URL illisible', () {
    expect(downloadHostOf(_t('a', 'srv.example.com:8080')), 'srv.example.com:8080');
    expect(downloadHostOf(_t('a', 'srv.example.com')), 'srv.example.com');
    expect(downloadHostOf(_t('a', '')), '');
  });

  test('un seul transfert par hôte : le 2e du même abonnement attend', () {
    final picks = pickStartable(
      tasks: [_t('a', 'h1', order: 0), _t('b', 'h1', order: 1)],
      inFlightIds: {},
      maxParallel: 3,
    );
    expect(_ids(picks), ['a']);
  });

  test('deux abonnements différents partent ensemble, sous le plafond', () {
    final picks = pickStartable(
      tasks: [
        _t('a', 'h1', order: 0),
        _t('b', 'h2', order: 1),
        _t('c', 'h3', order: 2),
      ],
      inFlightIds: {},
      maxParallel: 2,
    );
    expect(_ids(picks), ['a', 'b'], reason: 'c dépasse le plafond global');
  });

  test('un transfert en vol occupe SON hôte et compte dans le plafond', () {
    final picks = pickStartable(
      tasks: [
        _t('run', 'h1', status: DownloadStatus.downloading),
        _t('a', 'h1', order: 1),
        _t('b', 'h2', order: 2),
      ],
      inFlightIds: {'run'},
      maxParallel: 2,
    );
    expect(_ids(picks), ['b'], reason: 'h1 est pris, une place globale reste');
  });

  test('ordre de création, pas ordre de la liste', () {
    final picks = pickStartable(
      tasks: [_t('late', 'h2', order: 5), _t('early', 'h1', order: 1)],
      inFlightIds: {},
      maxParallel: 1,
    );
    expect(_ids(picks), ['early']);
  });

  test('un hôte bloqué ne bloque pas le suivant de la file', () {
    final picks = pickStartable(
      tasks: [
        _t('run', 'h1', status: DownloadStatus.downloading),
        _t('a', 'h1', order: 1),
        _t('b', 'h1', order: 2),
        _t('c', 'h2', order: 3),
      ],
      inFlightIds: {'run'},
      maxParallel: 3,
    );
    expect(_ids(picks), ['c']);
  });

  test('seules les tâches « en attente » sont candidates', () {
    final picks = pickStartable(
      tasks: [
        _t('f', 'h1', status: DownloadStatus.failed),
        _t('p', 'h2', status: DownloadStatus.paused),
        _t('d', 'h3', status: DownloadStatus.completed),
        _t('q', 'h4', order: 9),
      ],
      inFlightIds: {},
      maxParallel: 4,
    );
    expect(_ids(picks), ['q']);
  });

  test('plafond atteint ou nul → rien', () {
    final tasks = [_t('a', 'h1'), _t('r', 'h2', status: DownloadStatus.downloading)];
    expect(pickStartable(tasks: tasks, inFlightIds: {'r'}, maxParallel: 1), isEmpty);
    expect(pickStartable(tasks: tasks, inFlightIds: {}, maxParallel: 0), isEmpty);
  });

  test('URL illisible : jamais bloquée par la règle par hôte', () {
    final picks = pickStartable(
      tasks: [_t('a', '', order: 0), _t('b', '', order: 1)],
      inFlightIds: {},
      maxParallel: 2,
    );
    expect(_ids(picks), ['a', 'b']);
  });
}
