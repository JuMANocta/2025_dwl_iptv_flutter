// §heroHand — Le hero de l'accueil tient comme une main de cartes sur grand
// écran : chaque carte tourne autour d'un pivot loin sous les cartes, et la
// main couvre ~90 % de la largeur. Sur téléphone en portrait (et hors profil
// Complet), l'éventail historique doit rester au pixel près.
import 'dart:math' as math;

import 'package:aetherStream/feature/home/home_page.dart';
import 'package:flutter_test/flutter_test.dart';

/// Formules de l'éventail AVANT §heroHand (`_buildFannedCard`, 1.20.0+156).
({double x, double y, double angle, double scale, double opacity}) _legacy(
    double delta, double w) {
  final a = delta.abs();
  return (
    x: delta * (w * 0.22),
    y: math.min(a * 14.0, 42.0),
    angle: delta * 0.08,
    scale: math.max(0.55, 1.0 - a * 0.07),
    opacity: math.max(0.0, 1.0 - a * 0.32).clamp(0.0, 1.0),
  );
}

/// Écrans mesurés : AVD TV 1920×1080 moins le rail (~180 px), tablette en
/// paysage, téléphone en paysage.
const _screens = <({String name, double width, double cardW})>[
  (name: 'TV 1080p', width: 1740 - 16, cardW: 1080 * 0.58 / 1.45),
  (name: 'tablette', width: 1280 - 16, cardW: 800 * 0.42 / 1.45),
  (name: 'téléphone paysage', width: 800 - 16, cardW: 360 * 0.42 / 1.45),
];

HeroHandGeometry _wide(double width, double cardW, {int cards = 15}) =>
    HeroHandGeometry.fit(
      availableWidth: width,
      cardWidth: cardW,
      cardHeight: cardW * 1.45,
      wide: true,
      cardCount: cards,
    );

void main() {
  test('portrait : éventail historique inchangé, valeur par valeur', () {
    const w = 180.0;
    final g = HeroHandGeometry.fit(
      availableWidth: 400,
      cardWidth: w,
      cardHeight: w * 1.45,
      wide: false,
      cardCount: 15,
    );
    expect(g.wide, isFalse);
    expect(g.spacing, w * 0.22);
    for (var d = -3.0; d <= 3.0; d += 0.25) {
      final p = g.pose(d);
      final l = _legacy(d, w);
      expect(p.x, closeTo(l.x, 1e-9), reason: 'x @ $d');
      expect(p.y, closeTo(l.y, 1e-9), reason: 'y @ $d');
      expect(p.angle, closeTo(l.angle, 1e-9), reason: 'angle @ $d');
      expect(p.scale, closeTo(l.scale, 1e-9), reason: 'scale @ $d');
      expect(p.opacity, closeTo(l.opacity, 1e-9), reason: 'opacity @ $d');
    }
    // §heroPaint — le rang 3 (4 %) reste écarté, le rang 2 (36 %) construit.
    expect(g.opacity(3) < HeroHandGeometry.minVisibleOpacity, isTrue);
    expect(g.opacity(2) >= HeroHandGeometry.minVisibleOpacity, isTrue);
  });

  for (final s in _screens) {
    group('main élargie — ${s.name}', () {
      final g = _wide(s.width, s.cardW);

      test('carte active au centre, pleine, droite', () {
        expect(g.wide, isTrue);
        final p = g.pose(0);
        expect(p.x, 0);
        expect(p.y, 0);
        expect(p.angle, 0);
        expect(p.scale, 1);
        expect(p.opacity, 1);
      });

      test('symétrie gauche / droite', () {
        for (var d = 0.25; d <= g.maxVisibleDelta; d += 0.25) {
          final r = g.pose(d);
          final l = g.pose(-d);
          expect(l.x, closeTo(-r.x, 1e-9));
          expect(l.y, closeTo(r.y, 1e-9));
          expect(l.angle, closeTo(-r.angle, 1e-9));
          expect(l.scale, r.scale);
          expect(l.opacity, r.opacity);
        }
      });

      test('3 à 4 cartes tenues par côté', () {
        expect(g.sideCount, inInclusiveRange(3, 4));
        expect(g.opacity(g.sideCount.toDouble()) >=
            HeroHandGeometry.minVisibleOpacity, isTrue);
      });

      test('la main couvre ≥ 85 % de la largeur au repos, jamais plus de 100 %',
          () {
        final covered = 2 * g.outerEdge(g.sideCount.toDouble());
        expect(covered, greaterThanOrEqualTo(0.85 * s.width),
            reason: 'couvert ${covered.round()} / ${s.width.round()} px');
        // Toute carte construite, même en pleine rotation, reste dans l'écran.
        for (var d = 0.0; d <= g.maxVisibleDelta; d += 0.05) {
          expect(2 * g.outerEdge(d), lessThanOrEqualTo(s.width + 1e-6),
              reason: 'déborde @ $d');
        }
      });

      test('un arc, pas une pile : les bords descendent en courbe', () {
        // Pied sur le cercle : la descente croît plus vite que le rang.
        final y1 = g.pose(1).y, y2 = g.pose(2).y, y3 = g.pose(3).y;
        expect(y1 > 0, isTrue);
        expect(y2 - y1 > y1, isTrue);
        expect(y3 - y2 > y2 - y1, isTrue);
        // Pied posé à la distance R du pivot.
        for (var d = 0.5; d <= 4; d += 0.5) {
          final p = g.pose(d);
          final dist = math.sqrt(p.x * p.x + math.pow(g.radius - p.y, 2));
          expect(dist, closeTo(g.radius, 1e-6));
        }
      });

      test('opacité et échelle décroissent avec |delta|', () {
        var prevO = 2.0, prevS = 2.0;
        for (var d = 0.0; d <= g.maxVisibleDelta + 0.5; d += 0.1) {
          final p = g.pose(d);
          expect(p.opacity <= prevO, isTrue, reason: 'opacité @ $d');
          expect(p.scale <= prevS, isTrue, reason: 'échelle @ $d');
          prevO = p.opacity;
          prevS = p.scale;
        }
        // Au-delà du dernier rang construit, plus rien ne se voit.
        expect(g.opacity(g.maxVisibleDelta + 0.01),
            lessThan(HeroHandGeometry.minVisibleOpacity));
      });

      test('le glissé tient la carte : spacing = écart réel à l\'écran', () {
        expect(g.spacing, closeTo(g.pose(1).x, 1e-9));
        expect(g.spacing, lessThan(s.cardW), reason: 'les cartes se chevauchent');
      });

      test('descente bornée (marge basse du conteneur)', () {
        // La marge basse passe de 52 px à `max(52, maxDrop + 12)` : ce que le
        // hero gagne en hauteur reste sous 10 % de la hauteur d'une carte.
        expect(g.maxDrop, greaterThan(0));
        final grown = math.max(52.0, g.maxDrop + 12) - 52;
        expect(grown, lessThanOrEqualTo(0.10 * s.cardW * 1.45),
            reason: '+${grown.round()} px');
      });
    });
  }

  test('peu de cartes : pas plus de côtés que de cartes', () {
    final g = _wide(1724, 432, cards: 5);
    expect(g.sideCount, 2);
    expect(_wide(1724, 432, cards: 1).wide, isFalse);
  });
}
