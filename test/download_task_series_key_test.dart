import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/models/download_task.dart';

/// R39 / §heroSeriesResume — La clé de SÉRIE portée par la tâche.
///
/// Le piège qu'elle ferme : la progression d'un épisode s'écrit sous l'URL de
/// l'ÉPISODE, alors que le catalogue ne contient que le stub de la SÉRIE. Un
/// épisode lu ou diffusé depuis sa tuile n'entrait donc jamais au hero de
/// l'accueil. Et cette clé n'est PAS dérivable de l'URL : `…/series/u/p/{id}.mkv`
/// ne dit rien de `…/series/u/p/{series_id}`. Elle doit donc voyager AVEC la
/// tâche, posée par le seul site qui la connaisse — celui qui lance le
/// téléchargement.
void main() {
  Map<String, dynamic> base() => <String, dynamic>{
        'id': 't1',
        'url': 'http://h/series/u/p/501.mkv',
        'displayName': 'Heroes S01 E02',
        'finalPath': '/m/Heroes S01 E02.mkv',
        'tempPath': '',
        'status': DownloadStatus.completed.index,
        'progress': 1.0,
        'totalSize': 100,
        'createdAt': '2026-09-16T10:00:00.000',
      };

  const String stub = 'http://h/series/u/p/77';

  test('aller-retour JSON avec la clé de série', () {
    final t = DownloadTask.fromJson({...base(), 'seriesKey': stub});
    expect(t.seriesKey, stub);
    expect(DownloadTask.fromJson(t.toJson()).seriesKey, stub);
  });

  test('🔴 une tâche enregistrée AVANT R39 se relit sans lever, clé nulle', () {
    // Exactement le JSON d'hier : pas de champ `seriesKey` du tout.
    final t = DownloadTask.fromJson(base());
    expect(t.seriesKey, isNull);
    // Et elle se réécrit sans inventer de clé.
    expect(t.toJson()['seriesKey'], isNull);
  });

  test('un film n\'a pas de clé de série, et c\'est écrit tel quel', () {
    final t = DownloadTask.fromJson({...base(), 'seriesKey': null});
    expect(t.seriesKey, isNull);
  });

  test('copyWith conserve la clé quand on ne la change pas', () {
    final t = DownloadTask.fromJson({...base(), 'seriesKey': stub});
    expect(t.copyWith(status: DownloadStatus.failed).seriesKey, stub);
  });

  test('🔴 l\'ordre de DownloadStatus n\'a pas bougé (persistance par index)',
      () {
    // Le champ ajouté ne doit RIEN changer à la relecture du statut : c'est
    // l'invariant qui protège les listes d'un retour arrière d'APK.
    expect(DownloadStatus.values.map((s) => s.name).toList(), <String>[
      'queued',
      'downloading',
      'completed',
      'failed',
      'canceled',
      'paused',
      'finalizing',
    ]);
  });
}
