import 'package:flutter/material.dart';
import '../core/themes/aether_theme_extension.dart';
import '../core/themes/colors.dart';
import '../core/themes/light_palette.dart';

/// Widget d'état vide unifié (§12).
///
/// Remplace les divers "rien à afficher" éparpillés dans l'app par une
/// présentation cohérente :
///   - Icône cerclée avec glow Matrix (la couleur suit le thème courant)
///   - Titre principal en bold
///   - Sous-titre explicatif optionnel
///   - CTA optionnel (`FilledButton` plein)
///
/// Usage :
/// ```dart
/// EmptyState(
///   icon: Icons.download_outlined,
///   title: 'Aucun téléchargement',
///   subtitle: 'Tes téléchargements apparaîtront ici dès qu\'un fichier est lancé.',
///   ctaLabel: 'Parcourir',
///   onCtaTap: () => Navigator.of(context).pushNamed('/home'),
/// )
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? ctaLabel;
  final IconData? ctaIcon;
  final VoidCallback? onCtaTap;
  /// Couleur d'accent (par défaut `kAccentPrimary` Matrix).
  final Color? accentColor;
  /// Padding extérieur — par défaut 24 partout, le widget se centre dans son parent.
  final EdgeInsetsGeometry padding;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.ctaLabel,
    this.ctaIcon,
    this.onCtaTap,
    this.accentColor,
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ext = Theme.of(context).extension<AetherThemeExtension>();
    final accent = accentColor ?? ext?.primaryColor ?? kAccentPrimary;
    final glow = ext?.glowIntensity ?? 0.4;

    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icône cerclée + glow.
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    accent.withAlpha(60),
                    accent.withAlpha(10),
                    Colors.transparent,
                  ],
                ),
                // §lightTheme (2026-09-16) — ⚠️ C'était `accent.withAlpha(160)` :
                // un accent DÉJÀ éclairci par le thème clair, encore atténué de
                // 37 %, sur du blanc. Le cercle n'était plus là et l'icône
                // flottait toute seule (planche `light_42`, « Aucun
                // téléchargement »). Le trait se dérive maintenant, avec un
                // plancher de contraste.
                border: Border.all(
                    color: mutedOn(accent, cs.surface), width: 1.5),
                boxShadow: glow > 0
                    ? [
                        BoxShadow(
                          color: accent.withAlpha((255 * 0.35 * glow).round()),
                          blurRadius: 18,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: Icon(icon, size: 44, color: accent),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
            if (ctaLabel != null && onCtaTap != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onCtaTap,
                icon: Icon(ctaIcon ?? Icons.arrow_forward),
                label: Text(
                  ctaLabel!,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: onColorFor(accent), // D4B-08
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
