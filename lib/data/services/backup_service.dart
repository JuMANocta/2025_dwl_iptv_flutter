import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/settings/perf_config.dart';
import 'hidden_regions_service.dart';
import 'visual_language_service.dart';
import '../../core/utils/user_error.dart' show UserFacingException;
import '../../core/settings/performance_settings_service.dart';
import '../../core/themes/app_theme_config.dart';
import '../../core/themes/theme_service.dart';
import '../models/stream_account.dart';
import 'favorites_service.dart';
import 'parsed_playlist_service.dart';
import 'stream_account_service.dart';
import 'tmdb_api_service.dart';
import 'tmdb_service.dart';
import 'watch_progress_service.dart';

/// Sauvegarde / restauration de la configuration (§10).
///
/// **Format du fichier `.aether`** (binaire, AES-256-GCM + PBKDF2-SHA256) :
/// ```
///   [4 bytes "AETH"] [1 byte version=1]
///   [16 bytes salt]  [12 bytes nonce]
///   [N bytes ciphertext]
///   [16 bytes mac (auth tag GCM)]
/// ```
/// Le `mac` est validé au déchiffrement : un mot de passe incorrect ou un
/// fichier altéré lève une `FormatException`.
///
/// **Contenu sauvegardé** : comptes IPTV, clé TMDB, thème custom, favoris,
/// progression de lecture. Exclus : search history, dernière chaîne TV
/// (éphémères) et téléchargements (trop volumineux).
///
/// **Stockage** : `/storage/emulated/0/Download/AetherStream/backup_*.aether`
/// via `media_store_plus`. Survit à l'uninstall, visible dans le file manager.

/// §langRegion — Lit une liste de chaînes sans jamais lever : tout ce qui
/// n'est pas une liste rend `null`, et les éléments non-textuels sont écartés.
List<String>? _readStringList(Object? raw) {
  if (raw is! List) return null;
  return raw.whereType<String>().toList(growable: false);
}

class BackupContent {
  final String appVersion;
  final DateTime exportedAt;
  final List<Map<String, dynamic>> accounts;
  final String? activeAccountId;
  final String? tmdbKey;
  final Map<String, dynamic>? theme;

  /// §perfSettings — réglages d'optimisation (null sur les vieux backups).
  final Map<String, dynamic>? perf;

  /// §langRegion — Langues / régions masquées. ⚠️ **`null` et liste vide ne
  /// veulent pas dire la même chose et se traitent pourtant pareil** :
  /// absent d'un vieux fichier comme explicitement vide, on ne coche rien.
  /// Une sauvegarde antérieure à ce champ ne doit JAMAIS faire échouer une
  /// restauration ni inventer un masquage.
  final List<String>? hiddenRegions;

  /// §posterLang — Langue des visuels TMDB (`auto|fr|en|original`).
  /// Même règle que [hiddenRegions] : `null` sur une sauvegarde antérieure à
  /// ce champ → on ne touche PAS au réglage local de la cible.
  final String? visualLanguage;
  final List<String> favorites;
  final Map<String, Map<String, dynamic>> watchProgress;

  const BackupContent({
    required this.appVersion,
    required this.exportedAt,
    required this.accounts,
    required this.activeAccountId,
    required this.tmdbKey,
    required this.theme,
    this.perf,
    this.hiddenRegions,
    this.visualLanguage,
    required this.favorites,
    required this.watchProgress,
  });

  Map<String, dynamic> toJson() => {
        'appVersion': appVersion,
        'exportedAt': exportedAt.toIso8601String(),
        'accounts': accounts,
        'activeAccountId': activeAccountId,
        'tmdbKey': tmdbKey,
        'theme': theme,
        'perf': perf,
        'hiddenRegions': hiddenRegions,
        'visualLanguage': visualLanguage,
        'favorites': favorites,
        'watchProgress': watchProgress,
      };

  factory BackupContent.fromJson(Map<String, dynamic> j) => BackupContent(
        appVersion: j['appVersion'] as String? ?? '?',
        exportedAt: DateTime.tryParse(j['exportedAt'] as String? ?? '') ??
            DateTime.now(),
        accounts:
            (j['accounts'] as List?)?.cast<Map<String, dynamic>>() ?? const [],
        activeAccountId: j['activeAccountId'] as String?,
        tmdbKey: j['tmdbKey'] as String?,
        theme: j['theme'] as Map<String, dynamic>?,
        perf: j['perf'] as Map<String, dynamic>?,
        // ⚠️ Tolérant pour de vrai : un `as List?` LÈVE sur une chaîne. On
        // teste le type au lieu de le supposer — champ absent, nul ou
        // inattendu donne `null`, donc « rien de coché », jamais une
        // restauration qui échoue pour un champ accessoire.
        hiddenRegions: _readStringList(j['hiddenRegions']),
        visualLanguage: j['visualLanguage'] as String?,
        favorites: (j['favorites'] as List?)?.cast<String>() ?? const [],
        watchProgress: ((j['watchProgress'] as Map?)
                ?.cast<String, Map<String, dynamic>>()) ??
            const {},
      );

  /// Résumé court pour les dialogs (affiché à l'utilisateur).
  String summary() {
    final parts = <String>[];
    if (accounts.isNotEmpty) {
      parts.add('${accounts.length} compte${accounts.length > 1 ? 's' : ''}');
    }
    if ((tmdbKey ?? '').isNotEmpty) parts.add('clé TMDB');
    if (theme != null) parts.add('thème');
    if (perf != null) parts.add('optimisation');
    final int regions = hiddenRegions?.length ?? 0;
    if (regions > 0) {
      parts.add('$regions langue${regions > 1 ? 's' : ''} masquée'
          '${regions > 1 ? 's' : ''}');
    }
    if (favorites.isNotEmpty) {
      parts.add('${favorites.length} favori${favorites.length > 1 ? 's' : ''}');
    }
    if (watchProgress.isNotEmpty) {
      parts.add(
          '${watchProgress.length} progression${watchProgress.length > 1 ? 's' : ''}');
    }
    if (parts.isEmpty) return 'Sauvegarde vide';
    return parts.join(' · ');
  }
}

class BackupService {
  static const List<int> _magic = [0x41, 0x45, 0x54, 0x48]; // "AETH"
  static const int _formatVersion = 1;
  static const int _saltLen = 16;
  static const int _nonceLen = 12;
  static const int _macLen = 16;
  static const int _headerLen = 4 + 1 + _saltLen + _nonceLen;
  // PBKDF2 — 100k itérations = ~250 ms sur smartphone moderne. Bon compromis
  // sécurité / latence (l'utilisateur ne saisit son mot de passe qu'à
  // l'export / import, pas à chaque opération).
  static const int _pbkdf2Iterations = 100000;

  static final Random _rng = Random.secure();

  // ── EXPORT ────────────────────────────────────────────────────────────────

  /// Collecte toute la configuration, la chiffre avec [password], et sauvegarde
  /// le fichier `.aether` dans `Download/AetherStream/`. Retourne le nom du
  /// fichier généré (le chemin complet dépend du device).
  static Future<String> exportAll(String password) async {
    if (password.isEmpty) {
      throw ArgumentError('Le mot de passe ne peut pas être vide.');
    }
    debugPrint('📤 BackupService: collecte des données…');
    final content = await _collectAll();
    final jsonStr = jsonEncode(content.toJson());
    final encrypted = await _encrypt(utf8.encode(jsonStr), password);

    // Écrit d'abord dans le cache privé.
    final cacheDir = await getTemporaryDirectory();
    final fileName = _buildBackupFileName();
    final tempPath = '${cacheDir.path}/$fileName';
    final tempFile = File(tempPath);
    await tempFile.writeAsBytes(encrypted, flush: true);

    // Déplace vers Download/AetherStream/ via MediaStore (le sous-dossier
    // "AetherStream" est défini globalement par MediaStore.appFolder dans main.dart).
    try {
      final mediaStore = MediaStore();
      await mediaStore.saveFile(
        tempFilePath: tempPath,
        dirType: DirType.download,
        dirName: DirName.download,
        relativePath: null,
      );
    } catch (e) {
      debugPrint(
          '💀 BackupService: MediaStore a échoué — $e (le fichier reste en cache privé).');
      // On laisse le fichier dans le cache plutôt que de le perdre.
      rethrow;
    }

    // Le déplacement a fait une copie côté MediaStore → on peut effacer le temp.
    try {
      if (await tempFile.exists()) await tempFile.delete();
    } catch (_) {}

    debugPrint('✅ BackupService: export terminé — $fileName');
    return fileName;
  }

  /// Variante de [exportAll] qui retourne directement les octets chiffrés
  /// `.aether` SANS écrire de fichier (utilisée par la console web pour
  /// proposer le téléchargement au navigateur). Retourne aussi le nom suggéré.
  static Future<({String fileName, Uint8List bytes})> exportToBytes(
      String password) async {
    if (password.isEmpty) {
      throw ArgumentError('Le mot de passe ne peut pas être vide.');
    }
    final content = await _collectAll();
    final jsonStr = jsonEncode(content.toJson());
    final encrypted = await _encrypt(utf8.encode(jsonStr), password);
    return (fileName: _buildBackupFileName(), bytes: encrypted);
  }

  // ── IMPORT ────────────────────────────────────────────────────────────────

  /// Comme [readBackup] mais à partir d'octets en mémoire (upload console web).
  static Future<BackupContent> readBackupBytes(
      Uint8List bytes, String password) async {
    final plain = await _decrypt(bytes, password);
    final json = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    return BackupContent.fromJson(json);
  }

  /// Lit + décrypte un fichier `.aether`. Retourne le contenu sans l'appliquer
  /// (utile pour afficher un résumé à l'utilisateur avant confirmation).
  ///
  /// Throws :
  ///   - [FormatException] si le fichier n'est pas un `.aether` valide ou si
  ///     le mot de passe est incorrect (le MAC GCM ne valide pas).
  static Future<BackupContent> readBackup(
      String filePath, String password) async {
    final bytes = await File(filePath).readAsBytes();
    final plain = await _decrypt(bytes, password);
    final json = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    return BackupContent.fromJson(json);
  }

  /// Applique un [BackupContent] en ÉCRASANT l'état courant.
  /// L'appelant DOIT avoir confirmé l'action côté UI (dialog de confirmation).
  static Future<void> applyBackup(BackupContent content) async {
    debugPrint('📥 BackupService: application — ${content.summary()}');

    // 1. Comptes IPTV — wipe puis re-create.
    final existing = await StreamAccountService.listAccounts();
    for (final acc in existing) {
      await StreamAccountService.deleteAccount(acc.id);
    }
    for (final json in content.accounts) {
      try {
        await StreamAccountService.saveAccount(StreamAccount.fromJson(json));
      } catch (e) {
        debugPrint('⚠️ Compte ignoré (parse fail) — $e');
      }
    }
    if ((content.activeAccountId ?? '').isNotEmpty) {
      try {
        await StreamAccountService.setCurrentAccount(content.activeAccountId!);
      } catch (e) {
        debugPrint('⚠️ Compte actif non restauré — $e');
      }
    }

    // 2. Clé TMDB
    if ((content.tmdbKey ?? '').isNotEmpty) {
      await TmdbApiService.saveApiKey(content.tmdbKey!);
    } else {
      await TmdbApiService.deleteApiKey();
    }
    TmdbService.resetInstance();

    // 3. Thème
    if (content.theme != null) {
      try {
        final cfg = AppThemeConfig.fromJson(content.theme!);
        await ThemeService.save(cfg);
      } catch (e) {
        debugPrint('⚠️ Thème ignoré (parse fail) — $e');
      }
    }

    // 3b. §perfSettings — Réglages d'optimisation (absents des vieux backups).
    if (content.perf != null) {
      try {
        await PerformanceSettingsService.save(
            PerfConfig.fromJson(content.perf!));
      } catch (e) {
        debugPrint('⚠️ Réglages optimisation ignorés (parse fail) — $e');
      }
    }

    // 3c. §langRegion — Langues / régions masquées. Absent d'un vieux
    // fichier : on ne touche à rien (l'utilisateur garde son réglage local)
    // plutôt que d'imposer un masquage vide venu de nulle part.
    final List<String>? regions = content.hiddenRegions;
    if (regions != null) {
      try {
        await HiddenRegionsService.setHidden(regions.toSet());
      } catch (e) {
        debugPrint('⚠️ Langues/régions ignorées (restauration) — $e');
      }
    }

    // 3d. §posterLang — Langue des visuels. Même règle que ci-dessus : `null`
    // (sauvegarde antérieure au champ) ou code inconnu → on ne touche pas au
    // réglage local, plutôt que d'imposer un défaut venu de nulle part.
    final VisualLanguage? visual =
        VisualLanguageService.fromCode(content.visualLanguage);
    if (visual != null) {
      try {
        await VisualLanguageService.set(visual);
      } catch (e) {
        debugPrint('⚠️ Langue des visuels ignorée (restauration) — $e');
      }
    }

    // 4. Favoris
    await FavoritesService.replaceAll(content.favorites);

    // 5. Progressions de lecture
    final wp = <String, WatchProgress>{};
    for (final entry in content.watchProgress.entries) {
      try {
        wp[entry.key] = WatchProgress.fromJson(entry.key, entry.value);
      } catch (_) {}
    }
    await WatchProgressService.replaceAll(wp);

    // 6. Hub mémoire playlist : on invalide tout. Les playlists seront
    //    re-téléchargées au prochain switch / démarrage.
    final newAccounts = await StreamAccountService.listAccounts();
    for (final acc in newAccounts) {
      ParsedPlaylistService.invalidate(acc.id);
    }

    debugPrint('✅ BackupService: restauration terminée.');
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  static Future<BackupContent> _collectAll() async {
    final accounts = await StreamAccountService.listAccounts();
    final currentAccount = await StreamAccountService.getCurrentAccount();
    final tmdbKey = await TmdbApiService.getApiKey();
    final theme = ThemeService.config.value;
    final favorites = FavoritesService.all.toList();
    final wp = WatchProgressService.all;
    final wpMap = <String, Map<String, dynamic>>{
      for (final p in wp) p.url: p.toJson(),
    };

    final info = await PackageInfo.fromPlatform();

    return BackupContent(
      appVersion: '${info.version}+${info.buildNumber}',
      exportedAt: DateTime.now(),
      accounts: accounts.map((a) => a.toJson()).toList(),
      activeAccountId: currentAccount?.id,
      tmdbKey: tmdbKey,
      theme: theme.toJson(),
      perf: PerformanceSettingsService.config.value.toJson(),
      hiddenRegions: HiddenRegionsService.hidden.toList(growable: false),
      visualLanguage: VisualLanguageService.value.name,
      favorites: favorites,
      watchProgress: wpMap,
    );
  }

  static String _buildBackupFileName() {
    final now = DateTime.now();
    String pad(int n) => n.toString().padLeft(2, '0');
    return 'backup_'
        '${now.year}-${pad(now.month)}-${pad(now.day)}_'
        '${pad(now.hour)}${pad(now.minute)}.aether';
  }

  // ── Crypto ────────────────────────────────────────────────────────────────

  static Future<Uint8List> _encrypt(List<int> plain, String password) async {
    final salt = _randomBytes(_saltLen);
    final key = await _deriveKey(password, salt);
    final nonce = _randomBytes(_nonceLen);
    final algo = AesGcm.with256bits();
    final box = await algo.encrypt(plain, secretKey: key, nonce: nonce);
    final out = BytesBuilder()
      ..add(_magic)
      ..addByte(_formatVersion)
      ..add(salt)
      ..add(nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return out.toBytes();
  }

  static Future<List<int>> _decrypt(Uint8List bytes, String password) async {
    // §userErrorOwn — [UserFacingException] et non `FormatException` : ces
    // messages sont écrits pour l'utilisateur, et `describeError` traduisait
    // toute `FormatException` par « Réponse illisible du serveur (format
    // inattendu) » — une phrase qui parle d'un SERVEUR alors qu'il s'agit
    // d'un fichier local et, le plus souvent, d'un mot de passe mal tapé.
    if (bytes.length < _headerLen + _macLen) {
      throw const UserFacingException(
          'Fichier de sauvegarde trop court ou corrompu.');
    }
    for (int i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) {
        throw const UserFacingException(
            'Ce n\'est pas un fichier .aether valide.');
      }
    }
    final version = bytes[4];
    if (version != _formatVersion) {
      throw UserFacingException(
          'Sauvegarde créée par une version plus récente de l\'app '
          '(format $version).');
    }
    final salt = bytes.sublist(5, 5 + _saltLen);
    final nonce = bytes.sublist(5 + _saltLen, 5 + _saltLen + _nonceLen);
    final macStart = bytes.length - _macLen;
    final cipherText = bytes.sublist(_headerLen, macStart);
    final macBytes = bytes.sublist(macStart);

    final key = await _deriveKey(password, salt);
    final algo = AesGcm.with256bits();
    try {
      return await algo.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
        secretKey: key,
      );
    } on SecretBoxAuthenticationError {
      // Le cas de LOIN le plus fréquent : le MAC GCM ne valide pas parce que
      // le mot de passe est faux. Le dire en premier, et sans jargon.
      throw const UserFacingException(
          'Mot de passe incorrect, ou fichier de sauvegarde altéré.');
    }
  }

  static Future<SecretKey> _deriveKey(String password, List<int> salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _pbkdf2Iterations,
      bits: 256,
    );
    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }

  static List<int> _randomBytes(int n) =>
      List<int>.generate(n, (_) => _rng.nextInt(256));
}
