// Lot 9 (§tmdbPlus) — « Disponible sur » pour les FILMS.
//
// Ce que ces tests tiennent : le bloc « Disponible sur » ne montre que des
// plateformes RÉELLES, du bon pays, et seulement celles où le titre se REGARDE.
//
// Le défaut d'origine (§tmdbInfo, 2026-09-06) était que ce bloc DEVINAIT :
// il lisait le suffixe du `group-title` du fournisseur, qui suffixe toutes ses
// séries de « ( NETFLIX| PRIME | HBO | APPLE TV+ | STARZ | PARAMOUNT+ ) » —
// six plateformes annoncées sur des milliers de titres, aucune vérifiée. Le
// remède avait été `networks`, mais TMDB ne rend jamais de `networks` pour un
// FILM : le bloc disparaissait sur toute une moitié du catalogue.
//
// Sincérité : retirer le filtre de pays fait tomber « un autre pays ne compte
// pas » ; accepter `rent`/`buy` fait tomber « acheter n'est pas regarder » ;
// retirer la déduplication fait tomber « deux familles, une seule pastille » ;
// ignorer `display_priority` fait tomber l'ordre.

import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/models/media_model.dart';

Map<String, dynamic> _response(Map<String, dynamic> byCountry) => {
      'watch/providers': {'results': byCountry}
    };

Map<String, Object?> _p(String name, int priority) =>
    {'provider_name': name, 'display_priority': priority};

void main() {
  group('watchRegionForLanguageTag — le pays, jamais la langue', () {
    test('une étiquette complète donne son pays', () {
      expect(watchRegionForLanguageTag('fr-FR'), 'FR');
      expect(watchRegionForLanguageTag('en-US'), 'US');
      expect(watchRegionForLanguageTag('pt-BR'), 'BR');
    });

    test('le souligné est accepté comme le tiret', () {
      expect(watchRegionForLanguageTag('en_GB'), 'GB');
    });

    test('la casse est normalisée', () {
      expect(watchRegionForLanguageTag('fr-fr'), 'FR');
    });

    test('⚠️ une étiquette SANS pays ne désigne aucun catalogue', () {
      // Prendre « le premier pays venu » annoncerait Hulu à quelqu'un en
      // France. On préfère ne rien dire.
      expect(watchRegionForLanguageTag('fr'), isNull);
      expect(watchRegionForLanguageTag(''), isNull);
      expect(watchRegionForLanguageTag(null), isNull);
      expect(watchRegionForLanguageTag('fr-FRA'), isNull);
    });
  });

  group('watchProvidersFor — ce qui se regarde, dans le bon pays', () {
    test('les abonnements du pays demandé, dans l\'ordre de TMDB', () {
      final json = _response({
        'FR': {
          'flatrate': [_p('Canal+', 7), _p('Netflix', 3)]
        }
      });
      expect(watchProvidersFor(json, 'FR'), ['Netflix', 'Canal+']);
    });

    test('le gratuit et le gratuit-avec-pub comptent aussi', () {
      final json = _response({
        'FR': {
          'free': [_p('France TV', 9)],
          'ads': [_p('Pluto TV', 12)],
        }
      });
      expect(watchProvidersFor(json, 'FR'), ['France TV', 'Pluto TV']);
    });

    test('⛔ louer ou acheter n\'est PAS regarder', () {
      final json = _response({
        'FR': {
          'flatrate': [_p('Netflix', 3)],
          'rent': [_p('Apple TV', 2)],
          'buy': [_p('Google Play Movies', 1)],
        }
      });
      expect(watchProvidersFor(json, 'FR'), ['Netflix']);
    });

    test('⚠️ un service présent dans deux familles ne sort qu\'une fois', () {
      final json = _response({
        'FR': {
          'flatrate': [_p('Pluto TV', 12)],
          'ads': [_p('Pluto TV', 12)],
        }
      });
      expect(watchProvidersFor(json, 'FR'), ['Pluto TV']);
    });

    test('⚠️ un autre pays ne répond pas à la question posée', () {
      final json = _response({
        'US': {
          'flatrate': [_p('Hulu', 1)]
        }
      });
      expect(watchProvidersFor(json, 'FR'), isEmpty);
    });

    test('sans pays, rien — jamais « le premier trouvé »', () {
      final json = _response({
        'US': {
          'flatrate': [_p('Hulu', 1)]
        }
      });
      expect(watchProvidersFor(json, null), isEmpty);
    });

    test('une priorité absente ne fait pas tomber la liste', () {
      final json = _response({
        'FR': {
          'flatrate': [
            {'provider_name': 'Sans priorité'},
            _p('Netflix', 3),
          ]
        }
      });
      expect(watchProvidersFor(json, 'FR'), ['Netflix', 'Sans priorité']);
    });
  });

  group('watchProvidersFor — les réponses qu\'on ne sait pas lire', () {
    test('aucun bloc `watch/providers` : la fiche se tait', () {
      expect(watchProvidersFor(<String, dynamic>{}, 'FR'), isEmpty);
    });

    test('un bloc vide, mal formé ou sans nom ne lève jamais', () {
      expect(watchProvidersFor({'watch/providers': null}, 'FR'), isEmpty);
      expect(watchProvidersFor({'watch/providers': 'oups'}, 'FR'), isEmpty);
      expect(watchProvidersFor(_response(<String, dynamic>{}), 'FR'), isEmpty);
      expect(
        watchProvidersFor(
          _response({
            'FR': {
              'flatrate': [
                {'logo_path': '/x.jpg'}
              ]
            }
          }),
          'FR',
        ),
        isEmpty,
      );
    });

    test('un nom vide ou en espaces n\'est pas une plateforme', () {
      final json = _response({
        'FR': {
          'flatrate': [_p('   ', 1), _p('Netflix', 3)]
        }
      });
      expect(watchProvidersFor(json, 'FR'), ['Netflix']);
    });
  });

  group('Media.fromJson — le champ arrive jusqu\'à la fiche', () {
    test('un FILM porte enfin ses plateformes, sans `networks`', () {
      final media = Media.fromJson(
        {
          'id': 42,
          'title': 'Un film',
          'watch/providers': {
            'results': {
              'FR': {
                'flatrate': [_p('Netflix', 3)]
              }
            }
          },
        },
        watchRegion: 'FR',
      );
      expect(media.networks, isEmpty, reason: 'TMDB n\'en donne pas aux films');
      expect(media.watchProviders, ['Netflix']);
    });

    test('sans région passée, le champ reste vide', () {
      final media = Media.fromJson({
        'id': 42,
        'title': 'Un film',
        'watch/providers': {
          'results': {
            'FR': {
              'flatrate': [_p('Netflix', 3)]
            }
          }
        },
      });
      expect(media.watchProviders, isEmpty);
    });
  });
}
