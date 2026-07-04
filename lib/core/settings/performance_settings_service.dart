import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'perf_config.dart';

/// §perfSettings — Service singleton gérant les réglages d'optimisation.
/// Charge depuis SharedPreferences au démarrage et notifie les listeners à
/// chaque changement via [config] (même moule que `ThemeService`).
class PerformanceSettingsService {
  static const _kKey = 'aether_perf_v1';

  static final ValueNotifier<PerfConfig> config =
      ValueNotifier(PerfConfig.defaults);

  /// Charge la config persistée. À appeler avant runApp().
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kKey);
      if (raw != null) {
        config.value = PerfConfig.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      }
    } catch (_) {
      // Conserve les valeurs par défaut si la lecture échoue.
    }
  }

  /// Applique et persiste une nouvelle config.
  /// Le ValueNotifier déclenche immédiatement le rebuild de la home.
  static Future<void> save(PerfConfig newConfig) async {
    config.value = newConfig;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kKey, jsonEncode(newConfig.toJson()));
    } catch (_) {}
  }

  static Future<void> reset() => save(PerfConfig.defaults);
}
