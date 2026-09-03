import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/services/tmdb_group_alias_service.dart';

/// §tmdbMerge — Réunir les copies d'un même film écrites dans deux langues.
///
/// Le cas d'origine, mesuré sur le corpus du 2026-08-30 : `100 METERS` et
/// `100 mètres` portent tous deux l'identifiant TMDB 1295026. Aucune
/// normalisation de chaîne ne peut les rapprocher — `metres` et `meters` ne se
/// ressemblent pas — mais l'identifiant, lui, l'affirme.
M3uEntry _e(String name, {String? tmdb, M3uContentType type = M3uContentType.movie}) =>
    M3uEntry(
      url: 'http://x/$name',
      type: type,
      title: TitleMetadata.parse(name),
      accountId: 'acc',
      tmdbId: tmdb,
    );

void main() {
  setUp(TmdbGroupAliasService.resetForTest);
  tearDown(TmdbGroupAliasService.resetForTest);

  group('tmdbMerge', () {
    test('deux titres, deux langues, un identifiant → une seule cle', () {
      final fr = _e('100 metres (2025)', tmdb: '1295026');
      final en = _e('100 METERS (2025)', tmdb: '1295026');
      expect(fr.title.groupKey, isNot(en.title.groupKey),
          reason: 'sans fusion, ce sont bien deux cles distinctes');

      TmdbGroupAliasService.rebuild([fr, en, en]); // EN majoritaire
      expect(TmdbGroupAliasService.canonical(fr.title.groupKey),
          TmdbGroupAliasService.canonical(en.title.groupKey));
    });

    test('la canonique est la forme la PLUS REPANDUE', () {
      final rare = _e('Kis Uykusu (2014)', tmdb: '265169');
      final common = _e('Winter Sleep (2014)', tmdb: '265169');
      TmdbGroupAliasService.rebuild([rare, common, common, common]);
      expect(TmdbGroupAliasService.canonical(rare.title.groupKey),
          common.title.groupKey);
    });

    test('a egalite, la canonique est STABLE (ordre alphabetique)', () {
      // Sans ce depart, la table changerait d une session a l autre et les
      // cles de favoris deriveraient a chaque demarrage.
      final a = _e('Alpha (2020)', tmdb: '42');
      final b = _e('Beta (2020)', tmdb: '42');
      TmdbGroupAliasService.rebuild([a, b]);
      final first = TmdbGroupAliasService.canonical(b.title.groupKey);
      TmdbGroupAliasService.rebuild([b, a]); // ordre d entree inverse
      expect(TmdbGroupAliasService.canonical(b.title.groupKey), first);
    });

    test('garde-fou : deux ANNEES differentes -> on ne fusionne pas', () {
      // Un identifiant fournisseur est de la donnee saisie par un tiers. Une
      // coquille fusionnerait deux films differents, sans que l utilisateur
      // puisse comprendre pourquoi.
      final v1 = _e('Le Film (2018)', tmdb: '999');
      final v2 = _e('Autre Film (2021)', tmdb: '999');
      TmdbGroupAliasService.rebuild([v1, v2]);
      expect(TmdbGroupAliasService.aliasCount, 0);
    });

    test('sans identifiant, rien ne bouge', () {
      final a = _e('100 metres (2025)');
      final b = _e('100 METERS (2025)');
      TmdbGroupAliasService.rebuild([a, b]);
      expect(TmdbGroupAliasService.aliasCount, 0);
      expect(TmdbGroupAliasService.canonical(a.title.groupKey),
          a.title.groupKey);
    });

    test('les chaines TV sont hors du perimetre', () {
      // Pas de TMDB pour une chaine : fusionner dessus n aurait aucun sens.
      final a = _e('TF1 HD', tmdb: '7', type: M3uContentType.tv);
      final b = _e('TF1 FHD', tmdb: '7', type: M3uContentType.tv);
      TmdbGroupAliasService.rebuild([a, b]);
      expect(TmdbGroupAliasService.aliasCount, 0);
    });

    test('un film et une serie de meme identifiant ne se melangent pas', () {
      final film = _e('Dune (2021)', tmdb: '5');
      final serie = _e('Dune Prophecy (2021)',
          tmdb: '5', type: M3uContentType.series);
      TmdbGroupAliasService.rebuild([film, serie]);
      expect(TmdbGroupAliasService.aliasCount, 0);
    });
  });
}
