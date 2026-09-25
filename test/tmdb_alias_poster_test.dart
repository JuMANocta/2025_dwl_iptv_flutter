// §aliasByPoster (lot 9, 2026-09-25) — Réunir deux vignettes d'une même œuvre
// que rien ne relie, par le FICHIER de leur affiche TMDB.
//
// VOD, XENO et PREMIUM pointent vers `image.tmdb.org/t/p/<taille>/<fichier>` ;
// un fichier d'affiche appartient à une seule œuvre. Chaque garde tenue ici est
// née d'un faux positif MESURÉ sur les dumps réels
// (`tmdb_alias_measure_test.dart`).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/services/favorites_service.dart';
import 'package:aetherStream/data/services/inferred_category_service.dart';
import 'package:aetherStream/data/services/tmdb_group_alias_service.dart';

String _poster(String file) =>
    'https://image.tmdb.org/t/p/w600_and_h900_bestv2/$file.jpg';

M3uEntry _e(
  String name, {
  String? poster,
  String? tmdb,
  String account = 'acc',
  M3uContentType type = M3uContentType.movie,
}) =>
    M3uEntry(
      url: 'http://$account/${name.hashCode}',
      type: type,
      title: TitleMetadata.parse(name),
      accountId: account,
      tmdbId: tmdb,
      logoUrl: poster,
    );

String _canon(M3uEntry e) => TmdbGroupAliasService.canonical(e.title.groupKey);

const String _p1 = 'rfRLWbxLZPq2eboKPsBvh1NgNwM';
const String _p2 = 'hVROmmS84az3CXbInKbmwY8PeOf';

void main() {
  setUp(TmdbGroupAliasService.resetForTest);
  tearDown(TmdbGroupAliasService.resetForTest);

  group('tmdbPosterFile — le fichier, quelle que soit la taille', () {
    test('deux tailles du même fichier : même identifiant', () {
      expect(tmdbPosterFile(_poster(_p1)), '$_p1.jpg');
      expect(tmdbPosterFile('http://image.tmdb.org/t/p/original/$_p1.jpg'),
          '$_p1.jpg');
    });

    test('un autre hôte ne prouve rien', () {
      expect(tmdbPosterFile('http://cdn.panel.tv/t/p/w600/$_p1.jpg'), isNull);
      expect(tmdbPosterFile(null), isNull);
      // Un logo vide ou tronqué ne fait pas lever la reconstruction.
      expect(tmdbPosterFile(''), isNull);
      expect(tmdbPosterFile('abc'), isNull);
      expect(tmdbPosterFile('https://image.tmdb.org/t/p'), isNull);
      expect(tmdbPosterFile('https://image.tmdb.org/t/p/$_p1.jpg'), isNull,
          reason: 'sans segment de taille, ce n\'est pas la forme TMDB');
      expect(tmdbPosterFile('https://image.tmdb.org/t/p/w92/a.jpg'), isNull);
    });
  });

  group('partSignature — les numéros d\'un titre', () {
    test('nombres, romains de II à IX, nombre en lettres après « part »', () {
      expect(partSignature('norman le spectacle de la maturite 2'), '2');
      expect(partSignature('der mordanschlag teil 1'), '1');
      expect(partSignature('mission impossible dead reckoning part one'), '1');
      expect(partSignature('history of the world part ii'), '2');
      expect(partSignature('22 11 63'), '11,22,63');
      expect(partSignature('le parrain'), '');
    });

    test('un nombre collé à des lettres compte aussi (ج2 = partie 2)', () {
      // Mesuré : « مرضي ودحام » et « مرضي ودحام ج2 » partagent une affiche.
      expect(partSignature('مرضي ودحام ج2'), '2');
      expect(partSignature('code geass r2'), '2');
      expect(partSignature('ref 123456789012345678901234'), '-1',
          reason: 'un nombre démesuré ne fait pas lever la reconstruction');
    });

    test('I, V et X sont aussi des mots : ils ne comptent pas', () {
      expect(partSignature('i robot'), '');
      expect(partSignature('v pour vendetta'), '');
      expect(partSignature('x men'), '');
    });
  });

  group('la seconde passe — même affiche, même œuvre', () {
    test('deux titres sans identifiant, une affiche : une vignette', () {
      final fr = _e('Kidnapping maison (2025)', poster: _poster(_p1));
      final ar = _e('The Fakenapping (2025)', poster: _poster(_p1));
      TmdbGroupAliasService.rebuild([fr, ar]);
      expect(_canon(fr), _canon(ar));
      expect(TmdbGroupAliasService.posterAliasCount, 1);
    });

    test('la même affiche servie par un AUTRE hôte : rien', () {
      final a = _e('Kidnapping maison (2025)',
          poster: 'http://cdn.x/t/p/w600/$_p1.jpg');
      final b = _e('The Fakenapping (2025)',
          poster: 'http://cdn.x/t/p/w600/$_p1.jpg');
      TmdbGroupAliasService.rebuild([a, b]);
      expect(_canon(a), isNot(_canon(b)));
    });

    test('garde 1 — années divergentes : on s\'abstient', () {
      // Mesuré : « The Lion King » 1994 et « Le Roi Lion » 2019.
      final a = _e('The Lion King (1994)', poster: _poster(_p1));
      final b = _e('Le Roi Lion (2019)', poster: _poster(_p1));
      TmdbGroupAliasService.rebuild([a, b]);
      expect(_canon(a), isNot(_canon(b)));
    });

    test('garde 1 — une année d\'un seul côté reste compatible', () {
      final a = _e('Moonlight (2016)', poster: _poster(_p1));
      final b = _e('Moonlight VOSTFR film', poster: _poster(_p1));
      TmdbGroupAliasService.rebuild([a, b]);
      expect(_canon(a), _canon(b));
    });

    test('garde 2 — une SÉRIE à plus de 3 titres sur une affiche : rien', () {
      // « On reste découpé » : les éditions de Koh-Lanta partagent l'affiche.
      final editions = [
        for (final n in ['Fidji', 'Cambodge', 'Johor', 'Malaisie'])
          _e('Koh-Lanta $n (FR) HD',
              poster: _poster(_p1), type: M3uContentType.series),
      ];
      TmdbGroupAliasService.rebuild(editions);
      expect(editions.map(_canon).toSet().length, 4);
    });

    test('garde 2 — un FILM à plus de 3 titres : garde STRICTE (Parrain 3)',
        () {
      // Mesuré : PREMIUM met l'identifiant 242 ET l'affiche sur les deux noms
      // du Parrain 3 ET sur l'Épilogue de 2020 ; VOD (JSON) a la même
      // affiche. Quatre titres : l'ancienne garde (≤ 3) ne réunissait rien.
      final gf3 = _e('The Godfather: Part III (MULTI) FHD 1990',
          poster: _poster(_p1), tmdb: '242');
      final fr3 = _e('Le Parrain, 3e partie (MULTI) FHD 1990',
          poster: _poster(_p1), tmdb: '242');
      final vod = _e('Le Parrain, 3e partie (1990) [MULTi] - The Godfather III',
          poster: _poster(_p1));
      final coda = _e(
          'LE PARRAIN DE MARIO PUZO, ÉPILOGUE : LA MORT DE MICHAEL CORLEONE '
          '(MULTI) FHD 2020',
          poster: _poster(_p1),
          tmdb: '242');
      TmdbGroupAliasService.rebuild([gf3, fr3, vod, coda]);
      expect(<String>{_canon(gf3), _canon(fr3), _canon(vod)}.length, 1,
          reason: 'les trois 1990 réunis');
      expect(_canon(coda), isNot(_canon(gf3)), reason: 'l\'Épilogue 2020 non');
    });

    test('garde 2 — stricte : sans année ÉCRITE des deux côtés, rien', () {
      final a = _e('Uncorked (2020)', poster: _poster(_p1));
      final b = _e('Le goût du vin (2020)', poster: _poster(_p1));
      final c = _e('Mafuta (2020)', poster: _poster(_p1));
      final noYear = _e('Le Goût Du Vin VF film', poster: _poster(_p1));
      TmdbGroupAliasService.rebuild([a, b, c, noYear]);
      expect(<String>{_canon(a), _canon(b), _canon(c)}.length, 1);
      expect(_canon(noYear), isNot(_canon(a)),
          reason: 'au-delà de 3 titres, une absence d\'année ne suffit plus');
    });

    test('garde 2 — au-delà de 8 titres : affiche générique, rien', () {
      final films = [
        for (int i = 0; i < 9; i++)
          _e('Titre ${String.fromCharCode(65 + i)}x (2020)',
              poster: _poster(_p1)),
      ];
      TmdbGroupAliasService.rebuild(films);
      expect(films.map(_canon).toSet().length, 9);
    });

    test('garde 3 — numéros de partie différents : jamais réunis', () {
      final p1 = _e('Norman, le spectacle de la maturité 1',
          poster: _poster(_p1));
      final p2 = _e('Norman, le spectacle de la maturité 2',
          poster: _poster(_p1));
      final t1 = _e('Der Mordanschlag: Teil 1 (2018)', poster: _poster(_p2));
      final t2 = _e('Der Mordanschlag: Teil 2 (2018)', poster: _poster(_p2));
      TmdbGroupAliasService.rebuild([p1, p2, t1, t2]);
      expect(_canon(p1), isNot(_canon(p2)));
      expect(_canon(t1), isNot(_canon(t2)));
    });

    test('garde 3 — un numéro d\'un seul côté : prudence, rien', () {
      final a = _e('Underworld 2 : Évolution (2006)', poster: _poster(_p1));
      final b = _e('Underworld: Evolution (2006)', poster: _poster(_p1));
      // Le prix de la prudence : un nombre écrit en chiffres d'un côté et en
      // lettres de l'autre ne se réunit pas non plus.
      final digits = _e('60 secondes chrono (2000)', poster: _poster(_p2));
      final words = _e('Gone in Sixty Seconds (2000)', poster: _poster(_p2));
      TmdbGroupAliasService.rebuild([a, b, digits, words]);
      expect(_canon(a), isNot(_canon(b)));
      expect(_canon(digits), isNot(_canon(words)));
    });

    test('« Part One » et « Teil 1 » : le même numéro, réunis', () {
      final en = _e('Mission: Impossible - Dead Reckoning Part One (2023)',
          poster: _poster(_p1));
      final de = _e('Mission: Impossible: Dead Reckoning (Teil 1) (2023)',
          poster: _poster(_p1));
      TmdbGroupAliasService.rebuild([en, de]);
      expect(_canon(en), _canon(de));
    });

    test('garde 4 — deux identifiants fournisseur différents : le '
        'fournisseur l\'emporte sur l\'affiche', () {
      final a = _e('Le Film (2020)', poster: _poster(_p1), tmdb: '1');
      final b = _e('The Movie (2020)', poster: _poster(_p1), tmdb: '2');
      TmdbGroupAliasService.rebuild([a, b]);
      expect(_canon(a), isNot(_canon(b)));
    });

    test('un identifiant d\'un seul côté : l\'orpheline rejoint le groupe '
        'identifié', () {
      final known = _e('Le Loup de Wall Street (2013)',
          poster: _poster(_p1), tmdb: '106646');
      final orphan =
          _e('The Wolf of Wall Street (2013)', poster: _poster(_p1));
      TmdbGroupAliasService.rebuild([known, known, orphan]);
      expect(_canon(orphan), known.title.groupKey);
    });

    test('en chaîne, les gardes valent pour le groupe ENTIER', () {
      // A et B partagent une affiche, B et C une autre ; A (2019) et C
      // (2021) ne doivent pas finir ensemble par B, qui n'a pas d'année.
      final a = _e('Titre A (2019)', poster: _poster(_p1));
      final b = _e('Titre B', poster: _poster(_p1));
      final b2 = _e('Titre B', poster: _poster(_p2));
      final c = _e('Titre C (2021)', poster: _poster(_p2));
      TmdbGroupAliasService.rebuild([a, b, b2, c]);
      expect(_canon(a), isNot(_canon(c)));
    });

    test('canonique = le groupe le plus lourd, stable quel que soit l\'ordre',
        () {
      final big = _e('Pirates of the Caribbean: On Stranger Tides (2011)',
          poster: _poster(_p1));
      final small = _e('Pirates des Caraïbes : La Fontaine de jouvence (2011)',
          poster: _poster(_p1));
      TmdbGroupAliasService.rebuild([small, big, big, big]);
      final first = _canon(small);
      TmdbGroupAliasService.rebuild([big, big, big, small]);
      expect(_canon(small), first);
      expect(first, big.title.groupKey);
    });

    test('un groupe réuni par IDENTIFIANT garde sa canonique quand il domine',
        () {
      // Aucune clé de favori existante ne doit bouger pour rien.
      final a = _e('100 METERS (2025)', tmdb: '1295026', poster: _poster(_p1));
      final b = _e('100 metres (2025)', tmdb: '1295026');
      final orphan = _e('100 Meter (2025)', poster: _poster(_p1));
      TmdbGroupAliasService.posterPassEnabled = false;
      TmdbGroupAliasService.rebuild([a, a, b, orphan]);
      final idCanon = _canon(b);
      TmdbGroupAliasService.posterPassEnabled = true;
      TmdbGroupAliasService.rebuild([a, a, b, orphan]);
      expect(_canon(b), idCanon);
      expect(_canon(orphan), idCanon);
    });
  });

  group('aliasClosureAdditions — la migration des favoris (R53)', () {
    const alias = <String, String>{
      'ajuste de contas parte 1': 'dead reckoning partie 1',
      'dead reckoning part one': 'dead reckoning partie 1',
    };

    test('une variante gagne sa canonique et ses sœurs, même année', () {
      expect(
        FavoritesService.aliasClosureAdditions(
            {'movie|ajuste de contas parte 1|2023'}, alias),
        {
          'movie|dead reckoning partie 1|2023',
          'movie|dead reckoning part one|2023',
        },
      );
    });

    test('une canonique gagne ses variantes (le jour où l\'alias disparaît)',
        () {
      expect(
        FavoritesService.aliasClosureAdditions(
            {'movie|dead reckoning partie 1|2023'}, alias),
        {
          'movie|ajuste de contas parte 1|2023',
          'movie|dead reckoning part one|2023',
        },
      );
    });

    test('idempotente : appliquée deux fois, n\'ajoute plus rien', () {
      final stored = <String>{'movie|ajuste de contas parte 1|2023'};
      stored.addAll(FavoritesService.aliasClosureAdditions(stored, alias));
      expect(FavoritesService.aliasClosureAdditions(stored, alias), isEmpty);
    });

    test('clé héritée sans année, année vide, série : la forme est gardée', () {
      expect(
        FavoritesService.aliasClosureAdditions(
            {'movie|ajuste de contas parte 1', 'series|dead reckoning partie 1|'},
            alias),
        containsAll(<String>[
          'movie|dead reckoning partie 1',
          'series|ajuste de contas parte 1|',
        ]),
      );
    });

    test('chaînes, titres sans alias, table vide : rien', () {
      expect(
          FavoritesService.aliasClosureAdditions(
              {'tv|TF1', 'movie|heat|1995'}, alias),
          isEmpty);
      expect(
          FavoritesService.aliasClosureAdditions(
              {'movie|ajuste de contas parte 1|2023'}, const {}),
          isEmpty);
    });
  });

  group('InferredCategoryService — une catégorie apprise suit la réunion', () {
    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      await InferredCategoryService.clear();
    });

    test('apprise sous la VARIANTE, retrouvée sous la canonique', () {
      // Elle ne se réapprend pas toute seule : l'apprentissage n'a lieu que
      // sur une recherche TMDB réseau, jamais sur une affiche en cache.
      final big = _e('Gone Baby Gone (2007)', poster: _poster(_p1));
      final small = _e('Disparue (2007)', poster: _poster(_p1));
      expect(small.title.groupKey, isNot(big.title.groupKey));
      InferredCategoryService.learn(small.title.groupKey, 'Policier');
      TmdbGroupAliasService.rebuild([big, big, small]);
      final String canon = _canon(small);
      expect(canon, big.title.groupKey, reason: 'le décor : réunis');

      expect(InferredCategoryService.get(canon), 'Policier');
    });

    test('la clé propre reste prioritaire', () {
      final big = _e('Gone Baby Gone (2007)', poster: _poster(_p1));
      final small = _e('Disparue (2007)', poster: _poster(_p1));
      InferredCategoryService.learn(small.title.groupKey, 'Policier');
      InferredCategoryService.learn(big.title.groupKey, 'Drame');
      TmdbGroupAliasService.rebuild([big, big, small]);
      expect(InferredCategoryService.get(_canon(small)), 'Drame');
    });
  });
}
