import 'package:flutter/material.dart';
import 'light_palette.dart';
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
// Revue 2026-09-11, D4B-07 — `kAetherPrimaryPurple`, `kAetherVibrantMagenta`,
// `kMatrixGreen`, `kProviderTag` et `kLangEpisode` n'avaient aucun lecteur :
// retirés. La couleur principale se lit par `kAccentPrimary` (thème).
const Color kAetherSecondaryCyan  = Color(0xFF00CED1); // Cyan/Turquoise
const Color kMatrixGreenDim       = Color(0xFF00C832); // Variante plus douce

// ── Terminal « Matrix » (dialogue de mise à jour) ────────────────────────────
/// Revue 2026-09-11, D3B-09 — §updateGreen : le dialogue de mise à jour garde
/// un style terminal FIGÉ, indépendant du thème (choix de style assumé). Ses
/// teintes vivaient en dur dans deux widgets ; elles sont nommées ici, valeurs
/// inchangées.
// Valeur de l'ancien `kMatrixGreen` (retiré par D4B-07, lot 6) : écrite ici,
// le terminal étant son seul lecteur.
const Color kTermGreen       = Color(0xFF00FF41);  // titres, boutons, filets
const Color kTermGreenDim    = Color(0xFF00AA00);  // texte secondaire
const Color kTermGreenYellow = Color(0xFFADFF2F);  // valeurs (taille, version)
const Color kTermGreenBright = Color(0xFF33FF33);  // barre ASCII, partie qui change
const Color kTermOlive       = Color(0xFF7A9A3F);  // préfixe commun atténué
const Color kTermRed         = Color(0xFFFF5555);  // erreur
const Color kTermBackground  = kBlack;             // fond du terminal (avec alpha)

// ── Posé SUR UNE IMAGE (vignettes, hero, logos) ──────────────────────────────
/// Revue 2026-09-11, D4A-16 — Texte, voiles et ombres posés sur une affiche.
/// ⚠️ Volontairement FIXES, jamais dérivés du thème : une affiche est la même
/// en thème clair et en thème sombre, et le voile qui rend le titre lisible
/// ne doit pas s'éclaircir avec le fond de l'app (§lightTheme). Valeurs
/// identiques aux littéraux qu'elles remplacent (aucun changement de rendu).
const Color kOnImage         = kWhite;             // texte / icône sur image
const Color kImageScrim      = kBlack;             // voile, ombre (avec alpha)
const Color kImageScrim70    = Color(0xB3000000);  // pastille ⋯ d'une vignette
const Color kImageScrim80    = Color(0xCC000000);  // ombre portée du hero
const Color kImageScrimSoft  = Color(0x42000000);  // = Colors.black26
const Color kOnImageFaint    = Color(0x1FFFFFFF);  // = Colors.white12
const Color kOnImageSubtle   = Color(0x3DFFFFFF);  // = Colors.white24
const Color kOnImageMuted    = Color(0x8AFFFFFF);  // = Colors.white54
const Color kDisabledOnDark  = Color(0x62FFFFFF);  // = Colors.white38
const Color kDisabledOnLight = Color(0x61000000);  // = Colors.black38
/// Tranche de la carte active du hero : cinq ombres dures, du clair au sombre,
/// sous une carte à bord blanc ([kHeroCardEdge]).
const Color kHeroEdge1 = Color(0xFFEDEDED);
const Color kHeroEdge2 = Color(0xFFD2D2D2);
const Color kHeroEdge3 = Color(0xFFA8A8A8);
const Color kHeroEdge4 = Color(0xFF7E7E7E);
const Color kHeroEdge5 = Color(0xFF4A4A4A);
const Color kHeroCardEdge = kWhite;
/// Fond derrière le logo d'une chaîne dans le hero (un logo n'a pas de fond).
const Color kHeroChannelBackdrop = Color(0xFF15171C);

// ── Alias sémantiques dynamiques ─────────────────────────────────────────────
// Getters lus depuis ThemeService à chaque build → réagissent aux changements
// de thème in-app sans toucher les widgets. Changer le preset = toute l'UI se recolore.
///
/// §lightTheme (2026-09-10) — ⚠️ Sur fond CLAIR, la valeur brute n'est pas
/// utilisable : ces couleurs sont pensées pour du noir. Le vert Matrix
/// `#00FF41` vaut 15,3:1 sur noir et **1,37:1 sur blanc**, soit onze fois
/// moins que le minimum lisible. Elles sont donc ASSOMBRIES juste ce qu'il
/// faut, teinte et saturation conservées (cf. `light_palette.dart`).
/// ⛔ Ne pas contourner ce passage en lisant `ThemeService.config` en direct
/// dans un widget : c'est précisément ce qui rendait le thème clair illisible.
Color themedOnSurface(Color raw) =>
    ThemeService.isLight ? readableOn(raw) : raw;

Color get kAccentPrimary   => themedOnSurface(ThemeService.config.value.primaryColor);
Color get kAccentSecondary => themedOnSurface(ThemeService.config.value.accentColor);
Color get kAccentTertiary  => themedOnSurface(ThemeService.config.value.tertiaryColor);

// ── Qualités vidéo (couleurs fixes — indépendantes du thème) ─────────────────
const Color kQuality4K  = Color(0xFFE53935); // Rouge vif
const Color kQualityFHD = Color(0xFFFFC107); // Ambre
const Color kQualityHD  = kAetherSecondaryCyan; // Cyan
const Color kQualitySD  = kMatrixGreenDim;   // Vert Matrix dim
/// Qualité non détectée dans le nom (fréquent : PLATINIUM `|FR| Titre (2022)`
/// sans tag). Blanc cassé fixe (décision user 2026-06-11) — remplace l'ancien
/// gris terne, distinct des 4 couleurs qualité ci-dessus et lisible sur fond
/// sombre sans crier.
const Color kQualityUnknown = Color(0xFFF0EAD6);
/// §camQuality — Rip de salle (HDTS/HDCAM/CAMRIP…). C'est bien une qualité,
/// mais la PIRE : orange d'alerte, pour qu'on ne lance pas un cam par erreur
/// en croyant prendre un flux normal.
const Color kQualityCam = Color(0xFFFF6D00);

// ── Diffuseurs (pastilles « Diffusé par » de la fiche) ──────────────────────
/// Revue 2026-09-11, D4A-08 — La couleur de MARQUE d'un diffuseur, par nom
/// normalisé (cf. `_normalizePlatform` de la fiche). Déplacée ici depuis
/// `details_page.dart` (« zéro couleur en dur dans un widget »). Couleur BRUTE :
/// ⚠️ l'afficher passe par `brandReadableOn(…, surface)` — Canal+ et Peacock
/// sont NOIRS, illisibles tels quels sur le thème sombre.
Color platformBrandColor(String platform) {
  switch (platform) {
    case 'Netflix':      return const Color(0xFFE50914);
    case 'Prime Video':  return const Color(0xFF00A8E1);
    case 'HBO Max':      return const Color(0xFF5B2D8E);
    case 'Apple TV+':    return const Color(0xFF555555);
    case 'Starz':        return const Color(0xFF00B4D8);
    case 'Paramount+':   return const Color(0xFF0064FF);
    case 'Disney+':      return const Color(0xFF0063E5);
    case 'Canal+':       return const Color(0xFF000000);
    case 'Peacock':      return const Color(0xFF000000);
    default:             return Colors.grey;
  }
}

// ── Langues ─────────────────────────────────────────────────────────────────
Color get kLangMulti     => kAccentPrimary;       // suit le thème
const Color kLangVOSTFR  = Color(0xFFFF8C00);     // Orange
const Color kLangVF      = kAetherSecondaryCyan;  // Cyan
/// §legLang — Portugais sous-titré (`|LEG.|`). Volontairement proche du
/// VOSTFR (même nature : version originale + sous-titres), en plus sourd pour
/// rester distinguable d'un coup d'œil.
const Color kLangLeg     = Color(0xFFB8860B);     // Or sombre

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
Color get kWarning  => themedOnSurface(ThemeService.config.value.warningColor);  // reprise/alertes
Color get kFavorite => themedOnSurface(ThemeService.config.value.favoriteColor); // favori actif
Color get kError    => themedOnSurface(ThemeService.config.value.errorColor);    // erreur/danger
Color get kSuccess  => themedOnSurface(ThemeService.config.value.successColor);  // succès/confirmé
Color get kDispo    => kAccentPrimary;   // suit le thème

// ── Dégradé principal (boutons, pills actives) ───────────────────────────────
LinearGradient get kAetherGradient => LinearGradient(
  colors: [kAccentPrimary, kAccentSecondary],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);
