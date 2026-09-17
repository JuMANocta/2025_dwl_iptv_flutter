// §detailsMore (b) — recette AVD TV du 2026-09-17 : l'indice n'apparaissait
// jamais, la page étant déjà défilée de ~90 points à l'ouverture (focus d'entrée).
import 'package:aetherStream/feature/search/details_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ouverture sur TV, page déjà défilée de 90 points : indice visible', () {
    expect(
        scrollHintVisibleFor(pixels: 90, baseline: 90, extentAfter: 800), isTrue);
  });
  test('la personne descend : l\'indice s\'efface', () {
    expect(scrollHintVisibleFor(pixels: 140, baseline: 90, extentAfter: 750),
        isFalse);
  });
  test('rien dessous : jamais d\'indice', () {
    expect(
        scrollHintVisibleFor(pixels: 0, baseline: 0, extentAfter: 10), isFalse);
  });
}
