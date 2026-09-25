// §22.1 + §22.5 (2026-09-25) — Ce que devient une réponse `get_series_info`.
//
// La traduction JSON → épisodes vivait dans `XtreamApiService.fetchEpisodes`,
// derrière un appel réseau : rien ne la testait. Sortie en fonction pure
// (`episodesFromSeriesInfo`), elle est tenue ici sur deux points :
//
// - §22.5 : l'URL de lecture et de téléchargement a la forme que le panel écrit
//   lui-même dans son `get.php` — `/series/{user}/{pass}/{id}.{ext}` ;
// - §22.1 : les étiquettes de la série (4K, VOSTFR…) passent sur ses épisodes.
//   Sans elles, deux séries d'une même liste (« Game of Thrones (4K) HDR » et
//   « … (MULTI) FHD ») donnaient des épisodes à la même pastille, et la fiche
//   n'en gardait qu'un.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/services/xtream_api_service.dart';
import 'package:aetherStream/feature/search/details_versions.dart';
import 'package:aetherStream/feature/search/version_dedup.dart';
import 'package:aetherStream/feature/search/xtream_catalog_parser.dart';

const _creds = (host: 'http://panel.tv:8080', username: 'jean', password: 'motdepasse');

Map<String, dynamic> _info({
  String name = 'Game of Thrones (MULTI) FHD',
  Object? episodes,
  String? tmdb,
}) =>
    <String, dynamic>{
      'info': <String, dynamic>{
        'name': name,
        'cover': 'http://img/cover.jpg',
        if (tmdb != null) 'tmdb': tmdb,
      },
      'episodes': episodes ??
          <String, dynamic>{
            '1': [
              {'id': '5001', 'episode_num': 1, 'container_extension': 'mkv'},
              {'id': '5002', 'episode_num': '2', 'container_extension': 'mp4'},
            ],
            '2': [
              {'id': 6001, 'episode_num': 1},
            ],
          },
    };

void main() {
  group('xtreamEpisodeUrl — §22.5, la forme que le panel attend', () {
    test('/series/{user}/{pass}/{id}.{ext}', () {
      expect(
        xtreamEpisodeUrl(
          host: 'http://panel.tv:8080',
          username: 'jean',
          password: 'motdepasse',
          episodeId: 5001,
          extension: 'mkv',
        ),
        'http://panel.tv:8080/series/jean/motdepasse/5001.mkv',
      );
    });

    test('extension absente : mp4, comme avant', () {
      expect(
        xtreamEpisodeUrl(
          host: 'http://h',
          username: 'u',
          password: 'p',
          episodeId: '7',
        ),
        'http://h/series/u/p/7.mp4',
      );
    });

    test('identifiants encodés comme un segment de chemin', () {
      // Un « / » ou un « @ » brut dans un mot de passe casserait le chemin.
      expect(
        xtreamEpisodeUrl(
          host: 'http://h',
          username: 'a b',
          password: 'x/y@z',
          episodeId: 1,
          extension: 'ts',
        ),
        'http://h/series/a%20b/x%2Fy%40z/1.ts',
      );
    });

    test('l\'extension du panel passe telle quelle (casse comprise)', () {
      // Mesuré chez xenoIptv : « MP4 », « mP4 » — c'est le nom du fichier sur
      // le panel, pas une faute à corriger.
      expect(
        xtreamEpisodeUrl(
          host: 'http://h',
          username: 'u',
          password: 'p',
          episodeId: 1,
          extension: 'MP4',
        ),
        endsWith('/1.MP4'),
      );
    });
  });

  group('films du catalogue — §22.5, la même forme côté `/movie/`', () {
    // Le parseur du catalogue n'est pas modifié ici : ce test FIGE ce qu'il
    // écrit, pour qu'un changement d'URL de film (clé des favoris, des
    // reprises et des téléchargements) ne passe jamais inaperçu.
    test('/movie/{user}/{pass}/{id}.{container_extension}, mp4 à défaut',
        () async {
      final Directory dir = Directory.systemTemp.createTempSync('as_225_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final File f = File('${dir.path}/playlist_x.json')
        ..writeAsStringSync(jsonEncode(<String, dynamic>{
          'host': 'http://panel.tv:8080',
          'user': 'jean',
          'pass': 'mot de/passe',
          'live': const <Object>[],
          'vod': [
            {'stream_id': 281995, 'name': 'Mutiny (2026)', 'container_extension': 'mkv'},
            {'stream_id': 12, 'name': 'Sans extension (2020)'},
          ],
          'series': [
            {'series_id': 77, 'name': 'Dark (2017)'},
          ],
        }));
      final films = <M3uEntry>[], series = <M3uEntry>[], tv = <M3uEntry>[];

      await XtreamCatalogParser.parseFile(f.path, films, series, tv,
          accountId: 'acc');

      expect(films.map((e) => e.url), [
        'http://panel.tv:8080/movie/jean/mot%20de%2Fpasse/281995.mkv',
        'http://panel.tv:8080/movie/jean/mot%20de%2Fpasse/12.mp4',
      ]);
      // Le stub de série, lui, n'a PAS d'extension : ce n'est pas un flux.
      expect(series.single.url, 'http://panel.tv:8080/series/jean/mot%20de%2Fpasse/77');
    });
  });

  group('episodesFromSeriesInfo — la réponse du panel en épisodes', () {
    test('saison lue sur la CLÉ, numéro sur `episode_num`, URL du panel', () {
      final eps = episodesFromSeriesInfo(_info(), creds: _creds, accountId: 'acc');

      expect(eps.map((e) => e.title.seasonEpisodeLabel),
          ['S01 E01', 'S01 E02', 'S02 E01']);
      expect(eps.map((e) => e.url), [
        'http://panel.tv:8080/series/jean/motdepasse/5001.mkv',
        'http://panel.tv:8080/series/jean/motdepasse/5002.mp4',
        'http://panel.tv:8080/series/jean/motdepasse/6001.mp4',
      ]);
      expect(eps.every((e) => e.accountId == 'acc'), isTrue);
      expect(eps.every((e) => e.type == M3uContentType.series), isTrue);
    });

    test('ce qui ne se lit pas est sauté, pas inventé', () {
      final eps = episodesFromSeriesInfo(
        _info(episodes: <String, dynamic>{
          'speciaux': [
            {'id': 1, 'episode_num': 1},
          ],
          '1': [
            {'episode_num': 1}, // pas d'identifiant
            {'id': 2, 'episode_num': 'x'}, // numéro illisible
            'pas un épisode',
            {'id': 3, 'episode_num': 3},
          ],
          '2': 'pas une liste',
        }),
        creds: _creds,
        accountId: 'acc',
      );

      expect(eps.single.url, endsWith('/3.mp4'));
    });

    test('`episodes` qui n\'est pas une Map : aucun épisode', () {
      expect(
        episodesFromSeriesInfo(_info(episodes: const <Object>[]),
            creds: _creds, accountId: 'acc'),
        isEmpty,
      );
    });

    test('§22.1 — les étiquettes du STUB passent sur chaque épisode', () {
      final stub = TitleMetadata.parse('Game of Thrones (4K) HDR');
      final eps = episodesFromSeriesInfo(
        _info(name: 'Game of Thrones'),
        creds: _creds,
        accountId: 'acc',
        seriesTitle: stub,
      );

      expect(eps.first.title.quality, stub.quality);
      expect(eps.first.title.quality, isNotNull);
      expect(eps.first.title.languages, stub.languages);
      expect(eps.first.title.versionLabel, stub.versionLabel);
      expect(eps.first.title.providerTag, stub.providerTag);
    });

    test('sans stub, les étiquettes du nom rendu par le panel', () {
      final meta = TitleMetadata.parse('Game of Thrones (MULTI) FHD');
      final eps = episodesFromSeriesInfo(_info(), creds: _creds, accountId: 'acc');

      expect(eps.first.title.quality, meta.quality);
      expect(eps.first.title.languages, meta.languages);
    });

    test('⛔ nom, clé de groupe et année restent ceux du panel (§favSeries)', () {
      final panel = TitleMetadata.parse('Dark (2017)');
      final eps = episodesFromSeriesInfo(
        _info(name: 'Dark (2017)'),
        creds: _creds,
        accountId: 'acc',
        seriesTitle: TitleMetadata.parse('|FR-4K| Dark Autre Nom (2019)'),
      );

      expect(eps.first.title.baseTitle, panel.baseTitle);
      expect(eps.first.title.groupKey, panel.groupKey);
      expect(eps.first.title.year, panel.year);
    });

    test('identifiant TMDB de la série propagé, titre d\'épisode nettoyé', () {
      final eps = episodesFromSeriesInfo(
        _info(
          name: 'Breaking Bad',
          tmdb: '1396',
          episodes: <String, dynamic>{
            '1': [
              {
                'id': 1,
                'episode_num': 1,
                'title': 'Breaking Bad S01E01 - Pilot',
                'info': {'plot': ' Walter. ', 'rating': '8.2', 'air_date': '2008-01-20'},
              },
              {'id': 2, 'episode_num': 2, 'title': 'Breaking Bad'},
            ],
          },
        ),
        creds: _creds,
        accountId: 'acc',
      );

      expect(eps.first.tmdbId, '1396');
      expect(eps.first.episodeTitle, 'Pilot');
      expect(eps.first.plot, 'Walter.');
      expect(eps.first.rating, 8.2);
      expect(eps.first.releaseDate, '2008-01-20');
      expect(eps.last.episodeTitle, isNull,
          reason: 'le nom de la série n\'est pas un titre d\'épisode');
    });

    test('§22.1 — deux séries d\'une même liste gardent chacune leur pastille',
        () {
      // Le défaut, bout à bout : les deux stubs sont interrogés, leurs
      // épisodes réunis, puis dédoublonnés par pastille + liste.
      List<M3uEntry> fetch(String raw, String id) => episodesFromSeriesInfo(
            _info(
              name: 'Game of Thrones',
              episodes: <String, dynamic>{
                '1': [
                  {'id': id, 'episode_num': 1, 'container_extension': 'mkv'},
                ],
              },
            ),
            creds: _creds,
            accountId: 'premium',
            seriesTitle: TitleMetadata.parse(raw),
          );
      List<M3uEntry> label(List<M3uEntry> v) => dedupeVersions(
            v,
            (e, _) => '${e.title.quality ?? 'FHD'} · '
                '${e.title.languages.isEmpty ? '' : e.title.languages.first}',
          );

      final merged = mergeSeasonEpisodes(
        [
          ...fetch('Game of Thrones (MULTI) FHD', '11'),
          ...fetch('Game of Thrones (4K) HDR', '22'),
        ],
        dedupe: label,
      );

      expect(merged[1]!.single.versions.length, 2);
    });
  });
}
