import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/models/parsed_playlist.dart';
import 'package:aetherStream/data/models/stream_account.dart';
import 'package:aetherStream/feature/search/m3u_parser.dart';

/// Hub central des playlists parsées.
///
/// Cycle de vie :
///   1. [loadActive] — démarrage, compte actif uniquement (cache disque ou parse complet)
///   2. [preloadOthersFromDisk] — background silencieux, autres comptes depuis disque uniquement
///   3. [entries] — accès synchrone à toutes les entrées disponibles en mémoire
///   4. [invalidate] — appelé par PlaylistService après téléchargement d'une nouvelle playlist
class ParsedPlaylistService {
  // ── Mémoire — persiste toute la session app ───────────────────────────────
  static final Map<String, ParsedPlaylist> _memory = {};
  /// accountId → label affiché (ex: "Provider FR") — pour les badges multi-comptes.
  static final Map<String, String> _accountNames = {};
  /// Bumpe à chaque fois qu'une playlist est ajoutée/retirée de [_memory].
  /// Les widgets qui font [entries] peuvent écouter ce notifier pour se rebuilder.
  static final ValueNotifier<int> version = ValueNotifier(0);

  // ── API publique ───────────────────────────────────────────────────────────

  /// Charge le compte actif.
  /// - Cache mémoire → retour immédiat.
  /// - Cache disque valide → ~50ms.
  /// - Sinon → parse complet + sauvegarde disque (fire & forget).
  static Future<ParsedPlaylist> loadActive(
    String accountId,
    String accountName,
    String m3uPath, {
    void Function(double)? onProgress,
  }) async {
    // 1. Déjà en mémoire
    if (_memory.containsKey(accountId)) {
      _accountNames[accountId] = accountName;
      onProgress?.call(1.0);
      debugPrint('⚡ ParsedPlaylist: déjà en mémoire — $accountName');
      return _memory[accountId]!;
    }

    // 2. Cache disque valide
    final disk = await _loadFromDisk(accountId, m3uPath);
    if (disk != null) {
      debugPrint('✅ ParsedPlaylist: cache disque chargé — $accountName (${disk.entries.length} entrées)');
      _memory[accountId] = disk;
      _accountNames[accountId] = accountName;
      onProgress?.call(1.0);
      version.value++;
      return disk;
    }

    // 3. Parse complet du fichier .m3u
    debugPrint('🔍 ParsedPlaylist: parse complet — $accountName');
    final films   = <M3uEntry>[];
    final series  = <M3uEntry>[];
    final tv      = <M3uEntry>[];
    await M3uParser.parseFile(
      m3uPath, films, series, tv,
      accountId: accountId,
      onProgress: onProgress,
    );

    final allEntries = [...films, ...series, ...tv];
    final m3uModified = await File(m3uPath).lastModified();
    final playlist = ParsedPlaylist(
      accountId:    accountId,
      schema:       ParsedPlaylist.schemaVersion,
      m3uModifiedAt: m3uModified,
      entries:      allEntries,
    );

    _memory[accountId] = playlist;
    _accountNames[accountId] = accountName;
    version.value++;

    // Sauvegarde disque en arrière-plan (non bloquant)
    _saveToDisk(accountId, playlist);

    debugPrint('✅ ParsedPlaylist: parse terminé — ${allEntries.length} entrées');
    return playlist;
  }

  /// Précharge les autres comptes depuis le disque uniquement (background silencieux).
  /// N'effectue aucun téléchargement réseau — ignore les comptes sans cache disque.
  static Future<void> preloadOthersFromDisk(List<StreamAccount> accounts) async {
    for (final acc in accounts) {
      if (_memory.containsKey(acc.id)) continue;
      // Construire le chemin M3U attendu (même convention que PlaylistService)
      final dir = await getApplicationDocumentsDirectory();
      final m3uPath = '${dir.path}/playlist_${acc.id}.m3u';
      if (!File(m3uPath).existsSync()) continue;

      final disk = await _loadFromDisk(acc.id, m3uPath);
      if (disk != null) {
        _memory[acc.id] = disk;
        _accountNames[acc.id] = acc.label;
        debugPrint('✅ ParsedPlaylist: préchargé depuis disque — ${acc.label} (${disk.entries.length} entrées)');
        version.value++;
      }
    }
  }

  // ── Accesseurs synchrones ─────────────────────────────────────────────────

  /// Toutes les entrées de tous les comptes actuellement chargés en mémoire.
  /// Utilisé par ActorDetailsPage, FavoritesService, etc.
  static List<M3uEntry> get entries =>
      _memory.values.expand((p) => p.entries).toList();

  /// Entrées avec le compte prioritaire en PREMIER.
  /// À utiliser dans RechercheM3U pour que putIfAbsent donne la priorité
  /// aux URLs/qualités du compte actif sur les autres comptes chargés.
  static List<M3uEntry> entriesWithPriority(String priorityAccountId) {
    final priority = _memory[priorityAccountId]?.entries ?? [];
    final others   = _memory.entries
        .where((e) => e.key != priorityAccountId)
        .expand((e) => e.value.entries)
        .toList();
    return [...priority, ...others];
  }

  /// Playlist d'un compte spécifique (null si pas encore chargée).
  static ParsedPlaylist? getAccount(String accountId) => _memory[accountId];

  /// Vrai si plusieurs comptes sont chargés en mémoire → afficher les badges provider.
  static bool get isMultiAccount => _memory.length > 1;

  /// Nom affiché d'un compte (pour les badges [Provider A] dans les action sheets).
  static String? accountName(String accountId) => _accountNames[accountId];

  // ── Invalidation ──────────────────────────────────────────────────────────

  /// Invalide le cache mémoire + disque pour un compte.
  /// À appeler par PlaylistService après le téléchargement d'une nouvelle playlist.
  static void invalidate(String accountId) {
    _memory.remove(accountId);
    version.value++;
    _deleteDiskCache(accountId);
    debugPrint('🗑️ ParsedPlaylist: cache invalidé — $accountId');
  }

  /// Vide entièrement la mémoire (ex: déconnexion globale).
  static void clear() {
    _memory.clear();
    _accountNames.clear();
    version.value++;
  }

  // ── Disque — JSON gzippé ──────────────────────────────────────────────────

  static Future<String> _diskCachePath(String accountId) async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/parsed_playlist_$accountId.json.gz';
  }

  static Future<ParsedPlaylist?> _loadFromDisk(String accountId, String m3uPath) async {
    try {
      final path = await _diskCachePath(accountId);
      final cacheFile = File(path);
      if (!await cacheFile.exists()) return null;

      // Décompresser + désérialiser
      final compressed = await cacheFile.readAsBytes();
      final jsonBytes  = GZipCodec().decode(compressed);
      final json       = jsonDecode(utf8.decode(jsonBytes)) as Map<String, dynamic>;
      final playlist   = ParsedPlaylist.fromJson(json);

      // Invalider si schéma obsolète
      if (playlist.schema != ParsedPlaylist.schemaVersion) {
        debugPrint('⚠️ ParsedPlaylist: schéma v${playlist.schema} obsolète (v${ParsedPlaylist.schemaVersion} attendu) → invalidation');
        await cacheFile.delete();
        return null;
      }

      // Invalider si le fichier .m3u a été re-téléchargé depuis
      final m3uFile = File(m3uPath);
      if (!await m3uFile.exists()) return null;
      final m3uModified = await m3uFile.lastModified();
      if (playlist.m3uModifiedAt.isBefore(m3uModified.subtract(const Duration(seconds: 5)))) {
        debugPrint('⚠️ ParsedPlaylist: fichier M3U modifié → re-parse nécessaire');
        await cacheFile.delete();
        return null;
      }

      return playlist;
    } catch (e) {
      debugPrint('❌ ParsedPlaylist: erreur chargement disque — $e');
      return null;
    }
  }

  static Future<void> _saveToDisk(String accountId, ParsedPlaylist playlist) async {
    try {
      final path      = await _diskCachePath(accountId);
      final jsonStr   = jsonEncode(playlist.toJson());
      final compressed = GZipCodec().encode(utf8.encode(jsonStr));
      await File(path).writeAsBytes(compressed);
      debugPrint('💾 ParsedPlaylist: sauvegardé — ${(compressed.length / 1024).toStringAsFixed(0)} Ko');
    } catch (e) {
      debugPrint('❌ ParsedPlaylist: erreur sauvegarde disque — $e');
    }
  }

  static Future<void> _deleteDiskCache(String accountId) async {
    try {
      final path = await _diskCachePath(accountId);
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
