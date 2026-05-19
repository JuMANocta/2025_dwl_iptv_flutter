import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'secure_storage_compte.dart';
import '../../data/services/stream_account_service.dart';


/// Classe utilitaire pour la configuration réseau centralisée.
/// Elle fournit des instances de Dio préconfigurées.
///
/// **Sécurité SSL** : par défaut Dio refuse les certificats invalides.
/// Le contournement SSL n'est activé QUE pour les requêtes vers les
/// serveurs IPTV de l'utilisateur (via [buildDio] ou en passant
/// `allowInvalidCertificate: true` à [buildBaseDio]).
///
/// Les requêtes vers TMDB, GitHub, XMLTV, etc. ne doivent **jamais** activer
/// cette option : leurs certificats sont valides et les ignorer ouvrirait
/// la porte à du MITM.
class NetworkUtils {

  /// Construit une instance de Dio avec une configuration de base (User-Agent, etc.).
  ///
  /// [allowInvalidCertificate] : si `true`, accepte n'importe quel certificat
  /// SSL. À n'utiliser QUE pour les serveurs IPTV mal configurés. Défaut `false`.
  static Dio buildBaseDio({
    String? referer,
    String? origin,
    bool allowInvalidCertificate = false,
  }) {
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

    if (allowInvalidCertificate) {
      // ⚠️ Bypass certificat SSL : strictement réservé aux providers IPTV
      // utilisateur (souvent self-signed). Ne PAS étendre aux APIs publiques.
      (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
        return client;
      };
    }

    return dio;
  }


  /// Construit une instance de Dio **spécifiquement pour les serveurs IPTV
  /// utilisateur** (téléchargements playlist, médias, API Xtream).
  ///
  /// Active automatiquement le bypass SSL — les serveurs IPTV grand public
  /// utilisent fréquemment des certificats self-signed ou expirés.
  static Future<Dio> buildDio(String url) async {
    final uri = Uri.parse(url);
    final referer = "${uri.scheme}://${uri.host}/";
    final origin = "${uri.scheme}://${uri.host}";

    // On commence avec une instance de Dio de base
    final dio = buildBaseDio(referer: referer, origin: origin, allowInvalidCertificate: true);

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
