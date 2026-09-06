import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/feature/player/pip_policy.dart';

/// §pipPhone — Deux décisions PURES : « peut-on proposer le PiP ? » et
/// « avec quel ratio ? ». C'est tout ce qui est testable sans appareil : le
/// reste (ouvrir réellement une fenêtre flottante) ne se vérifie que sur
/// téléphone — cf. `.claude/decisions.md` §pipPhone.
void main() {
  group('canOfferPip', () {
    test('cas nominal : oui', () {
      expect(
        canOfferPip(
            isTv: false, supported: true, hasError: false, locked: false),
        isTrue,
      );
    });

    test('TV : jamais — « sans objet sur TV » (roadmap)', () {
      expect(
        canOfferPip(
            isTv: true, supported: true, hasError: false, locked: false),
        isFalse,
      );
    });

    test('appareil sans PiP : non', () {
      expect(
        canOfferPip(
            isTv: false, supported: false, hasError: false, locked: false),
        isFalse,
      );
    });

    test('écran d\'erreur : non', () {
      expect(
        canOfferPip(
            isTv: false, supported: true, hasError: true, locked: false),
        isFalse,
      );
    });

    test('mode verrou (§1i) : non — pas de PiP à l\'insu de l\'utilisateur',
        () {
      expect(
        canOfferPip(
            isTv: false, supported: true, hasError: false, locked: true),
        isFalse,
      );
    });

    test('cast actif (anticipe §castSend) : non', () {
      expect(
        canOfferPip(
          isTv: false,
          supported: true,
          hasError: false,
          locked: false,
          castActive: true,
        ),
        isFalse,
      );
    });
  });

  group('pipAspectFor', () {
    test('taille inconnue : repli 16:9', () {
      expect(pipAspectFor(null, null), (width: 16, height: 9));
      expect(pipAspectFor(0, 0), (width: 16, height: 9));
      expect(pipAspectFor(-10, 5), (width: 16, height: 9));
    });

    test('dans les bornes : le ratio réel, inchangé', () {
      expect(pipAspectFor(1920, 1080), (width: 1920, height: 1080));
      expect(pipAspectFor(2390, 1000), (width: 2390, height: 1000)); // 2.39:1 pile
    });

    test('au-dessus de 2.39:1 (scope large) : écrêté', () {
      // ⚠️ Sans écrêtage, Android lève IllegalArgumentException.
      final r = pipAspectFor(2400, 1000); // 2.4:1
      expect(r.width / r.height, closeTo(2.39, 0.01));
    });

    test('sous 1:2.39 (portrait extrême) : écrêté', () {
      final r = pipAspectFor(1000, 2400); // 1:2.4
      expect(r.width / r.height, closeTo(100 / 239, 0.01));
    });
  });
}
