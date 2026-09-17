// Lot 11 — La ligne « Chercher des sous-titres en ligne » de la feuille de
// pistes.
//
// Ce que ces tests tiennent, et pourquoi :
//
// 1. La ligne n'existe QUE si le contenu est identifiable. Sans contexte de
//    recherche (chaîne en direct, titre vide), la promettre serait promettre
//    une recherche qui ne peut rien rendre.
// 2. Elle est EN FIN de section sous-titres. À la télécommande, la première
//    ligne est ce que le bouton OK déclenche : partir sur le réseau ne doit
//    pas être l'action par défaut — même règle que les lignes de mémoire (R43)
//    et inverse de « Désactivés », qui reste en tête (R42).
//
// ⚠️ Ce qui n'est PAS couvert ici : la recherche elle-même (elle demande le
// réseau et une clé) — ses parties pures sont dans `online_subtitles_test.dart`.

import 'dart:async';

import 'package:aetherStream/data/services/online_subtitles_service.dart';
import 'package:aetherStream/data/services/track_preferences_service.dart';
import 'package:aetherStream/feature/player/playback_engine.dart';
import 'package:aetherStream/feature/player/widgets/track_selector_sheet.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const AetherTrack _sousTitreFr =
    AetherTrack(id: '0', title: 'Français', language: 'fr');

/// Moteur fictif réduit à ce que la feuille LIT. `noSuchMethod` couvre le
/// reste du contrat : aucun de ces tests ne joue quoi que ce soit.
class _FauxMoteur implements AetherPlaybackEngine {
  _FauxMoteur({this.subtitleTracks = const []});

  @override
  final List<AetherTrack> subtitleTracks;

  @override
  List<AetherTrack> get audioTracks => const [];

  @override
  AetherTrack? get currentAudioTrack => null;

  @override
  AetherTrack? get currentSubtitleTrack => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _ouvrir(
  WidgetTester tester,
  AetherPlaybackEngine moteur, {
  SubtitleSearchContext? recherche,
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
  unawaited(showTrackSelector(ctx, moteur, onlineSearch: recherche));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final AppLocalizations fr = lookupAppLocalizations(const Locale('fr'));

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TrackPreferencesService.subtitle = null;
    TrackPreferencesService.audio = null;
  });

  testWidgets('la ligne apparaît quand le contenu est identifiable',
      (tester) async {
    await _ouvrir(
      tester,
      _FauxMoteur(subtitleTracks: const [_sousTitreFr]),
      recherche: subtitleSearchContextFor(title: 'Le Martien'),
    );
    expect(find.text(fr.tracksSearchOnline), findsOneWidget);
  });

  testWidgets('sans contexte de recherche, la ligne n\'existe pas',
      (tester) async {
    // Le cas d'une chaîne en direct : rien à faire reconnaître par TMDB.
    await _ouvrir(tester, _FauxMoteur(subtitleTracks: const [_sousTitreFr]));
    expect(find.text(fr.tracksSearchOnline), findsNothing,
        reason: 'promettre une recherche qui ne peut rien rendre');
  });

  testWidgets('elle apparaît MÊME sans aucune piste : c\'est justement là '
      'qu\'elle sert', (tester) async {
    await _ouvrir(
      tester,
      _FauxMoteur(),
      recherche: subtitleSearchContextFor(title: 'Le Martien'),
    );
    expect(find.text(fr.tracksNoSubtitles), findsOneWidget);
    expect(find.text(fr.tracksSearchOnline), findsOneWidget);
  });

  testWidgets(
      'elle est APRÈS les pistes : à la télécommande, OK ne doit pas partir '
      'sur le réseau', (tester) async {
    await _ouvrir(
      tester,
      _FauxMoteur(subtitleTracks: const [_sousTitreFr]),
      recherche: subtitleSearchContextFor(title: 'Le Martien'),
    );
    final double coupure =
        tester.getTopLeft(find.text(fr.tracksDisabled)).dy;
    final double enLigne =
        tester.getTopLeft(find.text(fr.tracksSearchOnline)).dy;
    expect(enLigne, greaterThan(coupure),
        reason: 'R42 garde « Désactivés » en tête ; celle-ci ferme la section');
  });

  testWidgets('elle passe après TOUTES les pistes, pas seulement la coupure',
      (tester) async {
    await _ouvrir(
      tester,
      _FauxMoteur(subtitleTracks: const [
        _sousTitreFr,
        AetherTrack(id: '1', title: 'Anglais', language: 'en'),
      ]),
      recherche: subtitleSearchContextFor(title: 'Le Martien'),
    );
    final double enLigne =
        tester.getTopLeft(find.text(fr.tracksSearchOnline)).dy;
    for (final String piste in const ['Français', 'Anglais']) {
      expect(tester.getTopLeft(find.text(piste)).dy, lessThan(enLigne),
          reason: 'la piste « $piste » doit rester avant la recherche réseau');
    }
  });

  // ⚠️ §tvOptionsBack — que la sortie « Revenir à la vidéo » reste la DERNIÈRE
  // ligne n'est PAS vérifié ici : `BackToVideoRow` ne rend rien hors
  // téléviseur et n'a pas de couture `isTv:` (cf. `confirm_or_undo_test`).
  // Vérifié à la LECTURE : la ligne ajoutée l'est dans la section
  // sous-titres, la sortie ferme la `Column` après elle. À confirmer à la
  // recette sur l'AVD TV.
}
