import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/models/download_task.dart';
import 'package:aetherStream/feature/player/launch_playback.dart';
import 'package:aetherStream/feature/player/player_page.dart'
    show VideoSourceType;

/// §dlPlayLocal — Ce que le lecteur reçoit : le fichier ou le flux, et sous
/// QUELLE clé de reprise.
///
/// Le piège que ces tests verrouillent : lire le fichier téléchargé doit
/// nourrir la MÊME reprise que lire le flux (§forgetResume). Une clé de
/// reprise qui deviendrait le chemin du fichier sortirait le titre de
/// « Reprendre » sur l'accueil (qui cherche par URL) et ferait diverger la
/// tuile de l'onglet Téléchargements.
void main() {
  const String url = 'http://p.tv/series/u/pass/501.mkv';
  const String urlHd = 'http://p.tv/series/u/pass/502.mkv';

  DownloadTask done(String id, String u, String path) => DownloadTask(
        id: id,
        url: u,
        displayName: 'Heroes S01 E02',
        finalPath: path,
        tempPath: '',
        createdAt: DateTime(2026, 9, 16),
        status: DownloadStatus.completed,
      );

  test('aucun téléchargement : le flux, et AUCUNE clé de reprise imposée', () {
    final src = resolvePlaybackSource(
      networkPath: url,
      groupUrls: const [url],
      tasks: const <DownloadTask>[],
      exists: (_) => true,
      onMissing: (_) => fail('rien à marquer'),
    );
    expect(src.path, url);
    expect(src.sourceType, VideoSourceType.network);
    // `null` = `PlayerMedia.resumeKey` retombe sur le chemin, c'est-à-dire
    // l'URL : exactement le comportement d'avant §dlPlayLocal.
    expect(src.progressKey, isNull);
  });

  test('fichier présent : on lit le fichier, la reprise reste sur l\'URL', () {
    final src = resolvePlaybackSource(
      networkPath: url,
      groupUrls: const [url],
      tasks: [done('a', url, '/movies/a.mkv')],
      exists: (p) => p == '/movies/a.mkv',
      onMissing: (_) => fail('rien à marquer'),
    );
    expect(src.path, '/movies/a.mkv');
    expect(src.sourceType, VideoSourceType.file);
    // 🔴 L'URL RÉSEAU, jamais le chemin du fichier.
    expect(src.progressKey, url);
  });

  test(
      "c'est une AUTRE version qui est sur le disque : la reprise suit CETTE "
      'version, celle qu\'écrit aussi l\'onglet Téléchargements', () {
    final src = resolvePlaybackSource(
      networkPath: url,
      groupUrls: const [url, urlHd],
      tasks: [done('hd', urlHd, '/movies/hd.mkv')],
      exists: (p) => p == '/movies/hd.mkv',
      onMissing: (_) => fail('rien à marquer'),
    );
    expect(src.path, '/movies/hd.mkv');
    expect(src.progressKey, urlHd);
  });

  test('🔴 fichier disparu : on repart en flux ET la tâche est marquée', () {
    final marked = <String>[];
    final src = resolvePlaybackSource(
      networkPath: url,
      groupUrls: const [url],
      tasks: [done('a', url, '/movies/a.mkv')],
      exists: (_) => false,
      onMissing: (t) => marked.add(t.id),
    );
    expect(src.sourceType, VideoSourceType.network);
    expect(src.path, url);
    // Sans ce marquage, la liste continuerait d'annoncer « Terminé » pour un
    // fichier qui n'existe plus, et le retour au flux passerait pour une
    // panne réseau.
    expect(marked, ['a']);
  });

  test('hasLocalFileFor ne marque RIEN (il est appelé pendant un build)', () {
    final has = hasLocalFileFor(
      networkPath: url,
      groupUrls: const [url],
      tasks: [done('a', url, '/movies/a.mkv')],
      exists: (_) => false,
    );
    expect(has, isFalse);
  });

  test('hasLocalFileFor dit oui quand le fichier est là', () {
    expect(
      hasLocalFileFor(
        networkPath: url,
        groupUrls: const [url],
        tasks: [done('a', url, '/movies/a.mkv')],
        exists: (_) => true,
      ),
      isTrue,
    );
  });
}
