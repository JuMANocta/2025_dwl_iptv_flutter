import 'package:flutter/material.dart';

/// Configuration complète du thème AetherStream, sérialisable pour SharedPreferences.
class AppThemeConfig {
  final Color primaryColor;
  final Color accentColor;
  final Color tertiaryColor;
  final double glowIntensity; // 0.0 → 1.0
  final double borderRadius;  // 0.0 → 16.0
  final ThemeMode themeMode;

  const AppThemeConfig({
    required this.primaryColor,
    required this.accentColor,
    required this.tertiaryColor,
    required this.glowIntensity,
    required this.borderRadius,
    required this.themeMode,
  });

  // ── Presets ─────────────────────────────────────────────────────────────────

  static const AppThemeConfig matrix = AppThemeConfig(
    primaryColor:  Color(0xFF00FF41),
    accentColor:   Color(0xFF00CED1),
    tertiaryColor: Color(0xFFC71585),
    glowIntensity: 0.4,
    borderRadius:  8.0,
    themeMode:     ThemeMode.system,
  );

  static const AppThemeConfig bladeRunner = AppThemeConfig(
    primaryColor:  Color(0xFFFF6B35),
    accentColor:   Color(0xFFFFD700),
    tertiaryColor: Color(0xFFFF1493),
    glowIntensity: 0.6,
    borderRadius:  4.0,
    themeMode:     ThemeMode.dark,
  );

  static const AppThemeConfig tron = AppThemeConfig(
    primaryColor:  Color(0xFFFFFFFF),
    accentColor:   Color(0xFF00C8FF),
    tertiaryColor: Color(0xFF7B2FFF),
    glowIntensity: 0.5,
    borderRadius:  2.0,
    themeMode:     ThemeMode.dark,
  );

  static const AppThemeConfig minimaliste = AppThemeConfig(
    primaryColor:  Color(0xFF9E9E9E),
    accentColor:   Color(0xFFFFFFFF),
    tertiaryColor: Color(0xFF757575),
    glowIntensity: 0.0,
    borderRadius:  12.0,
    themeMode:     ThemeMode.system,
  );

  static const AppThemeConfig classic = AppThemeConfig(
    primaryColor:  Color(0xFF6A0DAD),
    accentColor:   Color(0xFF00CED1),
    tertiaryColor: Color(0xFFC71585),
    glowIntensity: 0.4,
    borderRadius:  8.0,
    themeMode:     ThemeMode.system,
  );

  static AppThemeConfig get defaults => matrix;

  static const List<({String name, AppThemeConfig config})> presets = [
    (name: 'Matrix',       config: matrix),
    (name: 'Blade Runner', config: bladeRunner),
    (name: 'Tron',         config: tron),
    (name: 'Minimaliste',  config: minimaliste),
    (name: 'Classic',      config: classic),
  ];

  // ── copyWith ─────────────────────────────────────────────────────────────────

  AppThemeConfig copyWith({
    Color? primaryColor,
    Color? accentColor,
    Color? tertiaryColor,
    double? glowIntensity,
    double? borderRadius,
    ThemeMode? themeMode,
  }) => AppThemeConfig(
    primaryColor:  primaryColor  ?? this.primaryColor,
    accentColor:   accentColor   ?? this.accentColor,
    tertiaryColor: tertiaryColor ?? this.tertiaryColor,
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
    'g': glowIntensity,
    'r': borderRadius,
    'm': themeMode.index,
  };

  factory AppThemeConfig.fromJson(Map<String, dynamic> j) => AppThemeConfig(
    // ignore: deprecated_member_use
    primaryColor:  Color(j['p'] as int),
    // ignore: deprecated_member_use
    accentColor:   Color(j['a'] as int),
    // ignore: deprecated_member_use
    tertiaryColor: Color(j['t'] as int),
    glowIntensity: (j['g'] as num).toDouble(),
    borderRadius:  (j['r'] as num).toDouble(),
    themeMode:     ThemeMode.values[j['m'] as int],
  );
}
