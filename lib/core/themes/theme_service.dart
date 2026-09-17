import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

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

  // ── §lightTheme — la luminosité EFFECTIVE ───────────────────────────────

  /// Forçage réservé aux tests : la luminosité ne dépend plus de l'appareil.
  @visibleForTesting
  static Brightness? debugBrightnessOverride;

  /// Clair ou sombre, MAINTENANT, tout compris : le mode choisi dans le thème,
  /// et — s'il vaut `system` — le réglage de l'appareil.
  ///
  /// ⚠️ Existe parce que les alias sémantiques de `colors.dart` sont des
  /// getters GLOBAUX (52 fichiers les lisent en direct, sans passer par
  /// `ThemeData`). Corriger le seul `lightTheme()` n'aurait donc rien changé à
  /// l'écran : il fallait un endroit où ces getters puissent savoir sur quel
  /// fond ils vont être peints.
  ///
  /// ⚠️ Aucun `Listenable` ici, et c'est voulu : `MaterialApp` se reconstruit
  /// déjà quand la luminosité système change, donc les getters sont réévalués
  /// au build suivant. En faire un notifieur ajouterait une seconde source de
  /// vérité pour rien.
  static Brightness get effectiveBrightness {
    final Brightness? forced = debugBrightnessOverride;
    if (forced != null) return forced;
    return brightnessFor(
        config.value.themeMode, PlatformDispatcher.instance.platformBrightness);
  }

  /// La même règle, **pure** : ce que donne [mode] quand l'appareil est en
  /// [platform].
  ///
  /// §themeStudio — Existe pour que l'APERÇU de la page des thèmes peigne
  /// exactement ce que l'app peindra, y compris en mode « système » : il lit
  /// la luminosité de son `MediaQuery` au lieu de celle du `PlatformDispatcher`
  /// (les tests, eux, n'en ont aucune). ⛔ Une seconde règle écrite à côté
  /// serait précisément ce qui fait mentir un aperçu.
  static Brightness brightnessFor(ThemeMode mode, Brightness platform) {
    switch (mode) {
      case ThemeMode.light:
        return Brightness.light;
      case ThemeMode.dark:
        return Brightness.dark;
      case ThemeMode.system:
        return platform;
    }
  }

  static bool get isLight => effectiveBrightness == Brightness.light;
}
