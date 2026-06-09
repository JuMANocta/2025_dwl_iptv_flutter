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
    // §iptvUaCompat — Profil de requête piloté par `allowInvalidCertificate` :
    //   - `true`  = appel vers serveur IPTV utilisateur → User-Agent
    //               **IPTVSmartersPro** (whitelisté par les panels Xtream qui
    //               renvoient 500 silencieux aux UAs non IPTV connus),
    //               pas de Referer/Origin (anti-embed), Accept-Encoding gzip.
    //   - `false` = appel vers une API publique (TMDB, GitHub, XMLTV…) →
    //               UA navigateur Chrome standard + Referer/Origin classiques.
    // Découvert via capture PCAP de ZenIPTV : sans `IPTVSmartersPro`, les
    // panels ouèrent `get.php` en mode dégradé → PHP timeout 30s → 500 vide.
    final isIptvProfile = allowInvalidCertificate;
    // §iptvUaCompat — Headers MINIMAUX pour le profil IPTV : on copie pile poil
    // ce que ZenIPTV envoie (vu dans le PCAP). Pas de `Connection: keep-alive`
    // (Dart HTTP/1.1 gère ça implicitement, et certains panels rejettent les
    // requêtes qui en ont un explicite — c'est leur heuristique pour distinguer
    // les "vrais clients IPTV" des "scrapers/curl/wget").
    final Map<String, dynamic> headers = isIptvProfile
        ? {
            'User-Agent': 'IPTVSmartersPro',
            'Accept': '*/*',
            'Accept-Encoding': 'gzip',
          }
        : {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
            'Accept': '*/*',
            'Connection': 'keep-alive',
            'Referer': referer,
            'Origin': origin,
          };
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 10),
        sendTimeout: const Duration(minutes: 2),
        headers: headers,
        // Valide les statuts HTTP qui ne sont pas des erreurs serveur graves (5xx)
        validateStatus: (s) => s != null && s < 500,
      ),
    );

    if (allowInvalidCertificate) {
      // ⚠️ Bypass certificat SSL : strictement réservé aux providers IPTV
      // utilisateur (souvent self-signed). Ne PAS étendre aux APIs publiques.
      // §iptvUaCompat — On force aussi le `userAgent` au niveau du HttpClient :
      // sans ça Dart ajoute "Dart/3.x (dart:io)" par défaut, ce qui peut être
      // détecté côté serveur en plus de notre UA dans les headers.
      (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        client.userAgent = 'IPTVSmartersPro';
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
    // §iptvUaCompat — `allowInvalidCertificate: true` active le profil "IPTV"
    // dans buildBaseDio : UA `IPTVSmartersPro` + Accept-Encoding gzip,
    // sans Referer/Origin. Le profil est appliqué à TOUTES les requêtes IPTV
    // (téléchargement playlist, médias, player_api.php, replay…).
    final dio = buildBaseDio(allowInvalidCertificate: true);

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
