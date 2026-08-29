import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'inferred_category_service.dart';
import 'tmdb_api_service.dart';
import 'tmdb_service.dart';

/// 🖼️ Cache mémoire des affiches TMDB résolues à la volée pour les entrées
/// dont le M3U ne fournit pas de `tvg-logo`.
///
/// Contexte (§Ultimate) : la playlist Ultimate met `tvg-logo=""` (vide) sur
/// la VOD — contrairement aux listes Premium/VOD qui embarquent directement
/// l'URL TMDB. Sans fallback, ces fiches n'affichent qu'une icône.
///
/// Règles perf (grosse playlist) :
/// - une seule recherche TMDB par (titre, type, année) — résultat **mis en
///   cache même quand il est null** (évite de re-tenter à chaque scroll) ;
/// - les appels concurrents pour la même clé sont dédupliqués (`_inFlight`) ;
/// - rien n'est tenté si aucune clé TMDB n'est configurée.
class TmdbPosterCache {
  TmdbPosterCache._();

  static final Map<String, String?> _cache = {};
  static final Map<String, Future<String?>> _inFlight = {};

  /// §tmdbUrlPersist — Clé de stockage. Le **suffixe de version** est ce qui
  /// permet d'invalider tout le cache quand l'heuristique de recherche change :
  /// une résolution obtenue par un `_cleanQuery` bogué (cf. §cleanQuery, qui
  /// décapitait 8 259 titres) doit pouvoir être jetée d'un coup, sans quoi on
  /// servirait indéfiniment de mauvaises affiches.
  ///
  /// ⚠️ **À incrémenter à CHAQUE modification de `_cleanQuery`, de
  /// `fetchPosterAndGenre` ou du barème de recherche TMDB.**
  static const _prefsKey = 'tmdb_poster_cache_v2';

  /// Plafond d'entrées. Au-delà, on cesse d'ajouter plutôt que d'évincer : une
  /// résolution déjà connue vaut mieux qu'une nouvelle, et une éviction ferait
  /// réapparaître des vignettes vides déjà réglées.
  static const _maxEntries = 20000;

  /// Écriture différée — au défilement, des dizaines de titres se résolvent par
  /// seconde ; une écriture disque par vignette saturerait le stockage.
  static const _persistDelay = Duration(seconds: 5);
  static bool _dirty = false;

  static String _key(String query, bool isTv, String? year) =>
      '${query.toLowerCase().trim()}|$isTv|${year ?? ''}';

  /// §tmdbUrlPersist — Recharge le cache depuis le disque. À awaiter au boot.
  ///
  /// **Pourquoi ça compte.** Ces entrées ne sont pas des images (couvertes
  /// depuis §imgDiskCache) mais des **recherches TMDB** — les requêtes les plus
  /// lentes de l'app — déclenchées pour chaque titre dont la liste ne fournit
  /// aucune affiche. Sur un catalogue « Ultimate » (aucun `tvg-logo`, aucun
  /// `tmdb_id`), c'était une vague d'appels réseau **à chaque lancement**.
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      var negatives = 0;
      decoded.forEach((k, v) {
        if (k is! String) return;
        // ⚠️ Les résultats NÉGATIFS (`null`) sont restaurés eux aussi : ce sont
        // eux qui évitent de re-chercher indéfiniment un titre que TMDB ne
        // connaît pas. Les jeter ferait repartir la vague d'appels qu'on veut
        // justement supprimer.
        if (v == null) {
          _cache[k] = null;
          negatives++;
        } else if (v is String && v.isNotEmpty) {
          _cache[k] = v;
        }
      });
      debugPrint('✅ §tmdbUrlPersist — ${_cache.length} résolutions TMDB '
          'restaurées (dont $negatives négatives)');
    } catch (e) {
      debugPrint('⚠️ §tmdbUrlPersist — lecture impossible : $e');
    }
  }

  /// Écriture groupée : un seul passage disque pour tout ce qui a été résolu
  /// pendant la fenêtre.
  static void _schedulePersist() {
    if (_dirty) return;
    _dirty = true;
    Future.delayed(_persistDelay, () async {
      _dirty = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, jsonEncode(_cache));
      } catch (e) {
        debugPrint('⚠️ §tmdbUrlPersist — écriture impossible : $e');
      }
    });
  }

  /// Oublie tout (entretien / changement de clé TMDB).
  static Future<void> clear() async {
    _cache.clear();
    _inFlight.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }

  @visibleForTesting
  static int get count => _cache.length;

  /// Lecture synchrone : URL d'affiche si déjà résolue, sinon null.
  static String? cached(String query, bool isTv, String? year) =>
      _cache[_key(query, isTv, year)];

  /// True si la clé a déjà été résolue (y compris résultat négatif null).
  static bool isResolved(String query, bool isTv, String? year) =>
      _cache.containsKey(_key(query, isTv, year));

  /// Résout l'affiche (réseau si nécessaire) et met le résultat en cache.
  ///
  /// §inferredCat — [categoryKey] : clé de groupe sous laquelle mémoriser la
  /// catégorie déduite des genres TMDB. Facultative : les listes qui rangent
  /// déjà leurs contenus n'en ont pas besoin, et de toute façon elles
  /// fournissent une affiche, donc ne passent pas par ici.
  static Future<String?> resolve({
    required String query,
    required bool isTv,
    String? year,
    String? groupTitle,
    String? categoryKey,
  }) {
    final k = _key(query, isTv, year);
    if (_cache.containsKey(k)) return Future.value(_cache[k]);
    final pending = _inFlight[k];
    if (pending != null) return pending;

    final future =
        _doResolve(query, isTv, year, groupTitle, categoryKey).then((url) {
      // §tmdbUrlPersist — On mémorise AUSSI les échecs (`url == null`), et on
      // les persiste : c'est ce qui empêche de re-chercher à chaque lancement
      // un titre que TMDB ne connaît pas.
      if (_cache.length < _maxEntries || _cache.containsKey(k)) {
        _cache[k] = url;
        _schedulePersist();
      }
      _inFlight.remove(k);
      return url;
    });
    _inFlight[k] = future;
    return future;
  }

  /// §tmdbUrlPersist — Nombre de recherches TMDB réellement parties sur le
  /// réseau depuis le lancement.
  ///
  /// Instrument de mesure : c'est le seul moyen de vérifier que la persistance
  /// fait son travail. Sans clé TMDB configurée, il reste à zéro.
  static int _networkResolutions = 0;

  static Future<String?> _doResolve(String query, bool isTv, String? year,
      String? groupTitle, String? categoryKey) async {
    if (!await TmdbApiService.hasApiKey()) return null;
    // Journalisé par paliers de 25 : une ligne par recherche noierait le
    // journal (des dizaines par seconde au défilement), et ce qui nous
    // intéresse est le VOLUME, pas le détail.
    _networkResolutions++;
    if (_networkResolutions % 25 == 0) {
      debugPrint('🔍 §tmdbUrlPersist — $_networkResolutions recherches TMDB '
          'réseau depuis le lancement (${_cache.length} en cache)');
    }
    final r = await TmdbService.instance.fetchPosterAndGenre(
      query: query,
      isTv: isTv,
      year: year,
      groupTitle: groupTitle,
    );
    // §inferredCat — On range le titre même quand TMDB n'a pas d'affiche : une
    // catégorie sans image reste utile, l'inverse aussi.
    InferredCategoryService.learn(categoryKey, r.category);
    return r.posterUrl;
  }
}
