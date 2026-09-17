import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/data/services/online_subtitles_service.dart';

/// Lot 11 — Les parties PURES de la recherche de sous-titres en ligne :
/// l'adresse construite, la réponse analysée, et le contexte de recherche tiré
/// de ce que le lecteur sait du contenu.
///
/// Le piège tenu en premier est de sécurité : la clé du fournisseur voyage
/// dans la query (la seule forme que l'API accepte), et le journal de l'app
/// est servi sur le LAN (§tvLogs). `redactUrl` ne masquait pas un `key=` sur
/// un hôte public — c'était la forme exacte de la fuite R35 ; le puits a été
/// bouché depuis (cf. `xtream_redact_invariant_test.dart`, groupe §subOnline).
/// La règle de la source tient malgré tout : cette URL ne se construit qu'ici
/// et ne se journalise jamais.
void main() {
  group('lot 11 — adresse de recherche', () {
    test('la clé part en query, sous le nom que l\'API attend', () {
      final uri = OnlineSubtitlesService.searchUri(
        tmdbId: 286217,
        languages: 'fr,en',
        apiKey: 'SECRET',
      );
      expect(uri.host, 'sub.wyzie.io');
      expect(uri.path, '/search');
      expect(uri.queryParameters['id'], '286217');
      expect(uri.queryParameters['language'], 'fr,en');
      expect(uri.queryParameters['format'], 'srt');
      expect(uri.queryParameters['key'], 'SECRET');
    });

    test('le transport est https, jamais http', () {
      // D1B-17 — `network_security_config.xml` ne couvre pas le trafic Dart :
      // l'URL en dur EST la garantie. En clair, la clé partirait en clair.
      final uri = OnlineSubtitlesService.searchUri(
          tmdbId: 1, languages: 'fr', apiKey: 'K');
      expect(uri.scheme, 'https');
    });

    test('saison et épisode n\'apparaissent que pour une série', () {
      final film = OnlineSubtitlesService.searchUri(
          tmdbId: 1, languages: 'fr', apiKey: 'K');
      expect(film.queryParameters.containsKey('season'), isFalse);
      expect(film.queryParameters.containsKey('episode'), isFalse);
      final serie = OnlineSubtitlesService.searchUri(
          tmdbId: 1, languages: 'fr', apiKey: 'K', season: 2, episode: 7);
      expect(serie.queryParameters['season'], '2');
      expect(serie.queryParameters['episode'], '7');
    });

    test('une liste de langues vide ne filtre rien', () {
      final uri = OnlineSubtitlesService.searchUri(
          tmdbId: 1, languages: '', apiKey: 'K');
      expect(uri.queryParameters.containsKey('language'), isFalse);
    });
  });

  group('lot 11 — analyse de la réponse', () {
    test('un tableau d\'objets devient une liste de sous-titres', () {
      final r = OnlineSubtitlesService.parseResults([
        {
          'id': 'abc',
          'url': 'https://x/1.srt',
          'language': 'fr',
          'display': 'French',
          'format': 'srt',
          'source': 'subdl',
          'release': '1080p.WEB-DL',
          'isHearingImpaired': true,
        }
      ]);
      expect(r, hasLength(1));
      expect(r.single.id, 'abc');
      expect(r.single.language, 'fr');
      expect(r.single.display, 'French');
      expect(r.single.source, 'subdl');
      expect(r.single.release, '1080p.WEB-DL');
      expect(r.single.hearingImpaired, isTrue);
    });

    test('un objet sans url est ignoré, les autres survivent', () {
      // Tolérance : une seule entrée abîmée ne doit pas vider la liste.
      final r = OnlineSubtitlesService.parseResults([
        {'id': 'x', 'language': 'fr'},
        {'url': 'https://x/2.srt', 'language': 'en'},
      ]);
      expect(r, hasLength(1));
      expect(r.single.language, 'en');
    });

    test('les champs absents prennent un repli, sans lever', () {
      final r = OnlineSubtitlesService.parseResults([
        {'url': 'https://x/3.srt'}
      ]);
      expect(r.single.format, 'srt');
      expect(r.single.hearingImpaired, isFalse);
      expect(r.single.release, isNull);
      expect(r.single.id, isNotEmpty);
    });

    test('un format inconnu retombe sur srt, vtt est conservé', () {
      OnlineSubtitle one(String f) => OnlineSubtitlesService.parseResults([
            {'url': 'https://x/a', 'format': f}
          ]).single;
      expect(one('ass').format, 'srt');
      expect(one('VTT').format, 'vtt');
    });

    test('une réponse inattendue rend une liste vide, jamais une exception', () {
      expect(OnlineSubtitlesService.parseResults(null), isEmpty);
      expect(OnlineSubtitlesService.parseResults('non'), isEmpty);
      expect(OnlineSubtitlesService.parseResults(<String, Object>{}), isEmpty);
    });
  });

  group('lot 11 — numéro d\'épisode tiré du badge', () {
    test('les formes réelles des listes sont reconnues', () {
      expect(episodeNumberFromTag('S01 E04'), 4);
      expect(episodeNumberFromTag('S1E4'), 4);
      expect(episodeNumberFromTag('1x04'), 4);
      expect(episodeNumberFromTag('S02 E12'), 12);
    });

    test('un badge absent ou muet ne bloque pas la recherche', () {
      expect(episodeNumberFromTag(null), isNull);
      expect(episodeNumberFromTag('Saison 1'), isNull);
      expect(episodeNumberFromTag(''), isNull);
    });
  });

  group('lot 11 — contexte de recherche', () {
    test('pour une série, c\'est la SÉRIE qu\'on fait reconnaître', () {
      // Le piège : chercher « Les Enfants de l'hiver » ne trouve aucune fiche
      // TMDB ; c'est le nom de la série qui en porte une.
      final c = subtitleSearchContextFor(
        title: 'Les Enfants de l\'hiver',
        seriesName: 'Le Trône de fer',
        episodeTag: 'S01 E04',
        seasonNumber: 1,
      )!;
      expect(c.query, 'Le Trône de fer');
      expect(c.isTv, isTrue);
      expect(c.season, 1);
      expect(c.episode, 4);
    });

    test('pour un film, le titre, et aucune saison', () {
      final c = subtitleSearchContextFor(title: 'Le Martien')!;
      expect(c.query, 'Le Martien');
      expect(c.isTv, isFalse);
      expect(c.season, isNull);
      expect(c.episode, isNull);
    });

    test('une saison traînante n\'est pas reprise sur un film', () {
      // Sincérité : sans la garde `isTv`, ce contexte partirait avec une
      // saison et l'API ne rendrait rien.
      final c = subtitleSearchContextFor(
          title: 'Le Martien', episodeTag: 'S01 E04', seasonNumber: 1)!;
      expect(c.season, isNull);
      expect(c.episode, isNull);
    });

    test('sans titre exploitable, pas de recherche du tout', () {
      expect(subtitleSearchContextFor(title: '   '), isNull);
      expect(subtitleSearchContextFor(title: '', seriesName: '  '), isNull);
    });
  });
}
