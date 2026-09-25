// R53 + §aliasByPoster (2026-09-25) — Un favori ne doit JAMAIS s'éteindre
// parce que la table d'alias a changé.
//
// **Le défaut (R53).** La clé d'un favori de film ou de série est
// `type|contentGroupKey|année`, et `contentGroupKey` passe par la table d'alias
// (`TmdbGroupAliasService.canonical`). Or cette table est REFAITE à chaque
// chargement et à chaque déchargement de liste (§lazyUnload) : qu'une liste
// arrive avec l'identifiant TMDB qui relie deux titres, et la clé d'une des
// deux variantes change sous le favori. Il restait stocké, mais plus rien ne
// le retrouvait : cœur éteint, titre absent de la rangée Favoris. La
// réconciliation (§favReconcile) ne tourne qu'une fois par schéma : elle ne
// voyait rien.
//
// **Le correctif.** Après chaque reconstruction de la table, les favoris sont
// complétés par leurs équivalents (la canonique et toutes ses variantes) —
// pur, idempotent, sans bump de schéma. Le favori est retrouvé quand l'alias
// apparaît, et encore quand il disparaît.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/services/favorites_service.dart';
import 'package:aetherStream/data/services/tmdb_group_alias_service.dart';

/// « Dead Reckoning Partie 1 » (FR) et « Ajuste de Contas (Parte 1) » (PT) :
/// le même film, identifiant TMDB 575264, deux clés.
M3uEntry _fr([int i = 0]) => M3uEntry(
      url: 'http://fr.tv/movie/u/p/$i.mkv',
      type: M3uContentType.movie,
      accountId: 'fr',
      tmdbId: '575264',
      title: TitleMetadata.parse(
          'Mission Impossible - Dead Reckoning Partie 1 (2023)'),
    );

M3uEntry _pt({String? tmdb = '575264'}) => M3uEntry(
      url: 'http://pt.tv/movie/u/p/9.mkv',
      type: M3uContentType.movie,
      accountId: 'pt',
      tmdbId: tmdb,
      title: TitleMetadata.parse(
          'Mission Impossible: Ajuste de Contas (Parte 1) (2023)'),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FavoritesService.resetForTest();
    TmdbGroupAliasService.resetForTest();
    await FavoritesService.init();
  });
  tearDown(TmdbGroupAliasService.resetForTest);

  group('R53 — un alias qui change ne doit pas éteindre un favori', () {
    test('favori posé sur la VARIANTE, puis la liste qui relie arrive', () async {
      // Seule la liste PT est chargée : aucun alias, la variante est sa
      // propre vignette.
      TmdbGroupAliasService.rebuild([_pt()]);
      await FavoritesService.addEntry(_pt());
      expect(FavoritesService.isEntryFavorite(_pt()), isTrue);

      // La liste FR arrive (majoritaire) : « Ajuste de Contas » devient une
      // variante de « Dead Reckoning ».
      TmdbGroupAliasService.rebuild([_fr(0), _fr(1), _fr(2), _pt()]);
      expect(
        TmdbGroupAliasService.canonical(_pt().title.groupKey),
        _fr().title.groupKey,
        reason: 'le décor du défaut : l\'alias existe bien',
      );

      expect(FavoritesService.isEntryFavorite(_pt()), isTrue,
          reason: 'R53 : le favori s\'éteignait ici');
      expect(FavoritesService.isEntryFavorite(_fr()), isTrue,
          reason: 'la vignette réunie EST le favori');
    });

    test('… puis la liste repart (§lazyUnload) : le favori reste', () async {
      TmdbGroupAliasService.rebuild([_pt()]);
      await FavoritesService.addEntry(_pt());
      TmdbGroupAliasService.rebuild([_fr(0), _fr(1), _fr(2), _pt()]);

      TmdbGroupAliasService.rebuild([_pt()]); // FR déchargée : plus d'alias
      expect(FavoritesService.isEntryFavorite(_pt()), isTrue);
    });

    test('favori posé sur la vignette RÉUNIE, puis l\'alias disparaît : la '
        'variante reste favorite', () async {
      TmdbGroupAliasService.rebuild([_fr(0), _fr(1), _fr(2), _pt()]);
      await FavoritesService.addEntry(_fr()); // clé canonique
      expect(FavoritesService.isEntryFavorite(_pt()), isTrue);

      // La liste FR repart : « Ajuste de Contas » redevient sa propre vignette.
      TmdbGroupAliasService.rebuild([_pt()]);
      expect(FavoritesService.isEntryFavorite(_pt()), isTrue,
          reason: 'un favori ne s\'éteint jamais : la variante le garde');
    });

    test('§aliasByPoster — même chose quand c\'est l\'AFFICHE qui réunit',
        () async {
      M3uEntry film(String name, String account) => M3uEntry(
            url: 'http://$account.tv/movie/u/p/${name.length}.mkv',
            type: M3uContentType.movie,
            accountId: account,
            logoUrl: 'https://image.tmdb.org/t/p/w600_and_h900_bestv2/'
                'rfRLWbxLZPq2eboKPsBvh1NgNwM.jpg',
            title: TitleMetadata.parse(name),
          );
      final xeno = film('Kidnapping maison (2025)', 'xeno');
      final vod = film('The Fakenapping (2025)', 'vod');

      TmdbGroupAliasService.rebuild([xeno]);
      await FavoritesService.addEntry(xeno);
      TmdbGroupAliasService.rebuild([vod, vod, xeno]); // l'affiche réunit
      expect(_canonOf(xeno), _canonOf(vod), reason: 'le décor : réunis');
      expect(FavoritesService.isEntryFavorite(xeno), isTrue);
      expect(FavoritesService.isEntryFavorite(vod), isTrue);

      TmdbGroupAliasService.rebuild([xeno]); // VOD déchargée
      expect(FavoritesService.isEntryFavorite(xeno), isTrue);
    });

    test('retirer le favori de la vignette réunie le retire PARTOUT', () async {
      TmdbGroupAliasService.rebuild([_fr(0), _fr(1), _fr(2), _pt()]);
      await FavoritesService.addEntry(_pt());
      expect(await FavoritesService.toggleEntry(_fr()), isFalse);

      expect(FavoritesService.isEntryFavorite(_fr()), isFalse);
      expect(FavoritesService.isEntryFavorite(_pt()), isFalse);
      TmdbGroupAliasService.rebuild([_pt()]);
      expect(FavoritesService.isEntryFavorite(_pt()), isFalse,
          reason: 'aucune variante oubliée ne le rallume');
    });
  });
}

String _canonOf(M3uEntry e) =>
    TmdbGroupAliasService.canonical(e.title.groupKey);
