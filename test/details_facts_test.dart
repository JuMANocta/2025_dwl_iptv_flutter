// §tmdbInfo (2026-09-06) — Cinq lignes ajoutées à l'encadré « Infos » de la
// fiche, à partir de champs que la réponse TMDB portait DÉJÀ et que l'app
// jetait (aucun appel réseau de plus : `append_to_response` emballe tout).
//
// Les règles de mise en forme sont testées ici parce que chacune porte un
// piège qui, seul, ferait dire une bêtise à l'écran.

import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/data/models/media_model.dart';
import 'package:aetherStream/feature/search/details_facts.dart';

void main() {
  group('moneyLabel — budget et recettes', () {
    test('⚠️ 0 ne s affiche PAS : TMDB rend 0 quand il ne sait pas', () {
      expect(moneyLabel(0), isNull);
      expect(moneyLabel(null), isNull);
      expect(moneyLabel(-1), isNull);
    });

    test('les millions sont abrégés et groupés', () {
      expect(moneyLabel(90000000), '90 M\$');
      expect(moneyLabel(1200000000), '1 200 M\$');
    });

    test('en dessous du million, le montant reste entier', () {
      expect(moneyLabel(750000), '750 000 \$');
    });
  });

  group('shortDate — la date de sortie', () {
    test('ISO complet → jour/mois/année sur deux chiffres', () {
      expect(shortDate('2023-07-12'), '12/07/2023');
      expect(shortDate('2026-03-05T00:00:00.000Z'), '05/03/2026');
    });

    test('rien à afficher plutôt qu une date fausse', () {
      expect(shortDate(null), isNull);
      expect(shortDate(''), isNull);
      expect(shortDate('bientôt'), isNull);
    });
  });

  group('nextEpisodeLabel — le prochain épisode ANNONCÉ', () {
    test('numéro, date et titre', () {
      expect(
        nextEpisodeLabel(const NextEpisodeInfo(
          seasonNumber: 2,
          episodeNumber: 5,
          name: 'Le Retour',
          airDate: '2026-03-12',
        )),
        'S02E05 · 12/03/2026 — Le Retour',
      );
    });

    test('sans titre, la ligne tient quand même', () {
      expect(
        nextEpisodeLabel(const NextEpisodeInfo(
          seasonNumber: 1,
          episodeNumber: 10,
          airDate: '2026-01-02',
        )),
        'S01E10 · 02/01/2026',
      );
    });

    test('un titre seul vaut mieux que rien', () {
      expect(
        nextEpisodeLabel(const NextEpisodeInfo(name: 'Pilote')),
        'Pilote',
      );
    });

    test('rien du tout → aucune ligne', () {
      expect(nextEpisodeLabel(null), isNull);
      expect(nextEpisodeLabel(const NextEpisodeInfo()), isNull);
    });
  });

  group('NextEpisodeInfo.fromJson', () {
    test('un objet vide de tout repère utile rend null', () {
      expect(NextEpisodeInfo.fromJson(null), isNull);
      expect(NextEpisodeInfo.fromJson(const {'season_number': 2}), isNull);
    });

    test('les champs TMDB sont repris tels quels', () {
      final n = NextEpisodeInfo.fromJson(const {
        'season_number': 3,
        'episode_number': 7,
        'name': 'Fin de partie',
        'air_date': '2026-05-01',
      });
      expect(n, isNotNull);
      expect(n!.seasonNumber, 3);
      expect(n.episodeNumber, 7);
      expect(n.name, 'Fin de partie');
      expect(n.airDate, '2026-05-01');
    });
  });

  group('Media.fromJson — les champs jusque-là jetés', () {
    test('série : saisons, épisodes, diffuseurs, prochain épisode', () {
      final m = Media.fromJson(const {
        'id': 1,
        'name': 'Une série',
        'overview': '',
        'vote_average': 8.0,
        'number_of_seasons': 3,
        'number_of_episodes': 24,
        'networks': [
          {'name': 'Netflix'},
          {'name': 'ARTE'},
        ],
        'next_episode_to_air': {
          'season_number': 3,
          'episode_number': 9,
          'air_date': '2026-04-02',
        },
      });

      expect(m.numberOfSeasons, 3);
      expect(m.numberOfEpisodes, 24);
      expect(m.networks, ['Netflix', 'ARTE']);
      expect(m.nextEpisode?.episodeNumber, 9);
      // Les champs film restent vides sur une série.
      expect(m.theatricalDate, isNull);
      expect(m.digitalDate, isNull);
    });

    test('film : budget, recettes, sortie salle FR prioritaire sur US', () {
      final m = Media.fromJson(const {
        'id': 2,
        'title': 'Un film',
        'overview': '',
        'vote_average': 7.0,
        'budget': 90000000,
        'revenue': 320000000,
        'release_dates': {
          'results': [
            {
              'iso_3166_1': 'US',
              'release_dates': [
                {'type': 3, 'release_date': '2023-07-01T00:00:00.000Z'},
              ],
            },
            {
              'iso_3166_1': 'FR',
              'release_dates': [
                {'type': 3, 'release_date': '2023-07-12T00:00:00.000Z'},
                {'type': 4, 'release_date': '2023-10-05T00:00:00.000Z'},
              ],
            },
          ],
        },
      });

      expect(m.budget, 90000000);
      expect(m.revenue, 320000000);
      expect(shortDate(m.theatricalDate), '12/07/2023');
      expect(shortDate(m.digitalDate), '05/10/2023');
      // Les champs série restent vides sur un film.
      expect(m.numberOfSeasons, isNull);
      expect(m.networks, isEmpty);
    });

    test('⚠️ un film sans budget connu porte 0, pas null — la ligne saute', () {
      final m = Media.fromJson(const {
        'id': 3,
        'title': 'Un film obscur',
        'overview': '',
        'vote_average': 0.0,
        'budget': 0,
        'revenue': 0,
      });

      expect(m.budget, 0);
      expect(moneyLabel(m.budget), isNull);
      expect(moneyLabel(m.revenue), isNull);
    });
  });
}
