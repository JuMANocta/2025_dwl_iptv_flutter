import 'package:flutter/material.dart';

/// Configuration complète du thème AetherStream, sérialisable pour SharedPreferences.
class AppThemeConfig {
  final Color primaryColor;
  final Color accentColor;
  final Color tertiaryColor;
  // §themePlus — Couleurs d'état personnalisables (2026-06-11). Avant, ces
  // rôles étaient soit des constantes figées (kFavorite rose, kWarning
  // orange), soit des `Colors.red/green` bruts éparpillés dans le front.
  /// Favori actif (cœurs fiche/action sheets, section ⭐).
  final Color favoriteColor;
  /// Avertissement / reprise (bouton REPRENDRE, alertes expiration, hints).
  final Color warningColor;
  /// Erreur / danger (suppression, échec réseau, expiration critique).
  final Color errorColor;
  /// Succès (téléchargement terminé, confirmations).
  final Color successColor;
  final double glowIntensity; // 0.0 → 1.0
  final double borderRadius;  // 0.0 → 16.0
  final ThemeMode themeMode;

  const AppThemeConfig({
    required this.primaryColor,
    required this.accentColor,
    required this.tertiaryColor,
    required this.favoriteColor,
    required this.warningColor,
    required this.errorColor,
    required this.successColor,
    required this.glowIntensity,
    required this.borderRadius,
    required this.themeMode,
  });

  // ── Presets ─────────────────────────────────────────────────────────────────

  static const AppThemeConfig matrix = AppThemeConfig(
    primaryColor:  Color(0xFF00FF41),
    accentColor:   Color(0xFF00CED1),
    tertiaryColor: Color(0xFFC71585),
    favoriteColor: Color(0xFFE040FB),
    warningColor:  Color(0xFFFF8C00),
    errorColor:    Color(0xFFE53935),
    successColor:  Color(0xFF00C853),
    glowIntensity: 0.4,
    borderRadius:  8.0,
    themeMode:     ThemeMode.system,
  );

  static const AppThemeConfig bladeRunner = AppThemeConfig(
    primaryColor:  Color(0xFFFF6B35),
    accentColor:   Color(0xFFFFD700),
    tertiaryColor: Color(0xFFFF1493),
    favoriteColor: Color(0xFFFF4081),
    warningColor:  Color(0xFFFFB300),
    errorColor:    Color(0xFFFF4444),
    successColor:  Color(0xFF66BB6A),
    glowIntensity: 0.6,
    borderRadius:  4.0,
    themeMode:     ThemeMode.dark,
  );

  static const AppThemeConfig tron = AppThemeConfig(
    primaryColor:  Color(0xFFFFFFFF),
    accentColor:   Color(0xFF00C8FF),
    tertiaryColor: Color(0xFF7B2FFF),
    favoriteColor: Color(0xFFFF5CF4),
    warningColor:  Color(0xFFFFC400),
    errorColor:    Color(0xFFFF3D71),
    successColor:  Color(0xFF00E5A0),
    glowIntensity: 0.5,
    borderRadius:  2.0,
    themeMode:     ThemeMode.dark,
  );

  static const AppThemeConfig minimaliste = AppThemeConfig(
    primaryColor:  Color(0xFF9E9E9E),
    accentColor:   Color(0xFFFFFFFF),
    tertiaryColor: Color(0xFF757575),
    favoriteColor: Color(0xFFBA68C8),
    warningColor:  Color(0xFFFFB74D),
    errorColor:    Color(0xFFE57373),
    successColor:  Color(0xFF81C784),
    glowIntensity: 0.0,
    borderRadius:  12.0,
    themeMode:     ThemeMode.system,
  );

  static const AppThemeConfig classic = AppThemeConfig(
    primaryColor:  Color(0xFF6A0DAD),
    accentColor:   Color(0xFF00CED1),
    tertiaryColor: Color(0xFFC71585),
    favoriteColor: Color(0xFFE040FB),
    warningColor:  Color(0xFFFF8C00),
    errorColor:    Color(0xFFE53935),
    successColor:  Color(0xFF00C853),
    glowIntensity: 0.4,
    borderRadius:  8.0,
    themeMode:     ThemeMode.system,
  );

  // §themePlus — Nouveaux presets (2026-06-11).

  /// Jaune néon + cyan + rouge — inspiré Cyberpunk 2077.
  static const AppThemeConfig cyberpunk = AppThemeConfig(
    primaryColor:  Color(0xFFFCEE0A),
    accentColor:   Color(0xFF00F0FF),
    tertiaryColor: Color(0xFFFF003C),
    favoriteColor: Color(0xFFFF2BD6),
    warningColor:  Color(0xFFFFA800),
    errorColor:    Color(0xFFFF003C),
    successColor:  Color(0xFF00FF9F),
    glowIntensity: 0.6,
    borderRadius:  2.0,
    themeMode:     ThemeMode.dark,
  );

  /// Rose néon + cyan + violet — esthétique synthwave/outrun années 80.
  static const AppThemeConfig synthwave = AppThemeConfig(
    primaryColor:  Color(0xFFFF2A6D),
    accentColor:   Color(0xFF05D9E8),
    tertiaryColor: Color(0xFF9D4EDD),
    favoriteColor: Color(0xFFFF71CE),
    warningColor:  Color(0xFFFFB347),
    errorColor:    Color(0xFFFF1744),
    successColor:  Color(0xFF05FFA1),
    glowIntensity: 0.7,
    borderRadius:  8.0,
    themeMode:     ThemeMode.dark,
  );

  /// Ambre + vert phosphore — terminal CRT rétro (Nostromo / Fallout).
  static const AppThemeConfig phosphore = AppThemeConfig(
    primaryColor:  Color(0xFFFFB000),
    accentColor:   Color(0xFF33FF33),
    tertiaryColor: Color(0xFFFF6000),
    favoriteColor: Color(0xFFFF5E78),
    warningColor:  Color(0xFFFFD166),
    errorColor:    Color(0xFFFF3B30),
    successColor:  Color(0xFF33FF33),
    glowIntensity: 0.5,
    borderRadius:  4.0,
    themeMode:     ThemeMode.dark,
  );

  /// Bleus glacials + aurora — palette Nord (scandinave, reposante).
  static const AppThemeConfig nordique = AppThemeConfig(
    primaryColor:  Color(0xFF88C0D0),
    accentColor:   Color(0xFF81A1C1),
    tertiaryColor: Color(0xFFB48EAD),
    favoriteColor: Color(0xFFD08770),
    warningColor:  Color(0xFFEBCB8B),
    errorColor:    Color(0xFFBF616A),
    successColor:  Color(0xFFA3BE8C),
    glowIntensity: 0.2,
    borderRadius:  10.0,
    themeMode:     ThemeMode.dark,
  );

  static AppThemeConfig get defaults => matrix;

  static const List<({String name, AppThemeConfig config})> presets = [
    (name: 'Matrix',       config: matrix),
    (name: 'Blade Runner', config: bladeRunner),
    (name: 'Tron',         config: tron),
    (name: 'Cyberpunk',    config: cyberpunk),
    (name: 'Synthwave',    config: synthwave),
    (name: 'Phosphore',    config: phosphore),
    (name: 'Nordique',     config: nordique),
    (name: 'Minimaliste',  config: minimaliste),
    (name: 'Classic',      config: classic),
  ];

  // ── copyWith ─────────────────────────────────────────────────────────────────

  AppThemeConfig copyWith({
    Color? primaryColor,
    Color? accentColor,
    Color? tertiaryColor,
    Color? favoriteColor,
    Color? warningColor,
    Color? errorColor,
    Color? successColor,
    double? glowIntensity,
    double? borderRadius,
    ThemeMode? themeMode,
  }) => AppThemeConfig(
    primaryColor:  primaryColor  ?? this.primaryColor,
    accentColor:   accentColor   ?? this.accentColor,
    tertiaryColor: tertiaryColor ?? this.tertiaryColor,
    favoriteColor: favoriteColor ?? this.favoriteColor,
    warningColor:  warningColor  ?? this.warningColor,
    errorColor:    errorColor    ?? this.errorColor,
    successColor:  successColor  ?? this.successColor,
    glowIntensity: glowIntensity ?? this.glowIntensity,
    borderRadius:  borderRadius  ?? this.borderRadius,
    themeMode:     themeMode     ?? this.themeMode,
  );

  // ── Sérialisation ────────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    // ignore: deprecated_member_use
    'p': primaryColor.value,
    // ignore: deprecated_member_use
    'a': accentColor.value,
    // ignore: deprecated_member_use
    't': tertiaryColor.value,
    // ignore: deprecated_member_use
    'f': favoriteColor.value,
    // ignore: deprecated_member_use
    'w': warningColor.value,
    // ignore: deprecated_member_use
    'e': errorColor.value,
    // ignore: deprecated_member_use
    's': successColor.value,
    'g': glowIntensity,
    'r': borderRadius,
    'm': themeMode.index,
  };

  /// §themePlus — Les 4 couleurs d'état sont OPTIONNELLES à la lecture
  /// (configs sauvegardées avant 2026-06-11 + backups `.aether` existants
  /// ne les ont pas) → fallback sur les valeurs du preset Matrix.
  factory AppThemeConfig.fromJson(Map<String, dynamic> j) => AppThemeConfig(
    // ignore: deprecated_member_use
    primaryColor:  Color(j['p'] as int),
    // ignore: deprecated_member_use
    accentColor:   Color(j['a'] as int),
    // ignore: deprecated_member_use
    tertiaryColor: Color(j['t'] as int),
    // ignore: deprecated_member_use
    favoriteColor: Color(j['f'] as int? ?? matrix.favoriteColor.value),
    // ignore: deprecated_member_use
    warningColor:  Color(j['w'] as int? ?? matrix.warningColor.value),
    // ignore: deprecated_member_use
    errorColor:    Color(j['e'] as int? ?? matrix.errorColor.value),
    // ignore: deprecated_member_use
    successColor:  Color(j['s'] as int? ?? matrix.successColor.value),
    glowIntensity: (j['g'] as num).toDouble(),
    borderRadius:  (j['r'] as num).toDouble(),
    themeMode:     ThemeMode.values[j['m'] as int],
  );
}
