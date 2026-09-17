// §btnShape (2026-09-17) — La forme d'un bouton est celle du thème, la même
// que l'anneau de focus TV (`FocusableCard` lit `AetherThemeExtension
// .borderRadius`). Constaté par l'utilisateur sur téléviseur : des boutons
// « pilule » (défaut Material 3) dans un anneau rectangulaire arrondi.
//
// Ce test tombe si l'on retire `shape:` d'un des quatre thèmes de boutons, ou
// si l'on y remet un rayon en dur.
import 'package:aetherStream/core/themes/aether_theme_extension.dart';
import 'package:aetherStream/core/themes/app_theme_config.dart';
import 'package:aetherStream/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BorderRadius? _radiusOf(ButtonStyle? style) {
  final OutlinedBorder? shape = style?.shape?.resolve(<WidgetState>{});
  if (shape is! RoundedRectangleBorder) return null;
  return shape.borderRadius.resolve(TextDirection.ltr);
}

void main() {
  for (final double r in <double>[0, 6, 16]) {
    for (final bool dark in <bool>[true, false]) {
      test('rayon $r, ${dark ? 'sombre' : 'clair'} : les quatre familles de '
          'boutons portent le rayon du thème, comme l\'anneau de focus', () {
        final AppThemeConfig config =
            AppThemeConfig.defaults.copyWith(borderRadius: r);
        final ThemeData theme = dark ? darkTheme(config) : lightTheme(config);
        final BorderRadius expected = BorderRadius.circular(r);

        expect(_radiusOf(theme.filledButtonTheme.style), expected);
        expect(_radiusOf(theme.outlinedButtonTheme.style), expected);
        expect(_radiusOf(theme.textButtonTheme.style), expected);
        expect(_radiusOf(theme.elevatedButtonTheme.style), expected);

        // Même source que l'anneau : l'extension lue par `FocusableCard`.
        final AetherThemeExtension? ext =
            theme.extension<AetherThemeExtension>();
        expect(ext?.borderRadius, r);
      });
    }
  }

  test('le style commun des boutons pleins ne fixe AUCUNE forme : il hérite '
      'de celle du thème', () {
    expect(aetherFilledStyle(const Color(0xFF00FF41)).shape, isNull);
  });
}
