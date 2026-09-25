// Lot 9 (§tmdbKeywords, 2026-09-25) — Les mots-clés TMDB de la fiche.
//
// Ils voyagent dans la réponse que la fiche attend déjà
// (`append_to_response=keywords`) : zéro requête de plus. Deux règles pures
// sont tenues ici — la lecture des DEUX formes de réponse (film / série), et ce
// que la ligne « Mots-clés » de l'encadré « Infos » accepte de montrer.
//
// Le branchement (la ligne dans l'encadré) se voit à la recette : aucun test
// ne monte `DetailsPage`, qui appelle TMDB à l'init.

import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/data/models/media_model.dart';
import 'package:aetherStream/feature/search/details_facts.dart';

Map<String, dynamic> _kw(String field, List<Object?> items) => <String, dynamic>{
      'id': 1,
      'keywords': <String, dynamic>{field: items},
    };

void main() {
  group('tmdbKeywordsFrom — les deux formes de réponse', () {
    test('film : `keywords.keywords`', () {
      expect(
        tmdbKeywordsFrom(_kw('keywords', [
          {'id': 4379, 'name': 'time travel'},
          {'id': 818, 'name': 'based on novel or book'},
        ])),
        ['time travel', 'based on novel or book'],
      );
    });

    test('série : `keywords.results`', () {
      expect(
        tmdbKeywordsFrom(_kw('results', [
          {'id': 10084, 'name': 'rescue'},
        ])),
        ['rescue'],
      );
    });

    test('nettoyés, dédoublonnés sans la casse, ordre TMDB gardé', () {
      expect(
        tmdbKeywordsFrom(_kw('keywords', [
          {'id': 1, 'name': '  heist '},
          {'id': 2, 'name': 'Heist'},
          {'id': 3, 'name': ''},
          {'id': 4},
          'pas un objet',
          {'id': 5, 'name': 'dystopia'},
        ])),
        ['heist', 'dystopia'],
      );
    });

    test('réponse sans mots-clés, ou illisible : rien', () {
      expect(tmdbKeywordsFrom(<String, dynamic>{'id': 1}), isEmpty);
      expect(tmdbKeywordsFrom(<String, dynamic>{'keywords': 'x'}), isEmpty);
      expect(
          tmdbKeywordsFrom(<String, dynamic>{
            'keywords': <String, dynamic>{'keywords': 'x'},
          }),
          isEmpty);
    });

  });

  group("Media.keywords — le champ, lu sans casser une réponse d'avant", () {
    Map<String, dynamic> movie({Object? keywords}) => <String, dynamic>{
          'id': 27205,
          'title': 'Inception',
          'overview': 'Dom Cobb…',
          'vote_average': 8.4,
          'release_date': '2010-07-15',
          'genres': [
            {'id': 878, 'name': 'Science-Fiction'},
          ],
          if (keywords != null) 'keywords': keywords,
        };

    test("réponse d'AVANT (sans le bloc `keywords`) : null, rien d'autre ne "
        "change", () {
      final m = Media.fromJson(movie());
      expect(m.keywords, isNull);
      expect(m.title, 'Inception');
      expect(m.genres, isNotEmpty);
    });

    test('film : lus depuis la même réponse', () {
      final m = Media.fromJson(movie(keywords: {
        'keywords': [
          {'id': 1, 'name': 'dream'},
          {'id': 2, 'name': 'heist'},
        ],
      }));
      expect(m.keywords, ['dream', 'heist']);
    });

    test('série : `keywords.results`', () {
      final m = Media.fromJson(<String, dynamic>{
        'id': 1399,
        'name': 'Game of Thrones',
        'overview': '',
        'vote_average': 8.5,
        'first_air_date': '2011-04-17',
        'genres': const <Object>[],
        'keywords': {
          'results': [
            {'id': 3, 'name': 'dragon'},
          ],
        },
      });
      expect(m.keywords, ['dragon']);
    });

    test("bloc présent mais vide : liste vide (TMDB n'en connaît aucun)", () {
      final m = Media.fromJson(movie(keywords: {'keywords': const <Object>[]}));
      expect(m.keywords, isEmpty);
    });
  });

  group('showTmdbKeywords — la SEULE condition de langue', () {
    test("décision de l'utilisateur : partout, en anglais", () {
      expect(showTmdbKeywords('en'), isTrue);
      expect(showTmdbKeywords('en_GB'), isTrue);
      expect(showTmdbKeywords('fr'), isTrue);
    });
  });

  group('keywordsToShow — ce que la ligne « Mots-clés » montre', () {
    const all = ['time travel', 'aftercreditsstinger', 'dystopia'];

    test('écran anglais : les mots-clés', () {
      expect(keywordsToShow(all, lang: 'en'), ['time travel', 'dystopia']);
      expect(keywordsToShow(all, lang: 'en_US'), ['time travel', 'dystopia']);
    });

    test('écran français : les mêmes mots-clés, en anglais (TMDB ne les traduit pas)', () {
      expect(keywordsToShow(all, lang: 'fr'), ['time travel', 'dystopia']);
    });

    test('les mécaniques de générique sont écartées', () {
      expect(
        keywordsToShow(['duringcreditsstinger', 'AfterCreditsStinger'],
            lang: 'en'),
        isEmpty,
      );
    });

    test('au plus N, pour rester lisible à la télécommande', () {
      final many = [for (int i = 0; i < 30; i++) 'k$i'];
      expect(keywordsToShow(many, lang: 'en').length, 8);
      expect(keywordsToShow(many, lang: 'en', max: 3), ['k0', 'k1', 'k2']);
    });
  });
}
