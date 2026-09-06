import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'perf_config.dart';

/// §perfNotify (2026-09-05) — Le notifieur des réglages compare par IDENTITÉ,
/// jamais par égalité.
///
/// **Le bug qu'il corrige.** `ValueNotifier` refuse en silence une valeur
/// ÉGALE à l'ancienne — et `PerfConfig.==` ignore volontairement les réglages
/// de confort (`autoNextEpisode`, `tmdbPostersFirst`, les deux rangées TMDB)
/// pour que la page Optimisation ne bascule pas en « Personnalisé » quand on
/// les touche. Conséquence : `save()` écrivait bien la préférence sur disque,
/// mais la valeur EN MÉMOIRE ne bougeait pas. L'interrupteur restait muet
/// jusqu'au prochain lancement de l'app — constaté par l'utilisateur sur
/// « Affiches TMDB en priorité » (« il ne répond pas, puis au bout d'un
/// certain temps il se sélectionne »), et vrai depuis §perfSettings pour
/// « Épisode suivant automatique ».
///
/// Comparer par identité règle les quatre d'un coup sans toucher à `==`, qui
/// garde son seul rôle : reconnaître le profil actif. Garde-fou :
/// `test/perf_notify_test.dart`.
class PerfConfigNotifier extends ChangeNotifier
    implements ValueListenable<PerfConfig> {
  PerfConfigNotifier(this._value);

  PerfConfig _value;

  @override
  PerfConfig get value => _value;

  set value(PerfConfig next) {
    if (identical(next, _value)) return;
    _value = next;
    notifyListeners();
  }
}

/// §perfSettings — Service singleton gérant les réglages d'optimisation.
/// Charge depuis SharedPreferences au démarrage et notifie les listeners à
/// chaque changement via [config] (même moule que `ThemeService`).
class PerformanceSettingsService {
  static const _kKey = 'aether_perf_v1';

  static final PerfConfigNotifier config =
      PerfConfigNotifier(PerfConfig.defaults);

  /// Charge la config persistée. À appeler avant runApp().
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kKey);
      if (raw != null) {
        config.value = PerfConfig.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      }
    } catch (_) {
      // Conserve les valeurs par défaut si la lecture échoue.
    }
    applyImageCacheLimit();
  }

  /// Applique et persiste une nouvelle config.
  /// Le notifieur déclenche immédiatement le rebuild de la home.
  static Future<void> save(PerfConfig newConfig) async {
    config.value = newConfig;
    applyImageCacheLimit();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kKey, jsonEncode(newConfig.toJson()));
    } catch (_) {}
  }

  /// §imgMemCache — Applique le plafond du cache image EN MÉMOIRE
  /// (`PaintingBinding.instance.imageCache`), dont le défaut Flutter est de
  /// 100 Mo — beaucoup trop sur une box TV où la RAM est le goulot.
  ///
  /// Réglage rendu possible par §imgDiskCache : une image évincée de la RAM se
  /// relit désormais sur disque au lieu de repartir en réseau. Le plafond en
  /// NOMBRE d'images est aligné proportionnellement (défaut Flutter : 1000).
  static void applyImageCacheLimit() {
    try {
      final mb = config.value.imageCacheMb;
      final cache = PaintingBinding.instance.imageCache;
      cache.maximumSizeBytes = mb * 1024 * 1024;
      cache.maximumSize = (mb * 10).clamp(200, 1000);
      debugPrint('🖼️ §imgMemCache : cache image mémoire plafonné à $mb Mo');
    } catch (e) {
      debugPrint('⚠️ §imgMemCache : application du plafond échouée — $e');
    }
  }

  static Future<void> reset() => save(PerfConfig.defaults);
}
