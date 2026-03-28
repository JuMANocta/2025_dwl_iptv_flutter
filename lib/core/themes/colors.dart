import 'package:flutter/material.dart';

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

// ── Alias sémantiques (à utiliser dans tout le code UI) ─────────────────────
// Changer ces 3 lignes suffit pour recolorer toute l'appli.
const Color kAccentPrimary   = kMatrixGreen;          // Couleur principale (ex-violet)
const Color kAccentSecondary = kAetherSecondaryCyan;  // Accent cyan
const Color kAccentTertiary  = kAetherVibrantMagenta; // Accent magenta

// ── Qualités vidéo ──────────────────────────────────────────────────────────
const Color kQuality4K  = Color(0xFFE53935); // Rouge vif
const Color kQualityFHD = Color(0xFFFFC107); // Ambre
const Color kQualityHD  = kAetherSecondaryCyan; // Cyan (ex-blue)
const Color kQualitySD  = kMatrixGreenDim;   // Vert Matrix (ex-teal/purple)

// ── Langues ─────────────────────────────────────────────────────────────────
const Color kLangMulti  = kAccentPrimary;    // Vert Matrix (ex-purple)
const Color kLangVOSTFR = Color(0xFFFF8C00); // Orange
const Color kLangVF     = kAetherSecondaryCyan; // Cyan (ex-blue)
const Color kLangEpisode = kAetherSecondaryCyan; // Cyan

// ── Badges media type (player + fiches) ─────────────────────────────────────
const Color kBadgeLive   = Color(0xFFE53935); // Rouge direct
const Color kBadgeReplay = Color(0xFFF9A825); // Ambre replay
const Color kBadgeMovie  = kAetherSecondaryCyan; // Cyan film (ex-blue)
const Color kBadgeSeries = kAccentPrimary;    // Vert Matrix série (ex-purple)
const Color kBadgeFilmType   = kAetherSecondaryCyan; // Chip FILM dans filmographie
const Color kBadgeSeriesType = kAccentPrimary; // Chip SÉRIE dans filmographie

// ── Statuts / alertes ────────────────────────────────────────────────────────
const Color kWarning = Color(0xFFFF8C00); // Orange avertissement
const Color kDispo   = kAccentPrimary;    // Vert Matrix "DISPO"

// ── Dégradé principal (boutons, pills actives) ───────────────────────────────
const LinearGradient kAetherGradient = LinearGradient(
  colors: [kAccentPrimary, kAccentSecondary],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);
