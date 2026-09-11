// §bootActiveCap + §bootEscape — revue 2026-09-11, D3B-01.
//
// La phase d'ANALYSE du démarrage faisait `return null` quand elle cessait
// d'attendre — que ce soit parce que l'utilisateur avait appuyé sur « Entrer
// sans attendre » ou parce que le plafond était atteint — et le décideur fait
// d'un `null` l'écran « aucun compte configuré ». La décision est désormais
// une fonction pure, la MÊME pour la phase téléchargement et la phase analyse.
import 'package:aetherStream/core/boot/boot_outcome.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decideBootWait', () {
    test('tâche terminée → on continue (et son erreur sera relevée)', () {
      expect(decideBootWait(finished: true, skipRequested: false),
          BootWaitOutcome.proceed);
    });

    test('tâche terminée pendant le dernier tour, bouton pressé → on continue '
        'normalement (inutile d\'entrer « à moitié »)', () {
      expect(decideBootWait(finished: true, skipRequested: true),
          BootWaitOutcome.proceed);
    });

    test('« Entrer sans attendre » → l\'accueil, JAMAIS « aucun compte »', () {
      expect(decideBootWait(finished: false, skipRequested: true),
          BootWaitOutcome.enterNow);
    });

    test('immobile ou plafond, sans demande → écran d\'erreur (Réessayer)', () {
      expect(decideBootWait(finished: false, skipRequested: false),
          BootWaitOutcome.stalled,
          reason: '⛔ §bootEscape : le compte existe, sa liste met du temps — '
              'ce n\'est pas « aucun compte configuré »');
    });

    test('les trois issues sont les SEULES possibles', () {
      // Garde-fou de forme : si une quatrième issue apparaît un jour (une
      // « sortie muette » par exemple), ce test oblige à la penser ici.
      expect(BootWaitOutcome.values, hasLength(3));
    });
  });
}
