import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// §langFilter — Régions/langues masquées par l'utilisateur (préfixes `|IT|`,
/// `|DE|`, …). Les entrées correspondantes sont **filtrées AU PARSING** (jamais
/// stockées en mémoire ni dans le cache JSON.gz) → RAM + taille de cache
/// réduites. Le catalogue brut `.json`/`.m3u` reste complet sur disque, donc
/// changer le filtre = simple re-parse (pas de re-téléchargement).
///
/// La [signature] est intégrée à l'en-tête du cache parsé : si elle change, le
/// cache est invalidé et re-parsé avec le nouveau filtre.
class HiddenRegionsService {
  static const String _prefsKey = 'hidden_regions_v1';

  static final Set<String> _hidden = <String>{};
  static bool _loaded = false;

  /// Bumpe à chaque modification → écouter via `ValueListenableBuilder`.
  static final ValueNotifier<int> version = ValueNotifier(0);

  static Future<void> init() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        _hidden.addAll((jsonDecode(raw) as List).cast<String>());
      }
    } catch (e) {
      debugPrint('❌ HiddenRegionsService: chargement — $e');
    }
    _loaded = true;
  }

  /// Snapshot des régions masquées.
  static Set<String> get hidden => Set.unmodifiable(_hidden);

  static bool isHidden(String region) => _hidden.contains(region);

  /// Vrai si AU MOINS une région est masquée (raccourci pour court-circuiter
  /// le filtre quand rien n'est masqué).
  static bool get hasAny => _hidden.isNotEmpty;

  /// Signature stable (triée) du jeu masqué → clé de validité du cache parsé.
  static String get signature {
    if (_hidden.isEmpty) return '';
    final list = _hidden.toList()..sort();
    return list.join('|');
  }

  /// Remplace l'ensemble masqué. Retourne `true` si ça a changé (→ l'appelant
  /// doit déclencher un re-parse).
  static Future<bool> setHidden(Set<String> regions) async {
    await init();
    if (_setEquals(_hidden, regions)) return false;
    _hidden
      ..clear()
      ..addAll(regions);
    version.value++;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_hidden.toList()));
    } catch (e) {
      debugPrint('❌ HiddenRegionsService: persistence — $e');
    }
    return true;
  }

  static bool _setEquals(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);
}
