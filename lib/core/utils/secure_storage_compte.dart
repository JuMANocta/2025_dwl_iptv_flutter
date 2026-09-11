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

  // Revue 2026-09-11, D1B-20 — Les écritures du stockage legacy
  // (`saveCredentials`, `saveCompleteUrl`, `saveSeparate`, `saveCookies`) et
  // `getCookies` n'avaient plus aucun appelant : ce stockage n'est plus que LU
  // (migration vers `StreamAccountService`, repli de §cookieScope) puis effacé.
  // ⛔ Ne rien y réécrire : un compte vit dans `StreamAccountService`.

  /// Efface le stockage mono-compte, en fin de migration réussie (D1B-10).
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
