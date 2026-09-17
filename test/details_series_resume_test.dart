// §heroSeriesResume (2026-09-12) — Une série en cours de lecture n'apparaissait
// JAMAIS dans le carrousel hero de l'accueil, ni avec une barre de progression
// sur sa vignette.
//
// La cause n'est pas un défaut d'affichage : le catalogue Xtream ne contient
// qu'UNE entrée par série — son stub `/series/{user}/{pass}/{id}`
// (`xtream_catalog_parser`) — alors que la progression est enregistrée sous
// l'URL de l'ÉPISODE. L'accueil, lui, ne résout une reprise qu'en retrouvant
// son URL dans l'index des entrées (`resumeGroupsFor` : « une URL inconnue est
// ignorée »). L'URL d'un épisode n'y étant pas, la reprise était écartée.
//
// La règle testée ici est le CHOIX du stub à écrire. Le branchement (le player
// qui écrit effectivement sous cette clé) se voit à la recette : aucun test ne
// monte `DetailsPage`, qui appelle TMDB à l'init.

import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/feature/search/details_page.dart';

/// Un stub de série tel que le parser du catalogue en produit un par compte.
M3uEntry _stub(String account, {String id = '42'}) => M3uEntry(
      url: 'http://$account.tv/series/user/pass/$id',
      accountId: account,
      type: M3uContentType.series,
      title: const TitleMetadata(rawTitle: 'Dark', baseTitle: 'Dark'),
    );

/// Un épisode tel que `fetchEpisodes` en rend : il porte l'`accountId` du
/// compte dont le stub l'a produit, et une URL jouable (avec extension).
M3uEntry _episode(String account, {int season = 1, int episode = 2}) =>
    M3uEntry(
      url: 'http://$account.tv/series/user/pass/900$episode.mkv',
      accountId: account,
      type: M3uContentType.series,
      title: TitleMetadata(
        rawTitle: 'Dark S0${season}E0$episode',
        baseTitle: 'Dark',
        seasonNumber: season,
        episodeNumber: episode,
      ),
    );

void main() {
  group('seriesResumeKeyFor — quelle clé de série écrire', () {
    test('un épisode rend le stub de la série, pas sa propre URL', () {
      final key = seriesResumeKeyFor(
        stubs: [_stub('a')],
        episode: _episode('a'),
      );

      expect(key, 'http://a.tv/series/user/pass/42');
    });

    test('multi-comptes : le stub du compte DE L\'ÉPISODE, pas le premier', () {
      // §seriesMultiList — les stubs arrivent dans l'ordre du vivier (le compte
      // de la vignette en tête), qui n'est pas celui de la version choisie :
      // prendre `stubs.first` écrirait la clé du mauvais compte.
      final key = seriesResumeKeyFor(
        stubs: [_stub('a'), _stub('b'), _stub('c')],
        episode: _episode('b'),
      );

      expect(key, 'http://b.tv/series/user/pass/42');
    });

    test('compte sans stub : repli sur un autre stub du même titre', () {
      // L'accueil indexe les stubs de TOUS les comptes vers le MÊME groupe :
      // n'importe lequel retrouve la bonne carte. Mieux vaut celui-là que rien.
      final key = seriesResumeKeyFor(
        stubs: [_stub('a')],
        episode: _episode('zz'),
      );

      expect(key, 'http://a.tv/series/user/pass/42');
    });

    test('aucun stub (série M3U qui porte ses épisodes) : rien à écrire', () {
      // Écrire l'URL de l'épisode n'ajouterait qu'une clé que l'accueil ignore.
      expect(
        seriesResumeKeyFor(stubs: const [], episode: _episode('a')),
        isNull,
      );
    });
  });

  group('seriesResumeKeyFor — ce qui ne doit RIEN écrire', () {
    test('un film ne reçoit jamais de clé de série', () {
      final film = M3uEntry(
        url: 'http://a.tv/movie/user/pass/7.mkv',
        accountId: 'a',
        type: M3uContentType.movie,
        title: const TitleMetadata(rawTitle: 'Heat', baseTitle: 'Heat'),
      );

      expect(seriesResumeKeyFor(stubs: [_stub('a')], episode: film), isNull);
    });

    test('une chaîne (direct/replay) ne reçoit jamais de clé de série', () {
      final chaine = M3uEntry(
        url: 'http://a.tv/live/user/pass/1.ts',
        accountId: 'a',
        type: M3uContentType.tv,
        title: const TitleMetadata(rawTitle: 'TF1', baseTitle: 'TF1'),
      );

      expect(seriesResumeKeyFor(stubs: [_stub('a')], episode: chaine), isNull);
    });

    test('une entrée série SANS numérotation est le stub, pas un épisode', () {
      // Fiche ouverte sans sélection d'épisode : `_selectedEntry` vaut alors le
      // stub lui-même. Lui écrire une reprise créerait une carte « en cours »
      // pour une série qu'on n'a jamais lancée.
      expect(
        seriesResumeKeyFor(stubs: [_stub('a')], episode: _stub('a')),
        isNull,
      );
    });
  });

  // §heroSeriesResume — « Oublier la reprise » n'effaçait que les clés
  // d'épisode : la série restait au hero de l'accueil juste après que
  // l'utilisateur ait demandé de l'oublier. Le défaut naît AVEC la clé de
  // série — avant, rien n'était écrit sous le stub.
  group('seriesKeyToForget — ce que « Oublier la reprise » efface', () {
    const String stub = 'http://a.tv/series/user/pass/42';

    test('plus aucun épisode en cours : la clé de série part aussi', () {
      expect(
        seriesKeyToForget(seriesKey: stub, anyEpisodeStillInProgress: false),
        stub,
      );
    });

    test('une autre saison encore en cours : la série RESTE au hero', () {
      // Elle est légitimement « en cours » : il reste quelque chose à
      // reprendre, on ne la retire pas de l'accueil.
      expect(
        seriesKeyToForget(seriesKey: stub, anyEpisodeStillInProgress: true),
        isNull,
      );
    });

    test('pas de clé de série (film, série M3U) : rien à effacer', () {
      expect(
        seriesKeyToForget(seriesKey: null, anyEpisodeStillInProgress: false),
        isNull,
      );
      expect(
        seriesKeyToForget(seriesKey: null, anyEpisodeStillInProgress: true),
        isNull,
      );
    });
  });
}
