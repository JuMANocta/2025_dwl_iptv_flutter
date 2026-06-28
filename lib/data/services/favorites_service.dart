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
  /// §23 — films/séries via [contentGroupKey] (minuscules) pour suivre la
  /// fusion cross-listes insensible à la casse. TV inchangé (tvGroupKey).
  /// §favYear — FILMS **et SÉRIES** incluent l'année (`movie|titre|année`,
  /// `series|titre|année`) pour ne pas mélanger les homonymes/remakes (cohérent
  /// avec §homonymYear des carrousels). TV inchangé (tvGroupKey).
  static String keyFor(M3uEntry e) {
    if (e.type == M3uContentType.tv) {
      return keyForGroup(e.type, tvGroupKey(e.displayName));
    }
    // movie | series : type|titre|année
    final t = e.type == M3uContentType.movie ? 'movie' : 'series';
    return '$t|${contentGroupKey(e)}|${e.title.year ?? ''}';
  }

  /// §favYear — Ancienne clé SANS année (`movie|titre` / `series|titre`), telle
  /// que stockée avant 2026-06-11. Conservée pour la rétro-compat : un favori
  /// legacy continue d'allumer le cœur (cf. [isEntryFavorite]) jusqu'à ce que
  /// l'utilisateur le re-toggle (qui le nettoie via [toggleEntry]).
  static String _legacyKey(M3uEntry e) {
    final t = e.type == M3uContentType.movie ? 'movie' : 'series';
    return '$t|${contentGroupKey(e)}';
  }

  /// §favPersistFix — Normalise une clé de favori **stockée** vers la forme
  /// canonique courante `type|groupKey[|année]`.
  ///
  /// Migration §23b : `groupKey` repassé en minuscules + ponctuation normalisée
  /// (`computeGroupKey`) pour les anciennes clés movie/series.
  ///
  /// ⚠️ Correctif persistance : l'ancienne version normalisait **tout** ce qui
  /// suit le 1er `|`, transformant `series|titre|2008` → `series|titre 2008`
  /// (le séparateur d'année `|` devenait une espace). La clé ne correspondait
  /// alors plus à [keyFor] → le favori « disparaissait » à chaque redémarrage,
  /// re-corrompu puis re-persisté. On isole désormais le **suffixe d'année** et
  /// on ne normalise QUE le `groupKey` → opération idempotente sur une clé saine.
  @visibleForTesting
  static String normalizeStoredKey(String key) {
    if (!key.startsWith('movie|') && !key.startsWith('series|')) return key;
    final firstSep = key.indexOf('|');
    final type = key.substring(0, firstSep);
    var body = key.substring(firstSep + 1); // groupKey[|année]
    String yearSuffix = '';
    // §favYear — l'année (chiffres ou vide) est le segment après le DERNIER `|`.
    final lastSep = body.lastIndexOf('|');
    if (lastSep >= 0) {
      final tail = body.substring(lastSep + 1);
      if (RegExp(r'^\d{0,4}$').hasMatch(tail)) {
        yearSuffix = '|$tail';
        body = body.substring(0, lastSep);
      }
    }
    return '$type|${TitleMetadata.computeGroupKey(body)}$yearSuffix';
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
        // §23b — Migration one-shot : les clés movie/series étaient stockées
        // avec la casse + ponctuation d'origine du displayName ; la clé
        // canonique est désormais `TitleMetadata.computeGroupKey` (minuscules
        // + ponctuation → espace, alignée sur la fusion cross-listes).
        // On migre à la lecture pour ne perdre aucun favori existant.
        var migrated = false;
        for (final key in list) {
          final normalized = normalizeStoredKey(key);
          if (normalized != key) migrated = true;
          _cache.add(normalized);
        }
        if (migrated) {
          debugPrint('🔄 FavoritesService: clés migrées en minuscules (§23)');
          _persist(); // fire & forget
        }
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
  /// §favYear — Pour un FILM/SÉRIE, on accepte AUSSI l'ancienne clé sans année
  /// (favori legacy) → le cœur reste allumé après mise à jour de l'app.
  static bool isEntryFavorite(M3uEntry e) {
    if (e.type != M3uContentType.tv) {
      return _cache.contains(keyFor(e)) || _cache.contains(_legacyKey(e));
    }
    return isFavorite(keyFor(e));
  }

  /// §favYear — Toggle/ajout/retrait À PARTIR DE L'ENTRÉE (recommandé pour les
  /// films) : gère la clé avec année ET nettoie l'éventuelle clé legacy au
  /// retrait. Retourne le nouvel état (`true` = ajouté).
  static Future<bool> toggleEntry(M3uEntry e) async {
    await _ensureLoaded();
    if (isEntryFavorite(e)) {
      await _removeEntry(e);
      return false;
    }
    await add(keyFor(e));
    return true;
  }

  /// Ajoute un favori depuis l'entrée (clé avec année pour les films).
  static Future<void> addEntry(M3uEntry e) => add(keyFor(e));

  static Future<void> _removeEntry(M3uEntry e) async {
    await _ensureLoaded();
    // Retire la clé courante ET la legacy (films/séries) en une notification.
    final removed = _cache.remove(keyFor(e));
    final removedLegacy =
        e.type != M3uContentType.tv && _cache.remove(_legacyKey(e));
    if (removed || removedLegacy) {
      version.value++;
      await _persist();
    }
  }

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
