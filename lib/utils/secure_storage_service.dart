import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  // Clés historiques (et variantes vues dans l'ancien zip)
  static const String _kCompleteUrl = 'completeUrl';
  static const String _kUrl        = 'url';
  static const String _kM3u        = 'm3u';
  static const String _kBaseUrl    = 'baseUrl';
  static const String _kUsername   = 'username';
  static const String _kLogin      = 'login';
  static const String _kPassword   = 'password';
  static const String _kCookies    = 'cookies';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// Lit toutes les clés pertinentes et renvoie une map *riche*,
  ///
  /// Clés retournées possibles :
  /// - completeUrl, url, m3u
  /// - baseUrl, username, login, password
  /// - cookies
  Future<Map<String, String?>> getCredentials() async {
    final completeUrl = await _storage.read(key: _kCompleteUrl);
    final url         = await _storage.read(key: _kUrl);
    final m3u         = await _storage.read(key: _kM3u);
    final baseUrl     = await _storage.read(key: _kBaseUrl);
    final username    = await _storage.read(key: _kUsername);
    final login       = await _storage.read(key: _kLogin);
    final password    = await _storage.read(key: _kPassword);
    final cookies     = await _storage.read(key: _kCookies);

    return <String, String?>{
      'completeUrl': completeUrl,
      'url'       : url,
      'm3u'       : m3u,
      'baseUrl'   : baseUrl,
      'username'  : username,
      'login'     : login,
      'password'  : password,
      'cookies'   : cookies,
    };
  }

  /// Écrit plusieurs clés d’un coup (utilisé pour sauver `cookies` après Set-Cookie).
  /// N’écrit que les clés connues. Si valeur vide/null → supprime la clé.
  Future<void> saveCredentials(Map<String, String?> updates) async {
    for (final entry in updates.entries) {
      final k = entry.key;
      final v = entry.value?.trim();

      // Liste blanche des clés acceptées
      if (k == 'completeUrl' || k == _kCompleteUrl) {
        await _writeOrDelete(_kCompleteUrl, v);
      } else if (k == 'url' || k == _kUrl) {
        await _writeOrDelete(_kUrl, v);
      } else if (k == 'm3u' || k == _kM3u) {
        await _writeOrDelete(_kM3u, v);
      } else if (k == 'baseUrl' || k == _kBaseUrl) {
        await _writeOrDelete(_kBaseUrl, v);
      } else if (k == 'username' || k == _kUsername) {
        await _writeOrDelete(_kUsername, v);
      } else if (k == 'login' || k == _kLogin) {
        await _writeOrDelete(_kLogin, v);
      } else if (k == 'password' || k == _kPassword) {
        await _writeOrDelete(_kPassword, v);
      } else if (k == 'cookies' || k == _kCookies) {
        await _writeOrDelete(_kCookies, v);
      } else {
        // ignore clé inconnue
      }
    }
  }

  Future<void> _writeOrDelete(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: value);
    }
  }

  /// Helpers ciblés (compat)
  Future<void> saveCompleteUrl(String? url) async =>
      _writeOrDelete(_kCompleteUrl, url?.trim());

  Future<void> saveSeparate({
    String? baseUrl,
    String? username,
    String? password,
  }) async {
    await _writeOrDelete(_kBaseUrl, baseUrl?.trim());
    await _writeOrDelete(_kUsername, username?.trim());
    await _writeOrDelete(_kPassword, password?.trim());
  }

  Future<void> saveCookies(String? cookies) async =>
      _writeOrDelete(_kCookies, cookies?.trim());

  Future<String?> getCookies() async => _storage.read(key: _kCookies);

  Future<void> clearLegacy() async {
    await _storage.delete(key: _kCompleteUrl);
    await _storage.delete(key: _kUrl);
    await _storage.delete(key: _kM3u);
    await _storage.delete(key: _kBaseUrl);
    await _storage.delete(key: _kUsername);
    await _storage.delete(key: _kLogin);
    await _storage.delete(key: _kPassword);
    await _storage.delete(key: _kCookies);
  }
}
