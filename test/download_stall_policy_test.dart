import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/services/download_stall_policy.dart';

/// §dlWatchdog — La règle qui remplace le bouton « Relancer ».
///
/// Elle décide seule quand reconnecter un transfert bridé. Deux façons de se
/// tromper, opposées et toutes deux coûteuses : ne jamais relancer (le fichier
/// n'arrive plus), ou relancer en boucle (on martèle une source morte sans
/// jamais finir).
void main() {
  group('détection du décrochage', () {
    test('un débit effondré sous le quart du meilleur EST un décrochage', () {
      expect(isStalled(speed: 200 * 1024, peak: 3 * 1024 * 1024), isTrue);
    });

    test('une connexion simplement lente n\'en est pas un', () {
      // La moitié du meilleur débit : médiocre, mais couper coûterait plus
      // cher que de laisser filer.
      expect(isStalled(speed: 1.5 * 1024 * 1024, peak: 3 * 1024 * 1024),
          isFalse);
    });

    test('SANS référence, rien n\'est un décrochage', () {
      // Première mesure : un démarrage lent passerait pour un effondrement.
      expect(isStalled(speed: 10, peak: null), isFalse);
    });

    test('un plafond à zéro ne déclenche rien (division vide de sens)', () {
      expect(isStalled(speed: 0, peak: 0), isFalse);
    });
  });

  group('décision de relance', () {
    test('première relance : rien ne s\'y oppose', () {
      expect(
        shouldAutoRestart(sinceLastRestart: null, gainSinceLastRestart: null),
        isTrue,
      );
    });

    test('le délai de garde interdit d\'enchaîner les reconnexions', () {
      expect(
        shouldAutoRestart(
          sinceLastRestart: const Duration(seconds: 5),
          gainSinceLastRestart: 100 << 20,
        ),
        isFalse,
      );
    });

    test('INVARIANT — une relance qui n\'a rien rapporté n\'est pas rejouée',
        () {
      // Sans cette garde, une source HS provoquerait une reconnexion toutes
      // les 30 s, indéfiniment.
      expect(
        shouldAutoRestart(
          sinceLastRestart: const Duration(minutes: 10),
          gainSinceLastRestart: 4096,
        ),
        isFalse,
      );
    });

    test('délai écoulé ET gain réel : on relance', () {
      expect(
        shouldAutoRestart(
          sinceLastRestart: const Duration(minutes: 2),
          gainSinceLastRestart: 50 << 20,
        ),
        isTrue,
      );
    });
  });
}
