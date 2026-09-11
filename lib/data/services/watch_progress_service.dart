import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/diagnostics/prefs_probe.dart';

/// Snapshot d'une progression de lecture.
class WatchProgress {
  /// URL utilisée comme identifiant unique de l'entrée VOD lue (films/séries).
  final String url;
  final Duration position;
  final Duration duration;
  final DateTime lastWatched;

  const WatchProgress({
    required this.url,
    required this.position,
    required this.duration,
    required this.lastWatched,
  });

  /// Ratio 0.0 → 1.0 (capé à 1.0). Renvoie 0 si la durée est nulle.
  double get ratio {
    if (duration.inMilliseconds <= 0) return 0;
    final r = position.inMilliseconds / duration.inMilliseconds;
    return r.clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'p': position.inMilliseconds,
        'd': duration.inMilliseconds,
        't': lastWatched.millisecondsSinceEpoch,
      };

  static WatchProgress fromJson(String url, Map<String, dynamic> j) =>
      WatchProgress(
        url: url,
        position: Duration(milliseconds: (j['p'] as num).toInt()),
        duration: Duration(milliseconds: (j['d'] as num).toInt()),
        lastWatched:
            DateTime.fromMillisecondsSinceEpoch((j['t'] as num).toInt()),
      );
}

/// Service de reprise de lecture (§1e Continue Watching).
///
/// **Modèle** : un `Map<url, {position, duration, lastWatched}>` persisté dans
/// `SharedPreferences` clé `"watch_progress_v1"`. Pas de service externe :
/// statique + cache mémoire, dans la lignée de [FavoritesService].
///
/// **Cycle de vie** :
///   - Sauvegarde toutes les 10s pendant la lecture + au `dispose()` du player.
///   - Entrée terminée (> 95%) → auto-clear (considérée comme vue).
///   - Chaînes TV live : pas concernées (durée infinie / inconnue).
///
/// **API** : tout statique. `version` (ValueNotifier) bump à chaque modif pour
/// rebuilder les vignettes via `ValueListenableBuilder`.
class WatchProgressService {
  static const String _prefsKey = 'watch_progress_v1';
  /// Seuil au-delà duquel on considère l'entrée comme "vue en entier".
  static const double _completionThreshold = 0.95;
  /// Durée minimale d'une entrée pour sauvegarder (filtre les pubs/intros < 60s).
  static const Duration _minDuration = Duration(seconds: 60);

  /// Revue 2026-09-11, D1A-17 — **Plafond de la table.**
  ///
  /// Elle n'en avait aucun : une entrée par film ou épisode entamé, gardée à
  /// vie (URL d'abonnements supprimés comprises), et RÉÉCRITE EN ENTIER toutes
  /// les 10 s de lecture — une table qui ne fait que grossir rend chaque
  /// sauvegarde plus lourde que la précédente, et gonfle le `.aether`.
  /// Au-delà, on oublie les reprises les plus ANCIENNES (`lastWatched`), comme
  /// `MeasuredQualityService` et `InferredCategoryService` bornent déjà les
  /// leurs. Le hero « Reprendre » n'en montre que les plus récentes : intact.
  static const int maxEntries = 500;

  static final Map<String, WatchProgress> _cache = {};
  static bool _loaded = false;

  /// D1A-17 — Les clés à oublier pour ramener [m] à [max] entrées : les plus
  /// anciennes par `lastWatched`, et à égalité la PREMIÈRE insérée (ordre de
  /// la table). [keep] n'est jamais proposée : c'est la reprise qu'on vient
  /// d'enregistrer, qu'une horloge reculée ne doit pas faire oublier aussitôt.
  ///
  /// Fonction pure : c'est elle qu'on teste.
  @visibleForTesting
  static List<String> keysBeyondCap(Map<String, WatchProgress> m, int max,
      {String? keep}) {
    if (m.length <= max) return const <String>[];
    final List<MapEntry<String, WatchProgress>> entries =
        m.entries.where((MapEntry<String, WatchProgress> e) => e.key != keep).toList();
    final List<int> order = List<int>.generate(entries.length, (int i) => i);
    order.sort((int a, int b) {
      final int c = entries[a]
          .value
          .lastWatched
          .compareTo(entries[b].value.lastWatched);
      return c != 0 ? c : a.compareTo(b);
    });
    return <String>[
      for (final int i in order.take(m.length - max)) entries[i].key,
    ];
  }

  /// D1A-17 — Applique le plafond à la table en mémoire. Rend le nombre de
  /// reprises oubliées (0 dans l'immense majorité des appels).
  static int _applyCap({String? keep}) {
    final List<String> drop = keysBeyondCap(_cache, maxEntries, keep: keep);
    for (final String k in drop) {
      _cache.remove(k);
    }
    if (drop.isNotEmpty) {
      // Une ligne par titre NOUVEAU au-delà du plafond (jamais par sauvegarde
      // périodique : mettre à jour une reprise existante ne fait pas grossir).
      debugPrint('🧹 WatchProgress — ${drop.length} reprise(s) la/les plus ancienne(s) oubliée(s) (plafond $maxEntries)');
    }
    return drop.length;
  }

  /// Bumpe à chaque modification — écouter via `ValueListenableBuilder`.
  static final ValueNotifier<int> version = ValueNotifier(0);

  // ── Chargement / persistence ────────────────────────────────────────────

  static Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        for (final entry in map.entries) {
          _cache[entry.key] = WatchProgress.fromJson(
            entry.key,
            entry.value as Map<String, dynamic>,
          );
        }
        // D1A-17 — Sonde (une ligne au démarrage) + plafond appliqué à une
        // table héritée d'avant le plafond. Rien n'est réécrit ici : la table
        // réduite part au disque à la prochaine sauvegarde.
        debugPrint('✅ WatchProgress — ${_cache.length} reprises restaurées '
            '(${(raw.length / 1024).toStringAsFixed(1)} Ko)');
        _applyCap();
      }
    } catch (e) {
      debugPrint('❌ WatchProgressService: erreur chargement — $e');
    }
    _loaded = true;
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = {
        for (final p in _cache.entries) p.key: p.value.toJson(),
      };
      // D1A-17 — Même écriture, chronométrée (journalisée au-delà de 8 ms).
      await PrefsProbe.setStringTimed(prefs, _prefsKey, () => jsonEncode(map),
          tag: 'WatchProgress');
    } catch (e) {
      debugPrint('❌ WatchProgressService: erreur persistence — $e');
    }
  }

  // ── API publique ────────────────────────────────────────────────────────

  /// Initialise le service au démarrage (à appeler depuis `main()`).
  static Future<void> init() => _ensureLoaded();

  /// Lecture synchrone (cache mémoire). Renvoie null si rien sauvegardé.
  static WatchProgress? getProgress(String url) => _cache[url];

  /// Lecture cross-URLs : utile pour les groupes multi-versions (un film
  /// existant en 2 qualités → on remonte la progression la plus récente).
  static WatchProgress? getProgressForAny(Iterable<String> urls) {
    WatchProgress? best;
    for (final u in urls) {
      final p = _cache[u];
      if (p == null) continue;
      if (best == null || p.lastWatched.isAfter(best.lastWatched)) {
        best = p;
      }
    }
    return best;
  }

  /// Snapshot synchrone de toutes les progressions (ordre indéfini).
  static List<WatchProgress> get all => _cache.values.toList();

  /// Sauvegarde la position courante.
  ///
  /// Règles silencieuses :
  ///   - duration trop courte ( < 60s) → ignoré (pub / intro).
  ///   - position > 95% → clear (vu en entier).
  ///   - position < 5s → ignoré (juste lancé, pas la peine de marquer).
  static Future<void> saveProgress(
    String url,
    Duration position,
    Duration duration,
  ) async {
    await _ensureLoaded();
    if (duration < _minDuration) return;
    final ratio = position.inMilliseconds / duration.inMilliseconds;
    if (ratio >= _completionThreshold) {
      await clearProgress(url);
      return;
    }
    if (position.inSeconds < 5) return;
    _cache[url] = WatchProgress(
      url: url,
      position: position,
      duration: duration,
      lastWatched: DateTime.now(),
    );
    // D1A-17 — Ne fait quelque chose que pour un titre NOUVEAU au-delà du
    // plafond ; la reprise qu'on vient d'enregistrer n'est jamais oubliée.
    _applyCap(keep: url);
    version.value++;
    await _persist();
  }

  /// Supprime la progression d'une URL (visionnage terminé ou reset manuel).
  static Future<void> clearProgress(String url) async {
    await _ensureLoaded();
    if (_cache.remove(url) != null) {
      version.value++;
      await _persist();
    }
  }

  /// Vide toutes les progressions (debug).
  static Future<void> clearAll() async {
    if (_cache.isEmpty) return;
    _cache.clear();
    version.value++;
    await _persist();
  }

  /// Tests : oublie la table en mémoire pour rejouer un chargement depuis
  /// les préférences simulées.
  @visibleForTesting
  static void resetForTest() {
    _cache.clear();
    _loaded = false;
  }

  /// Remplace l'intégralité du cache de progressions en une seule opération.
  /// Utilisé par le BackupService (§10) pour l'import.
  static Future<void> replaceAll(Map<String, WatchProgress> progresses) async {
    await _ensureLoaded();
    _cache
      ..clear()
      ..addAll(progresses);
    // D1A-17 — Une sauvegarde d'avant le plafond peut en porter davantage.
    _applyCap();
    version.value++;
    await _persist();
  }
}
