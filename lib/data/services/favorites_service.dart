import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/feature/search/m3u_filter.dart';

/// Service de gestion des favoris (§1d).
///
/// **Modèle** : un favori est identifié par une clé canonique de la forme
/// `"<type>|<groupKey>"` :
///   - `movie|Inception`
///   - `series|Breaking Bad`
///   - `tv|TF1`
///
/// `groupKey` est le `displayName` pour films/séries (= clé de regroupement
/// cross-comptes) et `tvGroupKey(displayName)` pour les chaînes (normalise les
/// suffixes de qualité).
///
/// **Stockage** :
///   - `SharedPreferences` clé `"favorites_v1"` → `List<String>` JSON
///   - Cache mémoire `_cache` chargé au premier accès
///   - `version` (`ValueNotifier<int>`) incrémenté à chaque modif → permet
///     aux widgets `ValueListenableBuilder` de se rebuilder
///
/// **API** : tout est statique. Pas d'injection, pas de DI — cohérent avec le
/// reste de l'app (`PlaylistService`, `ParsedPlaylistService`…).
class FavoritesService {
  static const String _prefsKey = 'favorites_v1';

  static final Set<String> _cache = <String>{};
  static bool _loaded = false;

  /// Bumpe à chaque modification — écouter via `ValueListenableBuilder`.
  static final ValueNotifier<int> version = ValueNotifier(0);

  // ── Génération des clés canoniques ──────────────────────────────────────

  /// Clé canonique pour une entrée M3U (cross-comptes, indépendante de la variante).
  static String keyFor(M3uEntry e) {
    final groupKey = e.type == M3uContentType.tv
        ? tvGroupKey(e.displayName)
        : e.displayName;
    return keyForGroup(e.type, groupKey);
  }

  /// Clé canonique pour un groupe (type + clé de regroupement).
  static String keyForGroup(M3uContentType type, String groupKey) {
    final t = switch (type) {
      M3uContentType.movie  => 'movie',
      M3uContentType.series => 'series',
      M3uContentType.tv     => 'tv',
    };
    return '$t|$groupKey';
  }

  // ── Chargement / persistence ────────────────────────────────────────────

  /// Charge le cache depuis `SharedPreferences` (idempotent).
  static Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final list = (jsonDecode(raw) as List).cast<String>();
        _cache.addAll(list);
      }
    } catch (e) {
      debugPrint('❌ FavoritesService: erreur chargement — $e');
    }
    _loaded = true;
  }

  /// Sauvegarde le cache dans `SharedPreferences` (fire & forget côté UI).
  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_cache.toList()));
    } catch (e) {
      debugPrint('❌ FavoritesService: erreur persistence — $e');
    }
  }

  // ── API publique ────────────────────────────────────────────────────────

  /// Initialise le service au démarrage de l'app (à appeler dans `main()`).
  /// Sans appel explicite, le cache se charge à la première lecture/écriture.
  static Future<void> init() => _ensureLoaded();

  /// Snapshot synchrone du jeu de favoris. Vide si non encore chargé.
  static Set<String> get all => Set.unmodifiable(_cache);

  /// Vrai si la clé est marquée comme favori.
  static bool isFavorite(String key) => _cache.contains(key);

  /// Vrai si l'entrée M3U correspond à un favori.
  static bool isEntryFavorite(M3uEntry e) => isFavorite(keyFor(e));

  /// Ajoute un favori. Idempotent.
  static Future<void> add(String key) async {
    await _ensureLoaded();
    if (_cache.add(key)) {
      version.value++;
      await _persist();
      debugPrint('⭐ FavoritesService: ajout — $key');
    }
  }

  /// Retire un favori. Idempotent.
  static Future<void> remove(String key) async {
    await _ensureLoaded();
    if (_cache.remove(key)) {
      version.value++;
      await _persist();
      debugPrint('🗑️ FavoritesService: retrait — $key');
    }
  }

  /// Toggle un favori. Retourne le nouvel état (`true` = favori ajouté).
  static Future<bool> toggle(String key) async {
    await _ensureLoaded();
    if (_cache.contains(key)) {
      await remove(key);
      return false;
    }
    await add(key);
    return true;
  }

  /// Vide tous les favoris (action destructive, utilisée pour reset/debug).
  static Future<void> clear() async {
    if (_cache.isEmpty) return;
    _cache.clear();
    version.value++;
    await _persist();
  }

  /// Remplace l'intégralité des favoris en une seule opération.
  /// Utilisé par le BackupService (§10) pour l'import. Une seule notification
  /// `version++` + un seul persist, contrairement à clear()+add()×N.
  static Future<void> replaceAll(Iterable<String> keys) async {
    await _ensureLoaded();
    _cache
      ..clear()
      ..addAll(keys);
    version.value++;
    await _persist();
  }
}
