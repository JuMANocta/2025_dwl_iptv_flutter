// §playerPanel — Le bloc bas des contrôles : la barre du replay AU-DESSUS de
// la rangée d'options, et une mesure qui les compte toutes les deux.
//
// Le défaut : la barre du replay (timeshift) était posée par le lecteur à
// 90 dp du bas, en dur. Avec la rangée d'options, le bloc bas en fait ~140 au
// téléphone : elle l'aurait chevauchée. Elle vit désormais dans le bloc bas
// (`PlayerControls.replayBar`), et la hauteur rendue par `onBottomBarHeight`
// — celle qui borne l'encart des stats vidéo — la compte.
//
// ⚠️ Ce qui n'est PAS couvert : `PlayerReplayBar` elle-même (remplacée ici par
// une boîte de taille connue) et le lecteur entier. À la recette, sur un
// replay.

import 'package:aetherStream/feature/player/playback_engine.dart';
import 'package:aetherStream/feature/player/widgets/player_controls.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Moteur fictif réduit à ce que les contrôles LISENT : des flux muets.
class _FauxMoteur implements AetherPlaybackEngine {
  @override
  Stream<bool> get playingStream => const Stream<bool>.empty();

  @override
  Stream<bool> get bufferingStream => const Stream<bool>.empty();

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();

  @override
  Stream<Duration> get durationStream => const Stream<Duration>.empty();

  @override
  Stream<Duration> get bufferStream => const Stream<Duration>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const Key _rangee = ValueKey<String>('rangee');
const Key _replay = ValueKey<String>('replay');

/// L'écran du téléphone de la recette, en dp.
const Size _ecran = Size(915, 411);

void main() {
  /// Monte les contrôles, affichés, et rend la hauteur MESURÉE du bloc bas.
  Future<double?> monter(WidgetTester tester, {required bool replay}) async {
    tester.view.physicalSize = _ecran;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    double? mesure;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          backgroundColor: Colors.black,
          body: PlayerControls(
            player: _FauxMoteur(),
            title: 'Blade Runner 2049',
            visible: true,
            onBack: () {},
            onInteraction: () {},
            onBottomBarHeight: (h) => mesure = h,
            optionBar: const SizedBox(key: _rangee, width: 600, height: 52),
            replayBar: replay
                ? const SizedBox(key: _replay, width: 600, height: 34)
                : null,
          ),
        ),
      ),
    );
    await tester.pump(); // le rappel de mesure part après la mise en page
    return mesure;
  }

  testWidgets('le replay est AU-DESSUS de la rangée, jamais dessous',
      (tester) async {
    await monter(tester, replay: true);

    final Rect replay = tester.getRect(find.byKey(_replay));
    final Rect rangee = tester.getRect(find.byKey(_rangee));
    expect(replay.bottom, lessThanOrEqualTo(rangee.top),
        reason: 'à 90 dp du bas en dur, il chevauchait la rangée');
  });

  testWidgets(
      'la mesure du bloc bas COMPTE le replay : l\'encart des stats '
      's\'arrête au-dessus de lui aussi', (tester) async {
    final double? sans = await monter(tester, replay: false);
    expect(sans, isNotNull, reason: 'le bloc bas est mesuré');
    expect(sans!, greaterThanOrEqualTo(_ecran.height - tester.getRect(find.byKey(_rangee)).top),
        reason: 'la mesure englobe la rangée');

    final double? avec = await monter(tester, replay: true);
    expect(avec, isNotNull);
    expect(avec!,
        greaterThanOrEqualTo(_ecran.height - tester.getRect(find.byKey(_replay)).top),
        reason: 'la mesure englobe le replay');
    expect(avec - sans, greaterThanOrEqualTo(34),
        reason: 'le replay ajoute au moins sa hauteur au bloc bas');
  });
}
