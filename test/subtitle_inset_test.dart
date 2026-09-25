import 'package:better_native_video_player/better_native_video_player.dart'
    show
        NativeVideoPlayerSubtitleStyle,
        kSubtitleMaxLiftFraction,
        subtitleLiftInBox;
// ignore: implementation_imports
import 'package:better_native_video_player/src/subtitles/subtitle_overlay.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/feature/player/subtitle_inset.dart';

/// R50 — Le sous-titre de la vidéo se dessinait sur la barre de lecture
/// (recette AVD TV du 2026-09-22). Deux décisions pures :
///   - QUAND remonter, et de combien de bas d'écran (`subtitleBottomInsetFor`,
///     côté app) ;
///   - de combien remonter DANS le cadre de l'image (`subtitleLiftInBox`,
///     paquet vendoré, patch 28 — la même règle que le natif).
/// Plus la surcouche des sous-titres « sidecar » (sous-titres en ligne),
/// dessinée par Flutter, qui doit suivre la même marge.
void main() {
  group('subtitleBottomInsetFor', () {
    test('contrôles à l\'écran : le bloc bas mesuré + l\'écart', () {
      expect(
        subtitleBottomInsetFor(
            controlsOnScreen: true, locked: false, bottomBlockHeight: 140),
        140 + kSubtitleControlsGap,
      );
    });

    test('contrôles masqués (ou PiP, ou diffusion) : à leur place', () {
      expect(
        subtitleBottomInsetFor(
            controlsOnScreen: false, locked: false, bottomBlockHeight: 140),
        0,
      );
    });

    test('verrou : seul le cadenas est affiché, en haut → à leur place', () {
      expect(
        subtitleBottomInsetFor(
            controlsOnScreen: true, locked: true, bottomBlockHeight: 140),
        0,
      );
    });

    test('mesure absente ou aberrante : rien', () {
      for (final h in [0.0, -5.0, double.nan, double.infinity]) {
        expect(
          subtitleBottomInsetFor(
              controlsOnScreen: true, locked: false, bottomBlockHeight: h),
          0,
          reason: 'hauteur $h',
        );
      }
    });
  });

  group('subtitleLiftInBox', () {
    test('cadre plein écran (16:9 sur 16:9) : toute la marge', () {
      expect(
          subtitleLiftInBox(inset: 148, gapBelowBox: 0, boxHeight: 540), 148);
    });

    test('film 2,39:1 : les bandes noires absorbent une partie', () {
      // 960×540, cadre de 401,7 de haut → 69,2 de bande sous l'image.
      const double box = 960 / 2.39;
      const double gap = (540 - box) / 2;
      expect(subtitleLiftInBox(inset: 148, gapBelowBox: gap, boxHeight: box),
          closeTo(148 - gap, 1e-9));
    });

    test('bandes plus hautes que la barre : on ne bouge pas', () {
      expect(
          subtitleLiftInBox(inset: 60, gapBelowBox: 69, boxHeight: 401), 0);
    });

    test('format « zoom » (cadre qui déborde) : plus que la marge', () {
      expect(
          subtitleLiftInBox(inset: 100, gapBelowBox: -40, boxHeight: 700), 140);
    });

    test('borne : jamais plus de la moitié du cadre (fenêtre PiP)', () {
      expect(subtitleLiftInBox(inset: 300, gapBelowBox: 0, boxHeight: 200),
          200 * kSubtitleMaxLiftFraction);
    });

    test('sans marge ou sans cadre : rien', () {
      expect(subtitleLiftInBox(inset: 0, gapBelowBox: 0, boxHeight: 540), 0);
      expect(subtitleLiftInBox(inset: 148, gapBelowBox: 0, boxHeight: 0), 0);
    });
  });

  group('surcouche sidecar (patch 28)', () {
    Future<double> cueBottom(
      WidgetTester tester, {
      required ValueNotifier<double> inset,
      double? aspect,
    }) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 960,
              height: 540,
              child: Stack(
                children: [
                  SubtitleOverlay(
                    cueLines: ValueNotifier<List<String>>(['Réplique']),
                    style: const NativeVideoPlayerSubtitleStyle(),
                    videoAspectRatio: aspect,
                    bottomInset: inset,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getBottomLeft(find.text('Réplique').first).dy;
    }

    testWidgets('16:9 plein cadre : la réplique remonte de toute la marge',
        (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final inset = ValueNotifier<double>(0);
      final double before = await cueBottom(tester, inset: inset);
      inset.value = 148;
      await tester.pumpAndSettle();
      final double after = tester.getBottomLeft(find.text('Réplique').first).dy;
      expect(before - after, closeTo(148, 0.5));
      // Contrôles masqués : elle redescend à sa place.
      inset.value = 0;
      await tester.pumpAndSettle();
      expect(tester.getBottomLeft(find.text('Réplique').first).dy,
          closeTo(before, 0.5));
    });

    testWidgets('2,39:1 : seule la part qui mord sur l\'image compte',
        (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final inset = ValueNotifier<double>(0);
      final double before = await cueBottom(tester, inset: inset, aspect: 2.39);
      inset.value = 148;
      await tester.pumpAndSettle();
      final double after = tester.getBottomLeft(find.text('Réplique').first).dy;
      const double gap = (540 - 960 / 2.39) / 2;
      expect(before - after, closeTo(148 - gap, 0.5));
    });
  });
}
