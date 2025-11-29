import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'tmdb_api_service.dart';
import '../models/media_model.dart';

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

  /// 🧹 Nettoyeur de nom de fichier
  String _cleanQuery(String rawName) {
    // 1. Normalisation des séparateurs
    String clean = rawName.replaceAll(RegExp(r'(\.|_|\(|\)|\[|\]|-)', caseSensitive: false), ' ').trim();

    // 2. Liste des parasites à éliminer (Qualités + LANGUES + Codecs)
    // Ajout de VOST, VOSTFR, VF, TRUEFRENCH, MULTI pour qu'ils ne polluent pas le titre
    final regexExclusion = RegExp(
      r'\b(S\d{2}E\d{2}|1080p|720p|4k|2160p|HDR|H\.264|x264|x265|HEVC|mkv|mp4|avi|webrip|bluray|dvdrip|VOSTFR|VOST|VF|VFF|TRUEFRENCH|MULTI|ENGLISH|FRENCH)\b',
      caseSensitive: false,
    );

    // On coupe la chaîne dès qu'on rencontre un de ces tags
    // Ex: "The.Movie.VOSTFR.1080p" -> "The Movie"
    if (regexExclusion.hasMatch(clean)) {
      clean = clean.split(regexExclusion).first.trim();
    }

    // 3. 🎯 Suppression Chirurgicale de l'année à la fin
    // Ex: "Joker 2019" -> "Joker"
    // On cible 4 chiffres entre 1900 et 2099 à la fin de la string
    final regexYear = RegExp(r'\s+(19|20)\d{2}\s*$', caseSensitive: false);
    clean = clean.replaceAll(regexYear, '').trim();

    // Nettoyage final des espaces
    return clean.replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<void> reinitialize() async => await _init();

  Future<bool> _init() async {
    final String? storedToken = await TmdbApiService.getApiKey();

    if (storedToken == null || storedToken.isEmpty) {
      if (_dio != null) {
        _dio = null;
        _bearerToken = null;
      }
      return false;
    }

    if (_bearerToken == storedToken && _dio != null) return true;

    _bearerToken = storedToken;
    _dio = Dio(
      BaseOptions(
        baseUrl: 'https://api.themoviedb.org/3',
        // Langue par défaut (sera surchargée dynamiquement si besoin)
        queryParameters: {'language': 'fr-FR', 'include_adult': 'false'},
        headers: {
          'Authorization': 'Bearer $_bearerToken',
          'accept': 'application/json',
        },
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    debugPrint("✅ TMDb: Service prêt.");
    return true;
  }

  /// 🧠 SMART SEARCH : Analyse VOST + Fallback Type
  Future<Media?> getFullDetails(String rawQuery, {required bool isTv}) async {
    if (!await _init()) return null;

    // 1. DÉTECTION DE LA LANGUE CIBLE 🕵️‍♂️
    // Si le titre brut contient des indices VO/Anglais, on cherche en anglais pour maximiser le match.
    final bool appearsEnglish = RegExp(r'\b(VO|VOST|VOSTFR|ENGLISH)\b', caseSensitive: false).hasMatch(rawQuery);
    final String searchLanguage = appearsEnglish ? 'en-US' : 'fr-FR';

    // 2. NETTOYAGE
    final cleanQuery = _cleanQuery(rawQuery);
    debugPrint("🔍 Scan TMDB (Lang: $searchLanguage) pour : '$cleanQuery' (Brut: '$rawQuery')");

    try {
      // 3. TENTATIVE PRINCIPALE
      var result = await _performSearch(cleanQuery, isTv: isTv, language: searchLanguage);

      // 4. FALLBACK TYPE (Si échec, on tente l'autre type)
      if (result == null) {
        debugPrint("⚠️ Bascule automatique de type vers ${!isTv ? 'TV' : 'Film'}...");
        result = await _performSearch(cleanQuery, isTv: !isTv, language: searchLanguage);
      }

      // 5. FALLBACK LANGUE (Si échec en anglais, on tente quand même en français ou inversement)
      if (result == null && appearsEnglish) {
        debugPrint("⚠️ Échec en mode VO ($searchLanguage). Tentative de repli en fr-FR...");
        result = await _performSearch(cleanQuery, isTv: isTv, language: 'fr-FR');
      }

      if (result == null) {
        debugPrint("❌ ECHEC TOTAL : Aucun signal pour '$cleanQuery'.");
        return null;
      }

      // --- RÉCUPÉRATION DES DÉTAILS ---
      final int id = result['id'];
      final bool foundAsTv = result['media_type'] == 'tv';

      debugPrint("🎯 Cible verrouillée : ID $id. Téléchargement détails...");

      final detailEndpoint = foundAsTv ? '/tv/$id' : '/movie/$id';

      // ⚠️ IMPORTANT : Pour les DETAILS, on veut toujours essayer de les avoir en Français
      // pour le synopsis, même si on a trouvé le film via son titre anglais.
      // On force donc 'fr-FR' pour le fetch final, sauf si l'utilisateur préfère tout en anglais (à voir).
      // Ici, je remets fr-FR pour avoir le synopsis en français.
      final detailResponse = await _dio!.get(
          detailEndpoint,
          queryParameters: {'language': 'fr-FR'}
      );

      return Media.fromJson(detailResponse.data);

    } on DioException catch (e) {
      debugPrint("❌ ERREUR DIO : ${e.message}");
      return null;
    } catch (e) {
      debugPrint("❌ Glitch système TMDB : $e");
      return null;
    }
  }

  /// Méthode interne de recherche avec paramètre de langue
  Future<Map<String, dynamic>?> _performSearch(String query, {required bool isTv, required String language}) async {
    try {
      final endpoint = isTv ? '/search/tv' : '/search/movie';
      // On surcharge le paramètre 'language' des BaseOptions pour cette requête spécifique
      final response = await _dio!.get(
          endpoint,
          queryParameters: {
            'query': query,
            'language': language
          }
      );

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
