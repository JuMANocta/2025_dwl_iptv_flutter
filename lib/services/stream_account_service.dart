import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/stream_account.dart';
import '../secure_storage_service.dart';

/// Service de gestion **multi-comptes IPTV**
/// Stockage : `flutter_secure_storage` (mêmes fondations que ton SecureStorageService)
///
/// Clés utilisées :
/// - `accounts_index`             → JSON: ["acc_...","acc_..."]
/// - `account:<id>`               → JSON d'un StreamAccount
/// - `current_account_id`         → "acc_..."
class StreamAccountService {
  static const String _kIndexKey = 'accounts_index';
  static const String _kCurrentKey = 'current_account_id';
  static String _kAccount(String id) => 'account:$id';

  // Même techno de stockage que ton SecureStorageService (EncryptedSharedPreferences sur Android).
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// Liste tous les comptes enregistrés (dans l'ordre de l'index).
  static Future<List<StreamAccount>> listAccounts() async {
    final raw = await _storage.read(key: _kIndexKey);
    if (raw == null || raw.isEmpty) return [];

    List<String> ids;
    try {
      ids = List<String>.from(jsonDecode(raw));
    } catch (_) {
      // Index corrompu → on réinitialise.
      await _storage.delete(key: _kIndexKey);
      return [];
    }

    final out = <StreamAccount>[];
    for (final id in ids) {
      final aj = await _storage.read(key: _kAccount(id));
      if (aj == null) continue;
      try {
        out.add(StreamAccount.fromJson(jsonDecode(aj)));
      } catch (_) {
        // entrée corrompue → ignorer
      }
    }
    return out;
  }

  static Future<void> _saveIndex(List<String> ids) async {
    // On supprime les doublons au passage.
    final uniq = <String>{};
    final normalized = <String>[];
    for (final id in ids) {
      if (uniq.add(id)) normalized.add(id);
    }
    await _storage.write(key: _kIndexKey, value: jsonEncode(normalized));
  }

  /// Crée ou met à jour un compte.
  /// Si l'id n'existe pas encore, il est ajouté à l'index.
  static Future<void> saveAccount(StreamAccount acc) async {
    final accounts = await listAccounts();
    final ids = accounts.map((a) => a.id).toList();
    if (!ids.contains(acc.id)) ids.add(acc.id);

    await _storage.write(key: _kAccount(acc.id), value: jsonEncode(acc.toJson()));
    await _saveIndex(ids);
  }

  /// Supprime un compte + maintient la sélection courante proprement.
  static Future<void> deleteAccount(String id) async {
    // Supprimer la fiche
    await _storage.delete(key: _kAccount(id));

    // Mettre à jour l'index
    final accounts = await listAccounts();
    final remaining = accounts.where((a) => a.id != id).map((a) => a.id).toList();
    await _saveIndex(remaining);

    // Mettre à jour le "current"
    final cur = await _storage.read(key: _kCurrentKey);
    if (cur == id) {
      if (remaining.isNotEmpty) {
        await _storage.write(key: _kCurrentKey, value: remaining.first);
      } else {
        await _storage.delete(key: _kCurrentKey);
      }
    }
  }

  /// Récupère un compte par son id.
  static Future<StreamAccount?> getAccount(String id) async {
    final raw = await _storage.read(key: _kAccount(id));
    if (raw == null) return null;
    try {
      return StreamAccount.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  /// Définit le compte courant (utilisé par défaut pour playlist/téléchargements).
  static Future<void> setCurrentAccount(String id) async {
    await _storage.write(key: _kCurrentKey, value: id);
  }

  /// Récupère le compte courant (ou le 1er de la liste si rien n'est sélectionné).
  static Future<StreamAccount?> getCurrentAccount() async {
    final curId = await _storage.read(key: _kCurrentKey);
    if (curId != null) {
      final acc = await getAccount(curId);
      if (acc != null) return acc;
      // si l'id courant ne correspond plus à un compte existant, on retombe sur le 1er.
    }
    final list = await listAccounts();
    if (list.isNotEmpty) {
      await setCurrentAccount(list.first.id);
      return list.first;
    }
    return null;
  }

  /// Migration automatique depuis l'ancien SecureStorageService "mono-compte".
  /// S'exécute une seule fois : si des comptes existent déjà, ne fait rien.
  static Future<void> migrateFromLegacyIfNeeded() async {
    final existing = await listAccounts();
    if (existing.isNotEmpty) return; // déjà migré / comptes présents

    // Récupère les credentials existants via ta classe déjà en place.
    final legacy = await SecureStorageService().getCredentials();
    final hasAny = legacy.values.any((v) => v != null && v.toString().trim().isNotEmpty);
    if (!hasAny) return;

    final bool hasComplete = (legacy['completeUrl'] ?? '').toString().trim().isNotEmpty;

    final acc = StreamAccount(
      id: "acc_${DateTime.now().millisecondsSinceEpoch}",
      label: "Compte par défaut",
      mode: hasComplete ? StreamAuthMode.completeUrl : StreamAuthMode.separate,
      completeUrl: (legacy['completeUrl'] ?? '').toString().trim().isNotEmpty
          ? (legacy['completeUrl'] as String)
          : null,
      baseUrl: (legacy['baseUrl'] ?? '').toString().trim().isNotEmpty
          ? (legacy['baseUrl'] as String)
          : null,
      username: (legacy['username'] ?? '').toString().trim().isNotEmpty
          ? (legacy['username'] as String)
          : null,
      password: (legacy['password'] ?? '').toString().trim().isNotEmpty
          ? (legacy['password'] as String)
          : null,
      cookies: (legacy['cookies'] ?? '').toString().trim().isNotEmpty
          ? (legacy['cookies'] as String)
          : null,
    );

    await saveAccount(acc);
    await setCurrentAccount(acc.id);
  }
}
