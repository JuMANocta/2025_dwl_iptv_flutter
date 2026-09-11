import 'package:aetherStream/feature/player/player_progress_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// Revue 2026-09-11, D2L-01 — quand le téléviseur rend la main, la page ne
/// réécrit plus la position LOCALE périmée.
///
/// Le défaut : film repris à 20 min, diffusé, regardé jusqu'au générique le
/// téléphone resté sur le panneau Cast. `CastService` efface la reprise à la
/// fin (§castSend) ; 10 s plus tard, la minuterie du lecteur réécrivait
/// 20:00 — « Reprendre » reculait et le film vu en entier réapparaissait.
void main() {
  group('castHandedBackAfter — quand le drapeau se lève', () {
    test('fin naturelle / arrêt depuis la télé : la diffusion de CE contenu '
        'disparaît → levé', () {
      expect(
        castHandedBackAfter(
            previous: false, wasCastingThis: true, castsThisNow: false),
        isTrue,
      );
    });

    test('un AUTRE contenu remplace celui-ci sur la télé → levé', () {
      // Même conséquence : le lecteur local est resté en pause au lancement.
      expect(
        castHandedBackAfter(
            previous: false, wasCastingThis: true, castsThisNow: false),
        isTrue,
      );
    });

    test('la diffusion ne concernait pas ce contenu → inchangé', () {
      expect(
        castHandedBackAfter(
            previous: false, wasCastingThis: false, castsThisNow: false),
        isFalse,
      );
    });

    test('simple mise à jour de statut de CE contenu → inchangé', () {
      expect(
        castHandedBackAfter(
            previous: false, wasCastingThis: true, castsThisNow: true),
        isFalse,
      );
    });

    test('déjà levé : un changement d’état ne le baisse JAMAIS', () {
      // Seule la reprise locale (ou « Reprendre sur le téléphone ») le baisse.
      expect(
        castHandedBackAfter(
            previous: true, wasCastingThis: false, castsThisNow: true),
        isTrue,
      );
    });
  });

  group('shouldWriteLocalProgress', () {
    test('pendant la diffusion de CE contenu → écrit (position de la télé)',
        () {
      expect(
        shouldWriteLocalProgress(
            castsThisMedia: true,
            handedBack: false,
            finished: false,
            skip: false),
        isTrue,
      );
    });

    test('D2L-01 — fin naturelle côté télé : la page se TAIT', () {
      expect(
        shouldWriteLocalProgress(
            castsThisMedia: false,
            handedBack: true,
            finished: false,
            skip: false),
        isFalse,
      );
    });

    test('D2L-01 — arrêt depuis la télécommande de la télé : la page se TAIT',
        () {
      expect(
        shouldWriteLocalProgress(
            castsThisMedia: false,
            handedBack: true,
            finished: false,
            skip: false),
        isFalse,
      );
    });

    test('« Reprendre sur le téléphone » : lecteur repositionné, drapeau '
        'baissé → écrit', () {
      expect(
        shouldWriteLocalProgress(
            castsThisMedia: false,
            handedBack: false,
            finished: false,
            skip: false),
        isTrue,
      );
    });

    test('relecture locale après la main rendue → écrit de nouveau', () {
      // Le drapeau est baissé quand le lecteur local rejoue.
      expect(
        shouldWriteLocalProgress(
            castsThisMedia: false,
            handedBack: false,
            finished: false,
            skip: false),
        isTrue,
      );
    });

    test('diffusion relancée de CE contenu (§castResume) malgré un drapeau '
        'resté levé → écrit la position de la télé', () {
      expect(
        shouldWriteLocalProgress(
            castsThisMedia: true,
            handedBack: true,
            finished: false,
            skip: false),
        isTrue,
      );
    });

    test('§endOfMovie : contenu fini → jamais', () {
      expect(
        shouldWriteLocalProgress(
            castsThisMedia: true,
            handedBack: false,
            finished: true,
            skip: false),
        isFalse,
      );
    });

    test('direct / replay → jamais', () {
      expect(
        shouldWriteLocalProgress(
            castsThisMedia: false,
            handedBack: false,
            finished: false,
            skip: true),
        isFalse,
      );
    });
  });
}
