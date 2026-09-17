import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Lot 11 — Un sous-titre proposé par le fournisseur en ligne.
@immutable
class OnlineSubtitle {
  const OnlineSubtitle({
    required this.id,
    required this.url,
    required this.language,
    required this.display,
    this.source,
    this.release,
    this.hearingImpaired = false,
    this.format = 'srt',
  });

  final String id;
  final String url;

  /// Code ISO 639-1 rendu par le fournisseur (« fr », « en »…).
  final String language;

  /// Le nom de la langue tel que le fournisseur l'écrit (« French »).
  final String display;

  /// Le site d'où le fournisseur l'a tiré (« subdl », « podnapisi »…).
  final String? source;

  /// La version du film à laquelle il est calé (« 1080p.WEB-DL »…) : c'est
  /// ce qui distingue deux sous-titres de la même langue, et donc la seule
  /// chose utile à montrer sous le nom.
  final String? release;

  final bool hearingImpaired;
  final String format;
}

/// Lot 11 — Ce qu'on cherche : un titre, et pour une série la saison et
/// l'épisode. Séparé du service pour être construit — et testé — sans réseau.
@immutable
class SubtitleSearchContext {
  const SubtitleSearchContext({
    required this.query,
    required this.isTv,
    this.season,
    this.episode,
  });

  /// Le titre à faire reconnaître par TMDB.
  final String query;
  final bool isTv;
  final int? season;
  final int? episode;
}

/// Lot 11 — Le numéro d'épisode caché dans un badge « S01 E04 ».
///
/// `PlayerMedia` porte la saison en clair mais l'épisode seulement dans ce
/// badge, écrit pour être LU (« S01 E04 », « S1E4 », « 1x04 » selon les
/// listes). Fonction pure, tolérante à la forme : `null` si rien de crédible,
/// jamais une exception — un badge exotique doit dégrader la recherche, pas
/// l'empêcher.
int? episodeNumberFromTag(String? tag) {
  if (tag == null) return null;
  final m = RegExp(r'(?:E|X)\s*0*(\d{1,3})', caseSensitive: false).firstMatch(tag);
  if (m == null) return null;
  return int.tryParse(m.group(1)!);
}

/// Lot 11 — De quoi chercher les sous-titres du contenu en cours.
///
/// Pour une série, c'est la SÉRIE qu'il faut faire reconnaître à TMDB, pas le
/// titre de l'épisode : « Le Trône de fer » trouve la fiche, « Les Enfants de
/// l'hiver » ne trouve rien. Fonction pure.
SubtitleSearchContext? subtitleSearchContextFor({
  required String title,
  String? seriesName,
  String? episodeTag,
  int? seasonNumber,
}) {
  final String series = seriesName?.trim() ?? '';
  final bool isTv = series.isNotEmpty;
  final String query = (isTv ? series : title).trim();
  if (query.isEmpty) return null;
  return SubtitleSearchContext(
    query: query,
    isTv: isTv,
    season: isTv ? seasonNumber : null,
    episode: isTv ? episodeNumberFromTag(episodeTag) : null,
  );
}

/// Lot 11 — Recherche et téléchargement de sous-titres en ligne, par
/// identifiant TMDB + langue (+ saison / épisode).
///
/// **Le fournisseur : Wyzie Subs** (`sub.wyzie.io`, documenté sur
/// `docs.wyzie.io/subs`). Vérifié le 2026-09-17 : il agrège plusieurs sources
/// et rend des adresses `.srt` DIRECTES — SubDL livre des archives ZIP (rien
/// pour les ouvrir sans dépendance nouvelle, §apkDiet) et OpenSubtitles limite
/// les téléchargements à quelques-uns par jour. Une clé gratuite s'obtient sur
/// [signupUrl] (vérification par e-mail, 1 000 requêtes par jour).
///
/// ⛔ **Aucune clé n'est intégrée à l'application** : celle-ci est celle de
/// l'UTILISATEUR (`SubtitleApiService`), comme la clé TMDB. C'est aussi ce que
/// le fournisseur demande — sa documentation interdit d'embarquer une clé dans
/// une application distribuée.
///
/// 🔴 **La clé voyage dans la QUERY** (`&key=…`, la seule forme que l'API
/// accepte). Elle ne doit donc JAMAIS atteindre le journal : celui-ci est
/// persisté (§logPersist) puis servi sur le LAN (§tvLogs), et c'est exactement
/// par là que le jeton Cast avait fuité (R35). Deux garde-fous ici :
/// [searchUri] n'est jamais journalisée, et tout échec est rendu comme un
/// [SubtitleSearchOutcome] — jamais comme une exception qui porterait l'URL
/// dans son message.
///
/// ⚠️ Le puits masque désormais `key=` sur tout hôte (§subOnline a ouvert le
/// trou et l'a bouché : `_secretQueryParams` dans `log_sanitizer.dart`,
/// alternance de `sanitizeForLog`). **Ces deux garde-fous restent quand
/// même** : une ceinture au puits ne dispense pas de bretelles à la source —
/// un message d'exception peut porter l'URL sous une forme que le puits ne
/// reconnaît pas (tronquée, ré-encodée), et c'est précisément ce genre de
/// « presque masqué » qui avait laissé passer R35.
class OnlineSubtitlesService {
  static const String _endpoint = 'https://sub.wyzie.io/search';
  static const Duration _timeout = Duration(seconds: 15);

  /// Où l'utilisateur obtient sa clé gratuite.
  static const String signupUrl = 'https://store.wyzie.io/redeem';

  /// L'adresse de recherche. Fonction pure : c'est elle qu'on teste.
  /// ⛔ Ne jamais la journaliser : elle porte la clé.
  static Uri searchUri({
    required int tmdbId,
    required String languages,
    required String apiKey,
    int? season,
    int? episode,
  }) =>
      Uri.parse(_endpoint).replace(queryParameters: <String, String>{
        'id': '$tmdbId',
        if (languages.isNotEmpty) 'language': languages,
        'format': 'srt',
        if (season != null) 'season': '$season',
        if (episode != null) 'episode': '$episode',
        'key': apiKey,
      });

  /// Les résultats, dans l'ordre du fournisseur.
  ///
  /// Fonction pure et TOLÉRANTE : la réponse est un tableau d'objets
  /// (`id`, `url`, `display`, `language`, `format`, `source`, `release`,
  /// `isHearingImpaired`…). Un champ absent ne fait pas tomber la liste ; un
  /// objet sans `url` est ignoré, parce que lui seul est indispensable.
  static List<OnlineSubtitle> parseResults(Object? json) {
    final List<dynamic> items = json is List
        ? json
        : (json is Map && json['results'] is List
            ? json['results'] as List
            : (json is Map && json['data'] is List
                ? json['data'] as List
                : const []));
    final out = <OnlineSubtitle>[];
    for (final dynamic it in items) {
      if (it is! Map) continue;
      final String? url = it['url'] as String?;
      if (url == null || url.isEmpty) continue;
      final String lang = (it['language'] ?? it['lang'] ?? '').toString();
      final String display =
          (it['display'] ?? it['title'] ?? it['name'] ?? lang).toString();
      final String format = (it['format'] ?? 'srt').toString().toLowerCase();
      final String release =
          (it['release'] ?? it['fileName'] ?? '').toString().trim();
      out.add(OnlineSubtitle(
        id: (it['id'] ?? url.hashCode).toString(),
        url: url,
        language: lang,
        display: display,
        source: it['source']?.toString(),
        release: release.isEmpty ? null : release,
        hearingImpaired:
            it['isHearingImpaired'] == true || it['hearing_impaired'] == true,
        format: format == 'vtt' ? 'vtt' : 'srt',
      ));
    }
    return out;
  }

  /// Cherche les sous-titres. Ne lève jamais : l'échec est une VALEUR, pour
  /// que l'URL (donc la clé) ne parte pas dans un message d'exception.
  static Future<SubtitleSearchOutcome> search({
    required int tmdbId,
    required String languages,
    required String apiKey,
    int? season,
    int? episode,
    http.Client? client,
  }) async {
    final http.Client c = client ?? http.Client();
    try {
      final resp = await c
          .get(searchUri(
            tmdbId: tmdbId,
            languages: languages,
            apiKey: apiKey,
            season: season,
            episode: episode,
          ))
          .timeout(_timeout);
      // ⛔ Le code et le nombre de résultats, jamais l'adresse.
      debugPrint('🔎 lot 11 — sous-titres tmdb $tmdbId → HTTP ${resp.statusCode}');
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        return const SubtitleSearchOutcome.badKey();
      }
      if (resp.statusCode == 429) return const SubtitleSearchOutcome.quota();
      if (resp.statusCode != 200) return const SubtitleSearchOutcome.failed();
      return SubtitleSearchOutcome.ok(
          parseResults(jsonDecode(utf8.decode(resp.bodyBytes))));
    } on TimeoutException {
      // ⛔ Jamais `$e` : le message d'une exception réseau porte l'URL, donc la
      // clé, et le journal part sur le LAN (§tvLogs, R35). ⛔ Jamais
      // `e.runtimeType` non plus : obfusqué en release, il ne dirait rien
      // (`test/obfuscation_guard_test.dart`). Les cas utiles sont NOMMÉS.
      debugPrint('⚠️ lot 11 — la recherche de sous-titres a expiré');
      return const SubtitleSearchOutcome.failed();
    } on SocketException {
      debugPrint('⚠️ lot 11 — pas de réseau pour chercher des sous-titres');
      return const SubtitleSearchOutcome.failed();
    } catch (_) {
      debugPrint('❌ lot 11 — recherche de sous-titres impossible');
      return const SubtitleSearchOutcome.failed();
    } finally {
      if (client == null) c.close();
    }
  }

  /// Télécharge le fichier dans `[cacheDir]/subtitles` et rend son chemin,
  /// `null` si rien d'exploitable. L'adresse de téléchargement ne porte pas la
  /// clé (le fournisseur la rend déjà signée), mais elle n'est pas journalisée
  /// non plus : une adresse de moins au journal LAN.
  static Future<String?> download(
    OnlineSubtitle s, {
    required Directory cacheDir,
    http.Client? client,
  }) async {
    final http.Client c = client ?? http.Client();
    try {
      final resp = await c.get(Uri.parse(s.url)).timeout(_timeout);
      if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) {
        debugPrint('⚠️ lot 11 — sous-titre non téléchargé : HTTP ${resp.statusCode}');
        return null;
      }
      final dir = Directory('${cacheDir.path}${Platform.pathSeparator}subtitles');
      if (!await dir.exists()) await dir.create(recursive: true);
      // Le nom vient de NOUS, jamais du fournisseur : un `id` exotique ne doit
      // pas pouvoir écrire ailleurs que dans ce dossier.
      final String safeId = s.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final file = File('${dir.path}${Platform.pathSeparator}$safeId.${s.format}');
      await file.writeAsBytes(resp.bodyBytes, flush: true);
      debugPrint('✅ lot 11 — sous-titre enregistré : ${resp.bodyBytes.length} octets');
      return file.path;
    } on TimeoutException {
      debugPrint('⚠️ lot 11 — le téléchargement du sous-titre a expiré');
      return null;
    } catch (_) {
      // ⛔ Ni `$e` (il porte l'adresse) ni `runtimeType` (obfusqué en release).
      debugPrint('❌ lot 11 — téléchargement du sous-titre impossible');
      return null;
    } finally {
      if (client == null) c.close();
    }
  }
}

/// Lot 11 — Le résultat d'une recherche, échec compris. Une VALEUR plutôt
/// qu'une exception : le message d'une exception réseau porte l'URL, donc la
/// clé, et finirait au journal servi sur le LAN (R35).
@immutable
class SubtitleSearchOutcome {
  const SubtitleSearchOutcome.ok(this.results)
      : error = null;
  const SubtitleSearchOutcome.badKey()
      : results = const [],
        error = SubtitleSearchError.badKey;
  const SubtitleSearchOutcome.quota()
      : results = const [],
        error = SubtitleSearchError.quota;
  const SubtitleSearchOutcome.failed()
      : results = const [],
        error = SubtitleSearchError.network;

  final List<OnlineSubtitle> results;
  final SubtitleSearchError? error;

  bool get isOk => error == null;
}

/// Ce qui a empêché la recherche d'aboutir — trois cas, parce que trois
/// gestes différents : refaire sa clé, attendre demain, réessayer.
enum SubtitleSearchError { badKey, quota, network }
