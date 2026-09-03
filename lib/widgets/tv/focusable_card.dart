import 'package:flutter/material.dart';
import 'package:dpad/dpad.dart';
import '../../core/themes/aether_theme_extension.dart';
import '../../data/services/remote_control_service.dart';
import 'dpad_row_anchor.dart';
import 'focus_visibility.dart';

/// Wrapper de focus pour la navigation D-pad / clavier (§3c-2 → §dpadNav).
///
/// **Refonte §dpadNav** : le moteur interne est désormais le package `dpad`
/// ([DpadFocusable]) — navigation par régions, mémoire de focus, auto-scroll. Le
/// modèle géométrique de Flutter (sauts erratiques, focus perdu) est abandonné.
/// **L'API publique de ce widget est INCHANGÉE** → aucun site d'appel à modifier.
///
/// - Focus visible (bordure + glow + scale optionnel) via les `effects` dpad,
///   à la couleur `focusGlowColor` du thème (s'affiche aussi au clavier desktop).
/// - **OK / Select** → [onTap] ; **long-OK** → [onLongPress] (menu contextuel).
/// - Tap souris/tactile : géré par l'`InkWell` interne (mode normal) ou par
///   l'enfant lui-même ([decorateOnly]) — `tapToSelect:false` évite le double
///   déclenchement.
/// - Télécommande web : on (dé)enregistre l'élément focusé auprès de
///   [RemoteControlService] au gain/perte de focus.
class FocusableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;

  /// Déprécié (§dpadNav) : les effets de focus s'affichent désormais sur toutes
  /// les plateformes au focus. Conservé pour compat d'API (sans effet).
  final bool forceTvLook;

  /// Auto-focus à la première frame (1re carte d'une liste, 1er item d'un dialog).
  final bool autofocus;

  /// Si `true`, ne fournit ni `Material` ni `InkWell` : l'enfant gère son propre
  /// tap/anim de press (ex. `_HomeCard`). [onTap] n'est alors déclenché que par
  /// la touche OK de la télécommande.
  final bool decorateOnly;

  /// Couleur de fond (mode normal). Si `null`, transparent.
  final Color? backgroundColor;

  /// Applique un léger `scale` au focus (vignettes/posters). À passer **`false`**
  /// pour les éléments **pleine largeur** (lignes de paramètres) : ils reçoivent
  /// alors un voile teinté à la place (focus visible sans débordement).
  final bool scaleOnFocus;

  /// §dpadRowEntry — Marque cette carte comme **point d'entrée** de sa
  /// `DpadRegion` : quand le focus entre dans la rangée sans mémoire (1re visite),
  /// dpad se cale ici (ex. la carte la plus à gauche d'un carrousel) au lieu de
  /// l'item géométriquement le plus proche (qui restait « à fond à droite »).
  final bool entry;

  /// §rowAnchor — Ancrage « façon Netflix » pour les cartes de carrousel
  /// horizontal : au focus, la carte se cale au DÉBUT (gauche) du viewport,
  /// la suite de la rangée défile devant. Sans ce flag, l'auto-scroll dpad
  /// fait un « reveal minimal » : en avançant à droite, la carte focusée
  /// reste collée au bord DROIT — vécu comme un défilement inversé (on ne
  /// voit jamais ce qui arrive). Les scrollables verticaux ancêtres gardent
  /// le reveal minimal standard. Sans effet hors carrousel (grilles).
  final bool anchorRowStart;

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
    this.entry = false,
    this.anchorRowStart = false,
    this.enabled = true,
  });

  /// §dpadAlign — `false` retire la carte des arrêts du D-pad, sans changer son
  /// rendu. Pour les items affichés mais non actionnables (programme replay sans
  /// archive, par ex.) : sans ça, la télécommande s'arrête sur des éléments où
  /// OK ne fait rien.
  final bool enabled;

  @override
  State<FocusableCard> createState() => _FocusableCardState();
}

class _FocusableCardState extends State<FocusableCard>
    with FocusEffectVisibility {
  @override
  void dispose() {
    // Filet de sécurité : libère l'enregistrement télécommande web.
    RemoteControlService.instance.clearActivate(this);
    super.dispose();
  }

  /// §rowAnchor — Scroll custom remplaçant l'auto-scroll dpad quand
  /// [FocusableCard.anchorRowStart] est actif. Logique partagée avec
  /// [FocusableChip] (§rowAnchorDetails) dans [DpadRowAnchor].
  void _anchorScroll() {
    if (!mounted) return;
    DpadRowAnchor.anchor(context);
  }

  @override
  Widget build(BuildContext context) {
    final ext = Theme.of(context).extension<AetherThemeExtension>();
    final cs = Theme.of(context).colorScheme;
    final radius = widget.borderRadius ??
        BorderRadius.circular(ext?.borderRadius ?? 12.0);

    final focusColor = ext?.focusGlowColor ?? cs.primary;

    // §focusVisibility (porté sur dpad) : bordure + glow ; scale pour les
    // vignettes, voile teinté pour les tuiles pleine largeur.
    //
    // §touchNoFocus — Rien n'est peint tant qu'on navigue au doigt : le nœud
    // garde son focus (la télécommande et le clavier continuent de marcher),
    // mais il ne s'AFFICHE pas. Cf. `focus_visibility.dart`.
    final effects = <DpadEffect>[
      if (focusEffectsVisible) ...[
        if (widget.scaleOnFocus) const DpadScaleEffect(scale: 1.05),
        DpadBorderEffect(color: focusColor, width: 2.6, borderRadius: radius),
        DpadGlowEffect(color: focusColor, opacity: 0.5, borderRadius: radius),
        if (!widget.scaleOnFocus)
          DpadTintEffect(color: focusColor, opacity: 0.12, borderRadius: radius),
      ],
    ];

    // Mode normal : Material + InkWell pour le tap tactile + ripple. En
    // `decorateOnly`, l'enfant gère lui-même le tap.
    final Widget inner = widget.decorateOnly
        ? widget.child
        : Material(
            color: widget.backgroundColor ?? Colors.transparent,
            borderRadius: radius,
            child: InkWell(
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
              borderRadius: radius,
              // §dpadChildFocus — jamais un 2e arrêt D-pad : seul le nœud dpad porte le focus.
              canRequestFocus: false,
              child: ClipRRect(borderRadius: radius, child: widget.child),
            ),
          );

    return DpadFocusable(
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      entry: widget.entry,
      onSelect: widget.onTap,
      onLongSelect: widget.onLongPress,
      // Tap tactile déjà géré (InkWell ou enfant) → on évite le double-fire.
      tapToSelect: false,
      // §rowAnchor — l'auto-scroll dpad (reveal au bord le plus proche) est
      // remplacé par notre ancrage début-de-rangée quand demandé.
      autoScroll: !widget.anchorRowStart,
      effects: effects,
      onFocusChange: (focused) {
        if (focused) {
          RemoteControlService.instance
              .registerActivate(this, widget.onTap, widget.onLongPress);
          if (widget.anchorRowStart) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _anchorScroll());
          }
        } else {
          RemoteControlService.instance.clearActivate(this);
        }
      },
      child: inner,
    );
  }
}
