import 'package:flutter/material.dart';
import 'colors.dart';
import 'app_theme_config.dart';
import 'aether_theme_extension.dart';

// Thème Clair AetherStream
ThemeData lightTheme(AppThemeConfig config) {
  return ThemeData(
    brightness: Brightness.light,
    primaryColor: config.primaryColor,
    hintColor: config.accentColor,
    scaffoldBackgroundColor: kWhite,
    cardColor: kWhite,
    colorScheme: ColorScheme.light(
      primary:   config.primaryColor,
      secondary: config.accentColor,
      tertiary:  config.tertiaryColor,
    ),
    extensions: [
      AetherThemeExtension(
        primaryColor:  config.primaryColor,
        accentColor:   config.accentColor,
        tertiaryColor: config.tertiaryColor,
        glowIntensity: config.glowIntensity,
        borderRadius:  config.borderRadius,
      ),
    ],
    textTheme: const TextTheme(
      headlineLarge:  TextStyle(color: kDarkGrey, fontWeight: FontWeight.bold),
      headlineMedium: TextStyle(color: kDarkGrey, fontWeight: FontWeight.bold),
      bodyLarge:      TextStyle(color: kDarkGrey),
      bodyMedium:     TextStyle(color: kMediumGrey),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: kWhite,
      foregroundColor: kDarkGrey,
      elevation: 0,
      titleTextStyle: TextStyle(color: kDarkGrey, fontSize: 20, fontWeight: FontWeight.bold),
      iconTheme: IconThemeData(color: kDarkGrey),
    ),
    buttonTheme: ButtonThemeData(
      buttonColor: config.primaryColor,
      textTheme: ButtonTextTheme.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: config.primaryColor,
      foregroundColor: kWhite,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: kBlack,
        backgroundColor: config.primaryColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.bold),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: config.primaryColor),
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
        borderSide: BorderSide(color: config.primaryColor, width: 2),
      ),
      labelStyle: const TextStyle(color: kMediumGrey),
      hintStyle:  const TextStyle(color: kMediumGrey),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: kWhite,
      selectedItemColor:   config.primaryColor,
      unselectedItemColor: kMediumGrey,
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
    ),
  );
}

// Thème Sombre AetherStream
ThemeData darkTheme(AppThemeConfig config) {
  return ThemeData(
    brightness: Brightness.dark,
    primaryColor: config.primaryColor,
    hintColor: config.accentColor,
    scaffoldBackgroundColor: kDeepDarkGrey,
    cardColor: kContainerDark,
    colorScheme: ColorScheme.dark(
      primary:   config.primaryColor,
      secondary: config.accentColor,
      tertiary:  config.tertiaryColor,
    ),
    extensions: [
      AetherThemeExtension(
        primaryColor:  config.primaryColor,
        accentColor:   config.accentColor,
        tertiaryColor: config.tertiaryColor,
        glowIntensity: config.glowIntensity,
        borderRadius:  config.borderRadius,
      ),
    ],
    textTheme: const TextTheme(
      headlineLarge:  TextStyle(color: kTextDarkPrimary, fontWeight: FontWeight.bold),
      headlineMedium: TextStyle(color: kTextDarkPrimary, fontWeight: FontWeight.bold),
      bodyLarge:      TextStyle(color: kTextDarkPrimary),
      bodyMedium:     TextStyle(color: kTextDarkSecondary),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: kDeepDarkGrey,
      foregroundColor: kTextDarkPrimary,
      elevation: 0,
      titleTextStyle: TextStyle(color: kTextDarkPrimary, fontSize: 20, fontWeight: FontWeight.bold),
      iconTheme: IconThemeData(color: kTextDarkPrimary),
    ),
    buttonTheme: ButtonThemeData(
      buttonColor: config.primaryColor,
      textTheme: ButtonTextTheme.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: config.primaryColor,
      foregroundColor: kBlack,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: kBlack,
        backgroundColor: config.primaryColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.bold),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: config.accentColor),
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
        borderSide: BorderSide(color: config.primaryColor, width: 2),
      ),
      labelStyle: const TextStyle(color: kTextDarkSecondary),
      hintStyle:  const TextStyle(color: kMediumGrey),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: kDeepDarkGrey,
      selectedItemColor:   config.primaryColor,
      unselectedItemColor: kMediumGrey,
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
    ),
  );
}
