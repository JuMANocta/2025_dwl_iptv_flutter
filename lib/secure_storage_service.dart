import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<void> saveCredentials(Map<String, String> credentials) async {
    for (var entry in credentials.entries) {
      await _storage.write(key: entry.key, value: entry.value);
    }
  }

  Future<Map<String, String?>> getCredentials() async {
    return await _storage.readAll();
  }

  Future<void> clearCredentials() async {
    await _storage.deleteAll();
  }
}