// R42 — Les sous-titres doivent pouvoir être COUPÉS.
//
// Le défaut (signalé par l'utilisateur, mesuré sur le S25 le 2026-09-13, Heroes
// S03E15) : ExoPlayer sélectionne de lui-même la piste marquée FORCED, et la
// feuille de pistes n'offrait aucun moyen de la couper. La ligne « Désactivés »
// n'existait que si une piste portait l'identifiant `'no'` — vestige mpv
// qu'aucun moteur Media3 ne fabrique — et son tap passait par
// `setSubtitleTrack('no')`, que le moteur refuse faute de savoir le parser.
//
// ⚠️ CE QUE CES TESTS NE COUVRENT PAS, ET POURQUOI. La moitié « succès » du
// moteur est hors de portée d'un test unitaire : `initialize()` attend un
// completer que seule la création d'une VUE de plateforme déclenche
// (`native_video_player_controller.dart:120-161`), et tant qu'aucune vue
// n'existe le contrôleur n'a pas de canal — `_methodChannel?.` avale l'appel.
// Un `open()` en test ne rendrait donc jamais la main. Sont hors couverture :
// l'ordre `_applySubPreference` avant `loadUrl`, la pose de `'no'` après une
// coupure réussie, et sa levée par `setSubtitleTrack`. Ce qui EST couvert côté
// moteur : le refus quand aucun lecteur n'est prêt, et le fait qu'un refus
// n'écrit RIEN. Le reste se recette sur appareil.

import 'dart:async';

import 'package:aetherStream/data/services/track_preferences_service.dart';
import 'package:aetherStream/feature/player/media3_engine.dart';
import 'package:aetherStream/feature/player/playback_engine.dart';
import 'package:aetherStream/feature/player/widgets/track_selector_sheet.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:aetherStream/widgets/tv/focusable_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Les trois pistes RELEVÉES sur l'appareil : une FORCED que le moteur a
/// sélectionnée seul, et deux autres. ⚠️ Aucune ne porte `'no'` — c'est
/// exactement la situation où la ligne de coupure était introuvable.
const AetherTrack kForcee =
    AetherTrack(id: '0', title: 'Français (Forced)', language: 'fr');
const AetherTrack kFrancais =
    AetherTrack(id: '1', title: 'Français', language: 'fr');
const AetherTrack kAnglais =
    AetherTrack(id: '2', title: 'Anglais (SDH)', language: 'en');

/// Moteur fictif tenu au MÊME contrat que `Media3Engine` : il porte la coupure
/// entière (session + mémoire) et rend `false` quand elle échoue. Un faux qui
/// mentirait sur ce contrat rendrait les tests de la feuille décoratifs.
class _FauxMoteur implements AetherPlaybackEngine {
  _FauxMoteur({
    this.subtitleTracks = const [],
    this.currentSubtitleTrack,
    this.coupureReussit = true,
  });

  @override
  final List<AetherTrack> subtitleTracks;

  @override
  AetherTrack? currentSubtitleTrack;

  @override
  List<AetherTrack> get audioTracks => const [];

  @override
  AetherTrack? get currentAudioTrack => null;

  /// Ce que le moteur répondra : une coupure peut échouer (aucun lecteur prêt).
  final bool coupureReussit;

  int coupures = 0;
  final List<AetherTrack> pistesChoisies = <AetherTrack>[];

  /// L'ordre réel des écritures, pour distinguer « la feuille délègue » de
  /// « la feuille refait le travail dans son coin ».
  final List<String> journal = <String>[];

  @override
  Future<bool> disableSubtitles() async {
    coupures++;
    if (!coupureReussit) {
      journal.add('coupure-refusée');
      return false;
    }
    currentSubtitleTrack = null;
    // Comme le vrai moteur : c'est LUI qui mémorise la coupure.
    await TrackPreferencesService.setSubtitle('no');
    journal.add('coupure');
    return true;
  }

  @override
  Future<void> setSubtitleTrack(AetherTrack track) async {
    pistesChoisies.add(track);
    currentSubtitleTrack = track;
    // Comme le vrai moteur : choisir une piste LÈVE la coupure mémorisée, sans
    // écrire la langue (qui appartient à la feuille).
    if (TrackPreferencesService.subtitle == 'no') {
      await TrackPreferencesService.setSubtitle(null);
    }
    journal.add('piste:${track.id}');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Ouvre la feuille de pistes et laisse l'animation se terminer.
Future<void> _ouvrirLaFeuille(
    WidgetTester tester, AetherPlaybackEngine moteur) async {
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

  unawaited(showTrackSelector(ctx, moteur));
  await tester.pump(); // route de la feuille poussée
  await tester.pump(const Duration(milliseconds: 400)); // animation d'ouverture
}

/// La carte focalisable qui porte ce libellé — c'est elle qui reçoit le tap.
Finder _carteDe(String titre) => find.ancestor(
      of: find.text(titre),
      matching: find.byType(FocusableCard),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final AppLocalizations fr = lookupAppLocalizations(const Locale('fr'));

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TrackPreferencesService.subtitle = null;
  });

  // ── La feuille ────────────────────────────────────────────────────────────

  testWidgets(
      'R42 — la ligne de coupure s\'affiche alors qu\'AUCUNE piste ne porte l\'identifiant « no »',
      (tester) async {
    final moteur = _FauxMoteur(
      subtitleTracks: const [kForcee, kFrancais, kAnglais],
      // Le moteur a choisi seul la piste FORCED : c'est le cas de l'utilisateur.
      currentSubtitleTrack: kForcee,
    );

    // La prémisse du test EST la rupture d'origine : aucun `'no'` dans la liste.
    expect(moteur.subtitleTracks.where((t) => t.id == 'no'), isEmpty,
        reason: 'la ligne ne doit plus dépendre d\'un identifiant de piste');

    await _ouvrirLaFeuille(tester, moteur);

    expect(find.text(fr.tracksDisabled), findsOneWidget,
        reason: 'R42 — sans elle, une piste FORCED reste incoupable');
  });

  testWidgets('R42 — la coupure est EN TÊTE de la section, avant les pistes',
      (tester) async {
    // ⚠️ Décision documentée à conséquence TV : à la télécommande, l'ordre des
    // lignes EST le chemin. La coupure doit être la première atteinte.
    final moteur = _FauxMoteur(
      subtitleTracks: const [kForcee, kFrancais, kAnglais],
      currentSubtitleTrack: kForcee,
    );

    await _ouvrirLaFeuille(tester, moteur);

    final yCoupure = tester.getTopLeft(_carteDe(fr.tracksDisabled)).dy;
    final yPremierePiste = tester.getTopLeft(_carteDe(fr.langEnglish)).dy;
    expect(yCoupure, lessThan(yPremierePiste),
        reason: 'la coupure doit précéder toutes les pistes');
  });

  testWidgets(
      'R42 — la coupure est cochée quand le moteur ne lit aucune piste',
      (tester) async {
    final moteur = _FauxMoteur(
      subtitleTracks: const [kForcee, kFrancais, kAnglais],
      currentSubtitleTrack: null, // sous-titres déjà coupés
    );

    await _ouvrirLaFeuille(tester, moteur);

    // L'état « sélectionné » se lit sur le MOTEUR, pas sur une entrée fantôme.
    expect(
      find.descendant(
        of: _carteDe(fr.tracksDisabled),
        matching: find.byIcon(Icons.check_circle_rounded),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget,
        reason: 'une seule ligne cochée dans toute la feuille');
  });

  testWidgets(
      'R42 — coupure réussie : la feuille se ferme, et c\'est le MOTEUR qui mémorise',
      (tester) async {
    final moteur = _FauxMoteur(
      subtitleTracks: const [kForcee, kFrancais, kAnglais],
      currentSubtitleTrack: kForcee,
    );

    await _ouvrirLaFeuille(tester, moteur);
    await tester.tap(_carteDe(fr.tracksDisabled));
    await tester.pumpAndSettle();

    expect(moteur.coupures, 1, reason: 'disableSubtitles() doit être appelé');
    expect(moteur.pistesChoisies, isEmpty,
        reason: 'une coupure n\'est JAMAIS un identifiant de piste');
    expect(find.text(fr.tracksDisabled), findsNothing,
        reason: 'la feuille se referme sur un succès');
    // ⚠️ La feuille n'écrit plus la préférence elle-même : le `'no'` visible ici
    // vient du MOTEUR (le faux respecte le même contrat). Deux
    // demi-propriétaires donnaient une coupure sans lendemain à tout autre
    // appelant que cette feuille.
    expect(moteur.journal, ['coupure']);
    expect(TrackPreferencesService.subtitle, 'no');
  });

  testWidgets(
      'R42 — coupure REFUSÉE : la feuille reste ouverte, le dit, et ne mémorise rien',
      (tester) async {
    final moteur = _FauxMoteur(
      subtitleTracks: const [kForcee, kFrancais, kAnglais],
      currentSubtitleTrack: kForcee,
      coupureReussit: false,
    );

    await _ouvrirLaFeuille(tester, moteur);
    await tester.tap(_carteDe(fr.tracksDisabled));
    await tester.pump(); // le tap et son attente
    await tester.pump(const Duration(milliseconds: 400)); // toast

    expect(find.text(fr.tracksDisableFailed), findsOneWidget,
        reason: 'un échec muet se lisait comme un succès');
    expect(find.text(fr.tracksDisabled), findsOneWidget,
        reason: 'la feuille NE se referme PAS sur un échec');
    expect(TrackPreferencesService.subtitle, isNull,
        reason: 'une coupure ratée ne doit rien mémoriser');

    // Laisse expirer le toast ET le minuteur de fermeture forcée d'AppSnackBar
    // (durée + 150 ms) : un minuteur encore en vol fait échouer le test.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'R42 — choisir une vraie piste lève le « no » : on peut les rallumer (retour)',
      (tester) async {
    // On part de l'état « coupés ».
    TrackPreferencesService.subtitle = 'no';
    final moteur = _FauxMoteur(
      subtitleTracks: const [kForcee, kFrancais, kAnglais],
      currentSubtitleTrack: null,
    );

    await _ouvrirLaFeuille(tester, moteur);
    // ⚠️ L'anglaise, et pas une française : les deux pistes `fr` portent le
    // MÊME libellé de langue, le finder serait ambigu.
    await tester.ensureVisible(_carteDe(fr.langEnglish));
    await tester.pumpAndSettle();
    await tester.tap(_carteDe(fr.langEnglish));
    await tester.pumpAndSettle();

    expect(moteur.coupures, 0);
    expect(moteur.pistesChoisies.single.id, kAnglais.id);
    // L'ordre compte : le moteur lève la coupure, PUIS la feuille écrit la
    // langue. L'inverse perdrait la langue au profit d'un effacement tardif.
    expect(moteur.journal, ['piste:2']);
    expect(TrackPreferencesService.subtitle, 'en',
        reason:
            'un « no » qui survit rendrait les sous-titres impossibles à rallumer');
  });

  testWidgets('R42 — sans aucune piste, l\'interface ne promet pas de couper',
      (tester) async {
    // ⚠️ Des sous-titres INCRUSTÉS dans l'image se présentent ainsi (zéro
    // piste, du texte à l'écran) : aucun lecteur ne sait les retirer, et
    // afficher « Désactivés » serait mentir.
    final moteur = _FauxMoteur(subtitleTracks: const []);

    await _ouvrirLaFeuille(tester, moteur);

    expect(find.text(fr.tracksNoSubtitles), findsOneWidget);
    expect(find.text(fr.tracksDisabled), findsNothing);
  });

  // ── Le moteur réel ────────────────────────────────────────────────────────

  group('Media3Engine — la coupure ne ment pas', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const pluginChannel = MethodChannel('native_video_player');

    setUp(() {
      messenger.setMockMethodCallHandler(pluginChannel, (call) async => null);
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(pluginChannel, null);
    });

    Media3Engine build() {
      final engine = Media3Engine();
      // Le canal d'événements s'ouvre après un aller-retour de canal.
      messenger.setMockStreamHandler(
        EventChannel('native_video_player_controller_${engine.controllerId}'),
        MockStreamHandler.inline(onListen: (arguments, events) {}),
      );
      return engine;
    }

    test('aucun lecteur natif prêt : la coupure est REFUSÉE, et rien n\'est '
        'mémorisé', () async {
      final moteur = build();

      // ⚠️ Sans vue de plateforme, le contrôleur n'a pas de canal : l'écriture
      // native partirait dans le vide SANS lever. Rendre `true` ici serait le
      // pire des cas — la feuille se fermerait et « coupés » serait mémorisé
      // pour tous les titres suivants, alors que rien n'a été coupé.
      final ok = await moteur.disableSubtitles();

      expect(ok, isFalse);
      expect(TrackPreferencesService.subtitle, isNull,
          reason: 'un refus n\'écrit RIEN');
      expect(moteur.subtitlePreference, isNull,
          reason: 'et ne pose pas la coupure de session');

      moteur.dispose();
      await Future<void>.delayed(Duration.zero);
    });

    test('un refus n\'efface pas une préférence déjà posée', () async {
      TrackPreferencesService.subtitle = 'fr';
      final moteur = build();

      expect(await moteur.disableSubtitles(), isFalse);
      expect(TrackPreferencesService.subtitle, 'fr');

      moteur.dispose();
      await Future<void>.delayed(Duration.zero);
    });
  });
}
