// Lot 11 — La ligne « Chercher des sous-titres en ligne » de la liste
// Sous-titres.
//
// §playerPanel (2026-09-22) — Portés de la feuille de pistes du téléphone,
// supprimée : la liste Sous-titres de la rangée d'options est construite par
// `subtitleOptionItems` (`track_choices.dart`), la même au doigt et à la
// télécommande. « Plus bas dans la feuille » devient « plus loin dans la
// liste ».
//
// Ce que ces tests tiennent, et pourquoi :
//
// 1. La ligne n'existe QUE si le contenu est identifiable. Sans contexte de
//    recherche (chaîne en direct, titre vide), le lecteur ne passe pas de
//    `onSearchOnline` : la promettre serait promettre une recherche qui ne
//    peut rien rendre.
// 2. Elle est EN FIN de liste. À la télécommande, la ligne courante est ce
//    que le bouton OK déclenche : partir sur le réseau ne doit pas être
//    l'action par défaut — même règle que les lignes de mémoire (R43) et
//    inverse de « Désactivés », qui reste en tête (R42).
//
// ⚠️ Ce qui n'est PAS couvert ici : la recherche elle-même (elle demande le
// réseau et une clé) — ses parties pures sont dans `online_subtitles_test.dart`.

import 'package:aetherStream/data/services/online_subtitles_service.dart';
import 'package:aetherStream/data/services/track_preferences_service.dart';
import 'package:aetherStream/feature/player/playback_engine.dart';
import 'package:aetherStream/feature/player/widgets/player_option_bar.dart';
import 'package:aetherStream/feature/player/widgets/track_choices.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const AetherTrack _sousTitreFr =
    AetherTrack(id: '0', title: 'Français', language: 'fr');

/// Moteur fictif réduit à ce que la liste LIT. `noSuchMethod` couvre le
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final AppLocalizations fr = lookupAppLocalizations(const Locale('fr'));

  /// Nombre de recherches lancées par la ligne.
  int recherches = 0;

  /// La liste Sous-titres telle que le lecteur la construit : `onSearchOnline`
  /// n'est passé que si le contenu s'identifie (`_onlineSearchContext`).
  List<PlayerOptionItem> lignes(
    AetherPlaybackEngine moteur, {
    SubtitleSearchContext? recherche,
    bool enCours = false,
  }) =>
      subtitleOptionItems(
        player: moteur,
        l10n: fr,
        onSearchOnline: recherche == null
            ? null
            : () async {
                recherches++;
                return false;
              },
        onlineBusy: enCours,
      );

  /// Les libellés, dans l'ordre.
  List<String> liste(
    AetherPlaybackEngine moteur, {
    SubtitleSearchContext? recherche,
    bool enCours = false,
  }) =>
      [
        for (final l in lignes(moteur, recherche: recherche, enCours: enCours))
          l.label,
      ];

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TrackPreferencesService.subtitle = null;
    TrackPreferencesService.audio = null;
    recherches = 0;
  });

  test('la ligne apparaît quand le contenu est identifiable', () {
    expect(
      liste(
        _FauxMoteur(subtitleTracks: const [_sousTitreFr]),
        recherche: subtitleSearchContextFor(title: 'Le Martien'),
      ),
      contains(fr.tracksSearchOnline),
    );
  });

  test('sans contexte de recherche, la ligne n\'existe pas', () {
    // Le cas d'une chaîne en direct : rien à faire reconnaître par TMDB.
    expect(liste(_FauxMoteur(subtitleTracks: const [_sousTitreFr])),
        isNot(contains(fr.tracksSearchOnline)),
        reason: 'promettre une recherche qui ne peut rien rendre');
  });

  test('elle apparaît MÊME sans aucune piste : c\'est justement là '
      'qu\'elle sert', () {
    final List<String> l = liste(
      _FauxMoteur(),
      recherche: subtitleSearchContextFor(title: 'Le Martien'),
    );
    expect(l, contains(fr.tracksNoSubtitles));
    expect(l, contains(fr.tracksSearchOnline));
    // R42 — sans piste, l'information en tête, la recherche en dernier.
    expect(l, [fr.tracksNoSubtitles, fr.tracksSearchOnline]);
  });

  test(
      'elle est APRÈS la coupure : à la télécommande, OK ne doit pas partir '
      'sur le réseau', () {
    final List<String> l = liste(
      _FauxMoteur(subtitleTracks: const [_sousTitreFr]),
      recherche: subtitleSearchContextFor(title: 'Le Martien'),
    );
    expect(l.indexOf(fr.tracksSearchOnline),
        greaterThan(l.indexOf(fr.tracksDisabled)),
        reason: 'R42 garde « Désactivés » en tête ; celle-ci ferme la liste');
  });

  test('elle passe après TOUTES les pistes, et après la mémoire : la DERNIÈRE',
      () {
    TrackPreferencesService.subtitle = TrackPreferencesService.kSubtitlesOff;
    final List<String> l = liste(
      _FauxMoteur(subtitleTracks: const [
        _sousTitreFr,
        AetherTrack(id: '1', title: 'Anglais', language: 'en'),
      ]),
      recherche: subtitleSearchContextFor(title: 'Le Martien'),
    );
    final int enLigne = l.indexOf(fr.tracksSearchOnline);
    for (final String piste in [
      fr.langFrench,
      fr.langEnglish,
      fr.tracksMemorySubOff,
    ]) {
      expect(l.indexOf(piste), allOf(isNonNegative, lessThan(enLigne)),
          reason: 'la ligne « $piste » doit rester avant la recherche réseau');
    }
    expect(l.last, fr.tracksSearchOnline);
  });

  test('la ligne dit « Recherche… » pendant la recherche, et relance la même',
      () async {
    final recherche = subtitleSearchContextFor(title: 'Le Martien');
    final moteur = _FauxMoteur(subtitleTracks: const [_sousTitreFr]);

    PlayerOptionItem enLigne(bool enCours) =>
        lignes(moteur, recherche: recherche, enCours: enCours)
            .singleWhere((l) => l.label == fr.tracksSearchOnline);

    expect(enLigne(false).detail, fr.tracksSearchOnlineSub);
    expect(enLigne(true).detail, fr.tracksOnlineSearching);

    // §boundFocus — la ligne reste activable pendant la recherche : c'est le
    // lecteur qui refuse un second départ, pas la liste qui la neutralise.
    expect(await enLigne(true).onSelect(), isFalse,
        reason: 'la liste reste ouverte : elle sera remplacée par les résultats');
    expect(recherches, 1);
  });

  test('les résultats : la langue en titre, la VERSION en détail', () {
    const s = OnlineSubtitle(
      id: '1',
      url: 'https://exemple.invalid/1.srt',
      language: 'fr',
      display: 'French',
      release: '1080p.WEB-DL',
      source: 'subdl',
    );
    final resultats = onlineSubtitleOptionItems(
      player: _FauxMoteur(),
      results: const [s],
      l10n: fr,
    );

    expect(resultats.single.label, fr.langFrench);
    expect(resultats.single.detail, onlineSubtitleDetail(fr, s));
    expect(resultats.single.selected, isFalse);
  });

  // ⚠️ §tvOptionsBack — la liste n'a plus de ligne « Revenir à la vidéo » :
  // dans la rangée, Retour referme la liste (`PlayerOptionsController.back`),
  // et au doigt un appui hors de la liste la referme (`player_option_bar`).
}
