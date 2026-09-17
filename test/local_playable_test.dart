import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/models/download_task.dart';
import 'package:aetherStream/feature/downloads/logic/local_playable.dart';

/// §dlPlayLocal — La règle qui fait qu'une série téléchargée se lit hors ligne
/// depuis SA FICHE, et pas seulement depuis l'onglet Téléchargements.
///
/// Chaque test tient UNE règle : retirer la règle du code doit en faire tomber
/// exactement un.
void main() {
  DownloadTask task({
    required String id,
    required String url,
    String path = '',
    DownloadStatus status = DownloadStatus.completed,
  }) =>
      DownloadTask(
        id: id,
        url: url,
        displayName: 'Heroes S01 E02',
        finalPath: path.isEmpty ? '/movies/$id.mkv' : path,
        tempPath: '/movies/.$id.aetherpart.mkv',
        createdAt: DateTime(2026, 9, 16),
        status: status,
      );

  // Le disque : seuls ces chemins existent.
  bool Function(String) diskWith(Set<String> present) => present.contains;

  const String urlFhd = 'http://p.tv/series/u/pass/501.mkv';
  const String urlHd = 'http://p.tv/series/u/pass/502.mkv';

  group('choix du fichier', () {
    test("la version SÉLECTIONNÉE passe avant les autres versions du groupe",
        () {
      final t1 = task(id: 'fhd', url: urlFhd, path: '/movies/fhd.mkv');
      final t2 = task(id: 'hd', url: urlHd, path: '/movies/hd.mkv');
      final r = pickLocalPlayable(
        // Ordre des tâches inverse de l'ordre des URL : c'est bien l'ordre
        // des URL qui décide, pas celui de la liste des téléchargements.
        tasks: [t2, t1],
        urls: const [urlFhd, urlHd],
        exists: diskWith({'/movies/fhd.mkv', '/movies/hd.mkv'}),
      );
      expect(r.playable?.id, 'fhd');
      expect(r.missing, isEmpty);
    });

    test('aucune tâche pour ce titre → flux (null)', () {
      final r = pickLocalPlayable(
        tasks: [task(id: 'autre', url: 'http://p.tv/movie/u/pass/9.mkv')],
        urls: const [urlFhd],
        exists: (_) => true,
      );
      expect(r.playable, isNull);
      expect(r.missing, isEmpty);
    });

    test('groupe vide ou sans tâche : rien, sans lever', () {
      expect(
        pickLocalPlayable(tasks: const [], urls: const [urlFhd],
                exists: (_) => true)
            .playable,
        isNull,
      );
      expect(
        pickLocalPlayable(
                tasks: [task(id: 'a', url: urlFhd)],
                urls: const [],
                exists: (_) => true)
            .playable,
        isNull,
      );
    });
  });

  group('🔴 seules les tâches TERMINÉES se lisent', () {
    test('tout statut autre que completed est ignoré', () {
      for (final s in DownloadStatus.values) {
        if (s == DownloadStatus.completed) continue;
        final r = pickLocalPlayable(
          tasks: [task(id: 'x', url: urlFhd, path: '/movies/x.mkv', status: s)],
          urls: const [urlFhd],
          // Le partiel EXISTE sur le disque : c'est bien le statut qui refuse,
          // pas l'absence de fichier. Un `.part` n'est pas un film.
          exists: (_) => true,
        );
        expect(r.playable, isNull, reason: '$s');
        expect(r.missing, isEmpty, reason: '$s');
      }
    });
  });

  group('🔴 le fichier doit EXISTER', () {
    test('fichier effacé à la main → flux, et la tâche est signalée', () {
      final t = task(id: 'fhd', url: urlFhd, path: '/movies/fhd.mkv');
      final r = pickLocalPlayable(
        tasks: [t],
        urls: const [urlFhd],
        exists: diskWith(const {}), // rien sur le disque
      );
      expect(r.playable, isNull);
      expect(r.missing.map((e) => e.id), ['fhd']);
    });

    test('finalPath vide (repli MediaStore) compte comme absent', () {
      final t = DownloadTask(
        id: 'vide',
        url: urlFhd,
        displayName: 'Heroes',
        finalPath: '   ',
        tempPath: '',
        createdAt: DateTime(2026, 9, 16),
        status: DownloadStatus.completed,
      );
      final r = pickLocalPlayable(
        tasks: [t],
        urls: const [urlFhd],
        // Le disque dirait « oui » à tout : seul le chemin vide décide.
        exists: (_) => true,
      );
      expect(r.playable, isNull);
      expect(r.missing.map((e) => e.id), ['vide']);
    });

    test(
        'version sélectionnée disparue, autre version présente : on lit '
        "l'autre ET on signale la disparue", () {
      final t1 = task(id: 'fhd', url: urlFhd, path: '/movies/fhd.mkv');
      final t2 = task(id: 'hd', url: urlHd, path: '/movies/hd.mkv');
      final r = pickLocalPlayable(
        tasks: [t1, t2],
        urls: const [urlFhd, urlHd],
        exists: diskWith({'/movies/hd.mkv'}),
      );
      expect(r.playable?.id, 'hd');
      expect(r.missing.map((e) => e.id), ['fhd']);
    });
  });

  group('correspondance des URL', () {
    test(
        "🔴 deux comptes, le même titre : le fichier de l'un ne se lit pas "
        "pour l'autre", () {
      // Mêmes identifiants de série, abonnement différent → URL différente.
      const String autreCompte = 'http://autre.tv/series/u2/pass2/501.mkv';
      final t = task(id: 'a', url: autreCompte, path: '/movies/a.mkv');
      final r = pickLocalPlayable(
        tasks: [t],
        urls: const [urlFhd],
        exists: (_) => true,
      );
      expect(r.playable, isNull);
      expect(r.missing, isEmpty);
    });

    test('espaces autour des URL : la comparaison les ignore', () {
      final t = task(id: 'a', url: '  $urlFhd  ', path: '/movies/a.mkv');
      final r = pickLocalPlayable(
        tasks: [t],
        urls: const ['$urlFhd '],
        exists: diskWith({'/movies/a.mkv'}),
      );
      expect(r.playable?.id, 'a');
    });

    test('une URL répétée dans le groupe ne signale pas deux fois la tâche',
        () {
      final t = task(id: 'a', url: urlFhd, path: '/movies/a.mkv');
      final r = pickLocalPlayable(
        tasks: [t],
        urls: const [urlFhd, urlFhd],
        exists: diskWith(const {}),
      );
      expect(r.missing.map((e) => e.id), ['a']);
    });

    test('une URL vide dans le groupe est ignorée sans effet', () {
      final t = task(id: 'a', url: '', path: '/movies/a.mkv');
      final r = pickLocalPlayable(
        tasks: [t],
        urls: const ['', urlFhd],
        exists: (_) => true,
      );
      expect(r.playable, isNull);
    });
  });
}
