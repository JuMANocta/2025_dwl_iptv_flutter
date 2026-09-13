import 'dart:convert';

import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/services/watch_progress_service.dart';
import 'package:aetherStream/feature/home/home_row_index.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// §heroSeriesResume (2026-09-12) — **Une série en cours doit se retrouver.**
///
/// La progression d'un épisode est enregistrée sous l'URL de l'ÉPISODE, or le
/// catalogue ne contient qu'une entrée par SÉRIE (URL stub
/// `/series/{user}/{pass}/{id}`). Le hero et les cartes résolvent une reprise
/// par l'URL de l'ENTRÉE (`resumeGroupsFor`, « une URL inconnue est ignorée ») :
/// une série en cours n'était donc trouvée nulle part. `saveProgress` écrit
/// désormais AUSSI sous la clé de la série.
///
/// Ce qui se vérifie ici :
///   · les deux clés partent en UNE écriture et UN bump de `version` ;
///   · la fin d'un épisode efface la reprise de l'épisode et LAISSE la série
///     sous le seuil des 95 % — sinon elle disparaîtrait du hero juste après
///     avoir été regardée ;
///   · bout en bout : `resumeGroupsFor` retrouve le groupe de la série.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String stub = 'http://panel/series/user/pass/42';
  const String ep1 = 'http://panel/series/user/pass/1001.mkv';
  const String ep2 = 'http://panel/series/user/pass/1002.mkv';
  const Duration dur = Duration(minutes: 50);

  M3uEntry entry(String url, M3uContentType type, String title) => M3uEntry(
        url: url,
        accountId: 'a',
        type: type,
        title: TitleMetadata.parse(title),
      );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    WatchProgressService.resetForTest();
  });

  group('écriture sous la clé de série', () {
    test('un épisode écrit les DEUX clés, en une seule fois', () async {
      final int v0 = WatchProgressService.version.value;
      await WatchProgressService.saveProgress(
          ep1, const Duration(minutes: 10), dur,
          seriesKey: stub);

      // La position exacte reste celle de l'épisode : c'est elle qui fait
      // reprendre le BON épisode.
      expect(WatchProgressService.getProgress(ep1)!.position,
          const Duration(minutes: 10));
      expect(WatchProgressService.getProgress(stub)!.position,
          const Duration(minutes: 10));
      // §perfBigList — un seul bump : l'accueil ne se recompose qu'une fois.
      // (C'est ce bump qui est observable ici ; le NOMBRE d'écritures disque
      // ne l'est pas depuis le mock de `SharedPreferences`.)
      expect(WatchProgressService.version.value, v0 + 1);

      // Ce qui part au disque porte les deux clés.
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final Map<String, dynamic> stored =
          jsonDecode(prefs.getString('watch_progress_v1')!)
              as Map<String, dynamic>;
      expect(stored.keys.toSet(), <String>{ep1, stub});
    });

    test('sans clé de série (un film), rien ne change', () async {
      await WatchProgressService.saveProgress(
          ep1, const Duration(minutes: 10), dur);
      expect(WatchProgressService.all.map((WatchProgress p) => p.url).toList(),
          <String>[ep1]);
    });

    test('clé de série identique à celle du titre : une seule entrée', () async {
      await WatchProgressService.saveProgress(
          stub, const Duration(minutes: 10), dur,
          seriesKey: stub);
      expect(WatchProgressService.all.length, 1);
      expect(WatchProgressService.getProgress(stub), isNotNull);
    });

    test('à peine lancé (< 5 s) : ni épisode ni série', () async {
      await WatchProgressService.saveProgress(
          ep1, const Duration(seconds: 3), dur,
          seriesKey: stub);
      expect(WatchProgressService.all, isEmpty);
    });

    test('durée trop courte : rien, clé de série comprise', () async {
      await WatchProgressService.saveProgress(
          ep1, const Duration(seconds: 20), const Duration(seconds: 40),
          seriesKey: stub);
      expect(WatchProgressService.all, isEmpty);
    });
  });

  group('fin d\'un épisode', () {
    test('la reprise de l\'épisode disparaît, celle de la série RESTE sous 95 %',
        () async {
      // 49 min sur 50 : l'épisode est « vu en entier » (≥ 95 %).
      await WatchProgressService.saveProgress(
          ep1, const Duration(minutes: 49), dur,
          seriesKey: stub);

      expect(WatchProgressService.getProgress(ep1), isNull);
      final WatchProgress? serie = WatchProgressService.getProgress(stub);
      expect(serie, isNotNull);
      // Le cas qui décide de tout : à 95 % ou plus, le hero l'écarterait —
      // la série disparaîtrait à la seconde où on vient de la regarder.
      expect(serie!.ratio, lessThan(0.95));
      expect(serie.ratio, closeTo(WatchProgressService.seriesMaxRatio, 0.001));
    });

    test('position au-delà de la durée : même règle, série plafonnée', () async {
      await WatchProgressService.saveProgress(
          ep1, const Duration(minutes: 70), dur,
          seriesKey: stub);
      expect(WatchProgressService.getProgress(ep1), isNull);
      expect(WatchProgressService.getProgress(stub)!.ratio,
          closeTo(WatchProgressService.seriesMaxRatio, 0.001));
    });

    test('l\'épisode suivant rend sa vraie place à la série', () async {
      await WatchProgressService.saveProgress(
          ep1, const Duration(minutes: 49), dur,
          seriesKey: stub);
      await WatchProgressService.saveProgress(
          ep2, const Duration(minutes: 5), dur,
          seriesKey: stub);
      expect(WatchProgressService.getProgress(ep2)!.position,
          const Duration(minutes: 5));
      expect(WatchProgressService.getProgress(stub)!.position,
          const Duration(minutes: 5));
    });
  });

  group('bout en bout — le hero retrouve la série', () {
    final List<M3uEntry> serie = <M3uEntry>[
      entry(stub, M3uContentType.series, 'Dark')
    ];
    final List<M3uEntry> film = <M3uEntry>[
      entry('http://panel/movie/user/pass/7.mkv', M3uContentType.movie,
          'Alien (1979)')
    ];
    final Map<String, List<M3uEntry>> byUrl = <String, List<M3uEntry>>{
      stub: serie,
      film.first.url: film,
    };

    test('la clé de l\'épisode SEULE ne donne rien (le défaut d\'origine)',
        () async {
      await WatchProgressService.saveProgress(
          ep1, const Duration(minutes: 10), dur);
      expect(
        resumeGroupsFor(
            progress: WatchProgressService.all, byUrl: byUrl, max: 5),
        isEmpty,
      );
    });

    test('avec la clé de série, le groupe de la série est proposé', () async {
      await WatchProgressService.saveProgress(
          ep1, const Duration(minutes: 10), dur,
          seriesKey: stub);
      final List<ResumeHit> hits = resumeGroupsFor(
          progress: WatchProgressService.all, byUrl: byUrl, max: 5);
      expect(hits.map((ResumeHit h) => h.group).toList(), <List<M3uEntry>>[serie]);
    });

    test('et elle y reste après un épisode terminé', () async {
      await WatchProgressService.saveProgress(
          ep1, const Duration(minutes: 49), dur,
          seriesKey: stub);
      final List<ResumeHit> hits = resumeGroupsFor(
          progress: WatchProgressService.all, byUrl: byUrl, max: 5);
      expect(hits.map((ResumeHit h) => h.group).toList(), <List<M3uEntry>>[serie]);
    });
  });

  group('seriesPositionFor (pure)', () {
    test('en cours d\'épisode : la position réelle', () {
      expect(
          WatchProgressService.seriesPositionFor(
              const Duration(minutes: 10), dur),
          const Duration(minutes: 10));
    });

    test('à la fin : plafonnée sous le seuil du « vu en entier »', () {
      final Duration p = WatchProgressService.seriesPositionFor(dur, dur);
      expect(p.inMilliseconds / dur.inMilliseconds,
          closeTo(WatchProgressService.seriesMaxRatio, 0.001));
    });

    test('durée inconnue : la position telle quelle', () {
      expect(
          WatchProgressService.seriesPositionFor(
              const Duration(minutes: 3), Duration.zero),
          const Duration(minutes: 3));
    });
  });

  group('plafond de la table', () {
    // ⚠️ Pas de test « plafond + 1 sauvegardes » ici : les deux clés y
    // porteraient `now()`, donc les plus RÉCENTES, et survivraient même sans
    // `keepAlso` — 501 réécritures de la table pour ne rien discriminer. C'est
    // l'horloge reculée qui prouve la protection.
    test('keysBeyondCap protège keep ET keepAlso', () {
      WatchProgress wp(String url, int minutesAgo) => WatchProgress(
            url: url,
            position: const Duration(minutes: 10),
            duration: dur,
            lastWatched:
                DateTime(2026, 9, 12).subtract(Duration(minutes: minutesAgo)),
          );
      final Map<String, WatchProgress> m = <String, WatchProgress>{
        'ep': wp('ep', 100), // horloge reculée : elles PARAISSENT anciennes
        'serie': wp('serie', 100),
        'autre': wp('autre', 50),
      };
      expect(
          WatchProgressService.keysBeyondCap(m, 2,
              keep: 'ep', keepAlso: 'serie'),
          <String>['autre']);
    });
  });
}
