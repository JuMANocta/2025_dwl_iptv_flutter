import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/services/load_failure.dart';
import 'package:aetherStream/data/services/xtream_api_service.dart';

/// §episodeTruth — « Aucun épisode disponible pour cette série » disait aussi
/// bien « il n'y en a pas » que « ton réseau est mort » : `fetchEpisodes`
/// rendait `const []` dans les deux cas (§audit0903 n° 9).
///
/// Ces tests verrouillent les deux fonctions PURES qui portent la distinction.
void main() {
  XtreamEpisodesResult ok(List<M3uEntry> eps) =>
      (episodes: eps, error: null, kind: null);
  XtreamEpisodesResult ko(String reason) =>
      (episodes: null, error: reason, kind: LoadFailureKind.network);

  group('episodesFieldError — lire le champ `episodes`', () {
    test('une Map saison → épisodes est lisible', () {
      expect(
        episodesFieldError({
          '1': [
            {'id': '1'}
          ]
        }),
        isNull,
      );
    });

    test('une Map VIDE est lisible : la série existe, sans épisode', () {
      expect(episodesFieldError(<String, dynamic>{}), isNull);
    });

    test('une liste vide est lisible (variante de panel)', () {
      expect(episodesFieldError(const []), isNull);
    });

    test('champ absent → échec, pas « aucun épisode »', () {
      expect(episodesFieldError(null), isNotNull);
    });

    test('une chaîne (page d\'erreur) → échec', () {
      expect(episodesFieldError('<html>error</html>'), isNotNull);
    });

    test('une liste NON vide n\'est pas la structure attendue → échec', () {
      // ⚠️ Un panel qui rend `[{...}]` ne dit pas « pas d'épisode » : il rend
      // autre chose que ce qu'on sait lire. Le confondre avec un succès vide
      // ferait réapparaître exactement le défaut corrigé.
      expect(
        episodesFieldError([
          {'id': '1'}
        ]),
        isNotNull,
      );
    });
  });

  group('episodesFailureReason — verdict sur PLUSIEURS comptes', () {
    test('aucun stub à interroger → aucune panne à signaler', () {
      expect(episodesFailureReason(const []), isNull);
    });

    test('tous en échec → le premier motif est affiché', () {
      expect(
        episodesFailureReason([ko('serveur injoignable'), ko('délai dépassé')]),
        'serveur injoignable',
      );
    });

    test('tous en échec sans motif → une phrase par défaut, jamais vide', () {
      expect(
        episodesFailureReason([(episodes: null, error: null, kind: null)]),
        isNotEmpty,
      );
    });

    test('un seul compte répond VIDE → pas de panne', () {
      // Le cœur du correctif : « le panel n'a pas d'épisode » reste un succès.
      expect(episodesFailureReason([ok(const [])]), isNull);
    });

    test('un compte répond vide, un autre échoue → pas de panne', () {
      // ⚠️ Une liste secondaire injoignable ne doit pas transformer la fiche
      // en écran d'erreur alors qu'un panel a répondu.
      expect(
        episodesFailureReason([ok(const []), ko('serveur injoignable')]),
        isNull,
      );
    });

    test('un motif vide ne passe pas pour un motif', () {
      expect(
        episodesFailureReason([
          (episodes: null, error: '', kind: null),
          ko('délai dépassé'),
        ]),
        'délai dépassé',
      );
    });
  });
}
