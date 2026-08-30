import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/widgets/tv/focus_visibility.dart';

/// §touchNoFocus — Quand peint-on la bordure + le halo de focus ?
///
/// Le défaut corrigé : sur téléphone, fermer un dialogue ou dépiler une route
/// déplace le focus, et une vignette s'allumait en vert sans que personne ne
/// l'ait touchée. Deux façons opposées de se tromper ici — laisser ce faux
/// focus sur mobile, ou masquer l'indicateur sur TV où il est vital.
void main() {
  test('mobile au doigt — rien n\'est peint', () {
    expect(
      focusEffectsVisibleFor(isTv: false, mode: FocusHighlightMode.touch),
      isFalse,
    );
  });

  test('mobile + clavier branché — l\'indicateur revient', () {
    // Dès qu'une touche physique arrive, Flutter bascule en `traditional` :
    // l'utilisateur navigue au clavier, il DOIT voir où il est.
    expect(
      focusEffectsVisibleFor(isTv: false, mode: FocusHighlightMode.traditional),
      isTrue,
    );
  });

  test('INVARIANT — sur TV on peint TOUJOURS, quel que soit le mode', () {
    // ⚠️ Sur Android TV, `defaultTargetPlatform` vaut `android`, donc
    // `highlightMode` DÉMARRE à `touch`. Appliquer le test là-bas rendrait la
    // page muette tant que l'utilisateur n'a pas appuyé à l'aveugle.
    for (final mode in FocusHighlightMode.values) {
      expect(
        focusEffectsVisibleFor(isTv: true, mode: mode),
        isTrue,
        reason: 'mode $mode masque le focus sur TV',
      );
    }
  });
}
