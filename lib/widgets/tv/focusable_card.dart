import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/themes/aether_theme_extension.dart';
import '../../core/utils/platform_tv.dart';
import '../../data/services/remote_control_service.dart';

/// Wrapper de focus pour la navigation D-pad / clavier (§3c-2).
///
/// Sur Android TV / Fire TV, chaque élément interactif doit afficher un
/// indicateur de focus très lisible à distance (3m+) :
///   - Bordure de couleur `focusGlowColor` (typiquement la couleur Matrix
///     primaire du thème) avec une épaisseur configurable.
///   - Glow `boxShadow` d'intensité proportionnelle à `glowIntensity` du thème.
///   - Léger `scale(1.05)` animé pour confirmer visuellement le focus.
///   - Couleur de fond plus claire derrière (highlight).
///
/// Sur mobile (`PlatformTv.isTv` false), le widget se comporte comme un
/// `InkWell` standard avec un border-radius — pas d'effet de focus parasite.
///
/// Le widget intercepte aussi la touche **Enter / OK / Select** de la
/// télécommande (`LogicalKeyboardKey.select`, `enter`, `numpadEnter`,
/// `gameButtonA`) pour déclencher `onTap` lorsque focused.
class FocusableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;

  /// Force l'effet focus même sur mobile (ex: pour démo). Par défaut, l'effet
  /// n'est appliqué que sur TV.
  final bool forceTvLook;

  /// Auto-focus à la première frame. Utile pour focus initial dans un dialog
  /// ou la première card d'une liste.
  final bool autofocus;

  /// Si `true`, ne fournit ni `Material` ni `InkWell` — utile quand le child
  /// a déjà son propre `GestureDetector`/anim de press (ex: `_HomeCard` de la
  /// home avec son animation `_pressed`). Dans ce mode, `onTap` est appelé
  /// UNIQUEMENT via la touche OK de la télécommande ; les taps souris/touch
  /// sont gérés par le child.
  final bool decorateOnly;

  /// Couleur de fond par défaut (sans focus). En mode focus, on superpose
  /// `surfaceContainerHighest.withAlpha(80)`. Si `null`, fond transparent.
  final Color? backgroundColor;

  const FocusableCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
    this.forceTvLook = false,
    this.autofocus = false,
    this.decorateOnly = false,
    this.backgroundColor,
  });

  @override
  State<FocusableCard> createState() => _FocusableCardState();
}

class _FocusableCardState extends State<FocusableCard> {
  bool _focused = false;

  @override
  void dispose() {
    // Libère l'enregistrement télécommande si cette card était la cible active.
    RemoteControlService.instance.clearActivate(this);
    super.dispose();
  }

  // Mapping des touches "OK" télécommande vers onTap.
  static final _activationKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA, // certaines manettes / remotes
    LogicalKeyboardKey.space,
  };

  // §3c-7 — touches "Menu" télécommande → équivalent long-press (menu
  // contextuel favoris / reprise / oubli).
  static final _longPressKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.contextMenu,
    LogicalKeyboardKey.info,
    LogicalKeyboardKey.gameButtonY,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_activationKeys.contains(event.logicalKey)) {
      widget.onTap?.call();
      return KeyEventResult.handled;
    }
    if (_longPressKeys.contains(event.logicalKey) && widget.onLongPress != null) {
      widget.onLongPress!.call();
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

    final isTv = widget.forceTvLook || PlatformTv.isTv;
    final showFocusEffect = isTv && _focused;

    final focusColor = ext?.focusGlowColor ?? cs.primary;
    final glow = ext?.glowIntensity ?? 0.4;
    final borderW = ext?.focusBorderWidth ?? 2.0;

    final decorated = AnimatedScale(
      scale: showFocusEffect ? 1.05 : 1.0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        // §ergo — Le glow reste en `decoration` (boxShadow = zéro coût layout).
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: showFocusEffect
              ? [
                  BoxShadow(
                    color: focusColor.withAlpha((255 * 0.55 * glow).round()),
                    blurRadius: 18 * (0.5 + glow),
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        // §ergo — La bordure de focus passe en `foregroundDecoration` : elle est
        // peinte PAR-DESSUS l'enfant sans agrandir la box. Avant, un
        // `Border.all(width: 2)` (même transparent) ajoutait 4px à chaque carte
        // → dans un Wrap calé au pixel, la 3e vignette passait à la ligne
        // (chaînes affichées 2 par ligne au lieu de 3). Plus de coût layout ici.
        foregroundDecoration: showFocusEffect
            ? BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: focusColor, width: borderW),
              )
            : null,
        child: widget.decorateOnly
            ? widget.child
            : Material(
                color: showFocusEffect
                    ? (widget.backgroundColor ?? cs.surfaceContainerHighest.withAlpha(80))
                    : (widget.backgroundColor ?? Colors.transparent),
                borderRadius: radius,
                child: InkWell(
                  onTap: widget.onTap,
                  onLongPress: widget.onLongPress,
                  borderRadius: radius,
                  child: ClipRRect(
                    borderRadius: radius,
                    child: widget.child,
                  ),
                ),
              ),
      ),
    );

    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) {
        if (mounted) setState(() => _focused = f);
        // §webConsole Phase 2 — la télécommande web cible l'élément focusé :
        // on s'enregistre (OK → onTap, Menu → onLongPress) au gain de focus,
        // on se désenregistre à la perte.
        if (f) {
          RemoteControlService.instance
              .registerActivate(this, widget.onTap, widget.onLongPress);
        } else {
          RemoteControlService.instance.clearActivate(this);
        }
        // §3c-bis #7 — Si la card vient de prendre le focus sur TV, l'amener
        // dans le viewport du ScrollView ancêtre (carrousel horizontal /
        // ListView vertical). Sans ça, le focus peut se déplacer sur une card
        // hors-écran → utilisateur perdu, scroll figé.
        if (f && isTv) {
          // post-frame pour laisser le layout se stabiliser avant le scroll.
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
      onKeyEvent: _onKey,
      child: decorated,
    );
  }
}
