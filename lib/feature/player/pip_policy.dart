/// §pipPhone — Décisions PURES du Picture-in-Picture. Rien ici ne touche à
/// une plateforme : c'est ce qui les rend testables sous `flutter test`.

/// « Peut-on proposer le PiP en ce moment ? » — bouton manuel ET armement
/// automatique (`onUserLeaveHint`) répondent à la MÊME question.
///
/// ⚠️ **Téléphone uniquement** : la roadmap est explicite, le PiP est « sans
/// objet sur TV ». Sur téléviseur, quitter le lecteur n'a jamais de sens à
/// couvrir par une fenêtre flottante — personne ne met une box en arrière-plan.
///
/// [locked] — §1i : en mode verrouillage, un geste Accueil ne doit pas
/// ouvrir de fenêtre PiP à l'insu de l'utilisateur.
///
/// [castActive] — anticipe §castSend (phase 4, pas encore livrée) : diffuser
/// et réduire en fenêtre en même temps n'a pas de sens, `false` par défaut.
bool canOfferPip({
  required bool isTv,
  required bool supported,
  required bool hasError,
  required bool locked,
  bool castActive = false,
}) {
  if (isTv) return false;
  if (!supported) return false;
  if (hasError) return false;
  if (locked) return false;
  if (castActive) return false;
  return true;
}

/// Ratio d'image pour la fenêtre PiP, borné aux limites qu'**Android impose**
/// (`PictureInPictureParams.Builder.setAspectRatio` lève `IllegalArgumentException`
/// hors de `[1/2.39, 2.39]`) — un scope 2.40:1 y suffit, donc l'écrêtage n'est
/// pas un cas d'école.
///
/// ⚠️ Sans taille connue (moteur pas encore décodé, valeurs dégénérées), repli
/// 16:9 — jamais un ratio de 0×0 qui ferait planter l'appel natif.
({int width, int height}) pipAspectFor(int? w, int? h) {
  const fallback = (width: 16, height: 9);
  if (w == null || h == null || w <= 0 || h <= 0) return fallback;

  // Bornes Android : 100/239 ≈ 0,4184 (portrait extrême) à 239/100 = 2,39
  // (cinémascope). Fractions à petits entiers : sûres pour `Rational` côté
  // Kotlin, pas besoin d'y re-borner.
  const double minRatio = 100 / 239;
  const double maxRatio = 239 / 100;
  final double ratio = w / h;

  if (ratio < minRatio) return (width: 100, height: 239);
  if (ratio > maxRatio) return (width: 239, height: 100);
  return (width: w, height: h);
}
