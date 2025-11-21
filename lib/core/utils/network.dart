import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'secure_storage_compte.dart';
import '../../data/services/stream_account_service.dart';


/// Classe utilitaire pour la configuration réseau centralisée.
/// Elle fournit des instances de Dio préconfigurées.
class NetworkUtils {

  /// Construit une instance de Dio avec une configuration de base (User-Agent, etc.).
  /// C'est la méthode à utiliser pour les requêtes génériques.
  static Dio buildBaseDio({String? referer, String? origin}) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 10),
        sendTimeout: const Duration(minutes: 2),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
          'Accept': '*/*',
          'Connection': 'keep-alive',
          'Referer': referer,
          'Origin': origin,
        },
        // Valide les statuts HTTP qui ne sont pas des erreurs serveur graves (5xx)
        validateStatus: (s) => s != null && s < 500,
      ),
    );

    // Permet d'ignorer les erreurs de certificat SSL (utile pour certaines sources IPTV)
    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
      return client;
    };

    return dio;
  }


  /// Construit une instance de Dio **spécifiquement pour les téléchargements**.
  /// Elle enrichit la configuration de base avec les cookies et les en-têtes
  static Future<Dio> buildDio(String url) async {
    final uri = Uri.parse(url);
    final referer = "${uri.scheme}://${uri.host}/";
    final origin = "${uri.scheme}://${uri.host}";

    // On commence avec une instance de Dio de base
    final dio = buildBaseDio(referer: referer, origin: origin);

    // On récupère les informations du compte pour enrichir la requête
    final acc = await StreamAccountService.getCurrentAccount();
    final legacy = await SecureStorageService().getCredentials();
    final cookies = (acc?.cookies?.trim().isNotEmpty == true)
        ? acc!.cookies!.trim()
        : (legacy["cookies"] ?? "").toString().trim();

    // On ajoute les cookies uniquement s'ils existent
    if (cookies.isNotEmpty) {
      dio.options.headers['Cookie'] = cookies;
    }

    return dio;
  }
}
