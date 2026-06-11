import 'package:flutter/material.dart';
import 'theme_service.dart';

// ── Couleurs Neutres ────────────────────────────────────────────────────────
const Color kWhite = Color(0xFFFFFFFF);
const Color kBlack = Color(0xFF000000);
const Color kLightGrey = Color(0xFFF5F5F5);
const Color kMediumGrey = Color(0xFFB0B0B0);
const Color kDarkGrey = Color(0xFF212121);
const Color kDeepDarkGrey = Color(0xFF121212);
const Color kContainerDark = Color(0xFF1F1F1F);
const Color kTextDarkSecondary = Color(0xFFE0E0E0);
const Color kTextDarkPrimary = Color(0xFFFFFFFF);

// ── Palette AetherStream (raw) ───────────────────────────────────────────────
const Color kAetherPrimaryPurple  = Color(0xFF6A0DAD); // Violet historique (conservé pour compat)
const Color kAetherSecondaryCyan  = Color(0xFF00CED1); // Cyan/Turquoise
const Color kAetherVibrantMagenta = Color(0xFFC71585); // Magenta
const Color kMatrixGreen          = Color(0xFF00FF41); // Terminal Matrix green
const Color kMatrixGreenDim       = Color(0xFF00C832); // Variante plus douce

// ── Alias sémantiques dynamiques ─────────────────────────────────────────────
// Getters lus depuis ThemeService à chaque build → réagissent aux changements
// de thème in-app sans toucher les widgets. Changer le preset = toute l'UI se recolore.
Color get kAccentPrimary   => ThemeService.config.value.primaryColor;
Color get kAccentSecondary => ThemeService.config.value.accentColor;
Color get kAccentTertiary  => ThemeService.config.value.tertiaryColor;

// ── Qualités vidéo (couleurs fixes — indépendantes du thème) ─────────────────
const Color kQuality4K  = Color(0xFFE53935); // Rouge vif
const Color kQualityFHD = Color(0xFFFFC107); // Ambre
const Color kQualityHD  = kAetherSecondaryCyan; // Cyan
const Color kQualitySD  = kMatrixGreenDim;   // Vert Matrix dim

// ── Langues ─────────────────────────────────────────────────────────────────
Color get kLangMulti     => kAccentPrimary;       // suit le thème
const Color kLangVOSTFR  = Color(0xFFFF8C00);     // Orange
const Color kLangVF      = kAetherSecondaryCyan;  // Cyan
const Color kLangEpisode = kAetherSecondaryCyan;  // Cyan

// ── Badges media type (player + fiches) ─────────────────────────────────────
const Color kBadgeLive   = Color(0xFFE53935);       // Rouge direct
const Color kBadgeReplay = Color(0xFFF9A825);       // Ambre replay
const Color kBadgeMovie  = kAetherSecondaryCyan;    // Cyan film
Color get kBadgeSeries     => kAccentPrimary;       // suit le thème
const Color kBadgeFilmType = kAetherSecondaryCyan;  // Chip FILM dans filmographie
Color get kBadgeSeriesType => kAccentPrimary;       // suit le thème

// ── Statuts / alertes ────────────────────────────────────────────────────────
// §themePlus (2026-06-11) — les 4 couleurs d'état suivent désormais le thème
// (personnalisables in-app via ThemeSettingsPage, définies par les presets).
Color get kWarning  => ThemeService.config.value.warningColor;  // reprise/alertes
Color get kFavorite => ThemeService.config.value.favoriteColor; // favori actif
Color get kError    => ThemeService.config.value.errorColor;    // erreur/danger
Color get kSuccess  => ThemeService.config.value.successColor;  // succès/confirmé
Color get kDispo    => kAccentPrimary;   // suit le thème

// ── Dégradé principal (boutons, pills actives) ───────────────────────────────
LinearGradient get kAetherGradient => LinearGradient(
  colors: [kAccentPrimary, kAccentSecondary],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);
