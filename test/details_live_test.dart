// §detailsLive (2026-09-06) — La fiche d'un FILM figeait ses versions au
// moment du tap : elle affichait la liste que l'accueil lui avait passée et ne
// la recalculait jamais. Quand une liste revenait (rechargement, ré-analyse
// terminée, retour de mémoire), ses qualités n'apparaissaient qu'après avoir
// refermé puis rouvert la fiche.
//
// Les règles sorties de la page sont testées ici. Le branchement (écoute de
// `ParsedPlaylistService.version`, restauration de la saison ouverte) se voit à
// la recette : aucun test ne monte `DetailsPage`, qui appelle TMDB à l'init.

import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/feature/search/details_versions.dart';

M3uEntry _entry(
  String title, {
  required String account,
  String url = '',
  M3uContentType type = M3uContentType.movie,
}) =>
    M3uEntry(
      url: url.isEmpty ? 'http://x/$account/${title.hashCode}' : url,
      accountId: account,
      type: type,
      title: TitleMetadata.parse(title),
    );

void main() {
  group('entriesOfTitle — le rapprochement partagé films / séries', () {
    test('ramasse les versions du MÊME titre dans toutes les listes', () {
      final ref = _entry('Interstellar (2014) FHD', account: 'a');
      final pool = [
        ref,
        _entry('Interstellar (2014) 4K', account: 'b'),
        _entry('Interstellar (2014) HD', account: 'c'),
        _entry('Inception (2010) 4K', account: 'b'),
      ];

      final out = entriesOfTitle(pool, ref);

      expect(out.length, 3);
      expect(out.map((e) => e.accountId), containsAll(['a', 'b', 'c']));
    });

    test('§homonymYear — deux films homonymes ne se mélangent pas', () {
      final ref = _entry('Vengeance (2022) FHD', account: 'a');
      final pool = [
        ref,
        _entry('Vengeance (2022) 4K', account: 'b'),
        _entry('Vengeance (1990) HD', account: 'b'),
      ];

      final out = entriesOfTitle(pool, ref);

      expect(out.length, 2);
      expect(out.every((e) => e.title.year == '2022'), isTrue);
    });

    test('une entrée SANS année reste rattachée (donnée incomplète)', () {
      final ref = _entry('Dune (2021) FHD', account: 'a');
      final pool = [ref, _entry('Dune FHD', account: 'b')];

      expect(entriesOfTitle(pool, ref).length, 2);
    });

    test('un autre TYPE ne remonte jamais (série vs film homonyme)', () {
      final ref = _entry('Fargo (1996) FHD', account: 'a');
      final pool = [
        ref,
        _entry('Fargo (1996)', account: 'b', type: M3uContentType.series),
      ];

      expect(entriesOfTitle(pool, ref).single.type, M3uContentType.movie);
    });

    test('§tmdbOnlyDetails — une entrée synthétique ne cherche rien', () {
      final ref = M3uEntry(
        url: '',
        accountId: '',
        type: M3uContentType.movie,
        title: TitleMetadata.parse('Un film hors listes'),
        tmdbId: '42',
      );

      expect(entriesOfTitle([_entry('Un film hors listes', account: 'a')], ref),
          isEmpty);
    });
  });

  group('versionsSignature — ne rien reconstruire pour rien', () {
    test('stable quel que soit l ordre des entrées', () {
      final a = _entry('Heat (1995) 4K', account: 'a');
      final b = _entry('Heat (1995) HD', account: 'b');

      expect(versionsSignature([a, b]), versionsSignature([b, a]));
    });

    test('change dès qu une liste arrive ou repart', () {
      final a = _entry('Heat (1995) 4K', account: 'a');
      final b = _entry('Heat (1995) HD', account: 'b');

      expect(versionsSignature([a]), isNot(versionsSignature([a, b])));
      expect(versionsSignature(const []), versionsSignature(const []));
    });
  });

  group('keepSelection — la version choisie ne saute pas', () {
    test('garde la version courante quand elle est toujours là', () {
      final a = _entry('Heat (1995) 4K', account: 'a');
      final b = _entry('Heat (1995) HD', account: 'b');

      expect(keepSelection([a, b], b.url), b);
    });

    test('retombe sur la première quand la source a disparu', () {
      final a = _entry('Heat (1995) 4K', account: 'a');
      final disparue = _entry('Heat (1995) HD', account: 'b');

      expect(keepSelection([a], disparue.url), a);
    });

    test('rend null s il ne reste RIEN — la fiche garde son affichage', () {
      expect(keepSelection(const [], 'http://x/1'), isNull);
    });
  });
}
