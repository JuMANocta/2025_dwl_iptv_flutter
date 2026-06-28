import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/utils/network.dart';
import '../models/m3u_entry.dart';
import '../models/stream_account.dart';

/// §xtreamApi — Client de la **JSON API Xtream** (`player_api.php?action=…`).
///
/// **Pourquoi cette couche ?** Beaucoup de panels Xtream renvoient des 500
/// silencieux sur `get.php` (PHP `max_execution_time` qui timeout sur la
/// génération du M3U complet), alors que `player_api.php?action=…` répond
/// rapidement avec du JSON segmenté. Tous les bons clients IPTV
/// (TiviMate, IPTV Smarters Pro, ZenIPTV, OTT Navigator…) construisent la
/// playlist en interne via cette API.
///
/// **Architecture :**
/// 1. `auth(account)` — vérifie les credentials (et récupère `server_info`).
/// 2. `get*Categories()` — liste les catégories (TV / VOD / Séries).
/// 3. `get*Streams()` — liste les flux (id + nom + logo + catégorie).
/// 4. §23 — `XtreamCatalogService` sauvegarde les réponses brutes dans
///    `playlist_<id>.json`, parsé directement par `XtreamCatalogParser`
///    (l'ancien `XtreamM3uBuilder` qui reconstituait un M3U texte a été
///    supprimé — plus de round-trip ni de perte de métadonnées).
class XtreamApiService {
  XtreamApiService._();

  /// §xtreamEpisodesCache — Cache LRU mémoire des épisodes série fetched via
  /// `fetchEpisodes`. Évite un re-fetch si l'utilisateur referme/rouvre la
  /// même fiche série rapidement. Capacité 60 séries, TTL 15 min (au-delà on
  /// re-fetch pour rester frais — l'utilisateur peut avoir ajouté des
  /// épisodes côté provider).
  static final _episodesCache = <String, ({DateTime at, List<M3uEntry> eps})>{};
  static const int _maxCacheEntries = 60;
  static const Duration _cacheTtl = Duration(minutes: 15);

  static String _cacheKey(String accountId, int seriesId) =>
      '$accountId#$seriesId';

  /// Invalide une entrée du cache (utile si on ajoute un refresh manuel un jour).
  static void invalidateEpisodes(String accountId, int seriesId) {
    _episodesCache.remove(_cacheKey(accountId, seriesId));
  }

  /// Construit le Dio pour appeler `player_api.php` du host de [account].
  /// Hérite du profil IPTV (UA `IPTVSmartersPro`, Accept-Encoding gzip).
  static Future<Dio> _dio(StreamAccount account) async {
    final url = account.buildM3uUrl() ?? '';
    return NetworkUtils.buildDio(url);
  }

  /// URL `player_api.php` pour [account], avec credentials embarqués.
  /// Retourne `null` si le compte n'a pas de creds extractibles.
  static String? _baseUrl(StreamAccount account) {
    final creds = account.resolveXtreamCredentials();
    if (creds == null) return null;
    return '${creds.host}/player_api.php'
        '?username=${Uri.encodeQueryComponent(creds.username)}'
        '&password=${Uri.encodeQueryComponent(creds.password)}';
  }

  /// Crédentials brutes pour construire les URLs de streams.
  static ({String host, String username, String password})? credentialsOf(
          StreamAccount account) =>
      account.resolveXtreamCredentials();

  /// GET interne avec gestion du JSON gzip et des erreurs réseau.
  static Future<dynamic> _get(
    Dio dio,
    String url, {
    Duration? timeout,
  }) async {
    final resp = await dio.get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
        receiveTimeout: timeout ?? const Duration(minutes: 2),
        validateStatus: (s) => s != null && s >= 200 && s < 300,
      ),
    );
    final body = resp.data ?? '';
    if (body.isEmpty) return null;
    return jsonDecode(body);
  }

  // ── Auth / info compte ──────────────────────────────────────────────────

  /// Appelle `player_api.php` sans action → renvoie le bloc complet
  /// `{ user_info: {…}, server_info: {…} }`. Null si échec / compte invalide.
  static Future<Map<String, dynamic>?> auth(StreamAccount account) async {
    final url = _baseUrl(account);
    if (url == null) return null;
    try {
      final dio = await _dio(account);
      final data = await _get(dio, url, timeout: const Duration(seconds: 20));
      if (data is Map<String, dynamic>) return data;
    } catch (e) {
      debugPrint('⚠️ XtreamApi.auth: $e');
    }
    return null;
  }

  // ── Live (chaînes TV) ───────────────────────────────────────────────────

  /// Liste des catégories live (TV). Retourne `[]` si échec.
  static Future<List<Map<String, dynamic>>> getLiveCategories(
          StreamAccount account) =>
      _listAction(account, 'get_live_categories');

  /// Liste de toutes les chaînes live (sans filtrage par catégorie).
  static Future<List<Map<String, dynamic>>> getLiveStreams(
          StreamAccount account) =>
      _listAction(account, 'get_live_streams');

  // ── VOD (films) ──────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getVodCategories(
          StreamAccount account) =>
      _listAction(account, 'get_vod_categories');

  static Future<List<Map<String, dynamic>>> getVodStreams(
          StreamAccount account) =>
      _listAction(account, 'get_vod_streams');

  // ── Séries ───────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getSeriesCategories(
          StreamAccount account) =>
      _listAction(account, 'get_series_categories');

  /// Liste des séries (un item = une série, sans détails des épisodes).
  static Future<List<Map<String, dynamic>>> getSeries(
          StreamAccount account) =>
      _listAction(account, 'get_series');

  /// §xtreamEpisodes — Récupère TOUS les épisodes d'une série et les retourne
  /// directement sous forme de `List<M3uEntry>` prêts à être affichés par
  /// `DetailsPage` (mêmes champs que des entrées issues du parser M3U).
  /// Utilisé en LAZY-LOAD : on n'appelle pas cette API au boot (trop coûteux
  /// pour 19 000+ séries) ; on l'appelle uniquement quand l'utilisateur ouvre
  /// une fiche série. Retourne `[]` si série introuvable ou erreur.
  static Future<List<M3uEntry>> fetchEpisodes(
    StreamAccount account,
    int seriesId,
  ) async {
    // §xtreamEpisodesCache — cache LRU lookup
    final key = _cacheKey(account.id, seriesId);
    final cached = _episodesCache[key];
    if (cached != null &&
        DateTime.now().difference(cached.at) < _cacheTtl) {
      // Hit : on remet l'entrée en tête (LRU) en la ré-insérant
      _episodesCache.remove(key);
      _episodesCache[key] = cached;
      return cached.eps;
    }

    final info = await getSeriesInfo(account, seriesId);
    if (info == null) return const [];
    final creds = credentialsOf(account);
    if (creds == null) return const [];

    final seriesName = ((info['info'] is Map
                ? (info['info'] as Map)['name']
                : null) ??
            '')
        .toString();
    // §favSeries — On PARSE le nom de série une fois (baseTitle + groupKey +
    // année cohérents) au lieu de prendre le nom brut. Sinon les épisodes
    // avaient un `groupKey` vide → recalculé sur le nom brut (avec année/
    // préfixe) ≠ celui du stub série → la clé favori ne matchait JAMAIS la
    // vignette (favoris séries cassés). Mêmes baseTitle/groupKey/year que le
    // stub → favoris + regroupement cohérents.
    final seriesMeta = TitleMetadata.parse(seriesName);
    final episodes = info['episodes'];
    if (episodes is! Map) return const [];

    final out = <M3uEntry>[];
    episodes.forEach((seasonKey, eps) {
      if (eps is! List) return;
      final seasonNum = int.tryParse(seasonKey.toString());
      if (seasonNum == null) return;
      for (final e in eps) {
        if (e is! Map) continue;
        final epId = e['id'];
        if (epId == null) continue;
        final epNum = int.tryParse((e['episode_num'] ?? '').toString());
        if (epNum == null) continue;
        final ext = (e['container_extension'] ?? 'mp4').toString();
        final url =
            '${creds.host}/series/${Uri.encodeComponent(creds.username)}/'
            '${Uri.encodeComponent(creds.password)}/$epId.$ext';
        final logo = ((e['info'] is Map
                    ? (e['info'] as Map)['movie_image']
                    : null) ??
                (info['info'] is Map
                    ? (info['info'] as Map)['cover']
                    : null) ??
                '')
            .toString();
        out.add(M3uEntry(
          url: url,
          type: M3uContentType.series,
          title: TitleMetadata(
            rawTitle: seriesName,
            baseTitle: seriesMeta.baseTitle,
            groupKey: seriesMeta.groupKey,
            year: seriesMeta.year,
            seasonNumber: seasonNum,
            episodeNumber: epNum,
          ),
          accountId: account.id,
          logoUrl: logo.isEmpty ? null : logo,
          streamId: int.tryParse(epId.toString()),
        ));
      }
    });

    // §xtreamEpisodesCache — Store : éviction LRU si capacité atteinte
    // (LinkedHashMap garde l'ordre d'insertion ; on retire le 1er élément
    // == le plus ancien, puis on insère le nouveau en fin == le plus récent).
    if (out.isNotEmpty) {
      if (_episodesCache.length >= _maxCacheEntries) {
        _episodesCache.remove(_episodesCache.keys.first);
      }
      _episodesCache[key] = (at: DateTime.now(), eps: out);
    }
    return out;
  }

  /// Détail complet d'une série (saisons + épisodes).
  /// Format Xtream : `{info: {…}, seasons: […], episodes: {"1": [{…}, …], "2": [...]}}`.
  static Future<Map<String, dynamic>?> getSeriesInfo(
      StreamAccount account, int seriesId) async {
    final base = _baseUrl(account);
    if (base == null) return null;
    final url = '$base&action=get_series_info&series_id=$seriesId';
    try {
      final dio = await _dio(account);
      final data = await _get(dio, url);
      if (data is Map<String, dynamic>) return data;
    } catch (e) {
      debugPrint('⚠️ XtreamApi.getSeriesInfo($seriesId): $e');
    }
    return null;
  }

  // ── Implémentation interne ─────────────────────────────────────────────

  /// Appelle une action qui retourne une liste de Map JSON. Retourne `[]`
  /// si échec — on dégrade gracieusement (un endpoint cassé ne plante pas
  /// tout le téléchargement).
  static Future<List<Map<String, dynamic>>> _listAction(
      StreamAccount account, String action) async {
    final base = _baseUrl(account);
    if (base == null) return const [];
    final url = '$base&action=$action';
    try {
      final dio = await _dio(account);
      final data = await _get(dio, url);
      if (data is List) {
        return data.whereType<Map<String, dynamic>>().toList(growable: false);
      }
    } catch (e) {
      debugPrint('⚠️ XtreamApi.$action: $e');
    }
    return const [];
  }
}
