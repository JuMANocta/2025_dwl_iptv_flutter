import 'package:flutter/material.dart';
import 'colors.dart';

// Thème Clair AetherStream
ThemeData lightTheme() {
  return ThemeData(
    brightness: Brightness.light,
    primaryColor: kAetherPrimaryPurple, // Couleur principale de l'app
    hintColor: kAetherSecondaryCyan, // Pour les accents subtils ou les champs de texte
    scaffoldBackgroundColor: kWhite, // Fond général de l'app
    cardColor: kWhite, // Couleur des cartes
    textTheme: const TextTheme(
      headlineLarge: TextStyle(color: kDarkGrey, fontWeight: FontWeight.bold),
      headlineMedium: TextStyle(color: kDarkGrey, fontWeight: FontWeight.bold),
      bodyLarge: TextStyle(color: kDarkGrey), // Texte principal
      bodyMedium: TextStyle(color: kMediumGrey), // Texte secondaire
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: kWhite,
      foregroundColor: kDarkGrey, // Couleur des icônes et du texte de l'AppBar
      elevation: 0,
      titleTextStyle: TextStyle(
        color: kDarkGrey,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
      iconTheme: IconThemeData(color: kDarkGrey),
    ),
    buttonTheme: ButtonThemeData(
      buttonColor: kAetherPrimaryPurple,
      textTheme: ButtonTextTheme.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kAetherPrimaryPurple,
      foregroundColor: kWhite,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: kWhite, backgroundColor: kAetherPrimaryPurple, // Couleur du texte du bouton
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.bold),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: kAetherPrimaryPurple, // Couleur du texte du bouton
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kLightGrey,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: kAetherPrimaryPurple, width: 2),
      ),
      labelStyle: const TextStyle(color: kMediumGrey),
      hintStyle: const TextStyle(color: kMediumGrey),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: kWhite,
      selectedItemColor: kAetherPrimaryPurple,
      unselectedItemColor: kMediumGrey,
      selectedLabelStyle: TextStyle(fontWeight: FontWeight.bold),
    ),
    // ... Ajoutez d'autres thèmes d'widgets au besoin
  );
}

// Thème Sombre AetherStream
ThemeData darkTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    primaryColor: kAetherPrimaryPurple,
    hintColor: kAetherSecondaryCyan,
    scaffoldBackgroundColor: kDeepDarkGrey,
    cardColor: kContainerDark, // Utiliser la couleur pour les conteneurs sombres
    textTheme: const TextTheme(
      headlineLarge: TextStyle(color: kTextDarkPrimary, fontWeight: FontWeight.bold),
      headlineMedium: TextStyle(color: kTextDarkPrimary, fontWeight: FontWeight.bold),
      bodyLarge: TextStyle(color: kTextDarkPrimary),
      bodyMedium: TextStyle(color: kTextDarkSecondary),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: kDeepDarkGrey,
      foregroundColor: kTextDarkPrimary,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: kTextDarkPrimary,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
      iconTheme: IconThemeData(color: kTextDarkPrimary),
    ),
    buttonTheme: ButtonThemeData(
      buttonColor: kAetherPrimaryPurple,
      textTheme: ButtonTextTheme.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kAetherPrimaryPurple,
      foregroundColor: kWhite,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: kWhite, backgroundColor: kAetherPrimaryPurple,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.bold),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: kAetherSecondaryCyan, // Un accent différent pour les liens
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kContainerDark,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: kAetherPrimaryPurple, width: 2),
      ),
      labelStyle: const TextStyle(color: kTextDarkSecondary),
      hintStyle: const TextStyle(color: kMediumGrey),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: kDeepDarkGrey,
      selectedItemColor: kAetherPrimaryPurple,
      unselectedItemColor: kMediumGrey,
      selectedLabelStyle: TextStyle(fontWeight: FontWeight.bold),
    ),
  );
}