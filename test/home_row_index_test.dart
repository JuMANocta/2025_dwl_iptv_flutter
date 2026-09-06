// §favIndex + §resumeIndex (2026-09-06) — La rangée Favoris et les reprises du
// hero partent des favoris / des reprises et retrouvent leurs groupes par un
// index, au lieu de parcourir tout le catalogue. Ce qui se vérifie : même
// résultat que le parcours (clés à trois parties, clés héritées, année,
// type), même ordre (celui du catalogue), même règle « ≥ 95 % = vu ».

import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/services/favorites_service.dart';
import 'package:aetherStream/data/services/watch_progress_service.dart';
import 'package:aetherStream/feature/home/home_row_index.dart';
import 'package:aetherStream/feature/search/m3u_filter.dart';

M3uEntry _entry(String title,
        {String url = '', M3uContentType type = M3uContentType.movie}) =>
    M3uEntry(
      url: url.isEmpty ? 'http://x/${type.name}/${title.hashCode}' : url,
      accountId: 'a',
      type: type,
      title: TitleMetadata.parse(title),
    );

WatchProgress _wp(String url, {required double ratio, required int minutesAgo}) =>
    WatchProgress(
      url: url,
      position: Duration(seconds: (ratio * 6000).round()),
      duration: const Duration(seconds: 6000),
      lastWatched: DateTime(2026, 9, 6, 12).subtract(Duration(minutes: minutesAgo)),
    );

void main() {
  group('favoriteGroupsFor — mêmes favoris que le parcours, même ordre', () {
    final zorro = [_entry('Zorro (1975)')];
    final alien = [_entry('Alien (1979) FHD'), _entry('Alien (1979) 4K')];
    final alien2 = [_entry('Alien (2024)')]; // homonyme, autre année
    final batman = [_entry('Batman (1989)')];
    final groups = [zorro, alien, alien2, batman];
    final byKey = <String, List<List<M3uEntry>>>{};
    for (final g in groups) {
      byKey.putIfAbsent(contentGroupKey(g.first), () => []).add(g);
    }

    test('clé complète (type|clé|année) → le groupe de CETTE année', () {
      final out = favoriteGroupsFor(
        favoriteKeys: {FavoritesService.keyFor(alien2.first)},
        type: M3uContentType.movie,
        byKey: byKey,
        groups: groups,
      );
      expect(out, [alien2]);
    });

    test('clé héritée (sans année) → toutes les années du titre', () {
      final out = favoriteGroupsFor(
        favoriteKeys: {'movie|${contentGroupKey(alien.first)}'},
        type: M3uContentType.movie,
        byKey: byKey,
        groups: groups,
      );
      expect(out, [alien, alien2]);
    });

    test('ordre du CATALOGUE, pas celui des clés', () {
      final out = favoriteGroupsFor(
        favoriteKeys: [
          FavoritesService.keyFor(batman.first),
          FavoritesService.keyFor(zorro.first),
        ],
        type: M3uContentType.movie,
        byKey: byKey,
        groups: groups,
      );
      expect(out, [zorro, batman]);
    });

    test('les clés d un autre type et les inconnues sont ignorées', () {
      final out = favoriteGroupsFor(
        favoriteKeys: {
          'series|${contentGroupKey(zorro.first)}|1975',
          'tv|tf1',
          'movie|inconnu|2000',
          'movie',
        },
        type: M3uContentType.movie,
        byKey: byKey,
        groups: groups,
      );
      expect(out, isEmpty);
    });

    test('équivalence avec isEntryFavorite sur un jeu réel de clés', () {
      final keys = {
        FavoritesService.keyFor(zorro.first),
        'movie|${contentGroupKey(alien.first)}',
      };
      final byScan = [
        for (final g in groups)
          if (keys.contains(FavoritesService.keyFor(g.first)) ||
              keys.contains('movie|${contentGroupKey(g.first)}'))
            g,
      ];
      final byIndex = favoriteGroupsFor(
        favoriteKeys: keys,
        type: M3uContentType.movie,
        byKey: byKey,
        groups: groups,
      );
      expect(byIndex, byScan);
      expect(byIndex, [zorro, alien, alien2]);
    });
  });

  group('resumeGroupsFor — les reprises, les plus récentes d abord', () {
    final film = [
      _entry('Interstellar (2014) FHD', url: 'http://x/fhd'),
      _entry('Interstellar (2014) 4K', url: 'http://x/4k'),
    ];
    final serie = [_entry('Dark (2017)', url: 'http://x/dark')];
    final vieux = [_entry('Heat (1995)', url: 'http://x/heat')];
    final byUrl = <String, List<M3uEntry>>{
      for (final g in [film, serie, vieux])
        for (final e in g) e.url: g,
    };

    test('tri par récence, plafond, URL inconnue ignorée', () {
      final out = resumeGroupsFor(
        progress: [
          _wp('http://x/heat', ratio: 0.3, minutesAgo: 300),
          _wp('http://x/dark', ratio: 0.5, minutesAgo: 10),
          _wp('http://x/fhd', ratio: 0.2, minutesAgo: 60),
          _wp('http://autre/compte', ratio: 0.2, minutesAgo: 1),
        ],
        byUrl: byUrl,
        max: 2,
      );
      expect(out.map((h) => h.group).toList(), [serie, film]);
    });

    test('un titre vu en entier (≥ 95 %) ne se propose pas', () {
      final out = resumeGroupsFor(
        progress: [_wp('http://x/dark', ratio: 0.97, minutesAgo: 1)],
        byUrl: byUrl,
        max: 5,
      );
      expect(out, isEmpty);
    });

    test('plusieurs versions : la progression la PLUS RÉCENTE décide', () {
      // La 4K vient d'être finie, la FHD s'était arrêtée à 20 % avant :
      // comme `getProgressForAny`, c'est la plus récente qui compte → vu.
      final out = resumeGroupsFor(
        progress: [
          _wp('http://x/fhd', ratio: 0.2, minutesAgo: 120),
          _wp('http://x/4k', ratio: 0.99, minutesAgo: 5),
        ],
        byUrl: byUrl,
        max: 5,
      );
      expect(out, isEmpty);

      // Et dans l'autre sens, le groupe apparaît UNE fois, à la date récente.
      final out2 = resumeGroupsFor(
        progress: [
          _wp('http://x/fhd', ratio: 0.99, minutesAgo: 120),
          _wp('http://x/4k', ratio: 0.4, minutesAgo: 5),
        ],
        byUrl: byUrl,
        max: 5,
      );
      expect(out2.length, 1);
      expect(out2.first.group, film);
      expect(out2.first.lastWatched, _wp('', ratio: 0, minutesAgo: 5).lastWatched);
    });

    test('max 0 → rien', () {
      expect(
        resumeGroupsFor(
          progress: [_wp('http://x/dark', ratio: 0.5, minutesAgo: 1)],
          byUrl: byUrl,
          max: 0,
        ),
        isEmpty,
      );
    });
  });
}
