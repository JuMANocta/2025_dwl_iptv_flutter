// §22.1 (2026-09-25) — Les épisodes d'une série, réunis entre toutes les listes.
//
// Une fiche de série rassemble des épisodes de deux origines : ceux qu'une
// liste M3U porte déjà (en mémoire) et ceux que la JSON API rend à la demande
// pour chaque stub `/series/{user}/{pass}/{id}`. Les règles qui décident QUELS
// stubs interroger, COMMENT réunir leurs épisodes, QUELLE version enchaîner et
// QUAND la tête d'un groupe est une demande ont quitté la page
// (`details_versions.dart`) : elles sont tenues ici.
//
// Le branchement (fusion au fil des réponses, reprise retrouvée sur une version
// arrivée tard) se voit à la recette : aucun test ne monte `DetailsPage`, qui
// appelle TMDB à l'init.

import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/feature/search/details_versions.dart';
import 'package:aetherStream/feature/search/version_dedup.dart';

/// Un stub de catalogue Xtream : une entrée par série, URL sans extension.
M3uEntry _stub(
  String account,
  int id, {
  String base = 'Dark',
  String? year,
  String? quality,
  List<String> languages = const [],
  String? tmdb,
  String? groupKey,
}) =>
    M3uEntry(
      url: 'http://$account.tv/series/u/p/$id',
      accountId: account,
      type: M3uContentType.series,
      tmdbId: tmdb,
      title: TitleMetadata(
        rawTitle: base,
        baseTitle: base,
        groupKey: groupKey ?? base.toLowerCase(),
        year: year,
        quality: quality,
        languages: languages,
      ),
    );

/// Un épisode, M3U ou API : une URL jouable, saison et numéro renseignés.
M3uEntry _ep(
  String account,
  int season,
  int episode, {
  String tag = '',
  String? quality,
  List<String> languages = const [],
}) =>
    M3uEntry(
      url: 'http://$account.tv/series/u/p/$tag${season * 100 + episode}.mkv',
      accountId: account,
      type: M3uContentType.series,
      title: TitleMetadata(
        rawTitle: 'Dark S${season}E$episode',
        baseTitle: 'Dark',
        groupKey: 'dark',
        seasonNumber: season,
        episodeNumber: episode,
        quality: quality,
        languages: languages,
      ),
    );

/// Le dédoublonnage de la fiche, avec un libellé à la manière de la pastille
/// (qualité · langue, « FHD » par défaut).
List<M3uEntry> _dedupe(List<M3uEntry> versions) => dedupeVersions(
      versions,
      (v, _) =>
          '${v.title.quality ?? 'FHD'} · ${v.title.languages.join('+')}',
    );

List<String> _accounts(EpisodeGroup g) =>
    g.versions.map((v) => v.accountId).toList();

void main() {
  group('mergeSeasonEpisodes — même saison + même numéro = UNE ligne', () {
    test('épisodes M3U d\'une liste + épisodes API d\'une autre : réunis', () {
      final merged = mergeSeasonEpisodes(
        [_ep('m3u', 1, 1), _ep('m3u', 1, 2), _ep('api', 1, 1), _ep('api', 2, 1)],
        dedupe: _dedupe,
      );

      expect(merged.keys, [1, 2]);
      expect(merged[1]!.map((g) => g.episodeNumber), [1, 2]);
      expect(_accounts(merged[1]!.first), ['m3u', 'api']);
      expect(_accounts(merged[2]!.first), ['api'],
          reason: 'une saison que seule l\'API connaît est ajoutée');
    });

    test('une même URL ne compte qu\'une fois (la fiche re-fusionne ce '
        'qu\'elle affiche déjà avec ce qui arrive)', () {
      final e = _ep('api', 1, 1);
      final merged =
          mergeSeasonEpisodes([e, e, _ep('m3u', 1, 1), e], dedupe: (v) => v);

      expect(merged[1]!.single.versions.map((v) => v.url).toSet().length, 2);
      expect(merged[1]!.single.versions.length, 2);
    });

    test('les versions suivent l\'ordre des listes, pas l\'ordre d\'arrivée',
        () {
      // Sans ordre, le résultat dépendait de la VOIE (M3U d'abord) et donc de
      // qui répondait le premier.
      final m3uFirst = mergeSeasonEpisodes(
        [_ep('m3u', 1, 1), _ep('api', 1, 1)],
        dedupe: _dedupe,
        accountOrder: ['api', 'm3u'],
      );
      final apiFirst = mergeSeasonEpisodes(
        [_ep('api', 1, 1), _ep('m3u', 1, 1)],
        dedupe: _dedupe,
        accountOrder: ['api', 'm3u'],
      );

      expect(_accounts(m3uFirst[1]!.single), ['api', 'm3u']);
      expect(_accounts(apiFirst[1]!.single), ['api', 'm3u']);
      expect(m3uFirst[1]!.single.best.accountId, 'api');
    });

    test('une liste inconnue de l\'ordre passe après, dans l\'ordre d\'arrivée',
        () {
      final merged = mergeSeasonEpisodes(
        [_ep('x', 1, 1), _ep('b', 1, 1), _ep('y', 1, 1), _ep('a', 1, 1)],
        dedupe: _dedupe,
        accountOrder: ['a', 'b'],
      );

      expect(_accounts(merged[1]!.single), ['a', 'b', 'x', 'y']);
    });

    test('deux versions d\'une même liste gardent leur ordre (tri stable)', () {
      final merged = mergeSeasonEpisodes(
        [
          _ep('b', 1, 1),
          _ep('a', 1, 1, tag: 'k', quality: '4K'),
          _ep('a', 1, 1, tag: 'h', quality: 'HD'),
          _ep('a', 1, 1, tag: 's', quality: 'SD'),
        ],
        dedupe: _dedupe,
        accountOrder: ['a', 'b'],
      );

      expect(merged[1]!.single.versions.map((v) => v.title.quality),
          ['4K', 'HD', 'SD', null]);
    });

    test('les stubs (sans saison ni numéro) ne font pas de ligne', () {
      final merged = mergeSeasonEpisodes(
        [_stub('api', 42), _ep('api', 1, 3)],
        dedupe: _dedupe,
      );

      expect(merged.keys, [1]);
      expect(merged[1]!.single.episodeNumber, 3);
    });

    test('saisons et épisodes triés, trous de numérotation conservés', () {
      final merged = mergeSeasonEpisodes(
        [_ep('a', 3, 1), _ep('a', 1, 4), _ep('a', 1, 1), _ep('a', 0, 1)],
        dedupe: _dedupe,
      );

      expect(merged.keys, [0, 1, 3]);
      expect(merged[1]!.map((g) => g.episodeNumber), [1, 4]);
    });

    test('le dédoublonnage de pastille s\'applique PAR ligne', () {
      // Deux entrées d'une même liste à la même pastille : une seule reste,
      // comme pour un film (`dedupeVersions`, clé libellé + liste).
      final merged = mergeSeasonEpisodes(
        [_ep('a', 1, 1, tag: 'x'), _ep('a', 1, 1, tag: 'y'), _ep('b', 1, 1)],
        dedupe: _dedupe,
      );

      expect(_accounts(merged[1]!.single), ['a', 'b']);
    });
  });

  group('seriesStubsToFetch — quels stubs interroger', () {
    test('le premier stub de CHAQUE liste, dans l\'ordre (règle d\'avant)', () {
      final out = seriesStubsToFetch([
        _stub('a', 1),
        _ep('m3u', 1, 1),
        _stub('b', 2),
        _stub('c', 3),
      ]);

      expect(out.map((s) => s.accountId), ['a', 'b', 'c']);
    });

    test('une AUTRE version d\'une même liste est interrogée aussi', () {
      // Mesuré : « The Last of Us (4K) HDR » et « The Last of Us (MULTI) FHD »,
      // deux séries d'une même liste. Avant, la 4K n'était jamais atteinte.
      final out = seriesStubsToFetch([
        _stub('a', 1, quality: 'FHD', languages: ['MULTI']),
        _stub('a', 2, quality: '4K'),
        _stub('a', 3, quality: 'FHD', languages: ['VOSTFR']),
      ]);

      expect(out.map((s) => s.url.split('/').last), ['1', '2', '3']);
    });

    test('même pastille dans la même liste : le second n\'est PAS interrogé', () {
      // « Kingdom » / « Kingdom » : rien ne les distingue, ce sont deux séries
      // (homonymes) ; leurs épisodes se seraient mélangés sous une fiche.
      final out = seriesStubsToFetch([_stub('a', 1), _stub('a', 2)]);

      expect(out.single.url, endsWith('/1'));
    });

    test('un identifiant TMDB contradictoire écarte le second', () {
      // « Charmed » 1998 / 2018 : mesuré chez PREMIUM.
      final out = seriesStubsToFetch([
        _stub('a', 1, quality: 'FHD', tmdb: '1981'),
        _stub('a', 2, quality: 'HD', tmdb: '71663'),
      ]);

      expect(out.single.url, endsWith('/1'));
    });

    test('une année différente écarte le second (une saison rangée comme '
        'une série)', () {
      // « Koh-Lanta (FR) 2026 » / « Koh-Lanta (FR) FHD » : mesuré chez PREMIUM.
      final out = seriesStubsToFetch([
        _stub('a', 1, year: '2026', languages: ['FR'], tmdb: '67997'),
        _stub('a', 2, quality: 'FHD', languages: ['FR'], tmdb: '67997'),
      ]);

      expect(out.single.url, endsWith('/1'));
    });

    test('un autre NOM n\'est interrogé que si TMDB prouve la même série', () {
      final proven = seriesStubsToFetch([
        _stub('a', 1, base: 'Ahsoka', quality: '4K', tmdb: '114461'),
        _stub('a', 2,
            base: 'Star Wars : Ahsoka', quality: 'FHD', tmdb: '114461'),
      ]);
      final unproven = seriesStubsToFetch([
        _stub('a', 1, base: 'Ahsoka', quality: '4K'),
        _stub('a', 2, base: 'Star Wars : Ahsoka', quality: 'FHD'),
      ]);

      expect(proven.length, 2);
      expect(unproven.length, 1);
    });

    test('au plus N stubs par liste', () {
      const qualities = ['4K', 'FHD', 'HD', 'SD'];
      final out = seriesStubsToFetch(
        [
          for (int i = 0; i < qualities.length; i++)
            _stub('a', i + 1, quality: qualities[i]),
          _stub('b', 9),
        ],
        maxPerAccount: 2,
      );

      expect(out.where((s) => s.accountId == 'a').length, 2);
      expect(out.last.accountId, 'b', reason: 'le plafond est PAR liste');
    });

    test('rien n\'est filtré ENTRE listes (règle d\'avant)', () {
      final out = seriesStubsToFetch([
        _stub('a', 1, tmdb: '1'),
        _stub('b', 2, tmdb: '2', year: '1999'),
      ]);

      expect(out.length, 2);
    });

    test('une URL en double ne compte qu\'une fois', () {
      final s = _stub('a', 1);
      expect(seriesStubsToFetch([s, s]).length, 1);
    });

    test('sur des titres RÉELS, analysés par le vrai parseur', () {
      M3uEntry real(int id, String raw, {String? tmdb}) => M3uEntry(
            url: 'http://p.tv/series/u/p/$id',
            accountId: 'premium',
            type: M3uContentType.series,
            tmdbId: tmdb,
            title: TitleMetadata.parse(raw),
          );

      expect(
        seriesStubsToFetch([
          real(1, 'The Last of Us (MULTI) FHD', tmdb: '100088'),
          real(2, 'The Last of Us (4K) HDR', tmdb: '100088'),
        ]).length,
        2,
      );
      expect(
        seriesStubsToFetch([
          real(1, 'Koh-Lanta (FR) 2026', tmdb: '67997'),
          real(2, 'Koh-Lanta (FR) FHD', tmdb: '67997'),
        ]).length,
        1,
      );
      expect(
        seriesStubsToFetch([
          real(1, 'Legends. (MULTI) FHD'),
          real(2, 'Legends (MULTI) FHD'),
        ]).length,
        1,
      );
    });
  });

  group('continuationVersion — l\'épisode suivant prolonge la version en cours',
      () {
    final a4k = _ep('a', 1, 2, tag: 'k', quality: '4K');
    final aHd = _ep('a', 1, 2, tag: 'h', quality: 'HD');
    final bFhd = _ep('b', 1, 2, quality: 'FHD');

    test('même liste ET même pastille d\'abord', () {
      final playing = _ep('a', 1, 1, tag: 'h', quality: 'HD');
      expect(continuationVersion([bFhd, a4k, aHd], playing), aHd);
    });

    test('à défaut, la même liste', () {
      final playing = _ep('a', 1, 1, quality: 'SD');
      expect(continuationVersion([bFhd, a4k, aHd], playing), a4k);
    });

    test('à défaut, la première', () {
      final playing = _ep('c', 1, 1);
      expect(continuationVersion([bFhd, a4k], playing), bFhd);
    });

    test('rien à enchaîner : null', () {
      expect(continuationVersion(const [], _ep('a', 1, 1)), isNull);
    });
  });

  group('requestedEpisodeOf — la tête d\'un groupe n\'est pas une demande', () {
    test('un stub ne demande aucun épisode', () {
      expect(requestedEpisodeOf(_stub('a', 1), [_stub('a', 1)]), isNull);
    });

    test('un épisode seul (feuille d\'action : aucune version) est demandé',
        () {
      expect(requestedEpisodeOf(_ep('a', 2, 5), const []),
          (season: 2, episode: 5));
    });

    test('la tête d\'un groupe M3U (plusieurs épisodes) n\'est PAS demandée',
        () {
      final group = [_ep('a', 1, 1), _ep('a', 1, 2), _ep('a', 2, 1)];
      expect(requestedEpisodeOf(group.first, group), isNull);
    });

    test('groupe mixte (stub + épisodes M3U) : pas une demande non plus', () {
      final group = [_ep('m3u', 3, 5), _stub('api', 7), _ep('m3u', 1, 1)];
      expect(requestedEpisodeOf(group.first, group), isNull);
    });

    test('les versions du MÊME épisode (et des stubs) : demande tenue', () {
      final e = _ep('a', 1, 4);
      expect(requestedEpisodeOf(e, [e, _ep('b', 1, 4), _stub('c', 3)]),
          (season: 1, episode: 4));
    });
  });
}
