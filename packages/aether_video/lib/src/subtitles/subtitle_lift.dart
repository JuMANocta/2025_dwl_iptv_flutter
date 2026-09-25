/// AetherStream patch 28 (R50) — De combien remonter des sous-titres pour
/// qu'ils ne passent pas sous les contrôles de l'app.
///
/// Les sous-titres se dessinent dans le CADRE de l'image (la boîte au ratio de
/// la vidéo, centrée), les contrôles sont posés au bas de l'ÉCRAN. Seule la
/// part des contrôles qui mord sur le cadre compte : un film au format 2,39:1
/// a des bandes noires qui absorbent déjà une partie de la barre.
///
/// - [inset] : hauteur du bas de l'écran recouverte par les contrôles ;
/// - [gapBelowBox] : distance entre le bas du cadre et le bas de l'écran
///   (négative quand le cadre déborde, format « zoom ») ;
/// - [boxHeight] : hauteur du cadre.
///
/// Toutes les valeurs dans la même unité. Le résultat est borné à la moitié
/// du cadre : dans une fenêtre minuscule (entrée en PiP avant que l'app n'ait
/// retiré la marge), mieux vaut des sous-titres un peu masqués que partis
/// hors de l'image.
///
/// ⚠️ Le natif (`VideoPlayerView.subtitleLiftFor`, Kotlin) applique la MÊME
/// règle à la `SubtitleView` : les modifier ensemble.
double subtitleLiftInBox({
  required double inset,
  required double gapBelowBox,
  required double boxHeight,
}) {
  if (inset <= 0 || boxHeight <= 0) return 0;
  final double lift = inset - gapBelowBox;
  if (lift <= 0) return 0;
  final double max = boxHeight * kSubtitleMaxLiftFraction;
  return lift > max ? max : lift;
}

/// Part maximale du cadre dont les sous-titres peuvent remonter.
const double kSubtitleMaxLiftFraction = 0.5;
