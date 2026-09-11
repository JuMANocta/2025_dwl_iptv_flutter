import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aetherStream/data/services/tmdb_poster_cache.dart';
import 'package:aetherStream/data/services/tmdb_service.dart';

/// Revue 2026-09-11 — `TmdbPosterCache` :
///   - D1B-01 : il PERSISTAIT comme « introuvable » des titres jamais
///     cherchés (pas de clé, hors ligne, 401/429) ; après la saisie d'une
///     bonne clé, ces titres restaient sans affiche à chaque redémarrage ;
///   - D1B-23 : une résolution qui LEVAIT restait coincée dans `_inFlight`
///     pour toute la session (le futur en erreur resservi à chaque appel).
///
/// ⚠️ L'ORDRE des groupes compte : le premier tourne SANS stockage sécurisé
/// simulé — la lecture de la clé LÈVE (aucun greffon natif sous
/// `flutter test`), c'est exactement le cas D1B-23. Les suivants posent un
/// stockage simulé. Sous `flutter test`, toute requête HTTP reçoit un 400 :
/// c'est l'« erreur réseau » de D1B-01, sans aucun accès réseau réel.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await TmdbPosterCache.clear();
    TmdbService.resetInstance();
  });

  group('D1B-23 — une résolution qui lève', () {
    test('rend null sans lever, ne met rien en cache, et se RETENTE', () async {
      final Future<String?> first =
          TmdbPosterCache.resolve(query: 'Heat', isTv: false, year: '1995');
      // Pendant le vol, les appels concurrents sont dédoublonnés…
      expect(
          identical(
              first,
              TmdbPosterCache.resolve(
                  query: 'Heat', isTv: false, year: '1995')),
          isTrue);
      expect(await first, isNull);
      expect(TmdbPosterCache.isResolved('Heat', false, '1995'), isFalse);
      // …mais une fois l'échec passé, rien ne reste coincé : nouvel essai.
      final Future<String?> second =
          TmdbPosterCache.resolve(query: 'Heat', isTv: false, year: '1995');
      expect(identical(first, second), isFalse);
      expect(await second, isNull);
    });
  });

  group('D1B-01 — une panne n\'est pas un « introuvable »', () {
    test('sans clé TMDB : rien n\'est mis en cache ni persisté', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      expect(await TmdbPosterCache.resolve(query: 'Heat', isTv: false), isNull);
      expect(TmdbPosterCache.isResolved('Heat', false, null), isFalse);
      expect(TmdbPosterCache.count, 0);
    });

    test('clé présente mais TMDB injoignable (HTTP 400) : pas mémorisé',
        () async {
      FlutterSecureStorage.setMockInitialValues(
          <String, String>{'tmdb_api_key': 'k' * 40});
      expect(
          await TmdbPosterCache.resolve(query: 'Ronin', isTv: false), isNull);
      expect(TmdbPosterCache.isResolved('Ronin', false, null), isFalse,
          reason: 'une erreur doit se retenter au prochain affichage');
    });

    // Relecture 2026-09-11 — la présence de la clé est mémorisée par
    // génération de `TmdbService` : sans ce mémo, « pas de clé » (qui n'est
    // plus mis en cache) relisait le trousseau à chaque vignette montée.
    test('clé saisie après un passage sans clé : vue dès le changement de clé',
        () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      await TmdbPosterCache.resolve(query: 'Heat', isTv: false);
      final int before = TmdbPosterCache.networkResolutions;

      // Clé écrite SANS `resetInstance` : le mémo tient (aucune relecture,
      // aucune recherche) — c'est ce qu'il économise.
      FlutterSecureStorage.setMockInitialValues(
          <String, String>{'tmdb_api_key': 'k' * 40});
      await TmdbPosterCache.resolve(query: 'Heat', isTv: false);
      expect(TmdbPosterCache.networkResolutions, before);

      // Tous les chemins qui écrivent la clé appellent `resetInstance` (page
      // TMDB, restauration, console) : la génération avance, le mémo tombe.
      TmdbService.resetInstance();
      await TmdbPosterCache.resolve(query: 'Heat', isTv: false);
      expect(TmdbPosterCache.networkResolutions, before + 1);
    });
  });

  group('forgetNegatives — au changement de clé', () {
    test('oublie les introuvables, garde les affiches trouvées', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tmdb_poster_cache_v2': jsonEncode(<String, String?>{
          'inconnu|false||fr-FR': null,
          'heat|false|1995|fr-FR': 'https://image.tmdb.org/t/p/w342/heat.jpg',
        }),
      });
      await TmdbPosterCache.init();
      expect(TmdbPosterCache.count, 2);
      await TmdbPosterCache.forgetNegatives();
      expect(TmdbPosterCache.count, 1);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final Map<String, dynamic> persisted =
          jsonDecode(prefs.getString('tmdb_poster_cache_v2')!)
              as Map<String, dynamic>;
      expect(persisted.values, everyElement(isNotNull));
    });
  });
}
