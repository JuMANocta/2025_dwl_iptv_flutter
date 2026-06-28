import 'dart:async';

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

  static String _key(String query, bool isTv, String? year) =>
      '${query.toLowerCase().trim()}|$isTv|${year ?? ''}';

  /// Lecture synchrone : URL d'affiche si déjà résolue, sinon null.
  static String? cached(String query, bool isTv, String? year) =>
      _cache[_key(query, isTv, year)];

  /// True si la clé a déjà été résolue (y compris résultat négatif null).
  static bool isResolved(String query, bool isTv, String? year) =>
      _cache.containsKey(_key(query, isTv, year));

  /// Résout l'affiche (réseau si nécessaire) et met le résultat en cache.
  static Future<String?> resolve({
    required String query,
    required bool isTv,
    String? year,
    String? groupTitle,
  }) {
    final k = _key(query, isTv, year);
    if (_cache.containsKey(k)) return Future.value(_cache[k]);
    final pending = _inFlight[k];
    if (pending != null) return pending;

    final future = _doResolve(query, isTv, year, groupTitle).then((url) {
      _cache[k] = url;
      _inFlight.remove(k);
      return url;
    });
    _inFlight[k] = future;
    return future;
  }

  static Future<String?> _doResolve(
      String query, bool isTv, String? year, String? groupTitle) async {
    if (!await TmdbApiService.hasApiKey()) return null;
    return TmdbService.instance.fetchPosterUrl(
      query: query,
      isTv: isTv,
      year: year,
      groupTitle: groupTitle,
    );
  }
}
