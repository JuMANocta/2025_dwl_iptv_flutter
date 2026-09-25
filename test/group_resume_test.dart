// R52 (recette AVD du 2026-09-25) — La feuille d'appui long d'une série
// annonçait « Reprendre à 00:34 », reprise née sur la liste TestTV, et lançait
// la version de la liste VOD : la position d'un abonnement appliquée au flux
// d'un autre. La fiche reprend sur la bonne version depuis §22.1 ; ces tests
// tiennent la règle partagée, `groupResumeOf`, et le périmètre d'un « même
// objet » (`sameItemVersions`).
//
// Sincérité : rendre `entry` = première version fait tomber « la reprise se
// relance sur SA liste » ; retirer le filtre saison/épisode fait tomber « un
// épisode ne reprend jamais un autre épisode ».

import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/services/watch_progress_service.dart'
    show WatchProgress;
import 'package:aetherStream/feature/player/group_resume.dart';

M3uEntry _episode(String account, {int season = 1, int episode = 2}) =>
    M3uEntry(
      url: 'http://$account.tv/series/u/p/$account$season$episode.mkv',
      accountId: account,
      type: M3uContentType.series,
      title: TitleMetadata(
        rawTitle: 'Dark S0${season}E0$episode',
        baseTitle: 'Dark',
        seasonNumber: season,
        episodeNumber: episode,
      ),
    );

M3uEntry _stub(String account) => M3uEntry(
      url: 'http://$account.tv/series/u/p/42',
      accountId: account,
      type: M3uContentType.series,
      title: const TitleMetadata(rawTitle: 'Dark', baseTitle: 'Dark'),
    );

M3uEntry _movie(String account, String quality) => M3uEntry(
      url: 'http://$account.tv/movie/u/p/$quality.mkv',
      accountId: account,
      type: M3uContentType.movie,
      title: TitleMetadata(
          rawTitle: 'Dune $quality', baseTitle: 'Dune', quality: quality),
    );

WatchProgress _at(String url, int seconds, {int minutesAgo = 0}) =>
    WatchProgress(
      url: url,
      position: Duration(seconds: seconds),
      duration: const Duration(minutes: 50),
      lastWatched:
          DateTime(2026, 9, 25, 20).subtract(Duration(minutes: minutesAgo)),
    );

void main() {
  group('groupResumeOf', () {
    test('R52 : la reprise se relance sur la version qui la PORTE', () {
      final vod = _episode('vod');
      final testTv = _episode('testtv');
      final progress = {testTv.url: _at(testTv.url, 34)};
      // L'ordre des versions met VOD en tête : c'est elle que la feuille
      // lançait.
      final r = groupResumeOf([vod, testTv], progressOf: (u) => progress[u]);
      expect(r, isNotNull);
      expect(r!.entry, same(testTv));
      expect(r.progress.position, const Duration(seconds: 34));
    });

    test('deux reprises : la plus RÉCENTE gagne, avec sa version', () {
      final a = _movie('a', 'FHD');
      final b = _movie('b', 'HD');
      final progress = {
        a.url: _at(a.url, 600, minutesAgo: 60),
        b.url: _at(b.url, 1200, minutesAgo: 5),
      };
      final r = groupResumeOf([a, b], progressOf: (u) => progress[u]);
      expect(r!.entry, same(b));
      expect(r.progress.position, const Duration(seconds: 1200));
    });

    test('reprise portée par le stub de la série : aucune version au hasard',
        () {
      // §heroSeriesResume — la clé de série dit « regardée récemment », pas
      // quel épisode : seule la fiche sait le retrouver.
      final stub = _stub('xtream');
      final m3u = _episode('m3u');
      final progress = {stub.url: _at(stub.url, 300)};
      final r = groupResumeOf([m3u, stub], progressOf: (u) => progress[u]);
      expect(r, isNotNull);
      expect(r!.entry, isNull);
    });

    test('à peine commencée (≤ 5 s) ou absente : rien à reprendre', () {
      final a = _movie('a', 'FHD');
      expect(
          groupResumeOf([a], progressOf: (u) => _at(u, 5)), isNull);
      expect(groupResumeOf([a], progressOf: (_) => null), isNull);
      expect(groupResumeOf(const <M3uEntry>[], progressOf: (_) => null),
          isNull);
    });
  });

  group('sameItemVersions', () {
    test('un épisode ne garde que le même épisode, l\'entrée en tête', () {
      final e2 = _episode('a');
      final e2b = _episode('b');
      final e3 = _episode('a', episode: 3);
      final stub = _stub('x');
      final v = sameItemVersions(e2, [e3, stub, e2b, e2]);
      expect(v, [e2, e2b]);
    });

    test('un film garde toutes ses versions, sans doublon', () {
      final fhd = _movie('a', 'FHD');
      final hd = _movie('b', 'HD');
      expect(sameItemVersions(hd, [fhd, hd]), [hd, fhd]);
    });
  });
}
