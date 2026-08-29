import 'package:flutter/material.dart';
import 'colors.dart';
import 'app_theme_config.dart';
import 'aether_theme_extension.dart';

/// §snackTheme — Thème global des SnackBars (toasts).
///
/// Avant, les SnackBars utilisaient le rendu Material par défaut (bandeau
/// quasi blanc en thème clair, gris foncé en sombre) → hors identité visuelle.
/// On force ici un rendu **cohérent avec le thème cyberpunk** dans les deux
/// modes : surface sombre, bordure + action à la couleur principale, flottant
/// et arrondi. Appliqué à TOUTES les SnackBars de l'app sans toucher aux
/// appels individuels.
SnackBarThemeData _snackBarTheme(AppThemeConfig config) => SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: kContainerDark,
      contentTextStyle: const TextStyle(
        color: kTextDarkPrimary,
        fontWeight: FontWeight.w500,
      ),
      actionTextColor: config.primaryColor,
      elevation: 6,
      insetPadding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(config.borderRadius + 4),
        side: BorderSide(color: config.primaryColor.withAlpha(70)),
      ),
    );

// §focusVisibility — Anneau + voile de focus pour les boutons Material standards
// (sous-pages Paramètres, dialogs, FAB…) : focus très visible au D-pad TV, tout
// en restant neutre au touch mobile (n'agit que sur l'état `focused`, + léger
// feedback hover/pressed). Couvre ce que `FocusableCard` ne wrappe pas.
WidgetStateProperty<Color?> _focusOverlay(Color c) =>
    WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.focused)) return c.withAlpha(72);
      if (s.contains(WidgetState.pressed)) return c.withAlpha(40);
      if (s.contains(WidgetState.hovered)) return c.withAlpha(22);
      return null;
    });

WidgetStateProperty<BorderSide?> _focusSide(Color c) =>
    WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.focused) ? BorderSide(color: c, width: 2.6) : null);

FilledButtonThemeData _filledFocusTheme(Color ring) => FilledButtonThemeData(
      style: ButtonStyle(overlayColor: _focusOverlay(ring), side: _focusSide(ring)),
    );

IconButtonThemeData _iconFocusTheme(Color ring) => IconButtonThemeData(
      style: ButtonStyle(overlayColor: _focusOverlay(ring), side: _focusSide(ring)),
    );

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
      error:     config.errorColor, // §themePlus
    ),
    extensions: [
      AetherThemeExtension(
        primaryColor:    config.primaryColor,
        accentColor:     config.accentColor,
        tertiaryColor:   config.tertiaryColor,
        favoriteColor:   config.favoriteColor,
        warningColor:    config.warningColor,
        errorColor:      config.errorColor,
        successColor:    config.successColor,
        glowIntensity:   config.glowIntensity,
        borderRadius:    config.borderRadius,
        // §3c-2 — focus TV : on s'aligne sur la couleur principale du thème.
        focusGlowColor:  config.primaryColor,
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
      ).copyWith(
        overlayColor: _focusOverlay(config.primaryColor),
        side: _focusSide(config.primaryColor),
      ),
    ),
    // §focusVisibility — boutons pleins + boutons-icônes des sous-pages.
    filledButtonTheme: _filledFocusTheme(config.primaryColor),
    iconButtonTheme: _iconFocusTheme(config.primaryColor),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: config.primaryColor).copyWith(
        overlayColor: _focusOverlay(config.primaryColor),
        side: _focusSide(config.primaryColor),
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
        borderSide: BorderSide(color: config.primaryColor, width: 2),
      ),
      labelStyle: const TextStyle(color: kMediumGrey),
      hintStyle:  const TextStyle(color: kMediumGrey),
    ),
    // §navBarSeparate — Pendant clair du réglage documenté côté sombre : le
    // `NavigationBar` Material 3 lit `navigationBarTheme`, pas
    // `bottomNavigationBarTheme`.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kWhite,
      elevation: 0,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: kWhite,
      selectedItemColor:   config.primaryColor,
      unselectedItemColor: kMediumGrey,
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
    ),
    snackBarTheme: _snackBarTheme(config),
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
      error:     config.errorColor, // §themePlus
    ),
    extensions: [
      AetherThemeExtension(
        primaryColor:    config.primaryColor,
        accentColor:     config.accentColor,
        tertiaryColor:   config.tertiaryColor,
        favoriteColor:   config.favoriteColor,
        warningColor:    config.warningColor,
        errorColor:      config.errorColor,
        successColor:    config.successColor,
        glowIntensity:   config.glowIntensity,
        borderRadius:    config.borderRadius,
        // §3c-2 — focus TV : on s'aligne sur la couleur principale du thème.
        focusGlowColor:  config.primaryColor,
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
      ).copyWith(
        // §focusVisibility — anneau de focus TV.
        overlayColor: _focusOverlay(config.primaryColor),
        side: _focusSide(config.primaryColor),
      ),
    ),
    // §focusVisibility — boutons pleins + boutons-icônes des sous-pages.
    filledButtonTheme: _filledFocusTheme(config.primaryColor),
    iconButtonTheme: _iconFocusTheme(config.primaryColor),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: config.accentColor).copyWith(
        overlayColor: _focusOverlay(config.accentColor),
        side: _focusSide(config.accentColor),
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
        borderSide: BorderSide(color: config.primaryColor, width: 2),
      ),
      labelStyle: const TextStyle(color: kTextDarkSecondary),
      hintStyle:  const TextStyle(color: kMediumGrey),
    ),
    // §navBarSeparate — Le thème Material 2 `bottomNavigationBarTheme` (juste
    // au-dessus) ne s'applique QU'AU `BottomNavigationBar` hérité. L'app utilise
    // le `NavigationBar` Material 3, qui lit `navigationBarTheme` — absent
    // jusqu'ici. Il prenait donc sa couleur M3 par défaut, à un cheveu du
    // `scaffoldBackgroundColor` (#121212) : la barre se fondait dans le noir de
    // l'app et ne se distinguait plus du contenu.
    //
    // Un seul cran plus clair suffit ; le reste de la séparation vient du filet
    // et de l'ombre posés dans `MainNavigation` (effet volontairement léger).
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kContainerDark,
      elevation: 0,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: kDeepDarkGrey,
      selectedItemColor:   config.primaryColor,
      unselectedItemColor: kMediumGrey,
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
    ),
    snackBarTheme: _snackBarTheme(config),
  );
}
