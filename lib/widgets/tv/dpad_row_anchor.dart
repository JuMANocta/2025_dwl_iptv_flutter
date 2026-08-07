import 'dart:math' as math;

import 'package:flutter/material.dart';

/// §rowAnchor — Scroll custom « façon Netflix » remplaçant l'auto-scroll dpad
/// quand `anchorRowStart` est actif sur un [FocusableCard]/[FocusableChip] :
/// parcourt les scrollables ancêtres du widget focusé —
///   - axe HORIZONTAL → l'élément se cale au DÉBUT (gauche) du viewport, la
///     suite de la rangée défile devant (au lieu du « reveal minimal » dpad
///     qui laissait la carte collée au bord droit en avançant) ;
///   - axe VERTICAL → reveal minimal avec marge (mêmes maths que
///     `DpadScroll.ensureVisible` du package) pour que la page continue de
///     suivre le focus.
/// Sans effet hors carrousel (pas de scrollable horizontal ancêtre) ni au
/// tactile (déclenché uniquement par le focus D-pad/clavier).
abstract final class DpadRowAnchor {
  /// Marge gauche d'ancrage : alignée sur le padding horizontal des ListView
  /// de rangées (16) → l'élément focusé se pose exactement là où se trouve le
  /// 1er élément au repos (continuité visuelle).
  static const double _kAnchorPad = 16.0;

  /// §rowAnchorJump — Dernière rangée horizontale ayant reçu le focus.
  ///
  /// Sert à distinguer un déplacement **dans** une rangée (←/→) d'une arrivée
  /// **depuis une autre** rangée (↑/↓). Sans cette distinction, on ré-ancrait à
  /// chaque prise de focus : en descendant sur une rangée déjà défilée, la
  /// carte visée était brutalement ramenée à gauche et TOUTE la rangée sautait
  /// sous les yeux — le « saut au milieu d'un carrousel ».
  static ScrollableState? _lastRow;

  /// À appeler en post-frame quand le widget gagne le focus. [context] =
  /// contexte du widget focusé (son RenderBox donne la géométrie).
  static void anchor(BuildContext context) {
    if (!context.mounted) return;
    final render = context.findRenderObject();
    if (render is! RenderBox || !render.attached || !render.hasSize) return;

    final scrollables = <ScrollableState>[];
    context.visitAncestorElements((el) {
      if (el is StatefulElement && el.state is ScrollableState) {
        scrollables.add(el.state as ScrollableState);
      }
      return true;
    });

    // §rowAnchorJump — Si le focus quitte les carrousels (grille, bouton…), on
    // oublie la rangée courante : y revenir plus tard doit compter comme une
    // ARRIVÉE, pas comme un déplacement interne.
    if (!scrollables.any(
        (s) => axisDirectionToAxis(s.axisDirection) == Axis.horizontal)) {
      _lastRow = null;
    }

    for (final s in scrollables) {
      final viewport = s.context.findRenderObject();
      if (viewport is! RenderBox || !viewport.hasSize) continue;
      final position = s.position;
      if (!position.hasPixels || !position.hasContentDimensions) continue;

      final horizontal =
          axisDirectionToAxis(s.axisDirection) == Axis.horizontal;
      final bounds = MatrixUtils.transformRect(
        render.getTransformTo(viewport),
        Offset.zero & render.size,
      );

      double delta;
      if (horizontal) {
        // §rowAnchorJump — L'ancrage à gauche ne s'applique QUE lorsqu'on se
        // déplace à l'intérieur de la même rangée (←/→). En arrivant d'une
        // autre rangée (↑/↓), on laisse la rangée où elle est et on se contente
        // de rendre la carte visible : sinon elle était ramenée de force à
        // gauche et toute la rangée sautait.
        final sameRow = identical(s, _lastRow);
        _lastRow = s;
        if (sameRow) {
          // Ancrage début de rangée (le clamp gère les bords : premiers items
          // → pas de sur-scroll, derniers → butée fin de liste).
          delta = bounds.left - _kAnchorPad;
        } else {
          final extent = viewport.size.width;
          if (bounds.left >= _kAnchorPad && bounds.right <= extent) {
            continue; // déjà entièrement visible → aucun mouvement
          }
          delta = bounds.left < _kAnchorPad
              ? bounds.left - _kAnchorPad
              : bounds.right - (extent - _kAnchorPad);
        }
      } else {
        // Reveal minimal vertical (comportement dpad standard conservé).
        final extent = viewport.size.height;
        final pad =
            math.max(0.0, math.min(56.0, (extent - bounds.height) / 2));
        if (bounds.height + pad * 2 > extent) {
          delta = bounds.center.dy - extent / 2;
        } else if (bounds.top < pad) {
          delta = bounds.top - pad;
        } else if (bounds.bottom > extent - pad) {
          delta = bounds.bottom - (extent - pad);
        } else {
          continue; // déjà visible avec marge
        }
      }

      final reversed = s.axisDirection == AxisDirection.up ||
          s.axisDirection == AxisDirection.left;
      final offset = (position.pixels + (reversed ? -delta : delta))
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      if ((offset - position.pixels).abs() < 0.5) continue;
      position.animateTo(
        offset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }
}
