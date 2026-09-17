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

  /// §heroSeriesResume (2026-09-12) — Ratio maximal écrit sous une clé de
  /// **série**.
  ///
  /// Le hero et les cartes écartent toute reprise à 95 % ou plus (« vu en
  /// entier », `resumeGroupsFor`). Si la fin d'un épisode écrivait son ratio
  /// réel sous la clé de la série, la série DISPARAÎTRAIT de « Reprendre » à
  /// la seconde où l'on vient de la regarder — exactement l'inverse du but.
  /// Une série n'est pas finie parce qu'un épisode l'est : ce qui compte ici
  /// est qu'elle soit EN COURS.
  static const double seriesMaxRatio = 0.90;

  /// §heroSeriesResume — Position à écrire sous la clé de série pour une
  /// position d'ÉPISODE : la sienne, plafonnée à [seriesMaxRatio] de la durée.
  /// Le plafond ne mord que sur les dernières minutes (générique compris), là
  /// où la seule suite utile est l'épisode suivant.
  ///
  /// Fonction pure : c'est elle qu'on teste.
  @visibleForTesting
  static Duration seriesPositionFor(Duration position, Duration duration) {
    if (duration <= Duration.zero) return position;
    final int cap = (duration.inMilliseconds * seriesMaxRatio).round();
    return position.inMilliseconds <= cap
        ? position
        : Duration(milliseconds: cap);
  }

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
  /// [keepAlso] la protège de la même façon (§heroSeriesResume : la clé de
  /// série écrite dans le MÊME appel).
  ///
  /// Fonction pure : c'est elle qu'on teste.
  @visibleForTesting
  static List<String> keysBeyondCap(Map<String, WatchProgress> m, int max,
      {String? keep, String? keepAlso}) {
    if (m.length <= max) return const <String>[];
    final List<MapEntry<String, WatchProgress>> entries = m.entries
        .where((MapEntry<String, WatchProgress> e) =>
            e.key != keep && e.key != keepAlso)
        .toList();
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
  static int _applyCap({String? keep, String? keepAlso}) {
    final List<String> drop =
        keysBeyondCap(_cache, maxEntries, keep: keep, keepAlso: keepAlso);
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

  /// R46 — Les progressions EXISTANTES parmi [urls], pour pouvoir les rendre.
  ///
  /// 🔴 **Le défaut qu'elle corrige.** « Oublier la reprise » efface la
  /// progression de TOUTES les versions d'un groupe (qualités, comptes), mais
  /// l'annulation n'en restaurait qu'UNE — celle de `versions.first` côté
  /// accueil, celle du `snapshot` côté fiche. Mesuré sur appareil le
  /// 2026-09-13 : une série présente sur deux comptes avait deux reprises
  /// (28,1 s et 186,9 s) ; l'oubli a effacé les deux, « Annuler » n'en a rendu
  /// qu'une, l'autre était perdue pour de bon. Le défaut ne se voit QUE sur un
  /// titre multi-versions — d'où sa survie.
  ///
  /// Lecture synchrone du cache : à appeler AVANT l'effacement.
  ///
  /// ⛔ **PAS `@visibleForTesting`** : ses deux appelants sont de production
  /// (`home_card.dart`, `details_page.dart`). L'annotation avait été posée par
  /// mimétisme avec `seriesPositionFor`, qui elle est vraiment réservée aux
  /// tests — l'analyseur l'a refusée, à raison, et la porte CI est tombée.
  static List<WatchProgress> snapshotFor(Iterable<String> urls) => <WatchProgress>[
        for (final String u in urls)
          if (_cache[u] != null) _cache[u]!,
      ];

  /// R46 — Rend toutes les progressions capturées par [snapshotFor].
  ///
  /// ⚠️ [seriesKey] n'est passée qu'à la PREMIÈRE écriture : `saveProgress`
  /// écrit les deux clés d'un coup, la répéter ferait autant de réécritures du
  /// stub et d'invalidations de l'accueil (§perfBigList, §homeMeter).
  ///
  /// ⚠️ La restauration repasse par [saveProgress], donc par ses règles
  /// silencieuses (durée < 60 s, position < 5 s). C'est voulu : ce qui n'aurait
  /// jamais pu être écrit ne doit pas renaître par une annulation.
  static Future<void> restoreAll(
    List<WatchProgress> snapshots, {
    String? seriesKey,
  }) async {
    bool premier = true;
    for (final WatchProgress p in snapshots) {
      await saveProgress(
        p.url,
        p.position,
        p.duration,
        seriesKey: premier ? seriesKey : null,
      );
      premier = false;
    }
    // Le groupe n'avait aucune reprise mais la série en avait une : il faut
    // quand même la rendre.
    if (snapshots.isEmpty && seriesKey != null && seriesKey.isNotEmpty) {
      debugPrint('↩️ R46 — annulation : seule la clé de série est à rendre.');
    }
  }

  /// Sauvegarde la position courante.
  ///
  /// Règles silencieuses :
  ///   - duration trop courte ( < 60s) → ignoré (pub / intro).
  ///   - position > 95% → clear (vu en entier).
  ///   - position < 5s → ignoré (juste lancé, pas la peine de marquer).
  ///
  /// §heroSeriesResume (2026-09-12) — [seriesKey] : la clé de la **série**
  /// (l'URL stub de son entrée du catalogue, `PlayerMedia.seriesResumeKey`),
  /// écrite EN PLUS de celle de l'épisode.
  ///
  /// **Le défaut qu'elle corrige** : la progression d'un épisode est
  /// enregistrée sous l'URL de l'ÉPISODE, que le catalogue ne contient pas (une
  /// seule entrée par série, URL stub). Le hero comme les cartes résolvent une
  /// reprise par l'URL de l'ENTRÉE : une série en cours n'était donc trouvée
  /// nulle part. Les films marchaient parce que l'URL jouée EST celle de leur
  /// entrée.
  ///
  ///   - la position exacte reste celle de l'épisode ([url]) : c'est elle qui
  ///     fait reprendre le BON épisode. La clé de série ne dit que « série en
  ///     cours, à tel avancement », plafonné par [seriesPositionFor] ;
  ///   - la fin d'un épisode efface la reprise de l'ÉPISODE et RAFRAÎCHIT celle
  ///     de la série : c'est l'instant où elle mérite le plus la tête de la
  ///     pile « Reprendre ».
  ///
  /// ⚠️ Une seule écriture disque et un seul bump de [version] pour les deux
  /// clés : deux `saveProgress` d'affilée feraient recomposer l'accueil deux
  /// fois (§perfBigList, §homeMeter).
  static Future<void> saveProgress(
    String url,
    Duration position,
    Duration duration, {
    String? seriesKey,
  }) async {
    await _ensureLoaded();
    if (duration < _minDuration) return;
    final ratio = position.inMilliseconds / duration.inMilliseconds;
    final bool watched = ratio >= _completionThreshold;
    if (!watched && position.inSeconds < 5) return;
    final DateTime now = DateTime.now();
    bool changed = false;
    if (watched) {
      // Vu en entier : la reprise de CE titre (film ou épisode) disparaît.
      changed = _cache.remove(url) != null;
    } else {
      _cache[url] = WatchProgress(
        url: url,
        position: position,
        duration: duration,
        lastWatched: now,
      );
      changed = true;
    }
    if (seriesKey != null && seriesKey.isNotEmpty && seriesKey != url) {
      _cache[seriesKey] = WatchProgress(
        url: seriesKey,
        position: seriesPositionFor(position, duration),
        duration: duration,
        lastWatched: now,
      );
      changed = true;
    }
    if (!changed) return;
    // D1A-17 — Ne fait quelque chose que pour un titre NOUVEAU au-delà du
    // plafond ; les reprises qu'on vient d'enregistrer ne sont jamais oubliées.
    _applyCap(keep: url, keepAlso: seriesKey);
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
