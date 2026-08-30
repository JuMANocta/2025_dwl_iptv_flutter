import 'package:flutter/widgets.dart';

import '../../core/utils/platform_tv.dart';

/// §touchNoFocus — Quand faut-il PEINDRE le focus (bordure + halo + scale) ?
///
/// **Le défaut corrigé.** Depuis §dpadNav, les effets de focus s'affichaient sur
/// toutes les plateformes dès qu'un nœud avait le focus. Sur téléphone, où l'on
/// ne navigue qu'au doigt, ça produisait un « faux focus » : il suffisait qu'un
/// dialogue se ferme, qu'une route se dépile ou qu'un `autofocus` se pose pour
/// qu'une vignette s'allume en vert au milieu de l'écran, **sans que personne
/// l'ait touchée**. Reproduit sur émulateur : fermer le bandeau de mise à jour
/// laissait un halo sur une carte de la rangée Favoris.
///
/// **La règle.** Flutter modélise déjà exactement ça :
/// [FocusManager.highlightMode] vaut `touch` tant que le dernier événement est
/// un pointeur, et bascule en `traditional` dès qu'une touche physique arrive
/// (clavier, télécommande). Les surbrillances de focus de Material s'en servent
/// ; les effets `dpad`, eux, l'ignoraient. On s'y raccroche.
///
/// ⚠️ **La TV est exemptée du test.** Sur Android TV, `defaultTargetPlatform`
/// vaut `android`, donc `highlightMode` démarre à `touch` : au premier affichage
/// d'une page, plus rien ne serait visible tant que l'utilisateur n'a pas appuyé
/// sur une direction — c'est-à-dire qu'il devrait appuyer à l'aveugle pour voir
/// où il est. Exactement le défaut que `TvInitialFocus` corrige. Sur TV on peint
/// donc toujours ; le test ne s'applique qu'ailleurs.
///
/// Conséquence heureuse : un téléphone auquel on branche un clavier ou une
/// manette retrouve les indicateurs de focus au premier appui, sans réglage.
bool focusEffectsVisibleFor({
  required bool isTv,
  required FocusHighlightMode mode,
}) =>
    isTv || mode == FocusHighlightMode.traditional;

/// À mixer dans le `State` d'un widget qui dessine des effets de focus.
///
/// Expose [focusEffectsVisible] et redessine quand le mode d'entrée change
/// (branchement d'un clavier, première touche de télécommande). Le changement
/// de mode est rare : l'écouteur ne coûte rien en régime permanent.
mixin FocusEffectVisibility<T extends StatefulWidget> on State<T> {
  bool _visible = focusEffectsVisibleFor(
    isTv: PlatformTv.isTv,
    mode: FocusManager.instance.highlightMode,
  );

  /// `true` si les effets de focus doivent être peints maintenant.
  bool get focusEffectsVisible => _visible;

  void _onHighlightModeChanged(FocusHighlightMode mode) {
    final next = focusEffectsVisibleFor(isTv: PlatformTv.isTv, mode: mode);
    if (next == _visible || !mounted) return;
    setState(() => _visible = next);
  }

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onHighlightModeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onHighlightModeChanged);
    super.dispose();
  }
}
