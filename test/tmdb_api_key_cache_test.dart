import 'package:aetherStream/data/services/tmdb_api_service.dart';
import 'package:aetherStream/data/services/tmdb_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Revue 2026-09-11, D1B-15 — La clé TMDB est lue une fois puis servie de
/// mémoire ; toute écriture (seul `TmdbApiService` écrit la clé) met la
/// mémoire à jour, et `TmdbService.resetInstance()` la fait relire.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    TmdbApiService.invalidateCache();
  });

  test('après saveApiKey, getApiKey rend la nouvelle valeur', () async {
    expect(await TmdbApiService.getApiKey(), isNull);
    await TmdbApiService.saveApiKey('cle-1');
    expect(await TmdbApiService.getApiKey(), 'cle-1');
    expect(await TmdbApiService.hasApiKey(), isTrue);
    await TmdbApiService.saveApiKey('cle-2');
    expect(await TmdbApiService.getApiKey(), 'cle-2');
  });

  test('après deleteApiKey, plus de clé', () async {
    await TmdbApiService.saveApiKey('cle');
    await TmdbApiService.deleteApiKey();
    expect(await TmdbApiService.getApiKey(), isNull);
    expect(await TmdbApiService.hasApiKey(), isFalse);
  });

  test('servie de mémoire : un trousseau changé EN DEHORS n\'est vu qu\'après '
      'resetInstance', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{'tmdb_api_key': 'a'});
    TmdbApiService.invalidateCache();
    expect(await TmdbApiService.getApiKey(), 'a');
    // Écriture qui contourne `TmdbApiService` (n'existe pas dans l'app) :
    FlutterSecureStorage.setMockInitialValues(<String, String>{'tmdb_api_key': 'b'});
    expect(await TmdbApiService.getApiKey(), 'a',
        reason: 'aucune relecture du trousseau');
    // Tout chemin qui change la clé appelle `resetInstance` : relue.
    TmdbService.resetInstance();
    expect(await TmdbApiService.getApiKey(), 'b');
  });

  test('une lecture partie AVANT une écriture ne remet pas l\'ancienne valeur',
      () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{'tmdb_api_key': 'old'});
    TmdbApiService.invalidateCache();
    final Future<String?> inFlight = TmdbApiService.getApiKey();
    await TmdbApiService.saveApiKey('new');
    await inFlight;
    expect(await TmdbApiService.getApiKey(), 'new');
  });
}
