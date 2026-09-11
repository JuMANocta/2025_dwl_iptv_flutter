import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/data/models/tmdb_genres.dart';
import 'package:aetherStream/feature/search/m3u_filter.dart';

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

    // Revue 2026-09-11, D1A-13 — News donnait « Documentaire » alors que
    // `contentCategoryLabel` range NEWS sous « Actualités » : deux rangées pour
    // la même notion selon que la liste était riche ou pauvre.
    test('News → Actualités, le libellé des listes riches', () {
      expect(kTmdbGenreLabels[10763], 'Actualités');
      expect(contentCategoryLabel('NEWS'), 'Actualités');
      expect(tmdbGenreLabel([10763]), 'Actualités');
      // Documentaire reste plus spécifique qu'Actualités.
      expect(tmdbGenreLabel([10763, 99]), 'Documentaire');
    });

    test('Talk-show est émis ET lu : le libellé fait partie du vocabulaire', () {
      expect(kTmdbGenreLabels[10767], 'Talk-show');
      expect(tmdbGenreLabel([10767]), 'Talk-show');
      expect(contentCategoryLabel('TALK SHOW'), 'Talk-show');
      expect(contentCategoryLabel('TALK-SHOW'), 'Talk-show');
    });

    test('tout libellé TMDB existe dans le vocabulaire des listes', () {
      // L'en-tête de `tmdb_genres.dart` l'exige : sinon la rangée déduite d'une
      // liste pauvre ne rejoint jamais celle d'une liste riche.
      const lus = {
        'Action': 'ACTION', 'Aventure': 'AVENTURE', 'Animation': 'ANIMATION',
        'Comédie': 'COMEDIE', 'Crime': 'CRIME', 'Documentaire': 'DOCUMENTAIRE',
        'Drame': 'DRAME', 'Jeunesse': 'JEUNESSE', 'Fantastique': 'FANTASTIQUE',
        'Histoire': 'HISTOIRE', 'Horreur': 'HORREUR', 'Musical': 'MUSICAL',
        'Thriller': 'THRILLER', 'Romance': 'ROMANCE', 'Sci-Fi': 'SCI-FI',
        'Téléfilm': 'TELEFILM', 'Guerre': 'GUERRE', 'Western': 'WESTERN',
        'Actualités': 'NEWS', 'Téléréalité': 'TELEREALITE',
        'Talk-show': 'TALK SHOW',
      };
      for (final label in kTmdbGenreLabels.values.toSet()) {
        expect(lus.containsKey(label), isTrue, reason: label);
        expect(contentCategoryLabel(lus[label]!), label, reason: label);
      }
    });

    test('rien à déduire → null, jamais une catégorie inventée', () {
      expect(tmdbGenreLabel([]), isNull);
      expect(tmdbGenreLabel([999999]), isNull);
    });
  });
}
