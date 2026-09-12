// R32 — « Arrêter la diffusion » doit être atteignable DÈS LA PREMIÈRE FRAME.
//
// Le défaut (constaté le 2026-09-12) : la ligne d'arrêt ne vivait que dans la
// phase `list` du `switch` de la feuille, c'est-à-dire APRÈS le balayage mDNS
// (jusqu'à 4 s, plus longtemps encore si le réseau ne répond pas). Pendant tout
// ce temps, la seule façon d'arrêter la diffusion était l'action « Arrêter » de
// la notification — la feuille « Diffuser sur… », elle, ne proposait qu'un
// spinner.
//
// Ce que ce test tient :
//   1. pendant `searching` (spinner « Recherche des appareils… » à l'écran),
//      la ligne « Arrêter la diffusion » est déjà là ;
//   2. sans diffusion en cours (`connected: null`), elle n'apparaît pas ;
//   3. `CastService.state` est la VÉRITÉ : `connected` figé à l'ouverture ne
//      suffit pas, la ligne disparaît si le service dit qu'il n'y a plus rien.
//
// ⚠️ Jamais de `pumpAndSettle` ici : `initState` lance la vraie découverte
// réseau (`CastService.discover`), qui ne se termine pas dans un test. On pompe
// donc à la main, ce qui est exactement la situation qu'on veut vérifier —
// la feuille est encore en train de chercher.

import 'dart:async';

import 'package:aetherStream/data/services/cast_service.dart';
import 'package:aetherStream/feature/player/cast_policy.dart';
import 'package:aetherStream/feature/player/widgets/cast_sheet.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Un récepteur fictif : `CastDevice` est un modèle pur (aucun canal de
/// plateforme), on peut donc en construire un en test unitaire.
const CastDevice kSalon = CastDevice(
  id: 'salon._googlecast._tcp.local',
  name: 'salon',
  friendlyName: 'Télé du salon',
  host: '192.168.1.42',
  port: 8009,
);

CastState _diffusionEnCours() => const CastState(
      device: kSalon,
      url: 'http://192.168.1.1/film.mkv',
      title: 'Un film',
      live: false,
      status: CastSessionStatus(playerState: 'PLAYING'),
    );

/// Ouvre la feuille et s'arrête à la PREMIÈRE frame utile : la découverte est
/// encore en cours. Deux pompes seulement — l'ouverture, puis l'animation de la
/// feuille modale — jamais `pumpAndSettle`.
Future<void> _ouvrirLaFeuille(
  WidgetTester tester, {
  required CastDevice? connected,
}) async {
  late BuildContext ctx;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (c) {
          ctx = c;
          return const Scaffold(body: SizedBox.expand());
        },
      ),
    ),
  );

  unawaited(showCastSheet(
    ctx,
    // La sonde n'est appelée qu'au choix d'un appareil : jamais ici.
    checkStream: () => Completer<CastEligibility>().future,
    onCast: (_) async {},
    connected: connected,
    onStopCast: connected == null ? null : () async {},
  ));
  await tester.pump(); // route de la feuille poussée
  await tester.pump(const Duration(milliseconds: 400)); // animation d'ouverture
}

void main() {
  final AppLocalizations fr = lookupAppLocalizations(const Locale('fr'));

  setUp(() => CastService.state.value = null);
  tearDown(() => CastService.state.value = null);

  testWidgets(
      'R32 — la ligne d\'arrêt est là pendant le balayage, pas seulement après',
      (tester) async {
    CastService.state.value = _diffusionEnCours();

    await _ouvrirLaFeuille(tester, connected: kSalon);

    // La feuille CHERCHE encore : c'est la phase où l'arrêt manquait.
    expect(find.text(fr.castSheetSearching), findsOneWidget,
        reason: 'la feuille doit encore être en phase de recherche');
    expect(find.text(fr.castSheetStop), findsOneWidget,
        reason: 'R32 — l\'arrêt ne doit plus attendre la fin de la découverte');
    // Et elle désigne bien l'appareil en cours.
    expect(find.text(fr.castSheetStopSub(kSalon.displayName)), findsOneWidget);
  });

  testWidgets('sans diffusion en cours, aucune ligne d\'arrêt',
      (tester) async {
    await _ouvrirLaFeuille(tester, connected: null);

    expect(find.text(fr.castSheetSearching), findsOneWidget);
    expect(find.text(fr.castSheetStop), findsNothing);
  });

  testWidgets(
      '⚠️ c\'est le SERVICE qui décide : sans état vivant, pas de ligne d\'arrêt',
      (tester) async {
    // `connected` est figé à l'ouverture de la feuille ; si la diffusion est
    // morte entre-temps, proposer de l'arrêter serait proposer d'arrêter un
    // fantôme (et le gestionnaire, lui, relancerait la lecture locale).
    CastService.state.value = null;

    await _ouvrirLaFeuille(tester, connected: kSalon);

    expect(find.text(fr.castSheetSearching), findsOneWidget);
    expect(find.text(fr.castSheetStop), findsNothing);
  });
}
