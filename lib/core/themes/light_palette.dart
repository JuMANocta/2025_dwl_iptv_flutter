/// §lightTheme — Rendre lisible sur BLANC une couleur pensée pour du NOIR.
///
/// ## Le constat (signalé le 2026-09-10)
///
/// « Le thème jour ne rend pas bien avec les couleurs choisies de base. »
///
/// L'identité de l'app est cyberpunk : vert Matrix `#00FF41` sur fond noir, où
/// il donne un contraste de **15,3:1** — éclatant. Le thème clair réutilisait
/// **la même valeur** sur fond blanc, où elle tombe à **1,37:1**. Le minimum
/// lisible pour du texte est 4,5:1 : autrement dit, l'accent de l'application
/// était onze fois trop pâle pour être lu.
///
/// ⚠️ Ce n'était pas un défaut de code — `ThemeMode.system` faisait exactement
/// ce qu'on lui demandait. C'est que **la moitié claire de la palette n'avait
/// jamais été travaillée**.
///
/// ## Pourquoi une FONCTION et pas une seconde palette
///
/// Les couleurs ne viennent pas d'une table figée : il y a **9 préréglages**,
/// et l'utilisateur peut composer les siennes (§themePlus, 7 couleurs
/// personnalisables persistées dans le `.aether`). Écrire une variante claire à
/// la main obligerait à en écrire dix, puis à en écrire une de plus à chaque
/// couleur choisie par quelqu'un — c'est-à-dire jamais.
///
/// On **dérive** donc : la teinte et la saturation sont l'identité, on ne touche
/// qu'à la luminosité, juste assez pour atteindre le contraste exigé.
///
/// ⛔ Ne jamais remplacer ça par une table de correspondance codée en dur : la
/// couleur personnalisée de l'utilisateur n'y serait pas.
library;

import 'dart:ui' show Color;

import 'package:flutter/material.dart' show HSLColor;

/// Fond du thème clair. Le repère de tous les calculs de cette bibliothèque.
const Color kLightSurface = Color(0xFFFFFFFF);

/// Texte SECONDAIRE du thème clair (sous-titres, libellés, valeurs).
///
/// ⚠️ Remplace `kMediumGrey` (`#B0B0B0`), qui ne donnait que **1,9:1** sur
/// blanc. C'est lui qu'on voyait sur l'écran « Console web » : le code à
/// recopier, écrit en gris presque blanc. Celui-ci vaut **7,0:1**.
const Color kLightTextSecondary = Color(0xFF5F6368);

/// Texte TERTIAIRE (mentions discrètes). Reste au-dessus du minimum lisible.
const Color kLightTextTertiary = Color(0xFF767B80);

/// Contraste EXIGÉ pour un texte ou une icône (WCAG AA, texte normal).
const double kMinTextContrast = 4.5;

/// Contraste exigé pour un ÉLÉMENT d'interface : bordure, anneau de focus,
/// pastille, trait de séparation (WCAG AA, composants non textuels).
///
/// ⚠️ Plus permissif que le texte à dessein — mais **jamais** en dessous de 3:1.
/// Sur téléviseur, l'anneau de focus est le SEUL repère de navigation : en
/// dessous de ce seuil, l'app n'est pas « moins jolie », elle est
/// **impilotable à la télécommande**.
const double kMinUiContrast = 3.0;

/// Le rapport de contraste WCAG entre [a] et [b], de 1,0 (identiques) à 21,0
/// (noir contre blanc). **Pure** — testée.
///
/// S'appuie sur `Color.computeLuminance()`, qui EST la luminance relative du
/// WCAG (linéarisation sRGB comprise) : inutile de la recalculer à la main.
double contrastRatio(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double lighter = la > lb ? la : lb;
  final double darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// [color] assombrie juste ce qu'il faut pour atteindre [minRatio] sur [on].
///
/// La teinte et la saturation sont **conservées** : un vert reste ce vert, un
/// magenta reste ce magenta. Seule la luminosité descend, par paliers de 2 %.
///
/// ⚠️ Une couleur déjà assez contrastée est rendue **telle quelle** : un thème
/// dont l'accent est déjà sombre (« Minimaliste », « Nordique ») ne doit pas
/// être noirci pour rien.
///
/// ⚠️ La transparence est préservée, mais le calcul l'ignore : une couleur
/// semi-transparente sera jugée sur sa valeur pleine. C'est volontaire — on ne
/// sait pas ce qu'il y a derrière.
///
/// **Pure** — testée.
Color readableOn(
  Color color, {
  Color on = kLightSurface,
  double minRatio = kMinTextContrast,
}) {
  if (contrastRatio(color, on) >= minRatio) return color;

  HSLColor hsl = HSLColor.fromColor(color);
  // 50 paliers de 2 % couvrent tout l'intervalle : la boucle se termine
  // toujours, et le dernier palier est le noir.
  for (int i = 0; i < 50; i++) {
    final double next = hsl.lightness - 0.02;
    hsl = hsl.withLightness(next < 0.0 ? 0.0 : next);
    final Color candidate = hsl.toColor();
    if (contrastRatio(candidate, on) >= minRatio) return candidate;
    if (hsl.lightness <= 0.0) break;
  }
  return hsl.toColor();
}

/// Revue 2026-09-11, D4A-08 — Une couleur de MARQUE rendue lisible sur
/// [surface], thème clair OU sombre : rendue telle quelle si elle contraste
/// déjà d'au moins [minRatio], sinon assombrie (fond clair) ou éclaircie
/// (fond sombre) par paliers de 2 %, teinte et saturation conservées.
///
/// ⚠️ Le cas qui l'a fait naître : Canal+ et Peacock ont une couleur de
/// marque NOIRE, posée telle quelle (texte, fond, bordure de la pastille
/// « Diffusé par ») sur la surface quasi noire du thème sombre — contraste
/// ≈ 1:1. [readableOn] ne sait qu'assombrir : il n'y pouvait rien.
///
/// Le seuil 0,179 est la luminance où le noir et le blanc contrastent
/// autant : au-dessus, le fond « est clair ». **Pure** — testée.
Color brandReadableOn(
  Color brand,
  Color surface, {
  double minRatio = kMinUiContrast,
}) {
  if (contrastRatio(brand, surface) >= minRatio) return brand;
  final bool lightSurface = surface.computeLuminance() > 0.179;
  HSLColor hsl = HSLColor.fromColor(brand);
  for (int i = 0; i < 50; i++) {
    double next = hsl.lightness + (lightSurface ? -0.02 : 0.02);
    if (next < 0.0) next = 0.0;
    if (next > 1.0) next = 1.0;
    hsl = hsl.withLightness(next);
    final Color candidate = hsl.toColor();
    if (contrastRatio(candidate, surface) >= minRatio) return candidate;
    if (next == 0.0 || next == 1.0) break;
  }
  return hsl.toColor();
}

/// La couleur du TEXTE à poser sur un aplat de [background].
///
/// ⚠️ Le piège que ça évite : un même jeton sémantique sert tantôt de
/// **premier plan** (un titre coloré), tantôt de **fond** (un bouton plein).
/// Assombrir l'accent pour le rendre lisible sur blanc rend du coup le texte
/// NOIR illisible dessus — le bouton devenait vert foncé sur texte noir. On
/// choisit donc le noir ou le blanc, celui des deux qui contraste le plus.
///
/// **Pure** — testée.
Color onColorFor(Color background) =>
    contrastRatio(const Color(0xFFFFFFFF), background) >=
            contrastRatio(const Color(0xFF000000), background)
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF000000);
