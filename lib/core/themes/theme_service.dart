import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme_config.dart';

/// Service singleton gérant le thème runtime de l'application.
/// Charge depuis SharedPreferences au démarrage et notifie les listeners
/// à chaque changement via [config] (ValueNotifier).
class ThemeService {
  static const _kKey = 'aether_theme_v1';

  static final ValueNotifier<AppThemeConfig> config =
      ValueNotifier(AppThemeConfig.defaults);

  /// Charge la config persistée. À appeler avant runApp().
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kKey);
      if (raw != null) {
        config.value = AppThemeConfig.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      }
    } catch (_) {
      // Conserve les valeurs par défaut si la lecture échoue
    }
  }

  /// Applique et persiste une nouvelle config.
  /// Le ValueNotifier déclenche immédiatement le rebuild de MyApp.
  static Future<void> save(AppThemeConfig newConfig) async {
    config.value = newConfig;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kKey, jsonEncode(newConfig.toJson()));
    } catch (_) {}
  }

  static Future<void> reset() => save(AppThemeConfig.defaults);
}
