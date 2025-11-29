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
    String clean = rawName.replaceAll(RegExp(r'(\.|_|\(|\)|\[|\]|-)', caseSensitive: false), ' ').trim();

    // Liste des parasites (Qualités + LANGUES + Codecs)
    final regexExclusion = RegExp(
      r'\b(S\d{2}E\d{2}|1080p|720p|4k|2160p|HDR|H\.264|x264|x265|HEVC|mkv|mp4|avi|webrip|bluray|dvdrip|VOSTFR|VOST|VF|VFF|TRUEFRENCH|MULTI|ENGLISH|FRENCH)\b',
      caseSensitive: false,
    );

    if (regexExclusion.hasMatch(clean)) {
      clean = clean.split(regexExclusion).first.trim();
    }

    // Suppression de l'année à la fin pour ne garder que le titre propre
    final regexYear = RegExp(r'\s+(19|20)\d{2}\s*$', caseSensitive: false);
    clean = clean.replaceAll(regexYear, '').trim();

    return clean.replaceAll(RegExp(r'\s+'), ' ');
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

  /// 🧠 SMART SEARCH V3 : Langue + Type + ANNÉE
  Future<Media?> getFullDetails(String rawQuery, {required bool isTv}) async {
    if (!await _init()) return null;

    // 1. Détections Préalables
    final bool appearsEnglish = RegExp(r'\b(VO|VOST|VOSTFR|ENGLISH)\b', caseSensitive: false).hasMatch(rawQuery);
    final String searchLanguage = appearsEnglish ? 'en-US' : 'fr-FR';

    // 📅 Extraction de l'année (Crucial pour les homonymes)
    final String? year = _extractYear(rawQuery);

    // 2. Nettoyage
    final cleanQuery = _cleanQuery(rawQuery);
    debugPrint("🔍 Scan TMDB | Titre: '$cleanQuery' | Année: ${year ?? 'N/A'} | Lang: $searchLanguage");

    try {
      Map<String, dynamic>? result;

      // --- PHASES 1 à 4 (Recherche avec/sans année, inversion type, fallback langue) ---

      // Tente 1: Strict (Année + Type)
      if (year != null) {
        result = await _performSearch(cleanQuery, isTv: isTv, language: searchLanguage, year: year);
      }

      // Tente 2: Souple (Type seul)
      if (result == null) {
        if (year != null) debugPrint("⚠️ Pas de match avec l'année $year. Tentative sans année...");
        result = await _performSearch(cleanQuery, isTv: isTv, language: searchLanguage);
      }

      // Tente 3: Fallback Type
      if (result == null) {
        debugPrint("⚠️ Bascule de type (TV <-> Film)...");
        if (year != null) {
          result = await _performSearch(cleanQuery, isTv: !isTv, language: searchLanguage, year: year);
        }
        if (result == null) {
          result = await _performSearch(cleanQuery, isTv: !isTv, language: searchLanguage);
        }
      }

      // Tente 4: Fallback Langue Ultime
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

  /// Recherche atomique avec paramètres optionnels
  Future<Map<String, dynamic>?> _performSearch(String query, {
    required bool isTv,
    required String language,
    String? year // 📅 Nouveau paramètre
  }) async {
    try {
      final endpoint = isTv ? '/search/tv' : '/search/movie';

      // Construction des paramètres
      final params = <String, dynamic>{
        'query': query,
        'language': language,
      };

      // Ajout de l'année si présente
      if (year != null) {
        if (isTv) {
          // Pour les séries, c'est la date de première diffusion
          params['first_air_date_year'] = year;
        } else {
          // Pour les films
          params['year'] = year; // Filtre strict
          // params['primary_release_year'] = year; // Alternative si 'year' est trop strict
        }
      }

      final response = await _dio!.get(endpoint, queryParameters: params);

      if (response.statusCode == 200 && response.data['results'].isNotEmpty) {
        final item = response.data['results'][0];
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
