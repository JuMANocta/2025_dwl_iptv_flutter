// R44 — Le noyau partagé « URL → identifiant de série ».
//
// Ce que ces tests tiennent : la règle qui décide, à l'accueil ET sur la fiche,
// qu'une URL n'est pas un endpoint de stream mais le marqueur d'une série
// entière. Elle était écrite deux fois (§tourFix) ; ces tests sont ce qui
// empêche la copie unique de dériver à son tour.
//
// Sincérité : retirer le test d'extension fait tomber « un épisode `.mkv` »,
// retirer le test du premier segment fait tomber « un film », retirer
// `int.tryParse` fait tomber « un dernier segment qui n'est pas un nombre ».

import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/feature/search/series_stub.dart';

void main() {
  group('seriesIdFromUrl — ce que le catalogue Xtream porte vraiment', () {
    test('un stub `/series/{u}/{p}/{id}` rend son identifiant', () {
      expect(seriesIdFromUrl('http://host:8080/series/user/pass/123'), 123);
    });

    test('le port, le schéma et le sous-domaine ne changent rien', () {
      expect(seriesIdFromUrl('https://tv.example.org/series/u/p/98765'), 98765);
    });

    test('`SERIES` en capitales est le même segment', () {
      expect(seriesIdFromUrl('http://host/SERIES/u/p/7'), 7);
    });

    test('un préfixe de base avant `series` n\'est PAS reconnu', () {
      // Le premier segment doit être `series` : `/iptv/series/u/p/1` porte
      // `iptv` en tête. C'est la règle historique des deux copies, gardée
      // telle quelle — la changer changerait ce qu'est un stub pour toute
      // l'application, donc le comportement de l'accueil ET de la fiche.
      expect(seriesIdFromUrl('http://host/iptv/series/u/p/1'), isNull);
    });

    test('un identifiant très long reste un entier', () {
      expect(seriesIdFromUrl('http://host/series/u/p/2147483647'), 2147483647);
    });
  });

  group('seriesIdFromUrl — ce qui est une URL d\'épisode, donc jouable', () {
    test('une extension disqualifie : c\'est un vrai flux', () {
      expect(seriesIdFromUrl('http://host/series/u/p/123.mp4'), isNull);
      expect(seriesIdFromUrl('http://host/series/u/p/456.mkv'), isNull);
      expect(seriesIdFromUrl('http://host/series/u/p/789.ts'), isNull);
    });

    test('un film n\'est jamais un stub de série', () {
      expect(seriesIdFromUrl('http://host/movie/u/p/123'), isNull);
    });

    test('une chaîne en direct non plus', () {
      expect(seriesIdFromUrl('http://host/live/u/p/42.m3u8'), isNull);
      expect(seriesIdFromUrl('http://host/u/p/42'), isNull);
    });
  });

  group('seriesIdFromUrl — les formes qu\'on ne sait pas lire', () {
    test('moins de quatre segments : pas d\'identifiant extractible', () {
      expect(seriesIdFromUrl('http://host/series/u/123'), isNull);
      expect(seriesIdFromUrl('http://host/series/123'), isNull);
      expect(seriesIdFromUrl('http://host/series'), isNull);
    });

    test('un dernier segment qui n\'est pas un nombre', () {
      expect(seriesIdFromUrl('http://host/series/u/p/breaking-bad'), isNull);
      expect(seriesIdFromUrl('http://host/series/u/p/'), isNull);
    });

    test('une URL vide ou illisible ne lève pas, elle rend null', () {
      expect(seriesIdFromUrl(''), isNull);
      expect(seriesIdFromUrl('pas une url du tout'), isNull);
      expect(seriesIdFromUrl('http://[oops'), isNull);
    });
  });

  group('isSeriesStubUrl — même verdict, sans l\'identifiant', () {
    test('rend exactement `seriesIdFromUrl(...) != null`', () {
      const urls = <String>[
        'http://host/series/u/p/123',
        'http://host/series/u/p/123.mkv',
        'http://host/movie/u/p/123',
        'http://host/series/u/p/abc',
        '',
        'http://host/SERIES/u/p/9',
      ];
      for (final url in urls) {
        expect(
          isSeriesStubUrl(url),
          seriesIdFromUrl(url) != null,
          reason: 'URL « $url »',
        );
      }
    });
  });
}
