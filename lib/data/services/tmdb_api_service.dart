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

  /// Sauvegarde la clé d'API TMDb de manière sécurisée.
  static Future<void> saveApiKey(String key) async {
    await _storage.write(key: _apiKeyStorageKey, value: key);
  }

  /// Récupère la clé d'API TMDb. Retourne `null` si aucune clé n'est sauvegardée.
  static Future<String?> getApiKey() async {
    return await _storage.read(key: _apiKeyStorageKey);
  }

  /// Supprime la clé d'API TMDb.
  static Future<void> deleteApiKey() async {
    await _storage.delete(key: _apiKeyStorageKey);
  }

  /// Vérifie si une clé d'API est présente.
  static Future<bool> hasApiKey() async {
    final key = await getApiKey();
    return key != null && key.isNotEmpty;
  }
}
