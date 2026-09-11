import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'secure_storage_compte.dart';
import '../../data/services/stream_account_service.dart';
import '../../data/models/stream_account.dart';


/// Classe utilitaire pour la configuration réseau centralisée.
/// Elle fournit des instances de Dio préconfigurées.
///
/// **Sécurité SSL** : par défaut Dio refuse les certificats invalides.
/// Le contournement SSL n'est activé QUE pour les requêtes vers les
/// serveurs IPTV de l'utilisateur (via [buildDio] ou [buildIptvBaseDio]).
///
/// Les requêtes vers TMDB, GitHub, XMLTV, etc. ne passent **jamais** par
/// cette classe : elles ont leur propre Dio, certificats vérifiés (ignorer
/// un certificat valide ouvrirait la porte à du MITM).
class NetworkUtils {

  /// Construit le Dio de base d'un **serveur IPTV de l'utilisateur** : profil
  /// de requête §iptvUaCompat ET contournement du certificat TLS.
  ///
  /// Revue 2026-09-11, D1B-21 — S'appelait `buildBaseDio({referer, origin,
  /// allowInvalidCertificate = false})` : le MÊME booléen pilotait le
  /// contournement TLS et le profil d'en-têtes, et sa branche `false` (UA
  /// Chrome figé + Referer/Origin) n'avait aucun appelant — les deux appels
  /// passaient `true`. Branche et paramètres retirés, nom explicite.
  /// ⛔ Ne jamais l'utiliser pour une API publique : le certificat n'y est
  /// pas vérifié.
  static Dio buildIptvBaseDio() {
    // §iptvUaCompat — User-Agent **IPTVSmartersPro** (whitelisté par les
    // panels Xtream qui renvoient 500 silencieux aux UAs non IPTV connus),
    // pas de Referer/Origin (anti-embed), Accept-Encoding gzip.
    // Découvert via capture PCAP de ZenIPTV : sans `IPTVSmartersPro`, les
    // panels ouèrent `get.php` en mode dégradé → PHP timeout 30s → 500 vide.
    // §iptvUaCompat — Headers MINIMAUX : on copie pile poil ce que ZenIPTV
    // envoie (vu dans le PCAP). Pas de `Connection: keep-alive` (Dart
    // HTTP/1.1 gère ça implicitement, et certains panels rejettent les
    // requêtes qui en ont un explicite — c'est leur heuristique pour
    // distinguer les "vrais clients IPTV" des "scrapers/curl/wget").
    final Map<String, dynamic> headers = {
      'User-Agent': 'IPTVSmartersPro',
      'Accept': '*/*',
      'Accept-Encoding': 'gzip',
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

    return dio;
  }


  /// Construit une instance de Dio **spécifiquement pour les serveurs IPTV
  /// utilisateur** (téléchargements playlist, médias, API Xtream).
  ///
  /// Active automatiquement le bypass SSL — les serveurs IPTV grand public
  /// utilisent fréquemment des certificats self-signed ou expirés.
  /// §cookieScope — [account] : le compte AU NOM DUQUEL la requête part.
  ///
  /// ⚠️ **Le passer dès qu'on le connaît.** Sans lui, cette méthode retombe sur
  /// `getCurrentAccount()` — c'est-à-dire qu'elle envoyait les cookies du
  /// compte PRINCIPAL avec les requêtes d'un compte SECONDAIRE. Sur un panel
  /// qui lie la session au cookie, cela produit exactement le tableau observé
  /// le 2026-09-03 : un compte se charge, les autres reçoivent des réponses
  /// vides — et une réponse vide est indiscernable d'un catalogue vide
  /// (§catalogTruth). Le paramètre `url` n'était d'ailleurs **jamais lu**.
  static Future<Dio> buildDio(String url, {StreamAccount? account}) async {
    // §iptvUaCompat — profil "IPTV" de buildIptvBaseDio : UA `IPTVSmartersPro`
    // + Accept-Encoding gzip, sans Referer/Origin. Le profil est appliqué à
    // TOUTES les requêtes IPTV (téléchargement playlist, médias,
    // player_api.php, replay…).
    final dio = buildIptvBaseDio();

    // Le compte explicite gagne toujours ; le repli sur le compte courant n'est
    // là que pour les chemins qui ne savent pas de quel compte ils dépendent
    // (téléchargement d'un média depuis une URL nue).
    final acc = account ?? await StreamAccountService.getCurrentAccount();
    final legacy = await SecureStorageService().getCredentials();
    final cookies = cookiesFor(acc, legacy);

    // On ajoute les cookies uniquement s'ils existent
    if (cookies.isNotEmpty) {
      dio.options.headers['Cookie'] = cookies;
    }

    return dio;
  }

  /// §cookieScope — Choix des cookies à envoyer, extrait pour être testable
  /// sans appareil. Rend `''` quand il n'y en a pas.
  ///
  /// Revue 2026-09-11, D1B-10 — Un compte connu envoie SES cookies, et rien
  /// d'autre : le repli sur le stockage legacy mono-compte ne vaut plus que
  /// SANS compte du tout (installation d'avant la migration). Avant, tout
  /// compte sans cookies recevait ceux du legacy — c'est-à-dire la session du
  /// panel de l'ère mono-compte envoyée à un AUTRE fournisseur, exactement la
  /// fuite que §cookieScope voulait fermer (la migration copie déjà ces
  /// cookies dans le compte migré, qui n'y perd rien).
  /// Testé : `test/cookie_scope_test.dart`.
  static String cookiesFor(StreamAccount? account, Map<String, dynamic> legacy) {
    if (account != null) return (account.cookies ?? '').trim();
    return (legacy['cookies'] ?? '').toString().trim();
  }
}
