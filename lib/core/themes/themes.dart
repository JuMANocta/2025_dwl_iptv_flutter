import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'colors.dart';
import 'light_palette.dart';
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

/// §focusContrast — Un `FilledButton` est PLEIN, et souvent de la couleur
/// primaire : un anneau de la même couleur y est invisible (page « À propos »,
/// constaté sur TV le 2026-09-03 : « on ne voit pas bien celui qui est
/// sélectionné »). L'anneau des boutons pleins prend donc la couleur du TEXTE
/// (blanc en sombre, noir en clair) — contrastée contre le fond ET le bouton.
/// ⚠️ `FilledButton.styleFrom(foregroundColor:)` écrase l'`overlayColor` du
/// thème (il le dérive du texte), donc l'anneau est le SEUL signal fiable ici.
/// §btnShape (2026-09-17) — La FORME des boutons est celle du thème, la même
/// que l'anneau de focus TV (`FocusableCard` lit `AetherThemeExtension
/// .borderRadius`). Sans elle, Material 3 dessine des « pilules » et l'anneau,
/// lui, un rectangle arrondi : deux formes qui ne coïncident jamais (constaté
/// par l'utilisateur sur TV). ⛔ Ne pas redonner un `StadiumBorder` ni un rayon
/// en dur à un bouton : il sortirait de l'anneau. `WidgetStatePropertyAll`,
/// jamais `null` (§themeReboot).
WidgetStateProperty<OutlinedBorder> _buttonShape(double radius) =>
    WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
    );

FilledButtonThemeData _filledFocusTheme(
        Color ring, Color contrast, double radius) =>
    FilledButtonThemeData(
      style: ButtonStyle(
        overlayColor: _focusOverlay(ring),
        side: _focusSide(contrast),
        shape: _buttonShape(radius),
      ),
    );

IconButtonThemeData _iconFocusTheme(Color ring) => IconButtonThemeData(
      style: ButtonStyle(overlayColor: _focusOverlay(ring), side: _focusSide(ring)),
    );

/// R16 — Ce que les barres du SYSTÈME doivent afficher sur un fond de
/// luminosité [brightness] : l'heure, la batterie et les boutons de navigation
/// d'Android sont dessinés par le système, pas par nous, et rien dans l'app ne
/// lui disait de quelle couleur.
///
/// **Le défaut corrigé (recette du thème clair)** : sur un appareil dont la
/// dernière application avait demandé des icônes CLAIRES, l'heure et la
/// batterie restaient blanches sur le fond blanc du thème clair — invisibles.
/// Ce n'était pas un écran en particulier : `SystemUiOverlayStyle`
/// n'apparaissait **nulle part** dans `lib/`, donc l'app héritait de l'état
/// laissé par le lanceur.
///
/// ⚠️ `statusBarIconBrightness` (Android) dit la couleur des ICÔNES,
/// `statusBarBrightness` (iOS) celle du FOND : elles sont volontairement
/// opposées ici, ce n'est pas une faute de frappe.
///
/// ⚠️ Ça ne dit rien de la VISIBILITÉ des barres : le mode immersif du lecteur
/// reste gouverné par `SystemChrome.setEnabledSystemUIMode` (§barsRestore).
SystemUiOverlayStyle aetherOverlayStyle(Brightness brightness) {
  final bool light = brightness == Brightness.light;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: light ? Brightness.dark : Brightness.light,
    statusBarBrightness: light ? Brightness.light : Brightness.dark,
    systemNavigationBarColor: light ? kWhite : kDeepDarkGrey,
    systemNavigationBarIconBrightness:
        light ? Brightness.dark : Brightness.light,
  );
}

/// Le bouton plein de l'app : un aplat de [background], le texte que ce fond
/// exige ([onColorFor]), la même hauteur et le même gras partout.
///
/// **Le défaut corrigé (2026-09-16)** : les trois boutons de la page
/// Optimisation étaient des `FilledButton.tonalIcon` sans couleur — ils
/// prenaient le remplissage « tonal » de Material (un `secondaryContainer`
/// terne), en police normale. C'étaient les seuls boutons de l'app à ignorer
/// l'accent du thème, et ça se voyait.
///
/// ⛔ **Pourquoi ce n'est pas un défaut de `filledButtonTheme`** : y poser un
/// fond, un padding et un gras par défaut aurait restylé d'un coup les huit
/// `FilledButton` qui ne passent aucun style — dialogues, superposition Cast,
/// lecteur, état vide — jamais audités dans ce sens, et dont certains sont des
/// boutons de dialogue qu'un padding vertical de 14 ferait grossir. Le thème
/// garde donc ce qu'il portait déjà (l'anneau de focus, [_filledFocusTheme]),
/// et le style commun devient une fonction qu'on APPELLE : le rendu ne change
/// que là où on l'a demandé.
///
/// [minimumSize] : `Size.fromHeight(h)` rend le bouton pleine largeur (c'est
/// ainsi que la page Optimisation étirait déjà les siens).
ButtonStyle aetherFilledStyle(Color background, {Size? minimumSize}) =>
    FilledButton.styleFrom(
      backgroundColor: background,
      // §lightTheme — le texte suit le fond : noir sur un accent clair, blanc
      // sur un accent sombre. Jamais un blanc en dur (D4B-08).
      foregroundColor: onColorFor(background),
      padding: const EdgeInsets.symmetric(vertical: 14),
      minimumSize: minimumSize,
      textStyle: const TextStyle(fontWeight: FontWeight.bold),
    );

// §dpadChildFocus — Halo de focus pour les surfaces qui n'en avaient AUCUN :
// `ListTile` nus des feuilles d'action (`media_action_sheet.dart`, menus ⋯ des
// téléchargements…), `Chip`s et `OutlinedButton`s. Le focus natif Material ne
// s'allume qu'au clavier / D-pad (`FocusManager.highlightMode == traditional`,
// l'`InkWell` cache son voile en mode `touch`), donc rien ne teinte au tactile
// — §touchNoFocus respecté.
//
// ⚠️ `ListTileThemeData` n'a AUCUN réglage de focus : le voile du `ListTile`
// est celui de son `InkWell`, qui se replie sur `ThemeData.focusColor` (gris à
// 12 % par défaut — invisible sur un fond sombre). C'est donc `focusColor` de
// `ThemeData` qui porte le halo des tuiles, cf. [_listTileFocusColor].
OutlinedButtonThemeData _outlinedFocusTheme(Color ring, double radius) =>
    OutlinedButtonThemeData(
      style: ButtonStyle(
        overlayColor: _focusOverlay(ring),
        side: _focusSide(ring),
        shape: _buttonShape(radius),
      ),
    );

/// Voile de focus des `ListTile` (et de tout `InkWell` sans `focusColor`
/// explicite). Même intensité que [_focusOverlay] à l'état `focused`.
Color _listTileFocusColor(Color ring) => ring.withAlpha(72);

/// §themeReboot — ⚠️ **Ne JAMAIS rendre `null` ici.**
///
/// Constaté sur appareil réel le 2026-09-04 : changer une couleur de thème
/// faisait apparaître un écran rouge « Null check operator used on a null
/// value » et **remontait tout le sous-arbre de l'app** — donc relançait le
/// démarrage complet. Après une restauration `.aether` (qui écrit le thème),
/// l'app repartait sur « Bienvenue » et retéléchargeait les catalogues.
///
/// La cause est dans Flutter, mais c'est nous qui l'armons :
/// `ChipThemeData._lerpSides` (`chip_theme.dart`) résout les deux bordures
/// avec un ensemble d'états **VIDE** — donc jamais `focused` — puis fait
/// `b!` si la première est nulle. Deux `null` ⇒ exception, à chaque
/// interpolation entre l'ancien et le nouveau thème.
///
/// `BorderSide.none` est visuellement identique à l'absence de bordure, et
/// non nul : l'interpolation redevient possible.
ChipThemeData _chipFocusTheme(Color ring) => ChipThemeData(
      side: WidgetStateBorderSide.resolveWith((s) => s.contains(WidgetState.focused)
          ? BorderSide(color: ring, width: 2.6)
          : BorderSide.none),
    );

// Thème Clair AetherStream
ThemeData lightTheme(AppThemeConfig config) {
  // §lightTheme (2026-09-10) — ⚠️ Les couleurs du thème sont pensées pour du
  // NOIR. Posées telles quelles sur blanc, elles deviennent illisibles : le
  // vert Matrix y vaut 1,37:1 quand le minimum lisible est 4,5:1. Chaque
  // couleur qui sert de PREMIER PLAN (texte, icône, anneau de focus) est donc
  // dérivée ; celles qui servent de FOND gardent leur éclat, et c'est le texte
  // posé dessus qui s'adapte (`onColorFor`).
  final Color primary = readableOn(config.primaryColor);
  final Color accent = readableOn(config.accentColor);
  final Color tertiary = readableOn(config.tertiaryColor);
  final Color onPrimary = onColorFor(config.primaryColor);
  return ThemeData(
    brightness: Brightness.light,
    primaryColor: primary,
    hintColor: accent,
    scaffoldBackgroundColor: kWhite,
    cardColor: kWhite,
    colorScheme: ColorScheme.light(
      primary:   primary,
      onPrimary: onPrimary,
      secondary: accent,
      tertiary:  tertiary,
      error:     readableOn(config.errorColor), // §themePlus
    ),
    extensions: [
      AetherThemeExtension(
        primaryColor:    primary,
        accentColor:     accent,
        tertiaryColor:   tertiary,
        favoriteColor:   readableOn(config.favoriteColor),
        warningColor:    readableOn(config.warningColor),
        errorColor:      readableOn(config.errorColor),
        successColor:    readableOn(config.successColor),
        glowIntensity:   config.glowIntensity,
        borderRadius:    config.borderRadius,
        // §3c-2 — focus TV : on s'aligne sur la couleur principale du thème.
        // ⚠️ Sur TÉLÉVISEUR, l'anneau de focus est le SEUL repère de
        // navigation : sous le contraste minimal, l'app n'est pas moins jolie,
        // elle est impilotable à la télécommande.
        focusGlowColor:  primary,
      ),
    ],
    textTheme: const TextTheme(
      headlineLarge:  TextStyle(color: kDarkGrey, fontWeight: FontWeight.bold),
      headlineMedium: TextStyle(color: kDarkGrey, fontWeight: FontWeight.bold),
      bodyLarge:      TextStyle(color: kDarkGrey),
      bodyMedium:     TextStyle(color: kLightTextSecondary),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: kWhite,
      // ⚠️ Porte AUSSI le titre de la barre REPLIÉE d'une fiche : un
      // `SliverAppBar` sans `foregroundColor` propre lit celui-ci.
      foregroundColor: kDarkGrey,
      elevation: 0,
      titleTextStyle: const TextStyle(
          color: kDarkGrey, fontSize: 20, fontWeight: FontWeight.bold),
      iconTheme: const IconThemeData(color: kDarkGrey),
      // R16 — des icônes système SOMBRES sur la barre blanche.
      systemOverlayStyle: aetherOverlayStyle(Brightness.light),
    ),
    buttonTheme: ButtonThemeData(
      buttonColor: config.primaryColor,
      textTheme: ButtonTextTheme.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: config.primaryColor,
      foregroundColor: onPrimary,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: onPrimary,
        backgroundColor: config.primaryColor,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(config.borderRadius)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.bold),
      ).copyWith(
        overlayColor: _focusOverlay(primary),
        side: _focusSide(primary),
      ),
    ),
    // §focusVisibility — boutons pleins + boutons-icônes des sous-pages.
    filledButtonTheme: _filledFocusTheme(config.primaryColor, onPrimary, config.borderRadius),
    iconButtonTheme: _iconFocusTheme(primary),
    // §dpadChildFocus — ListTile / Chip / OutlinedButton : halo au D-pad.
    outlinedButtonTheme: _outlinedFocusTheme(primary, config.borderRadius),
    focusColor: _listTileFocusColor(primary),
    chipTheme: _chipFocusTheme(primary),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: primary).copyWith(
        overlayColor: _focusOverlay(primary),
        side: _focusSide(primary),
        shape: _buttonShape(config.borderRadius),
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
        borderSide: BorderSide(color: primary, width: 2),
      ),
      labelStyle: const TextStyle(color: kLightTextSecondary),
      hintStyle:  const TextStyle(color: kLightTextTertiary),
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
      selectedItemColor:   primary,
      unselectedItemColor: kLightTextSecondary,
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
    appBarTheme: AppBarTheme(
      backgroundColor: kDeepDarkGrey,
      foregroundColor: kTextDarkPrimary,
      elevation: 0,
      titleTextStyle: const TextStyle(
          color: kTextDarkPrimary, fontSize: 20, fontWeight: FontWeight.bold),
      iconTheme: const IconThemeData(color: kTextDarkPrimary),
      // R16 — des icônes système CLAIRES sur la barre sombre.
      systemOverlayStyle: aetherOverlayStyle(Brightness.dark),
    ),
    buttonTheme: ButtonThemeData(
      buttonColor: config.primaryColor,
      textTheme: ButtonTextTheme.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    // Revue 2026-09-11, D4B-08 (relecture) — le texte suit le fond, comme en
    // thème clair (`onPrimary`) : identique pour les neuf préréglages (tous
    // clairs en sombre), lisible sur une couleur personnalisée foncée.
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: config.primaryColor,
      foregroundColor: onColorFor(config.primaryColor),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: onColorFor(config.primaryColor),
        backgroundColor: config.primaryColor,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(config.borderRadius)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.bold),
      ).copyWith(
        // §focusVisibility — anneau de focus TV.
        overlayColor: _focusOverlay(config.primaryColor),
        side: _focusSide(config.primaryColor),
      ),
    ),
    // §focusVisibility — boutons pleins + boutons-icônes des sous-pages.
    filledButtonTheme: _filledFocusTheme(config.primaryColor, Colors.white, config.borderRadius),
    iconButtonTheme: _iconFocusTheme(config.primaryColor),
    // §dpadChildFocus — ListTile / Chip / OutlinedButton : halo au D-pad.
    outlinedButtonTheme: _outlinedFocusTheme(config.primaryColor, config.borderRadius),
    focusColor: _listTileFocusColor(config.primaryColor),
    chipTheme: _chipFocusTheme(config.primaryColor),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: config.accentColor).copyWith(
        overlayColor: _focusOverlay(config.accentColor),
        side: _focusSide(config.accentColor),
        shape: _buttonShape(config.borderRadius),
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
