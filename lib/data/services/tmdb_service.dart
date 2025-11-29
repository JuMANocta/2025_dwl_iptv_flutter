import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'tmdb_api_service.dart';
import '../models/media_model.dart'; // Import du modèle Media

class TmdbService {
  Dio? _dio;
  String? _bearerToken;

  // --- Singleton Core ---
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

  String _cleanQuery(String rawName) {
    String clean = rawName.replaceAll(RegExp(r'(\.|_|\(|\)|\[|\])'), ' ').trim();
    final regexTags = RegExp(
      r'(1080p|720p|4k|HDR|H\.264|x264|mkv|mp4|avi|webrip|bluray|dvdrip|S\d{2}E\d{2})',
      caseSensitive: false,
    );
    clean = clean.replaceAll(regexTags, ' ').trim();
    final regexYear = RegExp(r'\s+\d{4}\s*$', caseSensitive: false);
    clean = clean.replaceAll(regexYear, '').trim();
    return clean.replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<void> reinitialize() async => await _init();

  Future<bool> _init() async {
    final String? storedToken = await TmdbApiService.getApiKey();

    if (storedToken == null || storedToken.isEmpty) {
      if (_dio != null) {
        debugPrint("ℹ️ TMDb: Jeton absent. Service désactivé.");
        _dio = null;
        _bearerToken = null;
      } else {
        debugPrint("❌ ERREUR TMDb: Jeton d'accès NUL ou VIDE.");
        debugPrint("💡 NOTE: Le service reste inactif jusqu'à la sauvegarde de la clé.");
      }
      return false;
    }

    if (_bearerToken == storedToken && _dio != null) {
      debugPrint("✅ TMDb: Configuration existante, passe.");
      return true;
    }

    // (Re)configuration complète de Dio
    debugPrint("🔧 TMDb: Jeton trouvé. Configuration du client Dio...");
    _bearerToken = storedToken;
    _dio = Dio(
      BaseOptions(
        baseUrl: 'https://api.themoviedb.org/3',
        queryParameters: {'language': 'fr-FR', 'include_adult': 'false'},
        headers: {
          'Authorization': 'Bearer $_bearerToken', // Utilisation du Bearer Token
          'accept': 'application/json',
        },
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 10), // Temps d'attente pour la réponse
      ),
    );
    debugPrint("✅ TMDb: Service configuré pour utiliser le Bearer Token.");
    return true;
  }

  /// 🧠 Le Cerveau : Recherche ID -> Récupère Détails complets et harmonisés.
  /// Retourne un objet Media directement.
  Future<Media?> getFullDetails(String rawQuery, {required bool isTv}) async {
    if (!await _init()) return null;

    final cleanQuery = _cleanQuery(rawQuery);
    debugPrint("🔍 Scan TMDB pour : '$cleanQuery'");

    try {
      // 1. Recherche initiale (pour trouver l'ID)
      final searchEndpoint = isTv ? '/search/tv' : '/search/movie';
      final searchResponse = await _dio!.get(searchEndpoint, queryParameters: {'query': cleanQuery});

      if (searchResponse.data['results'].isEmpty) {
        debugPrint("⚠️ Aucun signal trouvé pour '$cleanQuery'.");
        return null;
      }

      final firstResult = searchResponse.data['results'][0];
      final int id = firstResult['id'];

      debugPrint("🎯 Cible verrouillée. ID trouvé: $id. Téléchargement des détails...");

      // 2. Récupération des détails via ID (pour les infos complètes)
      final detailEndpoint = isTv ? '/tv/$id' : '/movie/$id';
      final detailResponse = await _dio!.get(detailEndpoint);

      // 3. Sérialisation 🎯
      final Map<String, dynamic> json = detailResponse.data as Map<String, dynamic>;

      debugPrint("🎉 Détails téléchargés et convertis avec succès !");
      return Media.fromJson(json); // <-- Retourne l'objet Media

    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final responseData = e.response?.data;
      debugPrint("❌ ERREUR DIO (Détails) : Status $statusCode. Data: $responseData. Message: ${e.message}");
      return null;
    } catch (e) {
      debugPrint("❌ Glitch système TMDB : $e");
      return null;
    }
  }

  static String? getPosterUrl(String? path, {String size = 'w500'}) {
    if (path == null || path.isEmpty) return null;
    return 'https://image.tmdb.org/t/p/$size$path';
  }
}
