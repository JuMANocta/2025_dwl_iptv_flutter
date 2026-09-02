import 'dart:ui';

import 'package:aetherStream/core/diagnostics/jank_meter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// §jankMeter — L'instrument qui transforme « ça saccade » en un chiffre.
///
/// Ce qu'on verrouille ici, c'est surtout le piège de la sonde de défilement :
/// les notifications remontent l'arbre, donc une sonde posée sur la liste
/// verticale se déclencherait aussi pour chaque carrousel horizontal imbriqué.

/// Une frame dont `totalSpan` vaut exactement [totalUs].
///
/// `totalSpan` = `rasterFinish - vsyncStart` : c'est ce que l'œil subit, et non
/// la somme build+raster (qui ignore l'attente entre les deux).
FrameTiming _frameOfTotal(int totalUs) {
  final int build = (totalUs * 0.4).round();
  return FrameTiming(
    vsyncStart: 0,
    buildStart: 0,
    buildFinish: build,
    rasterStart: build,
    rasterFinish: totalUs,
    rasterFinishWallTime: totalUs,
  );
}

void main() {
  setUp(() {
    JankMeter.installForTest();
    JankMeter.resetForTest();
  });

  // Les fenêtres de mesure s'appuient sur des minuteries (délai de garde et
  // purge) : les laisser pendantes fait échouer le test suivant.
  tearDown(JankMeter.resetForTest);

  group('§jankMeter — comptage', () {
    test('sans fenêtre ouverte, les frames sont ignorées', () {
      JankMeter.feedForTest([_frameOfTotal(50000)]);
      expect(JankMeter.currentForTest, isNull);
    });

    test('une frame sous le budget n\'est pas une saccade', () {
      JankMeter.beginSpan('test');
      // Budget de repli en test = 16 667 µs (aucune vue attachée).
      JankMeter.feedForTest([_frameOfTotal(10000)]);

      final c = JankMeter.currentForTest!;
      expect(c.frames, 1);
      expect(c.janky, 0);
      expect(c.severe, 0);
    });

    test('une frame au-delà du budget compte comme saccade', () {
      JankMeter.beginSpan('test');
      JankMeter.feedForTest([_frameOfTotal(25000)]);

      final c = JankMeter.currentForTest!;
      expect(c.janky, 1);
      // 25 ms < 3 budgets (50 ms) → dépassement marginal, pas un à-coup franc.
      expect(c.severe, 0);
    });

    test('au-delà de trois budgets, l\'à-coup est FRANC', () {
      JankMeter.beginSpan('test');
      JankMeter.feedForTest([_frameOfTotal(120000)]);

      final c = JankMeter.currentForTest!;
      expect(c.janky, 1);
      expect(c.severe, 1,
          reason: 'une frame à 120 ms se voit — elle ne doit pas être noyée '
              'parmi les dépassements marginaux');
    });

    test('ouvrir une seconde fenêtre ABANDONNE la première', () {
      JankMeter.beginSpan('première');
      JankMeter.feedForTest([_frameOfTotal(50000), _frameOfTotal(50000)]);
      expect(JankMeter.currentForTest!.frames, 2);

      // Mélanger deux actions donnerait un chiffre qui ne décrit ni l'une ni
      // l'autre : la seconde repart de zéro.
      JankMeter.beginSpan('seconde');
      expect(JankMeter.currentForTest!.frames, 0);
    });

    test('le budget se déduit de l\'écran, il n\'est pas codé en dur', () {
      // Sans vue attachée, repli documenté à 60 Hz.
      expect(JankMeter.frameBudget.inMicroseconds, 16667);
    });

    test('un build debug se déclare comme non exploitable', () {
      // Les tests tournent en debug : c'est précisément le cas où un chiffre
      // ne doit pas être cité sans réserve.
      expect(JankMeter.isTrustworthy, isFalse);
    });
  });

  group('§jankMeter — JankScrollProbe', () {
    testWidgets('un défilement ouvre puis ferme une fenêtre', (tester) async {
      JankMeter.resetForTest();
      await tester.pumpWidget(
        MaterialApp(
          home: JankScrollProbe(
            label: 'liste verticale',
            child: ListView(
              children: [
                for (int i = 0; i < 40; i++) SizedBox(height: 60, child: Text('$i')),
              ],
            ),
          ),
        ),
      );

      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();

      // Pendant le geste ET pendant la purge, la fenêtre reste ouverte : les
      // dernières frames d'un défilement sont les plus lourdes.
      expect(JankMeter.currentForTest, isNotNull);

      // Une fois la purge écoulée, la mesure est publiée et refermée.
      await tester.pump(const Duration(milliseconds: 600));
      expect(JankMeter.currentForTest, isNull);
    });

    testWidgets('un second défilement ne PERD pas la mesure du premier',
        (tester) async {
      JankMeter.resetForTest();
      await tester.pumpWidget(
        MaterialApp(
          home: JankScrollProbe(
            label: 'liste',
            child: ListView(
              children: [
                for (int i = 0; i < 60; i++)
                  SizedBox(height: 60, child: Text('$i')),
              ],
            ),
          ),
        ),
      );

      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pump();
      JankMeter.feedForTest([_frameOfTotal(90000)]);
      expect(JankMeter.currentForTest!.severe, 1);

      // Second geste AVANT la fin de la purge — le cas normal quand on
      // parcourt l'accueil. La première mesure doit être publiée, pas jetée,
      // et la seconde repart de zéro.
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pump();
      expect(JankMeter.currentForTest, isNotNull);
      expect(JankMeter.currentForTest!.severe, 0);

      // Vider la purge DANS le test : le contrôle des minuteries pendantes
      // s'exécute avant `tearDown`.
      await tester.pump(const Duration(milliseconds: 600));
    });

    testWidgets(
        '⚠️ un carrousel IMBRIQUÉ ne déclenche pas la sonde du parent',
        (tester) async {
      JankMeter.resetForTest();
      await tester.pumpWidget(
        MaterialApp(
          home: JankScrollProbe(
            label: 'liste verticale',
            child: ListView(
              children: [
                SizedBox(
                  height: 120,
                  child: ListView(
                    key: const Key('carrousel'),
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (int i = 0; i < 40; i++)
                        SizedBox(width: 100, child: Text('h$i')),
                    ],
                  ),
                ),
                for (int i = 0; i < 20; i++)
                  SizedBox(height: 60, child: Text('v$i')),
              ],
            ),
          ),
        ),
      );

      await tester.drag(find.byKey(const Key('carrousel')), const Offset(-300, 0));
      await tester.pump();

      // Sans le filtre `depth == 0`, la sonde du parent se serait ouverte ici
      // et aurait attribué à la liste verticale les frames du carrousel.
      expect(JankMeter.currentForTest, isNull,
          reason: 'les notifications de défilement remontent l\'arbre : le '
              'parent ne doit mesurer QUE son propre défilement');
    });

    testWidgets('la sonde ne consomme pas la notification', (tester) async {
      JankMeter.resetForTest();
      int seenByAncestor = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationListener<ScrollNotification>(
            onNotification: (_) {
              seenByAncestor++;
              return false;
            },
            child: JankScrollProbe(
              label: 'liste',
              child: ListView(
                children: [
                  for (int i = 0; i < 40; i++)
                    SizedBox(height: 60, child: Text('$i')),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pump();

      // Renvoyer `true` couperait la remontée et casserait tout ce qui écoute
      // plus haut (barres qui se masquent, chargement paresseux…).
      expect(seenByAncestor, greaterThan(0));

      await tester.pump(const Duration(milliseconds: 600));
    });
  });
}
