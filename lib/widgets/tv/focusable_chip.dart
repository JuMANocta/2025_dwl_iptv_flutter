import 'package:flutter/material.dart';
import 'package:dpad/dpad.dart';
import '../../core/themes/aether_theme_extension.dart';
import '../../data/services/remote_control_service.dart';

/// Wrapper de focus léger pour petits contrôles inline (§3c Phase 1 → §dpadNav) :
/// onglets Séries/Films/Chaînes, sélecteurs saison / épisode / qualité, presets
/// de thème, pastilles de couleur, et hero fan (←/→ font tourner les cartes).
///
/// **Refonte §dpadNav** : moteur interne = [DpadFocusable] (package `dpad`). Pas
/// de `scale` (contrôles serrés, parfois pastilles de couleur) ni de voile —
/// juste bordure + glow au focus. L'API publique est INCHANGÉE.
///
/// - **OK / Select** → [onTap].
/// - [onArrowLeft]/[onArrowRight] → interceptent ←/→ quand focusé (hero fan).
/// - [enabled] `false` retire l'élément de la traversée D-pad.
/// - Tap souris/tactile : géré par l'enfant (qui garde son `GestureDetector`).
class FocusableChip extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;
  final bool autofocus;
  final BorderRadius? borderRadius;

  /// Notifié à chaque changement de focus (ex. pause auto-rotation du hero).
  final ValueChanged<bool>? onFocusChange;

  /// Interceptent ←/→ quand l'élément est focusé (carrousels single-focus).
  final VoidCallback? onArrowLeft;
  final VoidCallback? onArrowRight;

  const FocusableChip({
    super.key,
    required this.child,
    this.onTap,
    this.enabled = true,
    this.autofocus = false,
    this.borderRadius,
    this.onFocusChange,
    this.onArrowLeft,
    this.onArrowRight,
  });

  @override
  State<FocusableChip> createState() => _FocusableChipState();
}

class _FocusableChipState extends State<FocusableChip> {
  @override
  void dispose() {
    RemoteControlService.instance.clearActivate(this);
    super.dispose();
  }

  bool _onDirection(TraversalDirection dir) {
    if (dir == TraversalDirection.left && widget.onArrowLeft != null) {
      widget.onArrowLeft!();
      return true;
    }
    if (dir == TraversalDirection.right && widget.onArrowRight != null) {
      widget.onArrowRight!();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final ext = Theme.of(context).extension<AetherThemeExtension>();
    final cs = Theme.of(context).colorScheme;
    final radius = widget.borderRadius ??
        BorderRadius.circular(ext?.borderRadius ?? 12.0);

    final focusColor = ext?.focusGlowColor ?? cs.primary;

    final effects = <DpadEffect>[
      DpadBorderEffect(color: focusColor, width: 2.6, borderRadius: radius),
      DpadGlowEffect(color: focusColor, opacity: 0.5, borderRadius: radius),
    ];

    return DpadFocusable(
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      onSelect: widget.onTap,
      tapToSelect: false,
      effects: effects,
      onDirection:
          (widget.onArrowLeft == null && widget.onArrowRight == null)
              ? null
              : _onDirection,
      onFocusChange: (focused) {
        widget.onFocusChange?.call(focused);
        if (focused) {
          RemoteControlService.instance
              .registerActivate(this, widget.onTap, null);
        } else {
          RemoteControlService.instance.clearActivate(this);
        }
      },
      child: widget.child,
    );
  }
}
