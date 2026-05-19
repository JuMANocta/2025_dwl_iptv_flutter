import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mémoire de la dernière chaîne TV regardée (§1i).
///
/// On stocke uniquement le minimum nécessaire pour relancer la chaîne
/// directement (URL + titre affichable + tvgId pour l'EPG).
/// Persisté dans `SharedPreferences` (`last_watched_channel_v1`).
class LastWatchedChannel {
  final String url;
  final String title;
  final String? tvgId;
  final String? logoUrl;
  final DateTime watchedAt;

  const LastWatchedChannel({
    required this.url,
    required this.title,
    this.tvgId,
    this.logoUrl,
    required this.watchedAt,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'tvgId': tvgId,
        'logoUrl': logoUrl,
        'watchedAt': watchedAt.toIso8601String(),
      };

  static LastWatchedChannel fromJson(Map<String, dynamic> j) =>
      LastWatchedChannel(
        url: j['url'] as String,
        title: j['title'] as String? ?? '',
        tvgId: j['tvgId'] as String?,
        logoUrl: j['logoUrl'] as String?,
        watchedAt: DateTime.tryParse(j['watchedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// Service statique — un seul "dernière chaîne" à la fois.
class LastWatchedChannelService {
  static const String _prefsKey = 'last_watched_channel_v1';

  static LastWatchedChannel? _cache;
  static bool _loaded = false;

  static final ValueNotifier<int> version = ValueNotifier(0);

  static Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        _cache = LastWatchedChannel.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('❌ LastWatchedChannelService: erreur chargement — $e');
    }
    _loaded = true;
  }

  static Future<void> init() => _ensureLoaded();

  /// Snapshot synchrone (peut être null si l'utilisateur n'a jamais regardé
  /// de TV ou si le cache n'est pas encore chargé).
  static LastWatchedChannel? get current => _cache;

  /// Enregistre la chaîne courante. Idempotent (skip si même URL).
  static Future<void> save({
    required String url,
    required String title,
    String? tvgId,
    String? logoUrl,
  }) async {
    await _ensureLoaded();
    if (_cache?.url == url) {
      // Même chaîne — on bump juste la date pour le tri ultérieur éventuel.
      _cache = LastWatchedChannel(
        url: url,
        title: title,
        tvgId: tvgId,
        logoUrl: logoUrl,
        watchedAt: DateTime.now(),
      );
    } else {
      _cache = LastWatchedChannel(
        url: url,
        title: title,
        tvgId: tvgId,
        logoUrl: logoUrl,
        watchedAt: DateTime.now(),
      );
    }
    version.value++;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_cache!.toJson()));
    } catch (e) {
      debugPrint('❌ LastWatchedChannelService: erreur persistence — $e');
    }
  }

  static Future<void> clear() async {
    if (_cache == null) return;
    _cache = null;
    version.value++;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }
}
