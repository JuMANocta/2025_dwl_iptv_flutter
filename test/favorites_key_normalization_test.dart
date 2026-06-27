import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/services/favorites_service.dart';

/// §favPersistFix — Verrouille la non-régression du bug de persistance des
/// favoris : la migration au chargement (`normalizeStoredKey`) écrasait le
/// séparateur d'année `|` en espace (`series|titre|2008` → `series|titre 2008`),
/// faisant « disparaître » les favoris à chaque redémarrage.
///
/// Propriété clé : sur une clé DÉJÀ saine, la normalisation doit être
/// **idempotente** (sortie == entrée) → sinon la clé est re-corrompue et
/// re-persistée en boucle.
void main() {
  String norm(String k) => FavoritesService.normalizeStoredKey(k);

  group('FavoritesService.normalizeStoredKey', () {
    test('clé saine avec année → idempotente (cœur du bug)', () {
      expect(norm('series|breaking bad|2008'), 'series|breaking bad|2008');
      expect(norm('movie|inception|2010'), 'movie|inception|2010');
    });

    test('clé legacy en MAJUSCULES → minuscules (migration §23b)', () {
      expect(norm('movie|The Matrix|1999'), 'movie|the matrix|1999');
      expect(norm('series|Breaking Bad|2008'), 'series|breaking bad|2008');
    });

    test('clé legacy SANS année → inchangée', () {
      expect(norm('series|breaking bad'), 'series|breaking bad');
      expect(norm('movie|inception'), 'movie|inception');
    });

    test('année vide (suffixe `|` final) → préservée', () {
      expect(norm('series|breaking bad|'), 'series|breaking bad|');
    });

    test('titre finissant par des chiffres → groupKey intact, année isolée', () {
      // Le "2049" interne (avant le dernier `|`) reste dans le groupKey ;
      // seul le "2017" final est traité comme l'année.
      expect(norm('movie|blade runner 2049|2017'), 'movie|blade runner 2049|2017');
      // Titre purement numérique ("2012") + année de sortie distincte.
      expect(norm('movie|2012|2009'), 'movie|2012|2009');
    });

    test('clé TV → jamais touchée (pas de normalisation année)', () {
      expect(norm('tv|TF1'), 'tv|TF1');
      expect(norm('tv|France 2'), 'tv|France 2');
    });

    test('ponctuation du groupKey normalisée en espace', () {
      // computeGroupKey collapse la ponctuation (ex. "M.A.S.H" → "m a s h").
      expect(norm('series|M.A.S.H|1972'), 'series|m a s h|1972');
    });
  });
}
