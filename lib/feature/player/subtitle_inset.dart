/// R50 — Hauteur (pixels logiques) du bas de l'écran que les sous-titres de
/// la vidéo doivent laisser libre, pour ne pas se dessiner sur la barre de
/// lecture ni sur la rangée d'options.
///
/// **Le constat** (recette AVD §tvPlayerPanel, 2026-09-22) : sur TV, avec la
/// rangée d'options et la barre affichées, le sous-titre — rendu par la
/// `SubtitleView` NATIVE, en bas de l'image, sous la couche Flutter — passait
/// sous la barre de progression. Même chose au téléphone : le bloc bas y
/// porte la même rangée (§playerPanel).
///
/// Décision PURE (testée) ; le moteur en déduit, contre le cadre RÉEL de
/// l'image, de combien remonter (patch 28 du paquet vendoré) :
///   - contrôles à l'écran → la hauteur MESURÉE du bloc bas
///     (`onBottomBarHeight`), plus l'écart qui le sépare de ce qui est
///     au-dessus (le même que l'encart « Infos vidéo ») ;
///   - contrôles masqués, PiP, diffusion (déjà exclus de [controlsOnScreen])
///     ou verrou (seul le cadenas est affiché, en haut) → 0 : les
///     sous-titres reprennent leur place.
double subtitleBottomInsetFor({
  required bool controlsOnScreen,
  required bool locked,
  required double bottomBlockHeight,
}) {
  if (!controlsOnScreen || locked) return 0;
  if (!bottomBlockHeight.isFinite || bottomBlockHeight <= 0) return 0;
  return bottomBlockHeight + kSubtitleControlsGap;
}

/// Écart entre le bloc bas et ce qui se pose au-dessus (encart des stats,
/// sous-titres).
const double kSubtitleControlsGap = 8;
