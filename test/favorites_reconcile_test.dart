import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/services/favorites_service.dart';

/// §favReconcile — Verrouille la réconciliation des favoris « fantômes ».
///
/// Contexte : les clés de favoris descendent de `TitleMetadata.baseTitle`.
/// Quand la sortie du parsing change (ex. §parseAudit2026-06-30 : préfixes
/// `|XX|` casse mixte strippés, pipes résiduels supprimés, exposants ᴴ²⁶⁵
/// normalisés — bump schéma 11→12), les clés persistées AVANT le changement
/// ne matchent plus `keyFor` → cœur éteint + titre absent de la rangée
/// Favoris. `reconcileKeys` ré-apparie ces clés orphelines contre la
/// playlist courante via une forme « squash » (groupKey sans espaces).
///
/// Les entrées de test passent par le VRAI `TitleMetadata.parse` → les clés
/// « nouvelles » sont exactement celles que produit l'app ; les clés
/// stockées « anciennes » reproduisent les sorties de l'ancien parsing
/// observées sur les données réelles de l'audit.
void main() {
  M3uEntry entry(String raw, M3uContentType type) => M3uEntry(
        url: 'http://test/$raw',
        type: type,
        title: TitleMetadata.parse(raw),
        accountId: 'acc1',
      );

  Map<String, String> reconcile(
    Set<String> stored,
    List<M3uEntry> entries, {
    Set<String>? unresolved,
  }) =>
      FavoritesService.reconcileKeys(stored, entries,
          unresolvedOut: unresolved);

  group('FavoritesService.reconcileKeys — cas réels §parseAudit', () {
    test('corruption pipes (CORP|US| CHRISTI) → égalité squash exacte', () {
      // Ancien parsing : pipes conservés → baseTitle "CORP|US| CHRISTI"
      // → clé "movie|corp us christi|2019". Nouveau : pipes supprimés →
      // "CORPUS CHRISTI" → "movie|corpus christi|2019".
      final entries = [
        entry('CORP|US| CHRISTI (MULTI) FHD 2019', M3uContentType.movie),
      ];
      final rewrites = reconcile({'movie|corp us christi|2019'}, entries);
      expect(rewrites, {
        'movie|corp us christi|2019': 'movie|corpus christi|2019',
      });
    });

    test('préfixe casse mixte (|FR-4k|) → ré-apparié par suffixe', () {
      // Ancien parsing : préfixe casse mixte NON strippé → garbage "fr 4k"
      // devant le titre dans le groupKey stocké.
      final entries = [
        entry("|FR-4k| L'amour dans l'objectif (2025)", M3uContentType.movie),
      ];
      final rewrites =
          reconcile({'movie|fr 4k l amour dans l objectif|2025'}, entries);
      expect(rewrites, {
        'movie|fr 4k l amour dans l objectif|2025':
            'movie|l amour dans l objectif|2025',
      });
    });

    test('TV — code région dupliqué (|DE| |DE|) → ré-apparié par suffixe', () {
      // Ancien parsing : seul le 1er |DE| était strippé → clé stockée
      // "tv||DE| SKY SPORT GOLF". Nouveau : les deux sautent.
      final entries = [
        entry('|DE| |DE| SKY SPORT GOLF ᶠᴴᴰ', M3uContentType.tv),
      ];
      final rewrites = reconcile({'tv||DE| SKY SPORT GOLF'}, entries);
      expect(rewrites, {'tv||DE| SKY SPORT GOLF': 'tv|SKY SPORT GOLF'});
    });

    test('TV — exposant ᴴ²⁶⁵ résiduel → ré-apparié par préfixe', () {
      // Ancien parsing : ᴴ²⁶⁵ absent de la table superscripts → restait dans
      // le baseTitle ("RAI 1 ᴴ²⁶⁵"). Nouveau : normalisé H265 puis strippé.
      final entries = [
        entry('|IT| RAI 1 UHD ᴴ²⁶⁵', M3uContentType.tv),
      ];
      final rewrites = reconcile({'tv|RAI 1 ᴴ²⁶⁵'}, entries);
      expect(rewrites, {'tv|RAI 1 ᴴ²⁶⁵': 'tv|RAI 1'});
    });

    test('clé legacy sans année orpheline → migrée vers la clé avec année', () {
      final entries = [
        entry('CORP|US| CHRISTI (MULTI) FHD 2019', M3uContentType.movie),
      ];
      final rewrites = reconcile({'movie|corp us christi'}, entries);
      expect(rewrites, {'movie|corp us christi': 'movie|corpus christi|2019'});
    });
  });

  group('FavoritesService.reconcileKeys — garde-fous', () {
    test('clé saine → jamais réécrite', () {
      final entries = [entry('Inception (2010) FHD', M3uContentType.movie)];
      final rewrites = reconcile({'movie|inception|2010'}, entries);
      expect(rewrites, isEmpty);
    });

    test('clé legacy sans année SAINE → jamais réécrite', () {
      // La forme legacy est encore acceptée par isEntryFavorite → pas
      // orpheline, on ne la touche pas (elle migre au re-toggle utilisateur).
      final entries = [entry('Inception (2010) FHD', M3uContentType.movie)];
      final rewrites = reconcile({'movie|inception'}, entries);
      expect(rewrites, isEmpty);
    });

    test('candidat trop court / ratio < ½ → non apparié, conservé', () {
      // "objectif" (8) est bien un préfixe du squash stocké (33), mais
      // 8×2 < 33 → rejeté (anti-faux-positif sur les titres courts).
      final entries = [entry('Objectif (2020)', M3uContentType.movie)];
      final unresolved = <String>{};
      final rewrites = reconcile(
        {'movie|objectif tres long suffixe garbage ici|2020'},
        entries,
        unresolved: unresolved,
      );
      expect(rewrites, isEmpty);
      expect(unresolved, {'movie|objectif tres long suffixe garbage ici|2020'});
    });

    test('deux candidats de même longueur → ambigu, non apparié', () {
      // "abcd" est préfixe et "wxyz" est suffixe du squash stocké
      // "abcdwxyz" — même longueur, clés différentes → on ne choisit pas.
      final entries = [
        entry('AB CD', M3uContentType.tv),
        entry('WX YZ', M3uContentType.tv),
      ];
      final unresolved = <String>{};
      final rewrites =
          reconcile({'tv|AB CD WX YZ'}, entries, unresolved: unresolved);
      expect(rewrites, isEmpty);
      expect(unresolved, {'tv|AB CD WX YZ'});
    });

    test('année stricte — même squash mais année différente → non apparié', () {
      // Homonymes/remakes (§favYear) : un favori "Michael 1996" ne doit
      // JAMAIS être ré-apparié sur "Michael 2023".
      final entries = [entry('Michael (2023) FHD', M3uContentType.movie)];
      final unresolved = <String>{};
      final rewrites =
          reconcile({'movie|mich ael|1996'}, entries, unresolved: unresolved);
      expect(rewrites, isEmpty);
      expect(unresolved, {'movie|mich ael|1996'});
    });

    test('types cloisonnés — une clé tv ne matche jamais un film', () {
      final entries = [entry('Inception (2010) FHD', M3uContentType.movie)];
      final unresolved = <String>{};
      final rewrites =
          reconcile({'tv|INCEPTION'}, entries, unresolved: unresolved);
      expect(rewrites, isEmpty);
      expect(unresolved, {'tv|INCEPTION'});
    });
  });
}
