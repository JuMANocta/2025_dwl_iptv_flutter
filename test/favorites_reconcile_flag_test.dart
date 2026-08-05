import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aetherStream/data/services/favorites_service.dart';

/// §favAudit — Verrouille le **flag one-shot** de la réconciliation.
///
/// Le flag (`favorites_reconciled_schema_<n>`) est ce qui évite de rescanner
/// toute la playlist à chaque démarrage. Deux régressions vécues côté audit :
///   1. l'ancienne garde `if (_reconciling) return;` faisait ABANDONNER la
///      passe appelante — quand c'était la passe FINALE (multi-comptes), le
///      flag n'était jamais posé et le scan repartait à chaque boot ;
///   2. un cache de favoris VIDE sortait avant la pose du flag, avec le même
///      effet (re-vérification perpétuelle alors qu'il n'y a rien à migrer).
///
/// La playlist n'étant pas chargée dans ces tests
/// (`ParsedPlaylistService.entries` est vide), on couvre ici les chemins qui
/// n'en dépendent pas — précisément ceux qui posaient problème.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FavoritesService.resetForTest();
  });

  Future<bool?> flag() async =>
      (await SharedPreferences.getInstance())
          .getBool(FavoritesService.reconcileFlagKey);

  test('aucun favori + passe finale → flag posé (plus de scan à chaque boot)',
      () async {
    await FavoritesService.reconcileWithPlaylist(finalPass: true);
    expect(await flag(), isTrue);
  });

  test('aucun favori + passe INTERMÉDIAIRE → flag NON posé', () async {
    // Seule la passe finale (tous les comptes en mémoire) a le droit de
    // clore le sujet.
    await FavoritesService.reconcileWithPlaylist();
    expect(await flag(), isNull);
  });

  test('playlist vide + favoris présents → flag NON posé', () async {
    // Rien n'a pu être réconcilié : poser le flag condamnerait les favoris
    // orphelins à le rester définitivement.
    await FavoritesService.add('movie|inception|2010');
    await FavoritesService.reconcileWithPlaylist(finalPass: true);
    expect(await flag(), isNull);
  });

  test('passes concurrentes : la finale n\'est pas abandonnée', () async {
    // Reproduit le boot multi-comptes : une 1re passe fire & forget, puis la
    // passe finale déclenchée en fin d'hydratation. Avant le correctif, la
    // seconde retournait immédiatement (garde `_reconciling`) → flag perdu.
    final intermediate = FavoritesService.reconcileWithPlaylist();
    final finalPass = FavoritesService.reconcileWithPlaylist(finalPass: true);
    await Future.wait([intermediate, finalPass]);
    expect(await flag(), isTrue);
  });

  test('flag déjà posé → repasse sans effet, pas de plantage', () async {
    await FavoritesService.reconcileWithPlaylist(finalPass: true);
    await FavoritesService.reconcileWithPlaylist(finalPass: true);
    expect(await flag(), isTrue);
  });
}
