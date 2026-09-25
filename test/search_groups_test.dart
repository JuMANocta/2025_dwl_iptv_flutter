// §searchAllNames (2026-09-25) — « Si je tape le nom du film en anglais, on le
// trouve dans la recherche » : un titre RÉUNI (doublons d'un même film sous
// une seule clé, `contentGroupKey` → `TmdbGroupAliasService.canonical`) se
// trouve par le nom de N'IMPORTE LAQUELLE de ses versions, et la recherche
// rend la vignette réunie ENTIÈRE — une carte, pas deux, pas zéro, pas une
// carte tronquée à la seule version dont le nom correspond.
//
// Sincérité : rendre `complete` inopérant (ne garder que les versions
// trouvées) fait tomber « groupe entier » ; retirer la fusion (table vide) fait
// apparaître le témoin « sans fusion, une carte par titre ».

import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/services/tmdb_group_alias_service.dart';
import 'package:aetherStream/feature/home/search_groups.dart';

M3uEntry _movie(String url, String title, {String? tmdbId, String? year}) =>
    M3uEntry(
      url: url,
      accountId: url.split('/')[2],
      type: M3uContentType.movie,
      tmdbId: tmdbId,
      title: TitleMetadata(
        rawTitle: year == null ? title : '$title ($year)',
        baseTitle: title,
        groupKey: TitleMetadata.computeGroupKey(title),
        year: year,
      ),
    );

M3uEntry _channel(String url, String name) => M3uEntry(
      url: url,
      accountId: 'live',
      type: M3uContentType.tv,
      title: TitleMetadata(
        rawTitle: name,
        baseTitle: name,
        groupKey: TitleMetadata.computeGroupKey(name),
      ),
    );

void main() {
  // Le même film sur trois listes, sous trois noms (même identifiant TMDB,
  // même année), plus un AUTRE film dont le titre contient « Scorpion ».
  final M3uEntry fr = _movie('http://vod/1.mkv', 'Le Roi Scorpion 2', tmdbId: '10204', year: '2008');
  final M3uEntry other = _movie('http://vod/2.mkv', 'Scorpion', year: '1986');
  final M3uEntry en = _movie('http://testtv/3.mkv', 'Scorpion King 2', tmdbId: '10204', year: '2008');
  final M3uEntry pt = _movie('http://xeno/4.mkv', 'O Escorpião Rei 2', tmdbId: '10204', year: '2008');
  final List<M3uEntry> catalog = <M3uEntry>[fr, other, en, pt];

  setUp(() => TmdbGroupAliasService.rebuild(catalog));
  tearDown(TmdbGroupAliasService.resetForTest);

  group('homeSearchGroups — un titre réuni, par n\'importe lequel de ses noms', () {
    test('le nom ANGLAIS trouve la vignette réunie, entière', () {
      final List<List<M3uEntry>> hits = homeSearchGroups(catalog, 'scorpion king', M3uContentType.movie);
      expect(hits, hasLength(1), reason: 'une carte, pas deux, pas zéro');
      expect(hits.single, <M3uEntry>[fr, en, pt],
          reason: 'toutes les versions, dans l\'ordre du catalogue (même tête que l\'accueil)');
    });

    test('le nom FRANÇAIS aussi', () {
      expect(homeSearchGroups(catalog, 'roi scorpion', M3uContentType.movie),
          <List<M3uEntry>>[<M3uEntry>[fr, en, pt]]);
    });

    test('le nom PORTUGAIS, tapé sans accent', () {
      expect(homeSearchGroups(catalog, 'escorpiao', M3uContentType.movie),
          <List<M3uEntry>>[<M3uEntry>[fr, en, pt]]);
    });

    test('un mot commun : le titre réuni reste UNE carte, à côté de l\'autre film', () {
      final List<List<M3uEntry>> hits = homeSearchGroups(catalog, 'scorpion', M3uContentType.movie);
      expect(hits, hasLength(2));
      expect(hits.first, <M3uEntry>[fr, en, pt]);
      expect(hits.last, <M3uEntry>[other]);
    });

    test('rien ne correspond : zéro carte', () {
      expect(homeSearchGroups(catalog, 'zzzz', M3uContentType.movie), isEmpty);
    });

    test('témoin : sans fusion, chaque nom reste sa propre carte', () {
      TmdbGroupAliasService.resetForTest();
      expect(homeSearchGroups(catalog, 'scorpion king', M3uContentType.movie),
          <List<M3uEntry>>[<M3uEntry>[en]]);
    });
  });

  group('searchHitGroups', () {
    test('complete: false garde l\'ancien comportement (versions trouvées seules)', () {
      final List<List<M3uEntry>> hits = searchHitGroups(
        catalog,
        matches: (M3uEntry e) => e.displayName.toLowerCase().contains('king'),
        keyOf: (M3uEntry e) => 'k',
        complete: false,
      );
      expect(hits, <List<M3uEntry>>[<M3uEntry>[en]]);
    });

    test('l\'ordre des groupes est celui de la première version trouvée', () {
      final List<List<M3uEntry>> hits = searchHitGroups(
        catalog,
        matches: (M3uEntry e) => e == pt || e == other,
        keyOf: (M3uEntry e) => e == other ? 'b' : 'a',
      );
      expect(hits, <List<M3uEntry>>[<M3uEntry>[other], <M3uEntry>[fr, en, pt]]);
    });

    test('chaînes : inchangées (pas de complétion, dédoublonnage de qualité)', () {
      final M3uEntry tf1 = _channel('http://live/1', 'TF1');
      final M3uEntry tf1hd = _channel('http://live/2', 'TF1 HD');
      final M3uEntry m6 = _channel('http://live/3', 'M6');
      final List<List<M3uEntry>> hits = homeSearchGroups(<M3uEntry>[tf1, m6, tf1hd], 'tf1', M3uContentType.tv);
      expect(hits.expand((List<M3uEntry> g) => g), isNot(contains(m6)));
      expect(hits, isNotEmpty);
    });
  });
}
