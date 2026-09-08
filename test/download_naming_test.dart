import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/feature/downloads/logic/download_naming.dart';

/// §dlEpisode (2026-09-08) — Deux épisodes d'une même série ne doivent JAMAIS
/// viser le même fichier.
///
/// Le défaut signalé : le bouton « Télécharger » de la fiche passait le seul
/// nom de la série, donc `Heroes.mp4` pour tous les épisodes — et `rename()`
/// remplace sa cible sans lever. Le nom est corrigé à la source, mais
/// l'écrasement silencieux est le défaut de fond : ces règles le ferment.
void main() {
  group('downloadNameCandidate — le suffixe se pose AVANT l\'extension', () {
    test('index 0 rend le nom inchangé', () {
      expect(downloadNameCandidate('Heroes S01 E02.mp4', 0),
          'Heroes S01 E02.mp4');
    });

    test('index 1 rend « (2) », devant l\'extension', () {
      expect(downloadNameCandidate('Heroes S01 E02.mp4', 1),
          'Heroes S01 E02 (2).mp4');
    });

    test('la numérotation visible commence à 2, pas à 1', () {
      // « (1) » laisserait croire à un premier exemplaire alors que le fichier
      // sans suffixe EST le premier.
      expect(downloadNameCandidate('film.mkv', 2), 'film (3).mkv');
    });

    test('un point dans le titre ne devient pas l\'extension', () {
      expect(downloadNameCandidate('S.W.A.T. S01 E01.mp4', 1),
          'S.W.A.T. S01 E01 (2).mp4');
    });

    test('un nom SANS extension reçoit le suffixe à la fin', () {
      expect(downloadNameCandidate('Heroes S01 E02', 1), 'Heroes S01 E02 (2)');
    });

    test('un point de TÊTE n\'est pas un séparateur d\'extension', () {
      // Cas réel : le fichier partiel de §dlDirectWrite s'appelle « .nom.part ».
      expect(downloadNameCandidate('.aether', 1), '.aether (2)');
    });

    test('un index négatif est traité comme 0', () {
      expect(downloadNameCandidate('film.mp4', -3), 'film.mp4');
    });
  });

  group('uniqueDownloadName — le premier nom libre', () {
    test('rend le nom tel quel quand rien ne le prend', () {
      expect(
        uniqueDownloadName('Heroes S01 E02.mp4', taken: (_) => false),
        'Heroes S01 E02.mp4',
      );
    });

    test('se pousse d\'un cran quand le nom est pris', () {
      const busy = {'Heroes S01 E02.mp4'};
      expect(
        uniqueDownloadName('Heroes S01 E02.mp4', taken: busy.contains),
        'Heroes S01 E02 (2).mp4',
      );
    });

    test('saute autant de crans qu\'il le faut', () {
      const busy = {
        'film.mp4',
        'film (2).mp4',
        'film (3).mp4',
      };
      expect(
        uniqueDownloadName('film.mp4', taken: busy.contains),
        'film (4).mp4',
      );
    });

    test('deux épisodes différents ne se poussent PAS l\'un l\'autre', () {
      // Le vrai correctif : des noms distincts n'entrent jamais en collision,
      // donc aucun suffixe n'apparaît dans l'usage normal.
      const busy = {'Heroes S01 E01.mp4'};
      expect(
        uniqueDownloadName('Heroes S01 E02.mp4', taken: busy.contains),
        'Heroes S01 E02.mp4',
      );
    });

    test('un dossier pathologique ne fait pas boucler l\'appui', () {
      // Tout est pris : on rend quand même un nom (borné), plutôt que de
      // laisser le bouton sans réponse.
      final String out =
          uniqueDownloadName('film.mp4', taken: (_) => true, maxTries: 5);
      expect(out, 'film (6).mp4');
    });
  });
}
