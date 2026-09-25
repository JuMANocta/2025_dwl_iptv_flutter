import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

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

/// §episodeTruth — Résultat de `fetchEpisodes`.
///
/// **`episodes == null` ⇔ ÉCHEC**, exactement comme [XtreamListResult]. Avant,
/// `fetchEpisodes` rendait `const []` pour « série sans épisode », « panel
/// injoignable », « compte non extractible » et « réponse illisible » : la
/// fiche affichait donc « Aucun épisode disponible pour cette série » alors que
/// c'était le réseau qui était mort, et l'utilisateur n'avait rien à réessayer.
typedef XtreamEpisodesResult = ({
  /// Les épisodes, ou `null` si le fetch a échoué. Une liste **vide** est un
  /// succès : la série existe et le panel n'a aucun épisode pour elle.
  List<M3uEntry>? episodes,

  /// Motif court, en français, sans identifiants.
  String? error,

  /// Nature de l'échec, pour l'affichage (§fleetState).
  LoadFailureKind? kind,
});

/// §episodeTruth — Résultat de `getSeriesInfo`. Même contrat : `info == null`
/// signifie échec, et [error] dit pourquoi.
typedef XtreamSeriesInfoResult = ({
  Map<String, dynamic>? info,
  String? error,
  LoadFailureKind? kind,
});

/// §episodeTruth — Le champ `episodes` d'un `get_series_info` est-il lisible ?
///
/// Rend `null` si oui, sinon le motif d'échec. Fonction **pure** : c'est elle
/// qui décide qu'une réponse illisible n'est PAS « aucun épisode ».
///
/// Un panel sain rend une `Map` saison → épisodes, ou (plus rarement) une
/// liste vide pour une série sans épisode. Tout le reste — `null`, une chaîne,
/// un objet d'erreur — est une réponse qu'on ne sait pas lire.
String? episodesFieldError(Object? episodes) {
  if (episodes is Map) return null;
  if (episodes is List && episodes.isEmpty) return null;
  return 'le serveur n\'a pas renvoyé de liste d\'épisodes';
}

/// §22.5 — L'URL de lecture (et de téléchargement) d'un épisode Xtream :
/// `{host}/series/{user}/{pass}/{id}.{ext}`.
///
/// C'est la forme que le panel écrit LUI-MÊME dans son `get.php` : vérifié sur
/// les deux M3U réels (`lib/iptv_exemple/`), 126 965 + 104 287 URL d'épisode,
/// toutes `…/series/…/<id>.<ext>`. Côté films, l'extension que le JSON annonce
/// (`container_extension`) est celle du `get.php` du même panel pour 26 097
/// films sur 26 097 (VOD).
///
/// ⚠️ L'extension est `container_extension` tel quel, `mp4` s'il manque. Une
/// valeur VIDE donnerait `…/<id>.` : jamais vue (0 sur 119 362 films des
/// quatre catalogues ; les épisodes ne sont pas dans les dumps). La corriger
/// changerait l'URL, donc la clé de reprise et de téléchargement, d'épisodes
/// déjà vus : décision à part, pas un correctif en passant.
///
/// Fonction pure : c'est elle qu'on teste.
String xtreamEpisodeUrl({
  required String host,
  required String username,
  required String password,
  required Object episodeId,
  Object? extension,
}) =>
    '$host/series/${Uri.encodeComponent(username)}/'
    '${Uri.encodeComponent(password)}/$episodeId.${extension ?? 'mp4'}';

/// §xtreamEpisodes — Les épisodes d'une réponse `get_series_info` dont le champ
/// `episodes` est une `Map` saison → épisodes, prêts pour la fiche (mêmes
/// champs qu'une entrée du parseur M3U).
///
/// §22.1 — Les ÉTIQUETTES de la série (qualité, langues, libellé de version,
/// marqueur) passent sur chaque épisode, prises sur [seriesTitle] (le stub du
/// catalogue) ou, à défaut, sur le nom que rend le panel. Sans elles, les
/// épisodes de « Game of Thrones (4K) HDR » et de « Game of Thrones (MULTI)
/// FHD », deux séries d'une même liste, portaient la même pastille par défaut
/// (« FHD ») et la fiche n'en gardait qu'un (`dedupeVersions`) ; le lecteur
/// n'annonçait aucune qualité, et la porte 4K (§deviceCaps) laissait passer un
/// épisode 4K qu'un appareil ne sait pas décoder.
///
/// ⚠️ Nom, clé de groupe et année restent ceux du nom rendu par le panel
/// (§favSeries) : la clé des favoris ne bouge pas.
///
/// Fonction pure : c'est elle qu'on teste.
List<M3uEntry> episodesFromSeriesInfo(
  Map<String, dynamic> info, {
  required ({String host, String username, String password}) creds,
  required String accountId,
  TitleMetadata? seriesTitle,
}) {
  final Object? episodes = info['episodes'];
  if (episodes is! Map) return const <M3uEntry>[];
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
  final TitleMetadata tags = seriesTitle ?? seriesMeta;
  // §epSynopsis — tmdb_id de la SÉRIE (champ `info.tmdb`), propagé sur
  // chaque épisode → l'action sheet épisode et `_providerTmdbId()` accèdent
  // à l'id exact (getEpisodeDetails saute la recherche floue).
  final seriesTmdb = (info['info'] is Map
          ? ((info['info'] as Map)['tmdb'] ?? '')
          : '')
      .toString();

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
      final url = xtreamEpisodeUrl(
        host: creds.host,
        username: creds.username,
        password: creds.password,
        episodeId: epId,
        extension: e['container_extension'],
      );
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
          quality: tags.quality,
          languages: tags.languages,
          versionLabel: tags.versionLabel,
          providerTag: tags.providerTag,
        ),
        accountId: accountId,
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
  return out;
}

/// §episodeTruth — Verdict d'un fetch d'épisodes réparti sur PLUSIEURS comptes.
///
/// Rend `null` quand il n'y a **pas** de panne à signaler, sinon le motif à
/// afficher. Règle : dès qu'un seul compte a répondu correctement — même avec
/// zéro épisode — il n'y a pas de panne du point de vue de l'utilisateur ;
/// qu'une liste secondaire soit injoignable pendant qu'une autre répond ne
/// doit pas transformer la fiche en écran d'erreur.
String? episodesFailureReason(List<XtreamEpisodesResult> results) {
  if (results.isEmpty) return null;
  if (results.any((r) => r.episodes != null)) return null;
  for (final r in results) {
    final e = r.error;
    if (e != null && e.isNotEmpty) return e;
  }
  return 'le serveur n\'a pas répondu';
}

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

/// Revue 2026-09-11, D1A-12 — Au-delà de cette taille, une réponse est
/// décodée dans un isolate. C'est le seuil que Dio lui-même retient pour
/// sortir un décodage JSON du thread principal (`BackgroundTransformer`,
/// 50 Ko). En dessous (catégories, `get_series_info` d'une fiche ouverte),
/// lancer un isolate coûterait plus que le décodage : on reste sur place.
const int _kIsolateDecodeThreshold = 50 * 1024;

/// Décodeur UTF-8 + JSON FUSIONNÉ, qui tolère l'UTF-8 invalide comme le
/// faisait Dio en `ResponseType.plain` (`utf8.decode(…, allowMalformed:
/// true)`).
final Converter<List<int>, Object?> _utf8JsonDecoder =
    const Utf8Decoder(allowMalformed: true).fuse(const JsonDecoder());

/// Revue 2026-09-11, D1A-12 — **Le corps d'une réponse `player_api.php`,
/// décodé depuis ses OCTETS.** Fonction pure, top-level : elle tourne aussi
/// bien sur le thread UI (petites réponses) que dans un isolate.
///
/// Rend EXACTEMENT ce que rendait l'ancien chemin — Dio en
/// `ResponseType.plain` (`utf8.decode(octets, allowMalformed: true)`), puis
/// `jsonDecode` — c'est-à-dire :
/// - `null` pour un corps vide ;
/// - le JSON décodé ;
/// - sinon le texte, tronqué à 500 caractères (`classifyListBody` y cherche
///   un « too many connections »).
///
/// Le décodeur fusionné saute la chaîne intermédiaire (une passe de moins).
/// ⚠️ Relecture lot 8a — ce n'est PAS un gain de mémoire : au-delà de 50 Ko,
/// les octets sont COPIÉS dans l'isolate (le message d'`Isolate.run`) et
/// l'original reste tenu par la réponse Dio jusqu'au retour, soit ~2n + le
/// graphe au pic — l'ordre de grandeur de l'ancien chemin (texte + graphe),
/// pas moins. Le gain est ailleurs : le décodage ne tient plus le thread UI.
/// Équivalence vérifiée
/// cas par cas (UTF-8 invalide dans une chaîne, octets Latin-1, BOM en tête,
/// BOM seul, `null`, HTML, espaces, séquences tronquées…) par
/// `test/xtream_body_decode_test.dart`, contre l'ancien algorithme. Le seul
/// écart du décodeur fusionné — un corps réduit à un BOM, que `utf8.decode`
/// rend vide — est rattrapé par le repli ci-dessous.
@visibleForTesting
Object? decodeXtreamBody(Uint8List bytes) {
  if (bytes.isEmpty) return null;
  try {
    return _utf8JsonDecoder.convert(bytes);
  } catch (_) {
    // Pas du JSON : on garde le texte, `classifyListBody` saura y
    // reconnaître un « too many connections ».
    final String raw = utf8.decode(bytes, allowMalformed: true);
    if (raw.isEmpty) return null; // BOM seul : vide, comme avant.
    return raw.length > 500 ? raw.substring(0, 500) : raw;
  }
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
/// 1. `get*CategoriesResult()` — liste les catégories (TV / VOD / Séries).
/// 2. `get*StreamsResult()` / `getSeriesResult()` — liste les flux (id + nom +
///    logo + catégorie).
/// 3. §23 — `XtreamCatalogService` sauvegarde les réponses brutes dans
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
  /// 2. `validateStatus` aligné sur `buildIptvBaseDio` (`< 500`) → un
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
          // Revue 2026-09-11, D1A-12 — OCTETS, et plus `ResponseType.plain` :
          // Dio décodait la réponse en texte (UTF-16, deux fois sa taille)
          // PUIS `jsonDecode` la parcourait, les deux sur le thread UI — pour
          // `get_vod_streams`, des dizaines de Mo, accueil affiché compris
          // (passe « reprise », `refreshIfStale`, « Tout recharger »). Une
          // grosse réponse est désormais décodée dans un isolate ; le
          // résultat revient par `Isolate.exit`, sans copie.
          final resp = await dio.get<List<int>>(
            url,
            options: Options(
              responseType: ResponseType.bytes,
              followRedirects: true,
              receiveTimeout: timeout ?? const Duration(minutes: 2),
              // ⚠️ Ne PAS remettre `s < 300` : le 403 doit être lu, pas levé.
              validateStatus: (s) => s != null && s < 500,
            ),
          );
          final List<int> data = resp.data ?? const <int>[];
          final Uint8List bytes =
              data is Uint8List ? data : Uint8List.fromList(data);
          final Object? decoded = await decodeBody(bytes);
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

  /// Revue 2026-09-11, D1A-12 — §isolateLeak : portée DÉDIÉE. La fermeture
  /// envoyée à l'isolate ne voit que [bytes] ; déclarée dans `_fetch`, elle
  /// aurait partagé le `Context` de la fermeture de `HostGate.run`, qui tient
  /// le `Dio` (son `HttpClient` ne se transmet pas) et le compte.
  static Future<Object?> _decodeOffUiThread(Uint8List bytes) =>
      Isolate.run(() => decodeXtreamBody(bytes), debugName: 'xtream-json');

  /// D1A-12 — Le choix du chemin : sur place sous [_kIsolateDecodeThreshold],
  /// dans un isolate au-delà. C'est CETTE fonction que `_fetch` appelle, et
  /// que `test/xtream_body_decode_test.dart` rejoue (aller-retour réel par
  /// l'isolate compris) contre l'ancien chemin de Dio.
  @visibleForTesting
  static FutureOr<Object?> decodeBody(Uint8List bytes) =>
      bytes.length < _kIsolateDecodeThreshold
          ? decodeXtreamBody(bytes)
          : _decodeOffUiThread(bytes);

  // ── Live (chaînes TV) ───────────────────────────────────────────────────
  //
  // §catalogTruth — Le contrat honnête : `items == null` ⇔ échec. C'est ce
  // qui permet à `XtreamCatalogService` de refuser d'écrire un catalogue
  // amputé.
  //
  // Revue 2026-09-11, D1A-14 — Les six façades « liste ou `[]` » (`get…()`),
  // leur `_itemsOrEmpty`, ainsi que `auth` / `_applyConnectionLimit` et
  // `invalidateEpisodes`, n'avaient plus AUCUN appelant : retirés.
  // ⛔ Ne pas réintroduire de façade qui rend `[]` en cas d'échec : un `[]`
  // d'échec est indiscernable d'un catalogue réellement vide, et c'est
  // exactement le bug qui effaçait les listes. La limite de connexions
  // annoncée par le panel (§hostGate) est posée par
  // `StreamAccountService.fetchAccountInfo`.

  static Future<XtreamListResult> getLiveCategoriesResult(
          StreamAccount account) =>
      _listAction(account, 'get_live_categories');

  static Future<XtreamListResult> getLiveStreamsResult(
          StreamAccount account) =>
      _listAction(account, 'get_live_streams');

  // ── VOD (films) ──────────────────────────────────────────────────────────

  static Future<XtreamListResult> getVodCategoriesResult(
          StreamAccount account) =>
      _listAction(account, 'get_vod_categories');

  static Future<XtreamListResult> getVodStreamsResult(StreamAccount account) =>
      _listAction(account, 'get_vod_streams');

  // ── Séries ───────────────────────────────────────────────────────────────

  static Future<XtreamListResult> getSeriesCategoriesResult(
          StreamAccount account) =>
      _listAction(account, 'get_series_categories');

  /// Liste des séries (un item = une série, sans détails des épisodes).
  static Future<XtreamListResult> getSeriesResult(StreamAccount account) =>
      _listAction(account, 'get_series');

  /// §xtreamEpisodes — Récupère TOUS les épisodes d'une série et les retourne
  /// directement sous forme de `List<M3uEntry>` prêts à être affichés par
  /// `DetailsPage` (mêmes champs que des entrées issues du parser M3U).
  /// Utilisé en LAZY-LOAD : on n'appelle pas cette API au boot (trop coûteux
  /// pour 19 000+ séries) ; on l'appelle uniquement quand l'utilisateur ouvre
  /// une fiche série.
  ///
  /// §episodeTruth — `episodes == null` signifie **échec** (et [error] dit
  /// lequel) ; une liste vide signifie « le panel n'a pas d'épisode pour cette
  /// série ». Les deux s'écrivaient `const []` avant.
  ///
  /// §22.1 — [seriesTitle] : le titre du STUB tel que le catalogue l'écrit.
  /// Ses étiquettes (qualité, langues, libellé, marqueur) passent sur chaque
  /// épisode — cf. [episodesFromSeriesInfo].
  static Future<XtreamEpisodesResult> fetchEpisodes(
    StreamAccount account,
    int seriesId, {
    TitleMetadata? seriesTitle,
  }) async {
    // §xtreamEpisodesCache — cache LRU lookup
    final key = _cacheKey(account.id, seriesId);
    final cached = _episodesCache[key];
    if (cached != null &&
        DateTime.now().difference(cached.at) < _cacheTtl) {
      // Hit : on remet l'entrée en tête (LRU) en la ré-insérant
      _episodesCache.remove(key);
      _episodesCache[key] = cached;
      return (episodes: cached.eps, error: null, kind: null);
    }

    final r = await getSeriesInfo(account, seriesId);
    final info = r.info;
    if (info == null) {
      return (episodes: null, error: r.error, kind: r.kind);
    }
    final creds = credentialsOf(account);
    if (creds == null) {
      return (
        episodes: null,
        error: 'identifiants Xtream inextractibles',
        kind: LoadFailureKind.badAccount,
      );
    }

    final episodes = info['episodes'];
    if (episodes is! Map) {
      // §episodeTruth — Un panel sain rend `{}` (ou une liste vide) pour une
      // série sans épisode : c'est un succès vide. Tout le reste est une
      // réponse qu'on ne sait pas lire, donc un échec — pas « aucun épisode ».
      final fieldError = episodesFieldError(episodes);
      if (fieldError == null) {
        return (episodes: const <M3uEntry>[], error: null, kind: null);
      }
      return (
        episodes: null,
        error: fieldError,
        kind: LoadFailureKind.parse,
      );
    }

    final out = episodesFromSeriesInfo(
      info,
      creds: creds,
      accountId: account.id,
      seriesTitle: seriesTitle,
    );

    // §xtreamEpisodesCache — Store : éviction LRU si capacité atteinte
    // (LinkedHashMap garde l'ordre d'insertion ; on retire le 1er élément
    // == le plus ancien, puis on insère le nouveau en fin == le plus récent).
    if (out.isNotEmpty) {
      if (_episodesCache.length >= _maxCacheEntries) {
        _episodesCache.remove(_episodesCache.keys.first);
      }
      _episodesCache[key] = (at: DateTime.now(), eps: out);
    }
    return (episodes: out, error: null, kind: null);
  }

  /// Détail complet d'une série (saisons + épisodes).
  /// Format Xtream : `{info: {…}, seasons: […], episodes: {"1": [{…}, …], "2": [...]}}`.
  ///
  /// §episodeTruth — Rend un résultat qui DIT pourquoi il a échoué : la fiche
  /// série en a besoin pour distinguer « pas d'épisode » de « réseau mort ».
  static Future<XtreamSeriesInfoResult> getSeriesInfo(
      StreamAccount account, int seriesId) async {
    final base = _baseUrl(account);
    if (base == null) {
      return (
        info: null,
        error: 'identifiants Xtream inextractibles',
        kind: LoadFailureKind.badAccount,
      );
    }
    final url = '$base&action=get_series_info&series_id=$seriesId';
    // Chemin INTERACTIF (l'utilisateur vient d'ouvrir une fiche série) : on
    // n'attend pas indéfiniment derrière un rafraîchissement de catalogue.
    //
    // ⚠️ `timeout` (réception) était laissé au défaut de `_fetch`, soit DEUX
    // MINUTES : le spinner « Chargement des épisodes… » pouvait donc tourner
    // deux minutes avant de dire quoi que ce soit. 30 s est déjà très large
    // pour un `get_series_info`, qui rend quelques kilo-octets.
    final r = await _fetch(account, url,
        timeout: const Duration(seconds: 30),
        queueTimeout: const Duration(seconds: 90));
    if (r.error != null) {
      debugPrint('⚠️ XtreamApi.getSeriesInfo($seriesId) : ${r.error}');
      return (
        info: null,
        error: r.error,
        kind: LoadFailureKind.network,
      );
    }
    final data = r.body;
    if (data is Map<String, dynamic>) {
      return (info: data, error: null, kind: null);
    }
    debugPrint('⚠️ XtreamApi.getSeriesInfo($seriesId) : réponse inattendue '
        '(HTTP ${r.status ?? '?'})');
    return (
      info: null,
      error: 'réponse inattendue du serveur (HTTP ${r.status ?? '?'})',
      kind: LoadFailureKind.parse,
    );
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
