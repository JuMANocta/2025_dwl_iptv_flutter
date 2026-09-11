import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';

class TmdbApiService {
  static const AndroidOptions _androidOptions = AndroidOptions(
    encryptedSharedPreferences: true,
  );

  // Option pour iOS: configure l'accessibilité du Keychain
  static final IOSOptions _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  );

  static final _storage = FlutterSecureStorage(
    aOptions: kIsWeb ? const AndroidOptions() : _androidOptions,
    iOptions: _iosOptions, // Utiliser si tu supportes iOS
  );

  static const _apiKeyStorageKey = 'tmdb_api_key';

  /// Revue 2026-09-11, D1B-15 — **La clé est lue UNE fois, puis servie de
  /// mémoire.**
  ///
  /// Avant, chaque appel public de `TmdbService` (`_init`), chaque tap sur une
  /// vignette, chaque feuille d'actions (`FutureBuilder`), chaque recherche
  /// relisait le trousseau : un aller-retour par le canal natif et un
  /// déchiffrement (`encryptedSharedPreferences`), des dizaines de fois par
  /// minute au défilement d'une liste sans affiches.
  ///
  /// **Pourquoi c'est sûr** : cette classe est le SEUL écrivain de la clé
  /// (`saveApiKey`, `deleteApiKey` — page TMDB, restauration `.aether`,
  /// console web ; aucun `deleteAll` dans l'app, vérifié par grep). Toute
  /// écriture met la mémoire à jour APRÈS que le trousseau a répondu ; une
  /// écriture qui lève l'invalide (la lecture suivante retourne au trousseau).
  static String? _cachedKey;
  static bool _cacheValid = false;

  /// Avance à chaque écriture : une lecture partie AVANT une écriture ne doit
  /// pas remettre en mémoire la valeur qu'elle a lue (périmée).
  static int _writeGeneration = 0;

  /// Sauvegarde la clé d'API TMDb de manière sécurisée.
  static Future<void> saveApiKey(String key) async {
    final int gen = ++_writeGeneration;
    _cacheValid = false;
    await _storage.write(key: _apiKeyStorageKey, value: key);
    if (gen == _writeGeneration) {
      _cachedKey = key;
      _cacheValid = true;
    }
  }

  /// Récupère la clé d'API TMDb. Retourne `null` si aucune clé n'est sauvegardée.
  static Future<String?> getApiKey() async {
    if (_cacheValid) return _cachedKey;
    final int gen = _writeGeneration;
    final Stopwatch sw = Stopwatch()..start();
    final String? key = await _storage.read(key: _apiKeyStorageKey);
    if (gen == _writeGeneration) {
      _cachedKey = key;
      _cacheValid = true;
    }
    // D1B-15 — Sonde : une ligne par lecture RÉELLE du trousseau (une par
    // session, plus une après chaque changement de clé). Multipliée par le
    // nombre d'appels d'avant, elle chiffre ce que le cache économise.
    debugPrint('🔑 TmdbApiService — clé lue dans le trousseau en ${sw.elapsedMilliseconds} ms (servie de mémoire ensuite)');
    return key;
  }

  /// Supprime la clé d'API TMDb.
  static Future<void> deleteApiKey() async {
    final int gen = ++_writeGeneration;
    _cacheValid = false;
    await _storage.delete(key: _apiKeyStorageKey);
    if (gen == _writeGeneration) {
      _cachedKey = null;
      _cacheValid = true;
    }
  }

  /// Vérifie si une clé d'API est présente.
  static Future<bool> hasApiKey() async {
    final key = await getApiKey();
    return key != null && key.isNotEmpty;
  }

  /// Oublie la valeur mémorisée : la prochaine lecture retourne au trousseau.
  ///
  /// Appelé par `TmdbService.resetInstance()`, que TOUT chemin qui écrit ou
  /// efface la clé appelle déjà (invariant de la revue D1B-01) : ceinture et
  /// bretelles, si un jour une écriture contournait `saveApiKey`. Sert aussi
  /// aux tests, qui remplacent le trousseau simulé
  /// (`FlutterSecureStorage.setMockInitialValues`) sans passer par ici.
  static void invalidateCache() {
    _writeGeneration++;
    _cachedKey = null;
    _cacheValid = false;
  }
}
