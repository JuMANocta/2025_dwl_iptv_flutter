import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'tmdb_api_service.dart';
import 'package:aetherStream/data/models/media_model.dart';
import 'package:aetherStream/data/models/person_model.dart';

class TmdbService {
  Dio? _dio;
  String? _bearerToken;

  static TmdbService? _instance;
  static TmdbService get instance {
    _instance ??= TmdbService._internal();
    return _instance!;
  }

  TmdbService._internal();

  static void resetInstance() {
    debugPrint("💣 Forçage de la destruction du Singleton TmdbService.");
    _instance = null;
  }

  /// 📅 Extrait l'année (4 chiffres) d'une chaine brute
  String? _extractYear(String raw) {
    // Cherche 19xx ou 20xx (ex: 2024, (1999), [2005])
    final match = RegExp(r'\b(19|20)\d{2}\b').firstMatch(raw);
    return match?.group(0);
  }

  /// 🧹 Nettoyeur de nom de fichier
  String _cleanQuery(String rawName) {
    // 1. Mise en minuscule immédiate pour faciliter la comparaison
    String clean = rawName.toLowerCase();

    // --- ÉTAPE 1: Nettoyage des Préfixes IPTV & Caractères Non-Standard ---
    // Supprime les tags de pays/langue qui sont au début (ex: |FR|, FR: )
    clean = clean.replaceAll(RegExp(r'^(\|.*?\||\w{2,}\s*[:-])\s*', caseSensitive: false), ' ');

    // Ajout du pipe (|) aux séparateurs pour éviter qu'il ne reste seul
    clean = clean.replaceAll(RegExp(r'[|]'), ' ');

    // --- ÉTAPE 2: Supprimer les informations techniques et de langue ---
    final List<String> noiseWords = [
      // Saisons/Épisodes (Regex)
      r's\d{1,2}\s?e\d{1,2}|\d{1,2}x\d{1,2}|saison\s?\d{1,2}|episode\s?\d{1,2}', // Recherche et supprime SXXEXX, XXxXX, Saison XX, etc.

      // Qualité Vidéo & Résolutions
      '4k', 'uhd', '2160p', '1080p', '720p', '480p', 'fhd', 'hd', 'sd', 'bdrip', 'webrip',
      'hdr', 'dv', 'dvdscr', 'cam', 'ts', 'telecine', 'screener',

      // Codecs Vidéo
      'hevc', 'h.264', 'x264', 'h.265', 'x265', 'avc', 'vp9', 'divx', 'xvid', 'mpeg',

      // Codecs Audio & Formats
      'aac', 'dts', 'dtshd', 'dts-hd', 'atmos', 'truehd', 'dolby', 'ac3', 'dd5.1', 'mp3', 'flac',

      // Conteneurs
      'mkv', 'mp4', 'avi', 'ts', 'iso', 'img',

      // Langues & Groupes
      'vostfr', 'vost', 'vf', 'vo', 'vff', 'truefrench', 'multi', 'english', 'french', 'fr', 'en', 'sub',

      // Mentions Diverses (Groupes de release, versions)
      'extended', 'uncut', 'final cut', 'version longue', 'vostf', 'raw', 'repack', 'proper', 'retail', 'remux',
      'imax', 'imax enhanced', '4d', '3d', '2d'
    ];

    // Construit la Regex avec frontière de mot (\b)
    final noiseRegex = RegExp(r'\b(' + noiseWords.join('|') + r')\b', caseSensitive: true);
    clean = clean.replaceAll(noiseRegex, ' ');

    // --- ÉTAPE 3: Supprimer les séparateurs restants et l'année ---
    // Remplace les points, crochets, parenthèses, underscores, tirets par des espaces
    clean = clean.replaceAll(RegExp(r'[\.\[\]\(\)_\-]+'), ' ');

    // Supprime l'année (ex: 2024, 1999)
    clean = clean.replaceAll(RegExp(r'\b(19|20)\d{2}\b'), ' ');

    // --- ÉTAPE 4: Nettoyage final ---
    // Supprime les espaces multiples et les espaces au début/fin
    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();

    return clean;
  }

  Future<void> reinitialize() async => await _init();

  Future<bool> _init() async {
    final String? storedToken = await TmdbApiService.getApiKey();
    if (storedToken == null || storedToken.isEmpty) {
      if (_dio != null) { _dio = null; _bearerToken = null; }
      return false;
    }
    if (_bearerToken == storedToken && _dio != null) return true;

    _bearerToken = storedToken;
    _dio = Dio(
      BaseOptions(
        baseUrl: 'https://api.themoviedb.org/3',
        queryParameters: {'language': 'fr-FR', 'include_adult': 'false'},
        headers: {'Authorization': 'Bearer $_bearerToken', 'accept': 'application/json'},
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    return true;
  }

  /// 🎭 Mappe les mots-clés du group-title M3U vers des genre_ids TMDB.
  /// Utilisé pour désambiguïser les homonymes sans année (ex: anime vs live-action).
  static List<int> _groupTitleToGenreHints(String groupTitle) {
    final g = groupTitle.toUpperCase();
    final hints = <int>[];
    // Animation / Manga — id 16 (commun films ET séries TMDB)
    if (g.contains('MANGA') || g.contains('ANIME') || g.contains('ANIMÉ') ||
        g.contains('ANIMAT') || g.contains('CARTOON')) {
      hints.add(16);
    }
    // Documentaire
    if (g.contains('DOCU')) hints.add(99);
    // Comédie
    if (g.contains('COMÉD') || g.contains('COMED') || g.contains('HUMOUR')) hints.add(35);
    // Horreur
    if (g.contains('HORREUR') || g.contains('HORROR') || g.contains('ÉPOUVANTE')) hints.add(27);
    // Action (28 = film, 10759 = TV)
    if (g.contains('ACTION')) hints.addAll([28, 10759]);
    // Science-fiction (878 = film, 10765 = TV)
    if (g.contains('SCI-FI') || g.contains('SCIENCE-FI') || g.contains('SF ') ||
        g.contains(' SF') || g.contains('SCIFI')) {
      hints.addAll([878, 10765]);
    }
    // Fantastique (14 = film, 10765 = TV)
    if (g.contains('FANTAST') || g.contains('FANTASY')) hints.addAll([14, 10765]);
    // Famille / Enfants
    if (g.contains('FAMIL') || g.contains('ENFANT') || g.contains('KIDS')) {
      hints.addAll([10751, 10762]);
    }
    // Romance
    if (g.contains('ROMAN') || g.contains('ROMANCE')) hints.add(10749);
    // Thriller
    if (g.contains('THRILLER')) hints.add(53);
    // Drame
    if (g.contains('DRAME') || g.contains('DRAMA')) hints.add(18);
    // Western
    if (g.contains('WESTERN')) hints.add(37);
    // Crime
    if (g.contains('CRIME') || g.contains('POLICIER') || g.contains('POLAR')) hints.add(80);
    return hints;
  }

  /// 🧠 SMART SEARCH V3 : Langue + Type + ANNÉE + GENRE
  /// [explicitYear] : année déjà extraite par TitleMetadata (prioritaire sur l'extraction depuis rawQuery).
  /// [groupTitle]   : group-title M3U → converti en hints de genre pour désambiguïser les homonymes.
  /// Permet de désambiguïser les homonymes (ex: One Piece anime 1999 vs live-action 2023).
  Future<Media?> getFullDetails(String rawQuery, {required bool isTv, String? explicitYear, String? groupTitle}) async {
    if (!await _init()) return null;

    // 1. Détections Préalables
    final bool appearsEnglish = RegExp(r'\b(VO|VOST|VOSTFR|ENGLISH)\b', caseSensitive: false).hasMatch(rawQuery);
    final String searchLanguage = appearsEnglish ? 'en-US' : 'fr-FR';

    // 📅 Extraction de l'année (Crucial pour les homonymes)
    // L'année explicite (issue de TitleMetadata) est prioritaire — elle est déjà proprement parsée.
    // Fallback : extraction depuis rawQuery (cas où getFullDetails est appelé sans contexte).
    final String? year = explicitYear ?? _extractYear(rawQuery);

    // 2. Nettoyage
    final cleanQuery = _cleanQuery(rawQuery);

    // 🎭 Hints de genre issus du group-title (pour désambiguïser sans année)
    final List<int> genreHints = groupTitle != null ? _groupTitleToGenreHints(groupTitle) : [];
    debugPrint("🔍 Scan TMDB | Titre: '$cleanQuery' | Année: ${year ?? 'N/A'} | Lang: $searchLanguage | Genre hints: $genreHints");

    try {
      Map<String, dynamic>? result;

      // --- PHASES 1 à 4 (Recherche avec/sans année, inversion type, fallback langue) ---

      // Tente 1: Strict (Année + Type)
      if (year != null) {
        result = await _performSearch(cleanQuery, isTv: isTv, language: searchLanguage, year: year, genreHints: genreHints);
      }

      // Tente 2: Souple (Type seul, genre hints actifs)
      if (result == null) {
        if (year != null) debugPrint("⚠️ Pas de match avec l'année $year. Tentative sans année...");
        result = await _performSearch(cleanQuery, isTv: isTv, language: searchLanguage, genreHints: genreHints);
      }

      // Tente 3: Fallback Type
      if (result == null) {
        debugPrint("! Bascule de type (TV <-> Film)...");
        if (year != null) {
          result = await _performSearch(cleanQuery, isTv: !isTv, language: searchLanguage, year: year, genreHints: genreHints);
        }
        result ??= await _performSearch(cleanQuery, isTv: !isTv, language: searchLanguage, genreHints: genreHints);
      }

      // Tente 4: Fallback Langue Ultime (sans genre hints — dernier recours)
      if (result == null && appearsEnglish) {
        debugPrint("⚠️ Échec VO. Tentative repli FR...");
        result = await _performSearch(cleanQuery, isTv: isTv, language: 'fr-FR');
      }

      if (result == null) {
        debugPrint("❌ ECHEC TOTAL : '$cleanQuery' introuvable.");
        return null;
      }

      // --- SUCCÈS : Téléchargement Détails + Extras (credits, videos) ---
      final int id = result['id'];
      final bool foundAsTv = result['media_type'] == 'tv';

      debugPrint("🎯 Cible verrouillée : ID $id (${foundAsTv ? 'TV' : 'Film'}). Demande d'extras (Cast, Trailer)...");

      final detailEndpoint = foundAsTv ? '/tv/$id' : '/movie/$id';

      // 🎯 NOUVEAU : AJOUT DE APPEND_TO_RESPONSE
      final detailResponse = await _dio!.get(
          detailEndpoint,
          queryParameters: {
            'language': 'fr-FR',
            'append_to_response': 'credits,videos', // 👈 Ceci demande les acteurs et les vidéos
          }
      );

      // Le parsing de ces nouveaux champs (cast, trailerKey) doit être fait dans Media.fromJson
      return Media.fromJson(detailResponse.data);

    } catch (e) {
      debugPrint("❌ Glitch TMDB : $e");
      return null;
    }
  }

  Future<int?> getPersonId(String query) async {
    if (!await _init()) return null;

    try {
      debugPrint("🔎 Recherche ID personne pour : '$query'");
      final response = await _dio!.get('/search/person', queryParameters: {
        'query': query,
        'language': 'fr-FR', // Recherche de nom dans le langage ciblé
      });

      if (response.data['results'].isNotEmpty) {
        return response.data['results'][0]['id'] as int;
      }
    } catch (e) {
      debugPrint("❌ Erreur recherche personne : $e");
    }
    return null;
  }

  Future<Person?> getPersonDetails(int personId) async {
    if (!await _init()) return null;

    final endpoint = '/person/$personId';

    try {
      debugPrint("🎬 Demande détails acteur ID: $personId + filmographie.");
      final response = await _dio!.get(
          endpoint,
          queryParameters: {
            'language': 'fr-FR',
            'append_to_response': 'combined_credits' // Filmographie (films et séries)
          }
      );

      return Person.fromJson(response.data);

    } catch (e) {
      debugPrint("❌ Erreur récupération détails acteur : $e");
      return null;
    }
  }

  /// Détails d'un épisode précis : recherche la série, puis récupère l'épisode.
  /// [groupTitle] : group-title M3U transmis pour désambiguïser la série (ex: "MANGAS" → genre Animation).
  Future<Map<String, dynamic>?> getEpisodeDetails(
    String showQuery,
    int seasonNumber,
    int episodeNumber, {
    String? yearFilter,
    String? groupTitle,
  }) async {
    if (!await _init()) return null;

    final List<int> genreHints = groupTitle != null ? _groupTitleToGenreHints(groupTitle) : [];

    try {
      final searchResult = await _performSearch(
        showQuery,
        isTv: true,
        language: 'fr-FR',
        year: yearFilter,
        genreHints: genreHints,
      );
      if (searchResult == null) return null;
      final id = searchResult['id'] as int;

      final resp = await _dio!.get(
        '/tv/$id/season/$seasonNumber/episode/$episodeNumber',
        queryParameters: {
          'language': 'fr-FR',
          'append_to_response': 'credits,images,videos',
        },
      );

      if (resp.statusCode == 200) {
        return resp.data as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint("❌ Erreur récupération épisode TMDB : $e");
    }
    return null;
  }

  /// Recherche atomique avec paramètres optionnels.
  /// [genreHints] : liste de genre_ids TMDB préférés — si non vide, on regarde jusqu'à 5 résultats
  ///               et on préfère le premier dont les genres matchent. Fallback sur results[0].
  Future<Map<String, dynamic>?> _performSearch(String query, {
    required bool isTv,
    required String language,
    String? year,
    List<int> genreHints = const [],
  }) async {
    try {
      final endpoint = isTv ? '/search/tv' : '/search/movie';

      final params = <String, dynamic>{
        'query': query,
        'language': language,
      };

      if (year != null) {
        if (isTv) {
          params['first_air_date_year'] = year;
        } else {
          params['year'] = year;
        }
      }

      final response = await _dio!.get(endpoint, queryParameters: params);

      if (response.statusCode == 200) {
        final results = response.data['results'] as List?;
        if (results == null || results.isEmpty) return null;

        Map<String, dynamic>? best;

        // Désambiguïsation par genre : on parcourt jusqu'à 5 résultats
        if (genreHints.isNotEmpty) {
          for (final r in results.take(5)) {
            final genres = ((r as Map)['genre_ids'] as List?)?.cast<int>() ?? [];
            if (genres.any(genreHints.contains)) {
              best = r.cast<String, dynamic>();
              debugPrint("🎭 Genre match: '${r['name'] ?? r['title']}' genres=$genres hints=$genreHints");
              break;
            }
          }
        }

        final item = (best ?? results[0]) as Map<String, dynamic>;
        item['media_type'] = isTv ? 'tv' : 'movie';
        return item;
      }
    } catch (_) {}
    return null;
  }

  static String? getPosterUrl(String? path, {String size = 'w500'}) {
    if (path == null || path.isEmpty) return null;
    return 'https://image.tmdb.org/t/p/$size$path';
  }
}
