import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Historique de recherche local (§1i).
///
/// Stocke les 10 dernières requêtes non-triviales (>= 2 caractères) dans
/// `SharedPreferences` (`search_history_v1`). Pas de PII : seules les chaînes
/// tapées par l'utilisateur, jamais le contenu de la playlist.
///
/// L'UI consulte cette liste pour proposer des suggestions sous le champ de
/// recherche quand il est vide.
class SearchHistoryService {
  static const String _prefsKey = 'search_history_v1';
  static const int _maxEntries = 10;

  static final List<String> _cache = [];
  static bool _loaded = false;

  /// Bumpe à chaque modif — utilisable avec `ValueListenableBuilder`.
  static final ValueNotifier<int> version = ValueNotifier(0);

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
      debugPrint('❌ SearchHistoryService: erreur chargement — $e');
    }
    _loaded = true;
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_cache));
    } catch (e) {
      debugPrint('❌ SearchHistoryService: erreur persistence — $e');
    }
  }

  /// À appeler dans `main()` pour précharger le cache.
  static Future<void> init() => _ensureLoaded();

  /// Snapshot synchrone (plus récent en premier).
  static List<String> get all => List.unmodifiable(_cache);

  /// Ajoute une requête en tête. Déduplique (déplace en tête si déjà présent).
  /// Ignore les chaînes vides ou < 2 caractères (bruit).
  static Future<void> record(String query) async {
    final q = query.trim();
    if (q.length < 2) return;
    await _ensureLoaded();
    _cache.remove(q); // dédup
    _cache.insert(0, q);
    if (_cache.length > _maxEntries) {
      _cache.removeRange(_maxEntries, _cache.length);
    }
    version.value++;
    await _persist();
  }

  /// Retire une entrée précise (suggestion balayée par l'utilisateur).
  static Future<void> remove(String query) async {
    await _ensureLoaded();
    if (_cache.remove(query.trim())) {
      version.value++;
      await _persist();
    }
  }

  /// Vide l'historique (réglage debug / privacy).
  static Future<void> clear() async {
    if (_cache.isEmpty) return;
    _cache.clear();
    version.value++;
    await _persist();
  }
}
