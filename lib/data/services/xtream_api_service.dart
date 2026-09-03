import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/utils/host_gate.dart';
import '../../core/utils/network.dart';
import '../models/m3u_entry.dart';
import '../models/stream_account.dart';
import 'load_failure.dart';

/// §catalogTruth — Résultat d'une action `player_api.php` qui renvoie une liste.
///
/// **`items == null` ⇔ ÉCHEC.** C'est tout l'intérêt du type : avant, quatre
/// situations rendaient la même `const []` et étaient donc indiscernables —
/// « le panel n'a pas de films » et « le panel a refusé la connexion »
/// s'écrivaient pareil, et un catalogue amputé écrasait le bon.
typedef XtreamListResult = ({
  /// Les items, ou `null` si l'action a échoué. Une liste **vide** est un
  /// succès : le panel n'a réellement rien dans cette section.
  List<Map<String, dynamic>>? items,

  /// Motif court, en français, sans identifiants.
  String? error,

  /// Statut HTTP quand il y en a eu un (`null` = pas de réponse du tout).
  int? status,

  /// Nature de l'échec, pour l'affichage (§fleetState).
  LoadFailureKind? kind,
});

/// §catalogTruth — Classe le corps d'une réponse d'action « liste ».
///
/// Fonction **pure** (aucun réseau) : c'est elle qui porte la distinction
/// « vide » / « échec », donc c'est elle qu'on teste.
///
/// [body] est le JSON **décodé**, ou la chaîne brute si le décodage a échoué,
/// ou `null` si la réponse était vide.
///
/// Les sept cas :
/// - `status >= 400` → échec (403 « too many connections » ou 429 → saturé) ;
/// - `null` (corps vide) → **échec** : un panel sain répond au minimum `[]` ;
/// - `[]` → **succès vide** (le panel n'a vraiment pas de films) ;
/// - `[…]` → succès ;
/// - `{}` → échec ;
/// - `{"user_info": …}` → échec (le panel répond son bloc d'auth : refus) ;
/// - texte non-JSON → échec.
XtreamListResult classifyListBody(Object? body, int? status) {
  // 1. Un statut d'erreur prime sur tout le reste : le corps d'un 403 est du
  //    texte d'explication, jamais la liste demandée.
  if (status != null && status >= 400) {
    final saturated = status == 429 || (status == 403 && _mentionsConnections(body));
    return (
      items: null,
      error: saturated
          ? 'HTTP $status — trop de connexions simultanées'
          : 'HTTP $status',
      status: status,
      kind: saturated ? LoadFailureKind.busy : LoadFailureKind.network,
    );
  }

  // 2. Corps vide : ce n'est PAS « pas de films », c'est « pas de réponse ».
  if (body == null) {
    return (
      items: null,
      error: 'réponse vide',
      status: status,
      kind: LoadFailureKind.network,
    );
  }

  // 3. Le seul cas de succès : une liste JSON.
  if (body is List) {
    return (
      items: body.whereType<Map<String, dynamic>>().toList(growable: false),
      error: null,
      status: status,
      kind: null,
    );
  }

  // 4. Un objet à la place d'une liste = le panel a répondu autre chose
  //    (bloc d'auth, message d'erreur…). Jamais un catalogue vide.
  if (body is Map) {
    final saturated = _mentionsConnections(body);
    return (
      items: null,
      error: body.containsKey('user_info')
          ? 'le panel a renvoyé son bloc d\'authentification'
          : (saturated
              ? 'le panel signale trop de connexions'
              : 'objet JSON inattendu à la place d\'une liste'),
      status: status,
      kind: saturated ? LoadFailureKind.busy : LoadFailureKind.network,
    );
  }

  // 5. Texte non-JSON (page d'erreur HTML, message brut du panel…).
  final saturated = _mentionsConnections(body);
  return (
    items: null,
    error: saturated
        ? 'le panel signale trop de connexions'
        : 'réponse illisible (pas du JSON)',
    status: status,
    kind: saturated ? LoadFailureKind.busy : LoadFailureKind.network,
  );
}

/// Le corps parle-t-il d'un excès de connexions ? (fr/en, panels bavards)
bool _mentionsConnections(Object? body) {
  if (body == null) return false;
  final t = body.toString().toLowerCase();
  if (!t.contains('connection') && !t.contains('connexion')) return false;
  return t.contains('many') ||
      t.contains('max') ||
      t.contains('limit') ||
      t.contains('trop') ||
      t.contains('exceed');
}

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
    return NetworkUtils.buildDio(url, account: account);
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

  /// §hostGate + §catalogTruth — GET interne. **Ne lève jamais.**
  ///
  /// Trois changements par rapport à la version d'origine :
  /// 1. l'appel entier passe par [HostGate] → une seule requête à la fois vers
  ///    ce panel (les abonnements de l'utilisateur sont en « 1 / 1 ») ;
  /// 2. `validateStatus` aligné sur `buildBaseDio` (`< 500`) → un
  ///    `403 Too many connections` devient une **réponse lisible** au lieu
  ///    d'une exception opaque dont le corps était jeté sans être lu ;
  /// 3. le `Dio` est fermé avant de rendre le jeton : sans ça, le socket
  ///    keep-alive du `HttpClient` neuf créé à chaque requête reste ouvert et
  ///    compte encore comme une connexion côté panel.
  ///
  /// [body] rendu = JSON décodé, ou la chaîne brute si ce n'est pas du JSON,
  /// ou `null` si la réponse était vide. [error] non nul = pas de réponse.
  ///
  /// [queueTimeout] borne l'attente **dans la file** (pas la requête). Les
  /// chemins interactifs (ouvrir une fiche série) en imposent un court : mieux
  /// vaut échouer en 90 s que faire tourner un spinner pendant que le
  /// rafraîchissement d'une liste monopolise le panel.
  static Future<({Object? body, int? status, String? error})> _fetch(
    StreamAccount account,
    String url, {
    Duration? timeout,
    Duration? queueTimeout,
  }) async {
    try {
      return await HostGate.run(url, () async {
        final dio = await _dio(account);
        try {
          final resp = await dio.get<String>(
            url,
            options: Options(
              responseType: ResponseType.plain,
              followRedirects: true,
              receiveTimeout: timeout ?? const Duration(minutes: 2),
              // ⚠️ Ne PAS remettre `s < 300` : le 403 doit être lu, pas levé.
              validateStatus: (s) => s != null && s < 500,
            ),
          );
          final raw = resp.data ?? '';
          if (raw.isEmpty) {
            return (body: null, status: resp.statusCode, error: null);
          }
          Object? decoded;
          try {
            decoded = jsonDecode(raw);
          } catch (_) {
            // Pas du JSON : on garde le texte, `classifyListBody` saura y
            // reconnaître un « too many connections ».
            decoded = raw.length > 500 ? raw.substring(0, 500) : raw;
          }
          return (body: decoded, status: resp.statusCode, error: null);
        } finally {
          // Referme le HttpClient (et donc le socket) AVANT de rendre le jeton.
          dio.close(force: true);
        }
      }, timeout: queueTimeout);
    } on HostGateTimeoutException {
      return (
        body: null,
        status: null,
        error: 'file d\'attente saturée pour ce serveur',
      );
    } on DioException catch (e) {
      // §logHygiene — jamais `$e` brut : l'exception embarque l'URL avec les
      // identifiants. On ne garde que la nature de la panne.
      final reason = switch (e.type) {
        DioExceptionType.connectionError ||
        DioExceptionType.connectionTimeout =>
          'serveur injoignable',
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout =>
          'délai dépassé',
        DioExceptionType.badResponse =>
          'HTTP ${e.response?.statusCode ?? '?'}',
        _ => 'erreur réseau',
      };
      return (body: null, status: e.response?.statusCode, error: reason);
    } catch (_) {
      return (body: null, status: null, error: 'erreur inattendue');
    }
  }

  /// §hostGate — Applique la limite de connexions annoncée par le panel.
  ///
  /// ⚠️ `maxConnections - 1` : **la connexion restante est réservée au
  /// lecteur vidéo**, qui ne passe jamais par [HostGate].
  static void _applyConnectionLimit(StreamAccount account, Object? authBody) {
    if (authBody is! Map) return;
    final info = authBody['user_info'];
    if (info is! Map) return;
    final max = int.tryParse((info['max_connections'] ?? '').toString());
    if (max == null || max <= 0) return;
    final host = credentialsOf(account)?.host;
    if (host == null) return;
    HostGate.setLimit(host, max - 1 < 1 ? 1 : max - 1);
  }

  // ── Auth / info compte ──────────────────────────────────────────────────

  /// Appelle `player_api.php` sans action → renvoie le bloc complet
  /// `{ user_info: {…}, server_info: {…} }`. Null si échec / compte invalide.
  static Future<Map<String, dynamic>?> auth(StreamAccount account) async {
    final url = _baseUrl(account);
    if (url == null) return null;
    final r = await _fetch(account, url,
        timeout: const Duration(seconds: 20),
        queueTimeout: const Duration(seconds: 60));
    if (r.error != null) {
      debugPrint('⚠️ XtreamApi.auth : ${r.error}');
      return null;
    }
    final data = r.body;
    if (data is Map<String, dynamic>) {
      // §hostGate — Le panel vient de dire combien de connexions il tolère.
      _applyConnectionLimit(account, data);
      return data;
    }
    return null;
  }

  // ── Live (chaînes TV) ───────────────────────────────────────────────────
  //
  // §catalogTruth — DEUX familles de getters :
  //  · `get…Result()` — le contrat honnête (`items == null` ⇔ échec), utilisé
  //    par `XtreamCatalogService` pour refuser d'écrire un catalogue amputé ;
  //  · `get…()` — façade de compatibilité qui rend `[]` en cas d'échec, pour
  //    les appelants qui ne savent pas quoi faire d'une panne.
  //
  // ⚠️ Ne PAS appeler la façade depuis un chemin qui écrit sur le disque : un
  // `[]` d'échec y est indiscernable d'un catalogue réellement vide, et c'est
  // exactement le bug qui effaçait les listes.

  /// Liste des catégories live (TV). Retourne `[]` si échec (façade).
  static Future<List<Map<String, dynamic>>> getLiveCategories(
          StreamAccount account) =>
      _itemsOrEmpty(getLiveCategoriesResult(account));

  static Future<XtreamListResult> getLiveCategoriesResult(
          StreamAccount account) =>
      _listAction(account, 'get_live_categories');

  /// Liste de toutes les chaînes live (sans filtrage par catégorie).
  static Future<List<Map<String, dynamic>>> getLiveStreams(
          StreamAccount account) =>
      _itemsOrEmpty(getLiveStreamsResult(account));

  static Future<XtreamListResult> getLiveStreamsResult(
          StreamAccount account) =>
      _listAction(account, 'get_live_streams');

  // ── VOD (films) ──────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getVodCategories(
          StreamAccount account) =>
      _itemsOrEmpty(getVodCategoriesResult(account));

  static Future<XtreamListResult> getVodCategoriesResult(
          StreamAccount account) =>
      _listAction(account, 'get_vod_categories');

  static Future<List<Map<String, dynamic>>> getVodStreams(
          StreamAccount account) =>
      _itemsOrEmpty(getVodStreamsResult(account));

  static Future<XtreamListResult> getVodStreamsResult(StreamAccount account) =>
      _listAction(account, 'get_vod_streams');

  // ── Séries ───────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getSeriesCategories(
          StreamAccount account) =>
      _itemsOrEmpty(getSeriesCategoriesResult(account));

  static Future<XtreamListResult> getSeriesCategoriesResult(
          StreamAccount account) =>
      _listAction(account, 'get_series_categories');

  /// Liste des séries (un item = une série, sans détails des épisodes).
  static Future<List<Map<String, dynamic>>> getSeries(
          StreamAccount account) =>
      _itemsOrEmpty(getSeriesResult(account));

  static Future<XtreamListResult> getSeriesResult(StreamAccount account) =>
      _listAction(account, 'get_series');

  static Future<List<Map<String, dynamic>>> _itemsOrEmpty(
      Future<XtreamListResult> r) async =>
      (await r).items ?? const [];

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
    // §epSynopsis — tmdb_id de la SÉRIE (champ `info.tmdb`), propagé sur
    // chaque épisode → l'action sheet épisode et `_providerTmdbId()` accèdent
    // à l'id exact (getEpisodeDetails saute la recherche floue).
    final seriesTmdb = (info['info'] is Map
            ? ((info['info'] as Map)['tmdb'] ?? '')
            : '')
        .toString();
    final episodes = info['episodes'];
    if (episodes is! Map) return const [];

    // §epSynopsis — helper : première valeur non vide parmi des clés du bloc
    // `info` d'un épisode (les panels varient : plot / overview / description).
    String? epInfoStr(Map e, List<String> keys) {
      final i = e['info'];
      if (i is! Map) return null;
      for (final k in keys) {
        final v = (i[k] ?? '').toString().trim();
        if (v.isNotEmpty) return v;
      }
      return null;
    }

    // §epTitleProvider — Titre d'épisode du panel, nettoyé. Formats réels :
    // "Pilot", "Breaking Bad S01E01 - Pilot", "S01 E01"… On garde la partie
    // APRÈS le marqueur SxxExx s'il est présent (séparateurs de tête strippés),
    // et on rejette ce qui ne porte aucune info (vide / == nom de série).
    final seriesKey = TitleMetadata.computeGroupKey(seriesName);
    String? cleanEpisodeTitle(Object? raw) {
      var t = (raw ?? '').toString().trim();
      if (t.isEmpty) return null;
      final m = RegExp(r's\s*\d{1,2}\s*e\s*\d{1,2}', caseSensitive: false)
          .firstMatch(t);
      if (m != null) t = t.substring(m.end);
      t = t.replaceFirst(RegExp(r'^[\s\-–—:._]+'), '').trim();
      if (t.isEmpty) return null;
      final key = TitleMetadata.computeGroupKey(t);
      if (key.isEmpty || key == seriesKey) return null;
      return t;
    }

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
        // §epSynopsis — synopsis/note/date de l'ÉPISODE fournis par le panel :
        // fallback provider quand TMDB échoue (avant : jamais mappés → aucun
        // résumé d'épisode possible sans TMDB).
        final plot = epInfoStr(e, const ['plot', 'overview', 'description']);
        final rating = double.tryParse(
            (e['info'] is Map ? ((e['info'] as Map)['rating'] ?? '') : '')
                .toString());
        final releaseDate =
            epInfoStr(e, const ['air_date', 'releasedate', 'release_date']);
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
          tmdbId: seriesTmdb.isEmpty ? null : seriesTmdb,
          plot: plot,
          episodeTitle: cleanEpisodeTitle(e['title']),
          rating: (rating != null && rating > 0) ? rating : null,
          releaseDate: releaseDate,
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
    // Chemin INTERACTIF (l'utilisateur vient d'ouvrir une fiche série) : on
    // n'attend pas indéfiniment derrière un rafraîchissement de catalogue.
    final r = await _fetch(account, url,
        queueTimeout: const Duration(seconds: 90));
    if (r.error != null) {
      debugPrint('⚠️ XtreamApi.getSeriesInfo($seriesId) : ${r.error}');
      return null;
    }
    final data = r.body;
    if (data is Map<String, dynamic>) return data;
    debugPrint('⚠️ XtreamApi.getSeriesInfo($seriesId) : réponse inattendue '
        '(HTTP ${r.status ?? '?'})');
    return null;
  }

  // ── Implémentation interne ─────────────────────────────────────────────

  /// §catalogTruth — Appelle une action « liste » et **dit si elle a échoué**.
  ///
  /// Avant : tout échec rendait `const []`, donc « ce panel n'a pas de films »
  /// et « ce panel a refusé la connexion » s'écrivaient de la même façon — et
  /// le catalogue amputé qui en résultait écrasait le catalogue complet.
  static Future<XtreamListResult> _listAction(
      StreamAccount account, String action) async {
    final base = _baseUrl(account);
    if (base == null) {
      return (
        items: null,
        error: 'identifiants Xtream inextractibles',
        status: null,
        kind: LoadFailureKind.badAccount,
      );
    }
    final url = '$base&action=$action';
    final r = await _fetch(account, url);
    if (r.error != null) {
      debugPrint('⚠️ XtreamApi.$action : ${r.error}');
      return (
        items: null,
        error: r.error,
        status: r.status,
        kind: LoadFailureKind.network,
      );
    }
    final out = classifyListBody(r.body, r.status);
    if (out.items == null) {
      debugPrint('❌ XtreamApi.$action : ${out.error}');
    }
    return out;
  }
}
