// §playerPanel — L'encart des stats vidéo ne recouvre jamais le bloc bas des
// contrôles.
//
// Le défaut (recette téléphone du 2026-09-22, AVD paysage ~915×411 dp) :
// « Infos vidéo » affiché, les 13 lignes de l'encart (~250 dp) descendaient
// jusqu'en bas de l'écran et masquaient le bouton Audio de la rangée
// d'options. L'encart est désormais borné entre la barre du haut et le bloc
// bas, tous deux MESURÉS par `PlayerControls`, et il tait ses dernières
// lignes plutôt que de les couper à mi-hauteur.
//
// Ce que ces tests tiennent : la borne calculée ; le bas de l'encart ne
// franchit jamais `bottomInset` ; les lignes montrées sont ENTIÈRES (chacune
// tient dans le cadre) ; les lignes tues sont les DERNIÈRES (elles sortent de
// l'arbre de sémantique, qui ne voit que ce qui est peint) ; contrôles
// cachés, tout revient.
//
// ⚠️ Ce qui n'est PAS couvert : la mesure elle-même (`_MeasureHeight` dans
// `PlayerControls`) et l'ordre de peinture dans le `Stack` du lecteur — ils
// demandent la page entière et un moteur. À la recette.

import 'package:aetherStream/feature/player/playback_engine.dart';
import 'package:aetherStream/feature/player/video_stats.dart';
import 'package:aetherStream/feature/player/widgets/video_stats_overlay.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// L'instantané RELEVÉ sur l'AVD pendant la recette : 13 lignes.
const VideoStatsSnapshot _releve = VideoStatsSnapshot(
  width: 1280,
  height: 720,
  hwdec: 'c2.goldfish.h264.decoder',
  codec: 'video/avc',
  decoder: 'c2.goldfish.h264.decoder',
  vo: 'SurfaceView',
  hdr: false,
  renderedFps: 25.2,
  networkBitrate: 6100000,
  bufferAhead: Duration(milliseconds: 54200),
  bytesTransferred: 2 * 1024 * 1024,
  audioCodec: 'audio/mp4a-latm',
  audioChannels: 1,
  audioSampleRate: 44100,
  stalls: 1,
  startupMs: 4000,
);

/// Moteur fictif réduit à ce que l'encart LIT.
class _FauxMoteur implements AetherPlaybackEngine {
  @override
  Future<VideoStatsSnapshot> readStats() async => _releve;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// L'écran du téléphone de la recette, en dp.
const Size _ecran = Size(915, 411);

/// Les libellés de ce relevé, dans l'ORDRE de l'encart (13 lignes, comme sur
/// la capture de la recette).
List<String> ordre(AppLocalizations fr) => [
      fr.statsDecoding,
      fr.statsOutput,
      fr.statsCodec,
      fr.statsResolution,
      fr.statsAnnouncedLabel,
      fr.statsHdr,
      fr.statsRendered,
      fr.statsNetwork,
      fr.statsBuffer,
      fr.statsTransferred,
      fr.statsAudio,
      fr.statsStalls,
      fr.statsStartup,
    ];

void main() {
  final AppLocalizations fr = lookupAppLocalizations(const Locale('fr'));

  group('videoStatsMaxHeight', () {
    test('la place entre la barre du haut et le bloc bas', () {
      expect(
        videoStatsMaxHeight(
            screenHeight: 411, topInset: 82, bottomInset: 148),
        181,
      );
    });

    test('jamais négative (fenêtre minuscule, PiP)', () {
      expect(
        videoStatsMaxHeight(
            screenHeight: 120, topInset: 82, bottomInset: 148),
        0,
      );
    });
  });

  group('VideoStatsOverlay — borné au-dessus du bloc bas', () {
    /// Active tant que l'encart est monté ; rendue par [demonter] (le test
    /// exige qu'elle le soit AVANT sa fin, un `addTearDown` passe trop tard).
    SemanticsHandle? semantics;

    /// Monte l'encart seul, sur l'écran de la recette, sémantique active :
    /// une ligne tue n'y figure pas (seules les lignes peintes y entrent).
    Future<void> monter(
      WidgetTester tester, {
      required double top,
      required double bottom,
      Size ecran = _ecran,
      double texte = 1,
    }) async {
      semantics = tester.ensureSemantics();
      tester.view.physicalSize = ecran;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // TV : un texte plus grand (le plancher `TvSmallTextScaler`,
          // approché ici par un facteur uniforme).
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(texte)),
            child: child!,
          ),
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              fit: StackFit.expand,
              children: [
                VideoStatsOverlay(
                  player: _FauxMoteur(),
                  // La liste de la recette annonçait du FHD (servi : 720p).
                  announcedQuality: 'FHD',
                  topInset: top,
                  bottomInset: bottom,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(); // la première lecture des stats
      await tester.pump(const Duration(milliseconds: 250)); // AnimatedPositioned
    }

    /// Le cadre de l'encart (fond noir + bordure).
    Rect cadre(WidgetTester tester) => tester.getRect(find
        .descendant(
          of: find.byType(VideoStatsOverlay),
          matching: find.byType(Container),
        )
        .first);

    Future<void> demonter(WidgetTester tester) async {
      // Arrête le minuteur de 1 Hz de l'encart.
      await tester.pumpWidget(const SizedBox.shrink());
      semantics?.dispose();
      semantics = null;
    }

    testWidgets(
        'contrôles CACHÉS : toute la hauteur, les 13 lignes (le relevé tient)',
        (tester) async {
      await monter(tester, top: 12, bottom: 12);

      expect(tester.takeException(), isNull);
      for (final l in ordre(fr)) {
        expect(find.bySemanticsLabel(l), findsOneWidget,
            reason: 'contrôles cachés, la ligne « $l » doit être là');
      }
      expect(cadre(tester).bottom, lessThanOrEqualTo(_ecran.height - 12));

      await demonter(tester);
    });

    /// Contrôles affichés : l'encart s'arrête au-dessus du bloc bas, sur des
    /// lignes ENTIÈRES, et ce sont les dernières qui se taisent. Rend le
    /// nombre de lignes montrées.
    Future<int> verifierBorne(
      WidgetTester tester, {
      required Size ecran,
      required double top,
      required double bottom,
      double texte = 1,
    }) async {
      await monter(tester,
          top: top, bottom: bottom, ecran: ecran, texte: texte);
      expect(tester.takeException(), isNull,
          reason: 'aucun débordement : les lignes en trop sont tues');

      final Rect r = cadre(tester);
      expect(r.top, top);
      expect(r.bottom, lessThanOrEqualTo(ecran.height - bottom),
          reason: 'le bloc bas des contrôles (la rangée) reste découvert');

      final List<String> montrees = [
        for (final l in ordre(fr))
          if (find.bySemanticsLabel(l).evaluate().isNotEmpty) l,
      ];
      expect(montrees, isNotEmpty);
      // L'ordre de lecture est tenu : les lignes montrées sont les PREMIÈRES,
      // ce sont les dernières qui se taisent.
      expect(montrees, ordre(fr).take(montrees.length).toList());
      // Lignes ENTIÈRES : chaque ligne montrée tient dans le cadre (padding
      // du bas compris), aucune n'est coupée à mi-hauteur.
      for (final l in montrees) {
        expect(tester.getRect(find.text(l)).bottom,
            lessThanOrEqualTo(r.bottom - 9 + 0.01),
            reason: 'la ligne « $l » est coupée');
      }

      await demonter(tester);
      return montrees.length;
    }

    testWidgets(
        "téléphone, contrôles AFFICHÉS : l'encart s'arrête au-dessus du bloc "
        'bas, sur des lignes ENTIÈRES, et ce sont les dernières qui se taisent',
        (tester) async {
      // Les mesures de la recette : barre du haut ~82, bloc bas ~140 (+ 8).
      final int n = await verifierBorne(tester,
          ecran: _ecran, top: 82, bottom: 148);
      expect(n, lessThan(ordre(fr).length),
          reason: 'le relevé ne tient pas en entier dans ~180 dp');
    });

    testWidgets(
        'téléviseur (960×540 dp, texte agrandi), contrôles AFFICHÉS : même '
        'règle', (tester) async {
      // ⚠️ Hauteurs SUPPOSÉES (barre du haut, bloc bas + 8) : la TV n'a pas
      // été relevée. La règle, elle, vaut pour toutes les valeurs.
      await verifierBorne(tester,
          ecran: const Size(960, 540), top: 100, bottom: 178, texte: 1.3);
    });
  });
}
