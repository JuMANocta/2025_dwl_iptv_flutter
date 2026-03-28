import 'package:flutter/material.dart';
import 'colors.dart';

// Thème Clair AetherStream
ThemeData lightTheme() {
  return ThemeData(
    brightness: Brightness.light,
    primaryColor: kAccentPrimary,
    hintColor: kAccentSecondary,
    scaffoldBackgroundColor: kWhite,
    cardColor: kWhite,
    colorScheme: ColorScheme.light(
      primary: kAccentPrimary,
      secondary: kAccentSecondary,
      tertiary: kAccentTertiary,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(color: kDarkGrey, fontWeight: FontWeight.bold),
      headlineMedium: TextStyle(color: kDarkGrey, fontWeight: FontWeight.bold),
      bodyLarge: TextStyle(color: kDarkGrey),
      bodyMedium: TextStyle(color: kMediumGrey),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: kWhite,
      foregroundColor: kDarkGrey,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: kDarkGrey,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
      iconTheme: IconThemeData(color: kDarkGrey),
    ),
    buttonTheme: ButtonThemeData(
      buttonColor: kAccentPrimary,
      textTheme: ButtonTextTheme.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kAccentPrimary,
      foregroundColor: kWhite,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: kBlack, backgroundColor: kAccentPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.bold),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: kAccentPrimary,
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
        borderSide: const BorderSide(color: kAccentPrimary, width: 2),
      ),
      labelStyle: const TextStyle(color: kMediumGrey),
      hintStyle: const TextStyle(color: kMediumGrey),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: kWhite,
      selectedItemColor: kAccentPrimary,
      unselectedItemColor: kMediumGrey,
      selectedLabelStyle: TextStyle(fontWeight: FontWeight.bold),
    ),
  );
}

// Thème Sombre AetherStream
ThemeData darkTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    primaryColor: kAccentPrimary,
    hintColor: kAccentSecondary,
    scaffoldBackgroundColor: kDeepDarkGrey,
    cardColor: kContainerDark,
    colorScheme: ColorScheme.dark(
      primary: kAccentPrimary,
      secondary: kAccentSecondary,
      tertiary: kAccentTertiary,
    ),
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
      buttonColor: kAccentPrimary,
      textTheme: ButtonTextTheme.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kAccentPrimary,
      foregroundColor: kBlack,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: kBlack, backgroundColor: kAccentPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.bold),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: kAccentSecondary,
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
        borderSide: const BorderSide(color: kAccentPrimary, width: 2),
      ),
      labelStyle: const TextStyle(color: kTextDarkSecondary),
      hintStyle: const TextStyle(color: kMediumGrey),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: kDeepDarkGrey,
      selectedItemColor: kAccentPrimary,
      unselectedItemColor: kMediumGrey,
      selectedLabelStyle: TextStyle(fontWeight: FontWeight.bold),
    ),
  );
}
