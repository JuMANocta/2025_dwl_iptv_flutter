import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/themes/aether_theme_extension.dart';
import '../../core/utils/platform_tv.dart';

/// Wrapper de focus léger pour petits contrôles inline (§3c Phase 1) :
/// onglets Séries/Films/Chaînes, sélecteurs saison / épisode / qualité.
///
/// Contrairement à [FocusableCard] (orienté vignette, avec `scale(1.05)`), ce
/// wrapper **n'altère pas la taille** de l'enfant — donc aucun coût layout dans
/// un `Row` serré / `Expanded` (les onglets) ni dans un scroll horizontal
/// (saisons/épisodes). Au focus sur TV, il ajoute seulement par-dessus l'enfant :
///   - une bordure `focusGlowColor` en `foregroundDecoration` (peinte au-dessus,
///     n'agrandit pas la box),
///   - un léger glow `boxShadow`.
///
/// Il intercepte la touche **OK** de la télécommande pour déclencher `onTap`, et
/// amène l'élément dans le viewport au focus (`ensureVisible`). Sur mobile
/// (`PlatformTv.isTv` false) il est **neutre** : l'enfant garde son propre tap.
///
/// `enabled` pilote la focusabilité indépendamment de `onTap` : un onglet vide
/// (`enabled: false`) est retiré de la traversée D-pad, mais un chip déjà
/// sélectionné reste focusable (sinon le focus serait perdu après sélection).
class FocusableChip extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;
  final bool autofocus;
  final BorderRadius? borderRadius;

  /// Notifié à chaque changement d'état de focus (utile p.ex. pour mettre en
  /// pause une auto-rotation pendant que l'élément est focusé sur TV).
  final ValueChanged<bool>? onFocusChange;

  const FocusableChip({
    super.key,
    required this.child,
    this.onTap,
    this.enabled = true,
    this.autofocus = false,
    this.borderRadius,
    this.onFocusChange,
  });

  @override
  State<FocusableChip> createState() => _FocusableChipState();
}

class _FocusableChipState extends State<FocusableChip> {
  bool _focused = false;

  static final _activationKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
    LogicalKeyboardKey.space,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_activationKeys.contains(event.logicalKey)) {
      widget.onTap?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final ext = Theme.of(context).extension<AetherThemeExtension>();
    final cs = Theme.of(context).colorScheme;
    final radius = widget.borderRadius ??
        BorderRadius.circular(ext?.borderRadius ?? 12.0);

    final isTv = PlatformTv.isTv;
    final show = isTv && _focused && widget.enabled;

    final focusColor = ext?.focusGlowColor ?? cs.primary;
    final glow = ext?.glowIntensity ?? 0.4;
    final borderW = ext?.focusBorderWidth ?? 2.0;

    return Focus(
      autofocus: widget.autofocus,
      canRequestFocus: widget.enabled,
      skipTraversal: !widget.enabled,
      onKeyEvent: _onKey,
      onFocusChange: (f) {
        if (mounted) setState(() => _focused = f);
        widget.onFocusChange?.call(f);
        if (f && isTv) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
            );
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: show
              ? [
                  BoxShadow(
                    color: focusColor.withAlpha((255 * 0.55 * glow).round()),
                    blurRadius: 16 * (0.5 + glow),
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        foregroundDecoration: show
            ? BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: focusColor, width: borderW),
              )
            : null,
        child: widget.child,
      ),
    );
  }
}
