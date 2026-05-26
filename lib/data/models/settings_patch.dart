import 'package:flutter/material.dart';

import '../../core/themes/app_theme_config.dart';

/// §18 — Transaction de paramètres envoyée par la webapp mobile au pairing TV.
///
/// Le mobile sert de "télécommande de configuration" : il remplit un formulaire
/// HTML (thème, clé TMDB, rafraîchissement EPG) puis envoie le tout en une seule
/// transaction. La TV applique le patch atomiquement (cf. `SettingsApplyService`).
///
/// Chaque champ est **nullable / opt-out** : `null` (ou `false` pour les flags)
/// signifie "ne pas toucher". Ainsi un patch ne modifie que ce que l'utilisateur
/// a réellement changé côté mobile.
class SettingsPatch {
  /// Nouvelle configuration de thème complète, ou `null` si inchangée.
  final AppThemeConfig? theme;

  /// Nouveau Bearer Token TMDB v4, ou `null` si inchangé.
  /// Chaîne vide = demande explicite de suppression de la clé.
  final String? tmdbToken;

  /// `true` → invalider le cache XMLTV et recharger l'EPG.
  final bool refreshXmltv;

  const SettingsPatch({
    this.theme,
    this.tmdbToken,
    this.refreshXmltv = false,
  });

  bool get isEmpty =>
      theme == null && tmdbToken == null && !refreshXmltv;

  /// Construit un patch depuis le JSON envoyé par la webapp mobile.
  ///
  /// Format attendu (tous les blocs optionnels) :
  /// ```json
  /// {
  ///   "theme": { "primary": "#00FF41", "accent": "#00CED1",
  ///              "tertiary": "#C71585", "glow": 0.4, "radius": 8,
  ///              "mode": "system" },
  ///   "tmdb": "eyJhbGciOi...",      // absent = inchangé, "" = supprimer
  ///   "refreshXmltv": true
  /// }
  /// ```
  factory SettingsPatch.fromJson(Map<String, dynamic> j) {
    AppThemeConfig? theme;
    final t = j['theme'];
    if (t is Map<String, dynamic>) {
      theme = AppThemeConfig(
        primaryColor: _parseHex(t['primary'] as String?) ??
            AppThemeConfig.defaults.primaryColor,
        accentColor: _parseHex(t['accent'] as String?) ??
            AppThemeConfig.defaults.accentColor,
        tertiaryColor: _parseHex(t['tertiary'] as String?) ??
            AppThemeConfig.defaults.tertiaryColor,
        glowIntensity:
            ((t['glow'] as num?)?.toDouble() ?? 0.4).clamp(0.0, 1.0),
        borderRadius:
            ((t['radius'] as num?)?.toDouble() ?? 8.0).clamp(0.0, 16.0),
        themeMode: _parseMode(t['mode'] as String?),
      );
    }

    // `tmdb` absent → null (inchangé). Présent (même vide) → on prend la valeur.
    String? tmdb;
    if (j.containsKey('tmdb')) {
      tmdb = (j['tmdb'] as String?)?.trim() ?? '';
    }

    return SettingsPatch(
      theme: theme,
      tmdbToken: tmdb,
      refreshXmltv: j['refreshXmltv'] == true,
    );
  }

  /// Parse `#RRGGBB` (ou `RRGGBB`) en [Color] opaque. Retourne `null` si invalide.
  static Color? _parseHex(String? hex) {
    if (hex == null) return null;
    var h = hex.trim();
    if (h.startsWith('#')) h = h.substring(1);
    if (h.length != 6) return null;
    final v = int.tryParse(h, radix: 16);
    if (v == null) return null;
    return Color(0xFF000000 | v);
  }

  static ThemeMode _parseMode(String? m) {
    switch (m) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
