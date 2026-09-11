import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/core/themes/app_theme_config.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/core/themes/light_palette.dart';
import 'package:aetherStream/core/themes/theme_service.dart';
import 'package:aetherStream/core/themes/themes.dart';

/// §lightTheme — Le thème CLAIR doit être LISIBLE.
///
/// Le défaut d'origine (signalé le 2026-09-10) : les couleurs de l'app sont
/// pensées pour du noir, et le thème clair réutilisait les MÊMES valeurs sur
/// fond blanc. Le vert Matrix y tombait à 1,37:1, le texte secondaire à 1,9:1.
///
/// Ce test est le cliquet : il refuse toute couleur de premier plan qui
/// n'atteint pas le seuil, **pour les neuf préréglages** — donc aussi pour ceux
/// qu'on ajoutera. ⚠️ Il ne dit rien du GOÛT ; il dit qu'on peut lire.
void main() {
  // ⚠️ `ThemeService.config` est un singleton PARTAGÉ par toute la suite : le
  // laisser modifié ferait échouer d'autres tests, très loin d'ici.
  tearDown(() {
    ThemeService.debugBrightnessOverride = null;
    ThemeService.config.value = AppThemeConfig.defaults;
  });

  group('contrastRatio — la mesure elle-même', () {
    test('les bornes du WCAG', () {
      expect(contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
          closeTo(21.0, 0.01));
      expect(contrastRatio(const Color(0xFF00FF41), const Color(0xFF00FF41)),
          closeTo(1.0, 0.001));
    });

    test('⚠️ le constat qui a ouvert le lot : le vert Matrix sur blanc', () {
      // Éclatant sur noir, illisible sur blanc — c'est TOUT le problème.
      const Color matrix = Color(0xFF00FF41);
      expect(contrastRatio(matrix, const Color(0xFF000000)), greaterThan(14.0));
      expect(contrastRatio(matrix, kLightSurface), lessThan(1.5));
    });

    test('le gris secondaire d\'avant était sous le seuil, le nouveau non', () {
      expect(contrastRatio(const Color(0xFFB0B0B0), kLightSurface),
          lessThan(kMinTextContrast));
      expect(contrastRatio(kLightTextSecondary, kLightSurface),
          greaterThanOrEqualTo(kMinTextContrast));
      expect(contrastRatio(kLightTextTertiary, kLightSurface),
          greaterThanOrEqualTo(kMinUiContrast));
    });
  });

  group('readableOn — la dérivation', () {
    test('assombrit juste ce qu\'il faut, et pas plus', () {
      final Color derived = readableOn(const Color(0xFF00FF41));
      expect(contrastRatio(derived, kLightSurface),
          greaterThanOrEqualTo(kMinTextContrast));
      // « Juste ce qu'il faut » : on ne noircit pas au passage.
      expect(contrastRatio(derived, kLightSurface), lessThan(9.0));
    });

    test('⚠️ la TEINTE est conservée — un vert reste ce vert', () {
      const Color matrix = Color(0xFF00FF41);
      final HSLColor before = HSLColor.fromColor(matrix);
      final HSLColor after = HSLColor.fromColor(readableOn(matrix));
      expect(after.hue, closeTo(before.hue, 1.0));
      expect(after.saturation, closeTo(before.saturation, 0.05));
    });

    test('une couleur DÉJÀ lisible n\'est pas touchée', () {
      const Color deja = Color(0xFF1A237E); // indigo sombre
      expect(readableOn(deja), deja);
    });

    test('le noir reste le noir (la boucle se termine)', () {
      expect(readableOn(const Color(0xFF000000)), const Color(0xFF000000));
    });
  });

  group('onColorFor — le texte POSÉ sur un aplat', () {
    test('sur le vert Matrix vif, le noir gagne', () {
      expect(onColorFor(const Color(0xFF00FF41)), const Color(0xFF000000));
    });

    test('sur un aplat sombre, le blanc gagne', () {
      expect(onColorFor(const Color(0xFF1A237E)), const Color(0xFFFFFFFF));
    });
  });

  group('⚠️ Les NEUF préréglages, en thème clair', () {
    for (final preset in AppThemeConfig.presets) {
      test('${preset.name} — toutes les couleurs de premier plan sont lisibles',
          () {
        final ThemeData t = lightTheme(preset.config);
        final Map<String, Color> foregrounds = <String, Color>{
          'colorScheme.primary': t.colorScheme.primary,
          'colorScheme.secondary': t.colorScheme.secondary,
          'colorScheme.tertiary': t.colorScheme.tertiary,
          'colorScheme.error': t.colorScheme.error,
          'texte principal': t.textTheme.bodyLarge!.color!,
          'texte secondaire': t.textTheme.bodyMedium!.color!,
        };
        foregrounds.forEach((String nom, Color c) {
          expect(contrastRatio(c, kLightSurface),
              greaterThanOrEqualTo(kMinTextContrast),
              reason: '${preset.name} — « $nom » est illisible sur blanc');
        });
      });

      test('${preset.name} — le texte des boutons pleins reste lisible', () {
        // ⚠️ Le piège du jeton à double emploi : assombrir l'accent pour qu'il
        // se lise sur blanc rendait le texte NOIR illisible sur le bouton.
        final Color bg = preset.config.primaryColor;
        expect(contrastRatio(onColorFor(bg), bg),
            greaterThanOrEqualTo(kMinUiContrast),
            reason: '${preset.name} — texte illisible sur le bouton principal');
      });
    }
  });

  group('⚠️ Les alias sémantiques suivent la luminosité', () {
    test('en SOMBRE, la valeur brute est intacte', () {
      ThemeService.debugBrightnessOverride = Brightness.dark;
      ThemeService.config.value = AppThemeConfig.matrix;
      expect(kAccentPrimary, AppThemeConfig.matrix.primaryColor);
    });

    test('en CLAIR, elle est dérivée et lisible', () {
      ThemeService.debugBrightnessOverride = Brightness.light;
      ThemeService.config.value = AppThemeConfig.matrix;
      expect(kAccentPrimary, isNot(AppThemeConfig.matrix.primaryColor));
      expect(contrastRatio(kAccentPrimary, kLightSurface),
          greaterThanOrEqualTo(kMinTextContrast));
    });

    test('les quatre couleurs d\'état aussi (§themePlus)', () {
      ThemeService.debugBrightnessOverride = Brightness.light;
      ThemeService.config.value = AppThemeConfig.matrix;
      for (final Color c in <Color>[kWarning, kFavorite, kError, kSuccess]) {
        expect(contrastRatio(c, kLightSurface),
            greaterThanOrEqualTo(kMinTextContrast));
      }
    });

    test('⛔ les couleurs de QUALITÉ ne bougent pas — c\'est un code couleur', () {
      ThemeService.debugBrightnessOverride = Brightness.light;
      expect(kQuality4K, const Color(0xFFE53935));
      expect(kQualityFHD, const Color(0xFFFFC107));
    });
  });
}
