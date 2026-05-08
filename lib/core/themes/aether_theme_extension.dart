import 'package:flutter/material.dart';

/// Extension ThemeData portant les paramètres cyberpunk spécifiques à AetherStream.
///
/// Usage dans un widget :
///   final ext = Theme.of(context).extension[AetherThemeExtension]()!;
///   decoration: ext.glowBorder()
class AetherThemeExtension extends ThemeExtension<AetherThemeExtension> {
  final Color primaryColor;
  final Color accentColor;
  final Color tertiaryColor;
  final double glowIntensity; // 0.0 → 1.0
  final double borderRadius;  // px

  const AetherThemeExtension({
    required this.primaryColor,
    required this.accentColor,
    required this.tertiaryColor,
    required this.glowIntensity,
    required this.borderRadius,
  });

  /// Bordure lumineuse avec glow optionnel.
  BoxDecoration glowBorder({Color? color, double? intensityOverride}) {
    final c = color ?? accentColor;
    final i = intensityOverride ?? glowIntensity;
    return BoxDecoration(
      border: Border.all(color: c.withAlpha((255 * 0.6).round()), width: 1.0),
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: i == 0
          ? null
          : [BoxShadow(
              color: c.withAlpha((255 * 0.3 * i).round()),
              blurRadius: 8 * i,
              spreadRadius: 1,
            )],
    );
  }

  /// Fond semi-transparent avec glow subtil (cartes home).
  BoxDecoration glassCard({Color? bg}) => BoxDecoration(
    color: (bg ?? Colors.black).withAlpha((255 * 0.4).round()),
    borderRadius: BorderRadius.circular(borderRadius),
    border: Border.all(color: accentColor.withAlpha((255 * 0.3).round()), width: 1.0),
    boxShadow: glowIntensity == 0
        ? null
        : [BoxShadow(
            color: primaryColor.withAlpha((255 * 0.15 * glowIntensity).round()),
            blurRadius: 12,
          )],
  );

  @override
  AetherThemeExtension copyWith({
    Color? primaryColor,
    Color? accentColor,
    Color? tertiaryColor,
    double? glowIntensity,
    double? borderRadius,
  }) => AetherThemeExtension(
    primaryColor:  primaryColor  ?? this.primaryColor,
    accentColor:   accentColor   ?? this.accentColor,
    tertiaryColor: tertiaryColor ?? this.tertiaryColor,
    glowIntensity: glowIntensity ?? this.glowIntensity,
    borderRadius:  borderRadius  ?? this.borderRadius,
  );

  @override
  AetherThemeExtension lerp(AetherThemeExtension? other, double t) {
    if (other == null) return this;
    return AetherThemeExtension(
      primaryColor:  Color.lerp(primaryColor, other.primaryColor, t)!,
      accentColor:   Color.lerp(accentColor, other.accentColor, t)!,
      tertiaryColor: Color.lerp(tertiaryColor, other.tertiaryColor, t)!,
      glowIntensity: glowIntensity + (other.glowIntensity - glowIntensity) * t,
      borderRadius:  borderRadius  + (other.borderRadius  - borderRadius)  * t,
    );
  }
}
