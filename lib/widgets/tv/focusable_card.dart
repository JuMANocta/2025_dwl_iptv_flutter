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

  /// Applique le `scale(1.05)` au focus. À laisser `true` pour les vignettes
  /// carrées (posters/logos). À passer **`false`** pour les éléments **pleine
  /// largeur** (tuiles de liste, lignes de paramètres) : sinon l'agrandissement
  /// horizontal fait déborder le rectangle hors de l'écran. Le focus reste
  /// visible via la bordure + le glow (aucun coût layout).
  final bool scaleOnFocus;

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
    this.scaleOnFocus = true,
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

    // §focusVisibility — Halo de focus RENFORCÉ pour être lisible à distance sur
    // TV (l'ancien `0.55 * glow` tombait à alpha ~56, voire 0 sur un thème à
    // glowIntensity nulle → focus quasi invisible). On garde un PLANCHER d'alpha
    // et un glow plus large/dense, indépendant de l'intensité du thème.
    final glowAlpha = (255 * (0.4 + 0.5 * glow)).round().clamp(110, 235);
    final effBorderW = (borderW + 0.6).clamp(2.4, 4.0);

    Widget decorated = AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        // §ergo — Le glow reste en `decoration` (boxShadow = zéro coût layout).
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: showFocusEffect
              ? [
                  BoxShadow(
                    color: focusColor.withAlpha(glowAlpha),
                    blurRadius: 24 * (0.7 + glow),
                    spreadRadius: 2.5,
                  ),
                ]
              : null,
        ),
        // §ergo — La bordure de focus passe en `foregroundDecoration` : elle est
        // peinte PAR-DESSUS l'enfant sans agrandir la box. Avant, un
        // `Border.all(width: 2)` (même transparent) ajoutait 4px à chaque carte
        // → dans un Wrap calé au pixel, la 3e vignette passait à la ligne
        // (chaînes affichées 2 par ligne au lieu de 3). Plus de coût layout ici.
        // §focusVisibility — En plus de la bordure épaisse, un VOILE teinté sur
        // les tuiles pleine largeur (`!scaleOnFocus`, ex. lignes de paramètres,
        // boutons) → focus évident même quand l'enfant est opaque et ne grossit
        // pas. Les vignettes (posters, scaleOnFocus) gardent juste scale+bordure
        // +glow pour ne pas teinter l'image.
        foregroundDecoration: showFocusEffect
            ? BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: focusColor, width: effBorderW),
                color: widget.scaleOnFocus ? null : focusColor.withAlpha(32),
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
      );

    // §tvErgo — scale(1.05) seulement pour les vignettes (scaleOnFocus true).
    // Désactivé pour les tuiles pleine largeur (sinon le rectangle déborde).
    if (widget.scaleOnFocus) {
      decorated = AnimatedScale(
        scale: showFocusEffect ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: decorated,
      );
    }

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
        // §focusScroll — Volontairement PAS de `Scrollable.ensureVisible` manuel
        // ici : le framework Flutter (`DirectionalFocusTraversalPolicyMixin`)
        // appelle déjà `ensureVisible` avec la BONNE alignmentPolicy selon la
        // direction (`keepVisibleAtEnd` pour droite/bas, `keepVisibleAtStart`
        // pour gauche/haut). L'ancien appel manuel `alignment: 0.5` recentrait
        // la carte à chaque focus → la géométrie changeait → le focus suivant
        // sautait 2-3 vignettes ("voir tout" devenait inaccessible). En se
        // reposant sur le framework, on a un scroll minimal et un focus
        // prévisible 1 par 1.
      },
      onKeyEvent: _onKey,
      child: decorated,
    );
  }
}
