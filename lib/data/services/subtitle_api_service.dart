import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Lot 11 — La clé du fournisseur de sous-titres en ligne (Wyzie), saisie par
/// l'utilisateur et gardée dans le trousseau, exactement comme la clé TMDB
/// (`TmdbApiService`). ⚠️ Aucune clé n'est intégrée à l'application : un quota
/// partagé qui saute et une violation des conditions du fournisseur.
class SubtitleApiService {
  static const AndroidOptions _androidOptions = AndroidOptions(
    encryptedSharedPreferences: true,
  );

  static final _storage = FlutterSecureStorage(
    aOptions: kIsWeb ? const AndroidOptions() : _androidOptions,
  );

  static const _apiKeyStorageKey = 'wyzie_api_key';

  /// Où l'utilisateur obtient sa clé gratuite (affiché tel quel, jamais ouvert
  /// sur téléviseur : critère TV-WB, aucun navigateur). ⚠️ `/redeem` et non la
  /// racine : c'est la page qui délivre la clé — vérifié le 2026-09-17 sur la
  /// documentation du fournisseur.
  static const String signupUrl = 'https://store.wyzie.io/redeem';

  static String? _cachedKey;
  static bool _cacheValid = false;
  static int _writeGeneration = 0;

  static Future<void> saveApiKey(String key) async {
    final int gen = ++_writeGeneration;
    _cacheValid = false;
    await _storage.write(key: _apiKeyStorageKey, value: key.trim());
    if (gen == _writeGeneration) {
      _cachedKey = key.trim();
      _cacheValid = true;
    }
  }

  static Future<String?> getApiKey() async {
    if (_cacheValid) return _cachedKey;
    final int gen = _writeGeneration;
    final String? key = await _storage.read(key: _apiKeyStorageKey);
    if (gen == _writeGeneration) {
      _cachedKey = key;
      _cacheValid = true;
    }
    return key;
  }

  static Future<void> deleteApiKey() async {
    final int gen = ++_writeGeneration;
    _cacheValid = false;
    await _storage.delete(key: _apiKeyStorageKey);
    if (gen == _writeGeneration) {
      _cachedKey = null;
      _cacheValid = true;
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _cachedKey = null;
    _cacheValid = false;
  }
}
