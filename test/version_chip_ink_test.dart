import 'package:aetherStream/core/themes/light_palette.dart';
import 'package:aetherStream/feature/search/details_page.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// R48 (recette AVD du 2026-09-21) — « FHD · MULTI PremiumV2 » jaune sur jaune :
/// sur la pastille FOCALISÉE à la TV (halo d'accent peint dedans) et sur la
/// pastille CHOISIE au téléphone en thème clair. Le texte se calcule désormais
/// contre le fond réel de la pastille, focus compris.
void main() {
  const Color fhdYellow = Color(0xFFFFC400);
  const Color darkSurface = Color(0xFF121212);
  const Color lightSurface = Color(0xFFFFFFFF);
  const Color amberGlow = Color(0xFFFFB300); // accent façon Phosphore

  Color bgOf(Color q, Color surface, bool selected, Color? glow) {
    Color bg = Color.alphaBlend(
        selected ? q.withAlpha(70) : mutedOn(q, surface).withAlpha(20),
        surface);
    if (glow != null) bg = Color.alphaBlend(glow.withAlpha(128), bg);
    return bg;
  }

  for (final bool selected in [true, false]) {
    for (final surface in [darkSurface, lightSurface]) {
      for (final Color? glow in [null, amberGlow]) {
        test(
            'lisible à 4,5:1 — choisie=$selected, '
            'fond=${surface == darkSurface ? 'sombre' : 'clair'}, '
            'focus=${glow != null}', () {
          final Color ink = versionChipInk(
            quality: fhdYellow,
            surface: surface,
            selected: selected,
            focusGlow: glow,
          );
          expect(contrastRatio(ink, bgOf(fhdYellow, surface, selected, glow)),
              greaterThanOrEqualTo(kMinTextContrast - 0.05));
        });
      }
    }
  }

  test('la teinte de la qualité est gardée (code couleur)', () {
    final Color ink = versionChipInk(
        quality: fhdYellow, surface: lightSurface, selected: true);
    final double hQ = HSLColor.fromColor(fhdYellow).hue;
    final double hI = HSLColor.fromColor(ink).hue;
    expect((hQ - hI).abs(), lessThan(6));
  });

  test('sur fond sombre sans focus, la version choisie garde sa couleur brute',
      () {
    expect(
        versionChipInk(
            quality: fhdYellow, surface: darkSurface, selected: true),
        fhdYellow);
  });
}
