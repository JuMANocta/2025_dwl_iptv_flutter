import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/models/media_model.dart';
import 'package:aetherStream/data/models/person_model.dart';

/// §directorView / §tmdbMore — Verrouille le parsing des champs TMDB ajoutés
/// le 2026-08-05. Points critiques :
///   - le réalisateur vient de `credits.crew` (films) ou `created_by`
///     (séries) : ces données ARRIVAIENT déjà dans la réponse mais n'étaient
///     jamais lues ;
///   - `Person.fromJson` ne lisait que `combined_credits.cast` → la fiche d'un
///     RÉALISATEUR s'affichait vide (bug fonctionnel, pas cosmétique) ;
///   - `FilmographyEntry` castait `media_type` en non-null → exception sur les
///     crédits `crew` qui ne le portent pas.
void main() {
  group('Media.fromJson — §directorView', () {
    test('film : réalisateur extrait de credits.crew (job == Director)', () {
      final m = Media.fromJson({
        'id': 1,
        'title': 'Inception', // présence de `title` ⇒ film
        'overview': '…',
        'credits': {
          'cast': [],
          'crew': [
            // Bruit : d'autres métiers ne doivent PAS être pris.
            {'id': 10, 'name': 'Un Monteur', 'job': 'Editor'},
            {
              'id': 525,
              'name': 'Christopher Nolan',
              'job': 'Director',
              'profile_path': '/nolan.jpg',
            },
          ],
        },
      });
      expect(m.director?.name, 'Christopher Nolan');
      expect(m.director?.id, 525);
      expect(m.director?.profilePath, '/nolan.jpg');
      // `character` porte le libellé du rôle → sert à choisir « De » / « Créé par ».
      expect(m.director?.character, 'Réalisateur');
    });

    test('série : créateur extrait de created_by (crew ne le porte pas)', () {
      final m = Media.fromJson({
        'id': 2,
        'name': 'Breaking Bad', // pas de `title` ⇒ série
        'overview': '…',
        'created_by': [
          {'id': 66633, 'name': 'Vince Gilligan', 'profile_path': '/vg.jpg'},
        ],
      });
      expect(m.director?.name, 'Vince Gilligan');
      expect(m.director?.character, 'Créateur');
    });

    test('aucun crew ni created_by → director null, pas de crash', () {
      final m = Media.fromJson({
        'id': 3,
        'title': 'Sans Crédits',
        'overview': '…',
        'credits': {'cast': []},
      });
      expect(m.director, isNull);
    });
  });

  group('Media.fromJson — §tmdbMore', () {
    test('tagline / voteCount / status / pays parsés', () {
      final m = Media.fromJson({
        'id': 4,
        'title': 'Dune',
        'overview': '…',
        'tagline': '  Au-delà de la peur  ', // doit être trimé
        'vote_count': 12400,
        'status': 'Released',
        'production_countries': [
          {'iso_3166_1': 'US', 'name': 'United States of America'},
          {'iso_3166_1': 'CA', 'name': 'Canada'},
        ],
        'release_date': '2021-09-15',
      });
      expect(m.tagline, 'Au-delà de la peur');
      expect(m.voteCount, 12400);
      expect(m.status, 'Released');
      expect(m.productionCountries, ['United States of America', 'Canada']);
      // La date COMPLÈTE est conservée (l'affichage historique la tronque).
      expect(m.releaseDateFull, '2021-09-15');
    });

    test('champs absents ou vides → null (jamais de chaîne vide affichée)', () {
      final m = Media.fromJson({
        'id': 5,
        'title': 'Minimal',
        'overview': '…',
        'tagline': '   ',
      });
      expect(m.tagline, isNull);
      expect(m.voteCount, isNull);
      expect(m.status, isNull);
      expect(m.productionCountries, isEmpty);
    });
  });

  group('Person.fromJson — §directorView (le bug bloquant)', () {
    test('crew ET cast fusionnés → un réalisateur a enfin une filmographie', () {
      final p = Person.fromJson({
        'id': 525,
        'name': 'Christopher Nolan',
        'known_for_department': 'Directing',
        'combined_credits': {
          'cast': [
            {
              'id': 99,
              'media_type': 'movie',
              'title': 'Un caméo',
              'release_date': '2002-01-01',
              'character': 'Passant',
            },
          ],
          'crew': [
            {
              'id': 27205,
              'media_type': 'movie',
              'title': 'Inception',
              'release_date': '2010-07-16',
              'job': 'Director',
            },
          ],
        },
      });
      expect(p.isDirector, isTrue);
      final titles = p.filmography.map((f) => f.title).toList();
      expect(titles, contains('Inception')); // ← vide avant le fix
      expect(titles, contains('Un caméo'));
    });

    test('crew filtré : seuls les crédits de réalisation sont retenus', () {
      final p = Person.fromJson({
        'id': 1,
        'name': 'Touche-à-tout',
        'combined_credits': {
          'cast': [],
          'crew': [
            {
              'id': 5,
              'media_type': 'movie',
              'title': 'Film Monté',
              'release_date': '2015-01-01',
              'job': 'Editor', // ni Director ni Directing → exclu
            },
          ],
        },
      });
      expect(p.filmography, isEmpty);
    });

    test('doublon crew+cast → dédupliqué, le crédit RÉALISATION gagne', () {
      final p = Person.fromJson({
        'id': 2,
        'name': 'Réalisateur-Acteur',
        'combined_credits': {
          'cast': [
            {
              'id': 42,
              'media_type': 'movie',
              'title': 'Son Film',
              'release_date': '2020-01-01',
              'character': 'Lui-même',
            },
          ],
          'crew': [
            {
              'id': 42, // MÊME id : c'est le même film
              'media_type': 'movie',
              'title': 'Son Film',
              'release_date': '2020-01-01',
              'job': 'Director',
            },
          ],
        },
      });
      expect(p.filmography.length, 1);
      expect(p.filmography.first.job, 'Director');
    });
  });

  group('FilmographyEntry.fromJson — tolérance', () {
    test('sans media_type → pas d\'exception (crash verrouillé)', () {
      // Certains crédits `crew` ne portent pas `media_type` : l'ancien
      // `json['media_type'] as String` levait et cassait toute la fiche.
      final e = FilmographyEntry.fromJson({
        'id': 7,
        'title': 'Film Sans Type',
        'release_date': '2019-01-01',
        'job': 'Director',
      });
      expect(e.mediaType, 'movie'); // déduit de `title`/`release_date`
      expect(e.title, 'Film Sans Type');
      expect(e.year, 2019);
    });

    test('sans media_type ni title → déduit série', () {
      final e = FilmographyEntry.fromJson({
        'id': 8,
        'name': 'Série Sans Type',
        'first_air_date': '2018-03-04',
      });
      expect(e.mediaType, 'tv');
      expect(e.title, 'Série Sans Type');
    });
  });
}
