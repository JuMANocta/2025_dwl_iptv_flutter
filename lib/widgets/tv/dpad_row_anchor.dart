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
        // Ancrage début de rangée (le clamp gère les bords : premiers items
        // → pas de sur-scroll, derniers → butée fin de liste).
        delta = bounds.left - _kAnchorPad;
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
