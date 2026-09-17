import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aetherStream/core/themes/aether_theme_extension.dart';
import 'package:aetherStream/core/themes/app_theme_config.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/core/themes/light_palette.dart';
import 'package:aetherStream/core/themes/saved_themes_service.dart';
import 'package:aetherStream/core/themes/theme_service.dart';
import 'package:aetherStream/core/themes/themes.dart';
import 'package:aetherStream/feature/settings/theme_settings_page.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:aetherStream/widgets/color_wheel.dart';

/// §themeStudio — L'aperçu doit peindre ce que l'app peindra.
///
/// ⚠️ Le défaut que ces tests tiennent : l'aperçu montrait une carte NOIRE en
/// dur et les couleurs BRUTES, même en thème clair où l'app les dérive par
/// contraste. Autrement dit, il mentait précisément là où il servait le plus.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SavedThemesService.reloadForTest();
  });

  tearDown(() {
    ThemeService.config.value = AppThemeConfig.defaults;
    ThemeService.debugBrightnessOverride = null;
  });

  Widget host(AppThemeConfig config, Brightness platform) => MediaQuery(
        data: MediaQueryData(platformBrightness: platform),
        child: MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: const [Locale('fr'), Locale('en')],
          // L'app est en SOMBRE : si l'aperçu se contentait d'hériter, il
          // peindrait sombre alors que le thème en cours d'édition est clair.
          theme: darkTheme(config),
          home: const ThemeSettingsPage(),
        ),
      );

  /// Le `ThemeData` que l'aperçu s'est construit, reconnaissable à sa
  /// luminosité : c'est le seul `Theme` du sous-arbre qui contredit l'app.
  ThemeData? previewTheme(WidgetTester tester, Brightness wanted) {
    for (final Theme t in tester.widgetList<Theme>(find.byType(Theme))) {
      if (t.data.brightness == wanted &&
          t.data.extension<AetherThemeExtension>() != null) {
        return t.data;
      }
    }
    return null;
  }

  group('aperçu', () {
    testWidgets('en mode CLAIR, il peint le fond clair et les couleurs dérivées',
        (tester) async {
      const AppThemeConfig cfg = AppThemeConfig(
        primaryColor: Color(0xFF00FF41), // Matrix : 1,37:1 sur blanc
        accentColor: Color(0xFF00CED1),
        tertiaryColor: Color(0xFFC71585),
        favoriteColor: Color(0xFFE040FB),
        warningColor: Color(0xFFFF8C00),
        errorColor: Color(0xFFE53935),
        successColor: Color(0xFF00C853),
        glowIntensity: 0.4,
        borderRadius: 8.0,
        themeMode: ThemeMode.light,
      );
      ThemeService.config.value = cfg;
      await tester.pumpWidget(host(cfg, Brightness.dark));
      await tester.pump();

      final ThemeData? data = previewTheme(tester, Brightness.light);
      expect(data, isNotNull,
          reason: 'aucun aperçu en thème clair : il a hérité du thème sombre '
              "de l'app au lieu de peindre le mode en cours d'édition");
      expect(data!.scaffoldBackgroundColor, lightTheme(cfg).scaffoldBackgroundColor);

      final AetherThemeExtension ext =
          data.extension<AetherThemeExtension>()!;
      // ⚠️ Le cœur du défaut : la couleur BRUTE n'est pas lisible sur blanc.
      expect(ext.primaryColor, isNot(cfg.primaryColor));
      expect(ext.primaryColor, readableOn(cfg.primaryColor));
      expect(contrastRatio(ext.primaryColor, kLightSurface),
          greaterThanOrEqualTo(kMinTextContrast));
      // Les quatre couleurs d'état sont dérivées elles aussi — elles n'avaient
      // aucun élément d'aperçu avant, donc personne ne le voyait.
      expect(ext.favoriteColor, readableOn(cfg.favoriteColor));
      expect(ext.warningColor, readableOn(cfg.warningColor));
      expect(ext.errorColor, readableOn(cfg.errorColor));
      expect(ext.successColor, readableOn(cfg.successColor));
    });

    testWidgets('en mode SOMBRE, les couleurs restent brutes', (tester) async {
      final AppThemeConfig cfg =
          AppThemeConfig.matrix.copyWith(themeMode: ThemeMode.dark);
      ThemeService.config.value = cfg;
      await tester.pumpWidget(host(cfg, Brightness.light));
      await tester.pump();

      final ThemeData? data = previewTheme(tester, Brightness.dark);
      expect(data, isNotNull);
      expect(data!.extension<AetherThemeExtension>()!.primaryColor,
          cfg.primaryColor);
      expect(data.scaffoldBackgroundColor, darkTheme(cfg).scaffoldBackgroundColor);
    });
  });

  group('mode « système » : une seule règle', () {
    test('elle rend la luminosité de l\'appareil, et rien d\'autre', () {
      expect(
          ThemeService.brightnessFor(ThemeMode.system, Brightness.light),
          Brightness.light);
      expect(ThemeService.brightnessFor(ThemeMode.system, Brightness.dark),
          Brightness.dark);
      // ⚠️ Un mode explicite IGNORE l'appareil : c'est ce qui permet de juger
      // le thème clair sur un téléphone en mode sombre.
      expect(ThemeService.brightnessFor(ThemeMode.light, Brightness.dark),
          Brightness.light);
      expect(ThemeService.brightnessFor(ThemeMode.dark, Brightness.light),
          Brightness.dark);
    });
  });

  group('couleur libre', () {
    test('un code hexadécimal se lit dans les deux sens', () {
      expect(hexOfColor(const Color(0xFF00FF41)), '#00FF41');
      expect(hexOfColor(const Color(0xFF000000)), '#000000');
      expect(parseHexColor('#00FF41'), const Color(0xFF00FF41));
      expect(parseHexColor('00ff41'), const Color(0xFF00FF41));
      expect(parseHexColor('  #00FF41  '), const Color(0xFF00FF41));
    });

    test('ce qui n\'est pas une couleur est REFUSÉ, jamais deviné', () {
      expect(parseHexColor(''), isNull);
      expect(parseHexColor('#0F0'), isNull); // trois chiffres : non
      expect(parseHexColor('#FF00FF41'), isNull); // un alpha : non
      expect(parseHexColor('rouge'), isNull);
      expect(parseHexColor('#GGGGGG'), isNull);
    });

    test('l\'aller-retour ne perd rien', () {
      for (final int v in [0xFF123456, 0xFFFFFFFF, 0xFF000001]) {
        expect(parseHexColor(hexOfColor(Color(v))), Color(v));
      }
    });
  });

  group('§lightTheme — un état ATTÉNUÉ reste visible', () {
    test('sur blanc, jamais sous le plancher de contraste', () {
      const List<Color> cases = [
        Color(0xFF00FF41), // Matrix : 1,37:1 brut sur blanc
        Color(0xFF00CED1), // cyan
        Color(0xFFFFC107), // ambre de la qualité FHD
        Color(0xFFF0EAD6), // blanc cassé « qualité inconnue »
        Color(0xFFFFFFFF), // le pire cas : du blanc sur du blanc
      ];
      for (final c in cases) {
        final Color m = mutedOn(c, kLightSurface);
        expect(contrastRatio(m, kLightSurface),
            greaterThanOrEqualTo(kMinUiContrast),
            reason: 'atténuée, $c disparaît du fond blanc');
      }
    });

    test('elle est bien ATTÉNUÉE, pas seulement lisible', () {
      const Color c = Color(0xFF00CED1);
      final Color full = readableOn(c);
      final Color muted = mutedOn(c, kLightSurface);
      expect(contrastRatio(muted, kLightSurface),
          lessThan(contrastRatio(full, kLightSurface)));
    });

    test('sur fond SOMBRE aussi : là, elle s\'éclaircit', () {
      const Color surface = Color(0xFF121212);
      const Color black = Color(0xFF000000);
      expect(contrastRatio(mutedOn(black, surface), surface),
          greaterThanOrEqualTo(kMinUiContrast));
    });

    test('⛔ le défaut d\'origine : deux opacités empilées', () {
      // Ce que faisait la page Optimisation : 45 % par-dessus 35 %.
      final Color old = Color.lerp(
          readableOn(const Color(0xFF00CED1)), kLightSurface, 1 - 0.45 * 0.35)!;
      expect(contrastRatio(old, kLightSurface), lessThan(kMinUiContrast),
          reason: 'si cette composition passait le seuil, le test ne tient '
              'plus rien');
      expect(contrastRatio(mutedOn(const Color(0xFF00CED1), kLightSurface),
              kLightSurface),
          greaterThanOrEqualTo(kMinUiContrast));
    });
  });

  group('§lightTheme — les couleurs FIXES qui servent de TEXTE', () {
    setUp(() {
      ThemeService.debugBrightnessOverride = Brightness.light;
      ThemeService.config.value = AppThemeConfig.matrix;
    });

    test('pastilles de langue et de type : lisibles sur blanc', () {
      // ⚠️ Mesuré sur la planche du thème clair : « VF » cyan valait 1,9:1,
      // « VOSTFR » orange 2,3:1, et une version sans tag de qualité (blanc
      // cassé) 1,1:1 — invisible.
      for (final Color c in <Color>[
        kLangVF,
        kLangVOSTFR,
        kLangLeg,
        kBadgeMovie,
        kBadgeFilmType,
        kQualityUnknown,
      ]) {
        expect(contrastRatio(c, kLightSurface),
            greaterThanOrEqualTo(kMinTextContrast));
      }
    });

    test('⛔ mais le code couleur des QUALITÉS, lui, ne bouge toujours pas',
        () {
      expect(kQuality4K, const Color(0xFFE53935));
      expect(kQualityFHD, const Color(0xFFFFC107));
      expect(kQualityHD, const Color(0xFF00CED1));
      expect(kQualitySD, const Color(0xFF00C832));
    });

    test('en thème SOMBRE, rien n\'a changé : ce sont les valeurs d\'origine',
        () {
      ThemeService.debugBrightnessOverride = Brightness.dark;
      expect(kLangVF, const Color(0xFF00CED1));
      expect(kLangVOSTFR, const Color(0xFFFF8C00));
      expect(kLangLeg, const Color(0xFFB8860B));
      expect(kBadgeMovie, const Color(0xFF00CED1));
      expect(kQualityUnknown, const Color(0xFFF0EAD6));
    });
  });

  group('R16 — barres du système', () {
    test('sur fond clair, des icônes sombres ; sur fond sombre, des claires',
        () {
      final light = aetherOverlayStyle(Brightness.light);
      expect(light.statusBarIconBrightness, Brightness.dark);
      expect(light.systemNavigationBarIconBrightness, Brightness.dark);
      // ⚠️ iOS lit le FOND, Android les ICÔNES : les deux sont opposées.
      expect(light.statusBarBrightness, Brightness.light);

      final dark = aetherOverlayStyle(Brightness.dark);
      expect(dark.statusBarIconBrightness, Brightness.light);
      expect(dark.systemNavigationBarIconBrightness, Brightness.light);
      expect(dark.statusBarBrightness, Brightness.dark);
    });

    test('les deux thèmes le posent sur leur barre de titre', () {
      expect(lightTheme(AppThemeConfig.matrix).appBarTheme.systemOverlayStyle
          ?.statusBarIconBrightness, Brightness.dark);
      expect(darkTheme(AppThemeConfig.matrix).appBarTheme.systemOverlayStyle
          ?.statusBarIconBrightness, Brightness.light);
    });

    test('le titre de la barre repliée reste lisible en clair', () {
      // ⚠️ Le défaut signalé : un titre blanc sur le beige d'une fiche. Le
      // thème clair doit donner un premier plan SOMBRE aux barres de titre.
      final ThemeData light = lightTheme(AppThemeConfig.matrix);
      expect(
          contrastRatio(
              light.appBarTheme.foregroundColor!, light.appBarTheme.backgroundColor!),
          greaterThanOrEqualTo(kMinTextContrast));
    });
  });
}
