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
/// 4. Le builder (`XtreamM3uBuilder`) reconstitue un fichier M3U Plus à partir
///    de tout ça, qui est ensuite parsé par le pipeline existant.
class XtreamApiService {
  XtreamApiService._();

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
    final info = await getSeriesInfo(account, seriesId);
    if (info == null) return const [];
    final creds = credentialsOf(account);
    if (creds == null) return const [];

    final seriesName = (info['info'] is Map
            ? (info['info'] as Map)['name']
            : null) ??
        '';
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
        final title = seriesName.toString();
        out.add(M3uEntry(
          url: url,
          type: M3uContentType.series,
          title: TitleMetadata(
            rawTitle: title,
            baseTitle: title,
            seasonNumber: seasonNum,
            episodeNumber: epNum,
          ),
          accountId: account.id,
          logoUrl: logo.isEmpty ? null : logo,
          streamId: int.tryParse(epId.toString()),
        ));
      }
    });
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
