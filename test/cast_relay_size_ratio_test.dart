import 'package:aetherStream/data/services/cast_relay_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// R33 — La recette du 2026-09-12 a relevé 2 591 Mo de sortie pour 1 509 Mo de
/// source, sans explication, et la fiche demande de REFAIRE la mesure sur un
/// second fichier avant d'en faire un ticket. La ligne de journal qui la rend
/// possible est pure : c'est elle qu'on tient ici, pour qu'un relevé ne puisse
/// pas mentir sur le rapport ni en inventer un quand la source est distante.
void main() {
  const int mo = 1024 * 1024;

  group('R33 — peser une conversion finie', () {
    test('le rapport relevé le 2026-09-12 se relit tel quel', () {
      final s = relaySizeRatioLine(
        sourceBytes: 1509 * mo,
        outputBytes: 2591 * mo,
      );
      expect(s, contains('source 1509.0 Mo'));
      expect(s, contains('sortie 2591.0 Mo'));
      expect(s, contains('rapport x1.72'));
    });

    test('source distante : la sortie seule, aucun rapport inventé', () {
      final s = relaySizeRatioLine(sourceBytes: null, outputBytes: 100 * mo);
      expect(s, contains('sortie 100.0 Mo'));
      expect(s, contains('non pesee'));
      expect(s, isNot(contains('rapport')));
    });

    test('une source de taille nulle ne produit pas de division par zéro', () {
      final s = relaySizeRatioLine(sourceBytes: 0, outputBytes: 10 * mo);
      expect(s, isNot(contains('rapport')));
      expect(s, isNot(contains('Infinity')));
      expect(s, isNot(contains('NaN')));
    });

    test('la durée convertie donne le débit d\'écriture', () {
      final s = relaySizeRatioLine(
        sourceBytes: 100 * mo,
        outputBytes: 120 * mo,
        converted: const Duration(minutes: 2),
      );
      expect(s, contains('converti 120 s'));
      expect(s, contains('60.0 Mo/min'));
    });

    test('sans durée connue, rien n\'est dit du débit', () {
      final s = relaySizeRatioLine(sourceBytes: 100 * mo, outputBytes: 120 * mo);
      expect(s, isNot(contains('Mo/min')));
      expect(relaySizeRatioLine(
        sourceBytes: 100 * mo,
        outputBytes: 120 * mo,
        converted: Duration.zero,
      ), isNot(contains('Mo/min')));
    });

    test('la ligne reste sans accent : le cliquet §l10nAll compte ce fichier', () {
      final s = relaySizeRatioLine(
        sourceBytes: 1509 * mo,
        outputBytes: 2591 * mo,
        converted: const Duration(minutes: 90),
      );
      expect(RegExp(r'[àâäéèêëîïôöùûüçœ«»]').hasMatch(s), isFalse,
          reason: 'cast_relay_service.dart doit rester a zero ligne accentuee');
    });
  });

  group('R30 — de combien la sortie dépasse ce qu\'on a demandé', () {
    test('le recul jusqu\'à l\'image clé se lit dans l\'écart', () {
      // Départ demandé à 1 200 s sur un film de 6 000 s : 4 800 s attendues.
      // La copie vidéo ne peut commencer que sur une image clé, 3,2 s plus tôt
      // → 4 803,2 s de sortie. ⚠️ Cet écart subsiste APRÈS
      // `setStartsAtKeyFrame(true)` (les deux pistes reculent ensemble) : il ne
      // valide pas le correctif, il dit de combien `CastRelayState.offset`
      // surestime le vrai début du contenu servi.
      final s = relayDurationDriftLine(
        sourceDuration: const Duration(seconds: 6000),
        startAt: const Duration(seconds: 1200),
        outputDuration: const Duration(milliseconds: 4803200),
      );
      expect(s, isNotNull);
      expect(s, contains('attendu 4800 s'));
      expect(s, contains('ecart 3200 ms'));
      expect(s, contains('depart demande a 1200000 ms'));
    });

    test('départ pile sur une image clé : écart nul, rien à signaler', () {
      final s = relayDurationDriftLine(
        sourceDuration: const Duration(seconds: 6000),
        startAt: const Duration(seconds: 1200),
        outputDuration: const Duration(seconds: 4800),
      );
      expect(s, contains('ecart 0 ms'));
    });

    test('durée du film inconnue : rien n\'est affirmé', () {
      expect(
        relayDurationDriftLine(
          sourceDuration: null,
          startAt: Duration.zero,
          outputDuration: const Duration(seconds: 4800),
        ),
        isNull,
      );
      expect(
        relayDurationDriftLine(
          sourceDuration: Duration.zero,
          startAt: Duration.zero,
          outputDuration: const Duration(seconds: 4800),
        ),
        isNull,
      );
    });

    test('conversion non terminée ou départ au-delà de la fin : rien', () {
      expect(
        relayDurationDriftLine(
          sourceDuration: const Duration(seconds: 6000),
          startAt: const Duration(seconds: 1200),
          outputDuration: null,
        ),
        isNull,
      );
      expect(
        relayDurationDriftLine(
          sourceDuration: const Duration(seconds: 600),
          startAt: const Duration(seconds: 900),
          outputDuration: const Duration(seconds: 10),
        ),
        isNull,
      );
    });
  });
}
