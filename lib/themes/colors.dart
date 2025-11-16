import 'package:flutter/material.dart';

// Couleurs Neutres
const Color kWhite = Color(0xFFFFFFFF);
const Color kBlack = Color(0xFF000000);
const Color kLightGrey = Color(0xFFF5F5F5); // Pour fond clair très subtil
const Color kMediumGrey = Color(0xFFB0B0B0); // Texte secondaire clair
const Color kDarkGrey = Color(0xFF212121); // Texte principal clair
const Color kDeepDarkGrey = Color(0xFF121212); // Fond sombre principal
const Color kContainerDark = Color(0xFF1F1F1F); // Conteneurs sombres
const Color kTextDarkSecondary = Color(0xFFE0E0E0); // Texte clair sur fond sombre
const Color kTextDarkPrimary = Color(0xFFFFFFFF); // Texte principal sur fond sombre

// Couleurs d'Accentuation AetherStream
const Color kAetherPrimaryPurple = Color(0xFF6A0DAD); // Bleu-violet principal
const Color kAetherSecondaryCyan = Color(0xFF00CED1); // Cyan/Turquoise secondaire
const Color kAetherVibrantMagenta = Color(0xFFC71585); // Magenta vibrant pour accents glow

// Plus de dégradés si vous voulez être spécifique
// Par exemple pour un dégradé de bouton :
const LinearGradient kAetherGradient = LinearGradient(
  colors: [kAetherPrimaryPurple, kAetherVibrantMagenta],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);