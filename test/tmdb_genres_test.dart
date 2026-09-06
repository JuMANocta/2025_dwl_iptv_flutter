import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/data/models/tmdb_genres.dart';

void main() {
  group('§inferredCat — genre TMDB → catégorie de l\'app', () {
    test('les libellés sont ceux de l\'app, pas ceux de TMDB', () {
      // C'est TOUT l'intérêt : la catégorie déduite d'une liste pauvre doit
      // fusionner avec celle d'une liste riche. Si on écrivait « Science
      // Fiction » là où `contentCategoryLabel` écrit « Sci-Fi », on obtiendrait
      // deux rangées côte à côte et le rangement serait pire qu'avant.
      expect(kTmdbGenreLabels[878], 'Sci-Fi');
      expect(kTmdbGenreLabels[10751], 'Jeunesse');
      expect(kTmdbGenreLabels[10752], 'Guerre');
      expect(kTmdbGenreLabels[16], 'Animation');
    });

    test('un genre qui DÉCRIT prime sur un genre fourre-tout', () {
      // TMDB renvoie souvent « Drame » en tête d'un film qui est avant tout un
      // documentaire ou un film d'horreur. Prendre le premier donnerait une
      // rangée « Drame » démesurée et vide de sens.
      expect(tmdbGenreLabel([18, 99]), 'Documentaire'); // Drame + Documentaire
      expect(tmdbGenreLabel([18, 27]), 'Horreur'); // Drame + Horreur
      expect(tmdbGenreLabel([28, 16]), 'Animation'); // Action + Animation
      expect(tmdbGenreLabel([18, 10749]), 'Romance'); // Drame + Romance
    });

    test('les fourre-tout restent utilisables quand ils sont seuls', () {
      expect(tmdbGenreLabel([18]), 'Drame');
      expect(tmdbGenreLabel([28]), 'Action');
    });

    test('les identifiants SÉRIE sont couverts', () {
      // TMDB utilise deux jeux d'ids ; n'en couvrir qu'un laisserait toutes les
      // séries dans « Autres ».
      expect(tmdbGenreLabel([10759]), 'Action');
      expect(tmdbGenreLabel([10765]), 'Sci-Fi');
      expect(tmdbGenreLabel([10762]), 'Jeunesse');
    });

    test('rien à déduire → null, jamais une catégorie inventée', () {
      expect(tmdbGenreLabel([]), isNull);
      expect(tmdbGenreLabel([999999]), isNull);
    });
  });
}
