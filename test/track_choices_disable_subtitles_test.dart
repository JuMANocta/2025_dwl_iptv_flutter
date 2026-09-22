// R42 — Les sous-titres doivent pouvoir être COUPÉS.
//
// Le défaut (signalé par l'utilisateur, mesuré sur le S25 le 2026-09-13, Heroes
// S03E15) : ExoPlayer sélectionne de lui-même la piste marquée FORCED, et la
// feuille de pistes n'offrait aucun moyen de la couper. La ligne « Désactivés »
// n'existait que si une piste portait l'identifiant `'no'` — vestige mpv
// qu'aucun moteur Media3 ne fabrique — et son tap passait par
// `setSubtitleTrack('no')`, que le moteur refuse faute de savoir le parser.
//
// §playerPanel (2026-09-22) — La feuille de pistes du téléphone est supprimée :
// Audio et Sous-titres sont des listes de la rangée d'options, construites par
// `audioOptionItems` / `subtitleOptionItems` (`track_choices.dart`). Ces tests,
// portés de la feuille, tiennent les MÊMES règles sur ces listes, sans monter
// le lecteur : « la feuille se referme » y devient « la ligne rend `true` »
// (la liste se referme), « la feuille reste ouverte » devient « la ligne rend
// `false` », et « plus haut dans la feuille » devient « plus tôt dans la
// liste » — à la télécommande comme au doigt, l'ordre des lignes EST le
// chemin.
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

import 'package:aetherStream/data/services/track_preferences_service.dart';
import 'package:aetherStream/feature/player/media3_engine.dart';
import 'package:aetherStream/feature/player/playback_engine.dart';
import 'package:aetherStream/feature/player/widgets/player_option_bar.dart';
import 'package:aetherStream/feature/player/widgets/track_choices.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
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

/// R43 — Deux pistes AUDIO : une avec langue, une SANS (le natif renvoie
/// « unknown » quand le conteneur n'en déclare pas). ⚠️ Allemand, pas anglais :
/// les sous-titres portent déjà une piste `en`, le libellé serait ambigu.
const AetherTrack kAudioAllemand =
    AetherTrack(id: '0', title: 'Deutsch', language: 'de');
const AetherTrack kAudioSansLangue =
    AetherTrack(id: '1', title: 'Commentaire', language: 'unknown');

/// Moteur fictif tenu au MÊME contrat que `Media3Engine` : il porte la coupure
/// entière (session + mémoire), efface la mémoire quand il rend la main
/// (R43), et rend `false` quand une écriture échoue. Un faux qui mentirait sur
/// ce contrat rendrait les tests des listes décoratifs.
class _FauxMoteur implements AetherPlaybackEngine {
  _FauxMoteur({
    this.subtitleTracks = const [],
    this.currentSubtitleTrack,
    this.audioTracks = const [],
    this.currentAudioTrack,
    this.coupureReussit = true,
    this.pisteReussit = true,
    this.retourReussit = true,
  });

  @override
  final List<AetherTrack> subtitleTracks;

  @override
  AetherTrack? currentSubtitleTrack;

  @override
  final List<AetherTrack> audioTracks;

  @override
  AetherTrack? currentAudioTrack;

  /// Ce que le moteur répondra : une coupure peut échouer (aucun lecteur prêt).
  final bool coupureReussit;

  /// R43 — Poser une piste peut échouer aussi (le canal vendoré ne l'avale
  /// plus depuis le patch 22).
  final bool pisteReussit;

  /// R43 — Et revenir à l'automatique, de même.
  final bool retourReussit;

  int coupures = 0;
  int retoursSousTitres = 0;
  int retoursAudio = 0;
  final List<AetherTrack> pistesChoisies = <AetherTrack>[];
  final List<AetherTrack> pistesAudioChoisies = <AetherTrack>[];

  /// L'ordre réel des écritures, pour distinguer « la liste délègue » de
  /// « la liste refait le travail dans son coin ».
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
    await TrackPreferencesService.setSubtitle(
        TrackPreferencesService.kSubtitlesOff);
    journal.add('coupure');
    return true;
  }

  @override
  Future<bool> setSubtitleTrack(AetherTrack track) async {
    if (!pisteReussit) {
      journal.add('piste-refusée');
      return false;
    }
    pistesChoisies.add(track);
    currentSubtitleTrack = track;
    // Comme le vrai moteur : choisir une piste LÈVE la coupure mémorisée, et
    // n'écrit rien d'autre (R43 : une piste de sous-titres ne vaut que pour ce
    // titre).
    if (TrackPreferencesService.subtitle ==
        TrackPreferencesService.kSubtitlesOff) {
      await TrackPreferencesService.setSubtitle(null);
    }
    journal.add('piste:${track.id}');
    return true;
  }

  @override
  Future<bool> setAudioTrack(AetherTrack track) async {
    if (!pisteReussit) {
      journal.add('audio-refusé');
      return false;
    }
    pistesAudioChoisies.add(track);
    currentAudioTrack = track;
    // Comme le vrai moteur : la LANGUE mémorisée appartient à la liste (un
    // geste de l'utilisateur = une préférence), pas au moteur.
    journal.add('audio:${track.id}');
    return true;
  }

  @override
  Future<bool> resetSubtitlesToAuto() async {
    retoursSousTitres++;
    if (!retourReussit) {
      journal.add('retour-sub-refusé');
      return false;
    }
    currentSubtitleTrack = null;
    // Comme le vrai moteur : c'est LUI qui efface la coupure mémorisée, après
    // l'écriture native.
    await TrackPreferencesService.setSubtitle(null);
    journal.add('auto-sub');
    return true;
  }

  @override
  Future<bool> resetAudioToAuto() async {
    retoursAudio++;
    if (!retourReussit) {
      journal.add('retour-audio-refusé');
      return false;
    }
    await TrackPreferencesService.setAudio(null);
    journal.add('auto-audio');
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final AppLocalizations fr = lookupAppLocalizations(const Locale('fr'));

  /// Nombre de changements réussis signalés au lecteur (qui relit alors les
  /// pistes) : un échec n'en signale aucun.
  int appliques = 0;

  List<PlayerOptionItem> sousTitres(AetherPlaybackEngine moteur,
          {ScaffoldMessengerState? messenger}) =>
      subtitleOptionItems(
        player: moteur,
        l10n: fr,
        messenger: messenger,
        onApplied: () => appliques++,
      );

  List<PlayerOptionItem> audio(AetherPlaybackEngine moteur,
          {ScaffoldMessengerState? messenger}) =>
      audioOptionItems(
        player: moteur,
        l10n: fr,
        messenger: messenger,
        onApplied: () => appliques++,
      );

  List<String> libelles(List<PlayerOptionItem> liste) =>
      [for (final l in liste) l.label];

  PlayerOptionItem ligne(List<PlayerOptionItem> liste, String libelle) =>
      liste.singleWhere((l) => l.label == libelle);

  /// Un écran avec un `ScaffoldMessenger` : c'est là que l'échec se DIT.
  Future<ScaffoldMessengerState> messager(WidgetTester tester) async {
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
    return ScaffoldMessenger.of(ctx);
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TrackPreferencesService.subtitle = null;
    TrackPreferencesService.audio = null;
    appliques = 0;
  });

  // ── La liste Sous-titres ─────────────────────────────────────────────────

  test(
      'R42 — la ligne de coupure existe alors qu\'AUCUNE piste ne porte l\'identifiant « no »',
      () {
    final moteur = _FauxMoteur(
      subtitleTracks: const [kForcee, kFrancais, kAnglais],
      // Le moteur a choisi seul la piste FORCED : c'est le cas de l'utilisateur.
      currentSubtitleTrack: kForcee,
    );

    // La prémisse du test EST la rupture d'origine : aucun `'no'` dans la liste.
    expect(moteur.subtitleTracks.where((t) => t.id == 'no'), isEmpty,
        reason: 'la ligne ne doit plus dépendre d\'un identifiant de piste');

    expect(libelles(sousTitres(moteur)), contains(fr.tracksDisabled),
        reason: 'R42 — sans elle, une piste FORCED reste incoupable');
  });

  test('R42 — la coupure est EN TÊTE de la liste, avant les pistes', () {
    // ⚠️ Décision documentée à conséquence TV : à la télécommande, l'ordre des
    // lignes EST le chemin. La coupure doit être la première atteinte.
    final moteur = _FauxMoteur(
      subtitleTracks: const [kForcee, kFrancais, kAnglais],
      currentSubtitleTrack: kForcee,
    );

    final List<String> l = libelles(sousTitres(moteur));
    expect(l.first, fr.tracksDisabled,
        reason: 'la coupure doit précéder toutes les pistes');
    expect(l.indexOf(fr.tracksDisabled), lessThan(l.indexOf(fr.langEnglish)));
  });

  test('R42 — la coupure est cochée quand le moteur ne lit aucune piste', () {
    final moteur = _FauxMoteur(
      subtitleTracks: const [kForcee, kFrancais, kAnglais],
      currentSubtitleTrack: null, // sous-titres déjà coupés
    );

    final liste = sousTitres(moteur);
    // L'état « sélectionné » se lit sur le MOTEUR, pas sur une entrée fantôme.
    expect(ligne(liste, fr.tracksDisabled).selected, isTrue);
    expect(liste.where((l) => l.selected), hasLength(1),
        reason: 'une seule ligne cochée dans toute la liste');
  });

  test(
      'R42 — coupure réussie : la liste se referme, et c\'est le MOTEUR qui mémorise',
      () async {
    final moteur = _FauxMoteur(
      subtitleTracks: const [kForcee, kFrancais, kAnglais],
      currentSubtitleTrack: kForcee,
    );

    final bool fait = await ligne(sousTitres(moteur), fr.tracksDisabled).onSelect();

    expect(moteur.coupures, 1, reason: 'disableSubtitles() doit être appelé');
    expect(moteur.pistesChoisies, isEmpty,
        reason: 'une coupure n\'est JAMAIS un identifiant de piste');
    expect(fait, isTrue, reason: 'la liste se referme sur un succès');
    expect(appliques, 1, reason: 'le lecteur relit les pistes après un succès');
    // ⚠️ La liste n'écrit pas la préférence elle-même : le `'no'` visible ici
    // vient du MOTEUR (le faux respecte le même contrat). Deux
    // demi-propriétaires donnaient une coupure sans lendemain à tout autre
    // appelant que cette liste.
    expect(moteur.journal, ['coupure']);
    expect(TrackPreferencesService.subtitle, 'no');
  });

  testWidgets(
      'R42 — coupure REFUSÉE : la liste reste ouverte, le dit, et ne mémorise rien',
      (tester) async {
    final messenger = await messager(tester);
    final moteur = _FauxMoteur(
      subtitleTracks: const [kForcee, kFrancais, kAnglais],
      currentSubtitleTrack: kForcee,
      coupureReussit: false,
    );

    final bool fait = await ligne(
            sousTitres(moteur, messenger: messenger), fr.tracksDisabled)
        .onSelect();
    await tester.pump(); // le toast
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(fr.tracksDisableFailed), findsOneWidget,
        reason: 'un échec muet se lisait comme un succès');
    expect(fait, isFalse, reason: 'la liste NE se referme PAS sur un échec');
    expect(appliques, 0);
    expect(TrackPreferencesService.subtitle, isNull,
        reason: 'une coupure ratée ne doit rien mémoriser');

    // Laisse expirer le toast ET le minuteur de fermeture forcée d'AppSnackBar
    // (durée + 150 ms) : un minuteur encore en vol fait échouer le test.
    await tester.pump(const Duration(seconds: 5));
  });

  test(
      'R42 — choisir une vraie piste lève le « no » : on peut les rallumer (retour)',
      () async {
    // On part de l'état « coupés ».
    TrackPreferencesService.subtitle = 'no';
    final moteur = _FauxMoteur(
      subtitleTracks: const [kForcee, kFrancais, kAnglais],
      currentSubtitleTrack: null,
    );

    // ⚠️ L'anglaise, et pas une française : les deux pistes `fr` portent le
    // MÊME libellé de langue, la ligne serait ambiguë.
    final bool fait = await ligne(sousTitres(moteur), fr.langEnglish).onSelect();

    expect(fait, isTrue);
    expect(moteur.coupures, 0);
    expect(moteur.pistesChoisies.single.id, kAnglais.id);
    expect(moteur.journal, ['piste:2']);
    // R43 — Plus AUCUNE langue mémorisée pour les sous-titres : une piste
    // choisie ne vaut que pour ce titre. Avant, la feuille écrivait `'en'` ici,
    // que rien ne lisait — et l'appliquer aurait allumé les sous-titres
    // anglais de tous les films anglais. Seule la coupure a été levée.
    expect(TrackPreferencesService.subtitle, isNull,
        reason: 'un « no » qui survit rendrait les sous-titres impossibles à '
            'rallumer ; une LANGUE qui apparaît serait une mémoire que personne '
            'n\'a demandée');
  });

  test(
      '§trackRebuffer — la piste de sous-titres DÉJÀ active n\'est pas ré-appliquée',
      () async {
    final moteur = _FauxMoteur(
      subtitleTracks: const [kForcee, kFrancais, kAnglais],
      currentSubtitleTrack: kAnglais,
    );

    final bool fait = await ligne(sousTitres(moteur), fr.langEnglish).onSelect();

    expect(fait, isTrue, reason: 'rien à faire : la liste se referme');
    expect(moteur.journal, isEmpty, reason: 'ré-appliquer re-démuxe (~3 s)');
  });

  // ── R43 : la mémoire se voit et se défait ────────────────────────────────

  test(
      'R43 — coupure mémorisée : la liste le DIT, et la ligne rend la main au moteur',
      () async {
    TrackPreferencesService.subtitle = TrackPreferencesService.kSubtitlesOff;
    final moteur = _FauxMoteur(
      subtitleTracks: const [kForcee, kFrancais, kAnglais],
      currentSubtitleTrack: null,
    );

    final liste = sousTitres(moteur);
    final List<String> l = libelles(liste);
    // Avant R43 : rien ne disait que la coupure valait pour les titres
    // suivants, et rien ne permettait de la lever sans choisir une piste.
    expect(l, contains(fr.tracksMemorySubOff));
    // « Désactivés » reste EN TÊTE (décision R42, conséquence TV) : la ligne
    // de mémoire ferme la section, elle ne la précède pas.
    expect(l.indexOf(fr.tracksMemorySubOff),
        greaterThan(l.indexOf(fr.tracksDisabled)));
    expect(l.last, fr.tracksMemorySubOff,
        reason: 'sans recherche en ligne, elle ferme la liste');
    expect(ligne(liste, fr.tracksMemorySubOff).selected, isFalse,
        reason: 'ce n\'est pas une piste, c\'est un retour en arrière');

    final bool fait = await ligne(liste, fr.tracksMemorySubOff).onSelect();

    expect(moteur.retoursSousTitres, 1, reason: 'resetSubtitlesToAuto() attendu');
    expect(moteur.pistesChoisies, isEmpty,
        reason: 'revenir à l\'automatique n\'est PAS choisir une piste');
    expect(moteur.journal, ['auto-sub']);
    expect(TrackPreferencesService.subtitle, isNull,
        reason: 'la mémoire est effacée par le moteur, après l\'écriture native');
    expect(fait, isTrue, reason: 'la liste se referme sur un succès');
    expect(libelles(sousTitres(moteur)), isNot(contains(fr.tracksMemorySubOff)),
        reason: 'la mémoire défaite, sa ligne disparaît');
  });

  test('R43 — la coupure mémorisée se lève MÊME sur un titre sans aucune piste',
      () {
    // C'est exactement le cas où l'on était coincé : sans piste, pas de ligne
    // à choisir, donc aucun retour possible (et « Désactivés » ne s'affiche pas
    // non plus, à raison — il n'y a rien à couper).
    TrackPreferencesService.subtitle = TrackPreferencesService.kSubtitlesOff;
    final moteur = _FauxMoteur(subtitleTracks: const []);

    final List<String> l = libelles(sousTitres(moteur));
    expect(l, contains(fr.tracksNoSubtitles));
    expect(l, isNot(contains(fr.tracksDisabled)));
    expect(l, contains(fr.tracksMemorySubOff));
    // L'information en tête, la mémoire ferme la liste (R43).
    expect(l, [fr.tracksNoSubtitles, fr.tracksMemorySubOff]);
  });

  test('R43 — sans mémoire, aucune ligne de retour n\'encombre les listes', () {
    final moteur = _FauxMoteur(
      subtitleTracks: const [kForcee, kFrancais, kAnglais],
      currentSubtitleTrack: kForcee,
      audioTracks: const [kAudioAllemand, kAudioSansLangue],
      currentAudioTrack: kAudioAllemand,
    );

    final lignes = [...sousTitres(moteur), ...audio(moteur)];
    expect(libelles(lignes), isNot(contains(fr.tracksMemorySubOff)));
    expect(lignes.where((l) => l.detail == fr.tracksMemoryForget), isEmpty);
    expect(
        lignes.where((l) => l.label.contains(fr.tracksMemoryAudio(''))),
        isEmpty);
  });

  testWidgets(
      'R43 — retour à l\'automatique REFUSÉ : la liste reste ouverte, le dit, et garde la mémoire',
      (tester) async {
    final messenger = await messager(tester);
    TrackPreferencesService.subtitle = TrackPreferencesService.kSubtitlesOff;
    final moteur = _FauxMoteur(
      subtitleTracks: const [kForcee, kFrancais, kAnglais],
      retourReussit: false,
    );

    final bool fait = await ligne(
            sousTitres(moteur, messenger: messenger), fr.tracksMemorySubOff)
        .onSelect();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(fr.tracksResetFailed), findsOneWidget);
    expect(fait, isFalse, reason: 'la liste NE se referme PAS sur un échec');
    // ⚠️ Une mémoire effacée sans que le natif ait suivi ferait revenir la
    // coupure au titre suivant tout en affichant « automatique ».
    expect(TrackPreferencesService.subtitle,
        TrackPreferencesService.kSubtitlesOff);

    await tester.pump(const Duration(seconds: 5));
  });

  // ── La liste Audio ───────────────────────────────────────────────────────

  test(
      'R43 — choisir une piste AUDIO mémorise sa LANGUE pour les prochains titres',
      () async {
    TrackPreferencesService.audio = 'fr';
    final moteur = _FauxMoteur(
      audioTracks: const [kAudioAllemand, kAudioSansLangue],
      currentAudioTrack: kAudioSansLangue,
    );

    final bool fait = await ligne(audio(moteur), fr.langGerman).onSelect();

    expect(moteur.pistesAudioChoisies.single.id, kAudioAllemand.id);
    expect(TrackPreferencesService.audio, 'de');
    expect(fait, isTrue, reason: 'liste refermée');
    expect(appliques, 1);
  });

  test(
      'R43 — une piste audio SANS langue ne touche pas à la mémoire (ni numéro, ni « unknown »)',
      () async {
    // Avant : `_trackKey` écrivait son NUMÉRO (« 1 »), qui écrasait la vraie
    // préférence et était rejoué à chaque ouverture comme une langue.
    TrackPreferencesService.audio = 'fr';
    final moteur = _FauxMoteur(
      audioTracks: const [kAudioAllemand, kAudioSansLangue],
      currentAudioTrack: kAudioAllemand,
    );

    final liste = audio(moteur);
    // Sans langue, la piste se nomme par son titre — jamais « UNKNOWN ».
    expect(libelles(liste), isNot(contains('UNKNOWN')));
    final bool fait = await ligne(liste, 'Commentaire').onSelect();

    expect(fait, isTrue);
    expect(moteur.pistesAudioChoisies.single.id, kAudioSansLangue.id,
        reason: 'la piste est bien posée pour CE titre');
    expect(TrackPreferencesService.audio, 'fr',
        reason: 'la mémoire n\'est ni écrasée par un numéro, ni effacée');
  });

  test('§trackRebuffer — la piste audio DÉJÀ active n\'est pas ré-appliquée',
      () async {
    TrackPreferencesService.audio = 'fr';
    final moteur = _FauxMoteur(
      audioTracks: const [kAudioAllemand, kAudioSansLangue],
      currentAudioTrack: kAudioAllemand,
    );

    final bool fait = await ligne(audio(moteur), fr.langGerman).onSelect();

    expect(fait, isTrue);
    expect(moteur.journal, isEmpty, reason: 'ré-appliquer re-démuxe (~3 s)');
    expect(TrackPreferencesService.audio, 'fr',
        reason: 'aucun choix fait, aucune mémoire écrite');
  });

  test(
      'R43 — mémoire audio : la ligne NOMME la langue, ferme la liste, et la défait',
      () async {
    TrackPreferencesService.audio = 'de';
    final moteur = _FauxMoteur(
      audioTracks: const [kAudioAllemand, kAudioSansLangue],
      currentAudioTrack: kAudioAllemand,
      subtitleTracks: const [kFrancais],
    );

    final liste = audio(moteur);
    final libelle = fr.tracksMemoryAudio(fr.langGerman);
    expect(libelles(liste), contains(libelle),
        reason: 'la mémoire se dit avec le NOM de la langue, pas « de »');
    // EN FIN de liste audio : à la télécommande, la ligne cochée (ou la
    // première) est l'action par défaut du bouton OK — « oublier ma langue »
    // ne doit pas l'être. Et elle n'appartient qu'à la liste AUDIO.
    expect(libelles(liste).last, libelle);
    expect(libelles(liste).indexOf(libelle),
        greaterThan(libelles(liste).indexOf('Commentaire')));
    expect(libelles(sousTitres(moteur)), isNot(contains(libelle)));
    expect(ligne(liste, libelle).selected, isFalse);

    final bool fait = await ligne(liste, libelle).onSelect();

    expect(moteur.retoursAudio, 1);
    expect(moteur.pistesAudioChoisies, isEmpty);
    expect(TrackPreferencesService.audio, isNull);
    expect(fait, isTrue, reason: 'liste refermée');
  });

  testWidgets(
      'R43 — une piste audio REFUSÉE ne mémorise rien et laisse la liste ouverte',
      (tester) async {
    final messenger = await messager(tester);
    final moteur = _FauxMoteur(
      audioTracks: const [kAudioAllemand, kAudioSansLangue],
      currentAudioTrack: kAudioSansLangue,
      pisteReussit: false,
    );

    final bool fait =
        await ligne(audio(moteur, messenger: messenger), fr.langGerman)
            .onSelect();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(fr.tracksTrackFailed), findsOneWidget,
        reason: 'avant, le canal vendoré avalait l\'échec : la feuille se '
            'fermait et mémorisait une langue qu\'aucune piste ne portait');
    expect(fait, isFalse, reason: 'liste ouverte');
    expect(appliques, 0);
    expect(TrackPreferencesService.audio, isNull);

    await tester.pump(const Duration(seconds: 5));
  });

  // ── Sans aucune piste : une information, jamais une promesse ─────────────

  test('R42 — sans aucune piste, l\'interface ne promet pas de couper',
      () async {
    // ⚠️ Des sous-titres INCRUSTÉS dans l'image se présentent ainsi (zéro
    // piste, du texte à l'écran) : aucun lecteur ne sait les retirer, et
    // afficher « Désactivés » serait mentir.
    //
    // §playerPanel — La rangée TV de la 1.20.2 avait perdu cette règle (ligne
    // « Désactivés » inconditionnelle) : régression refermée, pour les deux
    // plateformes, par la fonction partagée.
    final moteur = _FauxMoteur(subtitleTracks: const []);

    final liste = sousTitres(moteur);
    expect(libelles(liste), [fr.tracksNoSubtitles],
        reason: 'le hint est là, et rien d\'autre sans mémoire ni recherche');
    expect(libelles(liste), isNot(contains(fr.tracksDisabled)));

    // Une ligne d'INFORMATION : jamais cochée, et la choisir n'applique RIEN
    // — elle referme simplement la liste.
    final info = liste.single;
    expect(info.selected, isFalse);
    expect(await info.onSelect(), isTrue);
    expect(moteur.journal, isEmpty);
    expect(moteur.coupures, 0);
    expect(appliques, 0);
    expect(TrackPreferencesService.subtitle, isNull,
        reason: 'choisir l\'information ne mémorise aucune coupure');
  });

  test('R42 — sans aucune piste audio, la liste le DIT (et n\'est jamais vide)',
      () async {
    final moteur = _FauxMoteur(audioTracks: const []);

    final liste = audio(moteur);
    expect(libelles(liste), [fr.tracksNoAudio]);
    expect(liste.single.selected, isFalse);
    expect(await liste.single.onSelect(), isTrue,
        reason: 'la ligne referme la liste');
    expect(moteur.journal, isEmpty, reason: 'et n\'applique rien');
    expect(appliques, 0);
  });

  test(
      'R43 — sans aucune piste audio, la mémoire reste défaisable, APRÈS '
      'l\'information', () {
    TrackPreferencesService.audio = 'de';
    final moteur = _FauxMoteur(audioTracks: const []);

    expect(libelles(audio(moteur)), [
      fr.tracksNoAudio,
      fr.tracksMemoryAudio(fr.langGerman),
    ]);
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
      // pire des cas — la liste se fermerait et « coupés » serait mémorisé
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
      TrackPreferencesService.audio = 'fr';
      final moteur = build();

      expect(await moteur.disableSubtitles(), isFalse);
      expect(TrackPreferencesService.audio, 'fr');
      expect(TrackPreferencesService.subtitle, isNull);

      moteur.dispose();
      await Future<void>.delayed(Duration.zero);
    });

    test(
        'R43 — sans lecteur natif, les retours à l\'automatique sont REFUSÉS et '
        'n\'effacent RIEN', () async {
      // ⚠️ L'ordre est celui de la coupure : le natif d'abord, la mémoire
      // ensuite. Une mémoire effacée sans que le natif ait suivi ferait revenir
      // la coupure au titre suivant tout en affichant « automatique ».
      TrackPreferencesService.subtitle = TrackPreferencesService.kSubtitlesOff;
      TrackPreferencesService.audio = 'en';
      final moteur = build();

      expect(await moteur.resetSubtitlesToAuto(), isFalse);
      expect(TrackPreferencesService.subtitle,
          TrackPreferencesService.kSubtitlesOff);
      expect(await moteur.resetAudioToAuto(), isFalse);
      expect(TrackPreferencesService.audio, 'en');

      moteur.dispose();
      await Future<void>.delayed(Duration.zero);
    });

    test(
        'R43 — sans lecteur natif, poser une piste est refusé, et une coupure '
        'mémorisée n\'est PAS levée par un refus', () async {
      TrackPreferencesService.subtitle = TrackPreferencesService.kSubtitlesOff;
      final moteur = build();

      expect(await moteur.setAudioTrack(kAudioAllemand), isFalse);
      expect(await moteur.setSubtitleTrack(kAnglais), isFalse);
      expect(TrackPreferencesService.subtitle,
          TrackPreferencesService.kSubtitlesOff,
          reason: 'lever la coupure sur une piste qui n\'a PAS été posée '
              'rallumerait des sous-titres que personne ne voit');

      moteur.dispose();
      await Future<void>.delayed(Duration.zero);
    });
  });
}
