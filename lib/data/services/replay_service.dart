import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart'; // Import pour debugPrint
import 'package:aetherStream/core/utils/host_gate.dart';
import 'package:aetherStream/core/utils/log_sanitizer.dart';
import 'package:aetherStream/core/utils/network.dart';
import 'package:aetherStream/core/utils/formatters.dart';
import 'package:aetherStream/l10n/l10n_ext.dart';
import 'stream_account_service.dart';
import '../models/stream_account.dart';

/// Identifiants Xtream du replay (serveur + user + pass).
///
/// §tourFix — revue 2026-09-11, D1B-24 — S'appelait `XtreamCredentials`,
/// comme la classe de `stream_account.dart`, avec SES PROPRES règles
/// d'extraction : préfixe sensible à la casse (`/LIVE/` raté), aucune garde
/// anti-point (une URL de CDN `/a.b/c/d.m3u8` donnait des « identifiants »
/// `a.b` / `c`, et `get_short_epg` partait vers ce serveur-là). Renommée, et
/// [fromStreamUrl] passe désormais par `XtreamCredentials.tryExtract` — la
/// seule règle, celle que `redactUrl` sait masquer.
class ReplayCredentials {
  final String server; // https://host:port
  final String username;
  final String password;

  ReplayCredentials({required this.server, required this.username, required this.password});

  String get playerApiBase => '$server/player_api.php';

  Uri buildPlayerApiUri(Map<String, String> params) {
    final qp = <String, String>{
      'username': username,
      'password': password,
      ...params,
    };
    return Uri.parse(playerApiBase).replace(queryParameters: qp);
  }

  /// Format path-based Xtream Codes (le plus compatible).
  /// http://server/timeshift/{user}/{pass}/{duration_min}/{YYYY-MM-DD:HH-mm}/{stream_id}.{ext}
  /// [ext] : extension du stream original (.m3u8 ou .ts) — certains serveurs ne supportent
  /// le timeshift que dans un seul format, on réutilise donc l'extension du flux live.
  String buildTimeshiftPathUrl({
    required int streamId,
    required String startFormatted, // "YYYY-MM-DD:HH-mm" heure locale
    required int durationMinutes,
    String ext = 'm3u8',
  }) =>
      '$server/timeshift/$username/$password/$durationMinutes/$startFormatted/$streamId.$ext';

  static ReplayCredentials? fromAccount(StreamAccount? acc) {
    if (acc == null || acc.baseUrl == null || acc.username == null || acc.password == null) return null;
    final uri = Uri.parse(acc.baseUrl!);
    final server = uri.hasPort && uri.port != 0 ? '${uri.scheme}://${uri.host}:${uri.port}' : '${uri.scheme}://${uri.host}';
    return ReplayCredentials(server: server, username: acc.username!, password: acc.password!);
  }

  /// Identifiants lus dans l'URL du flux (query `username`/`password`, ou
  /// chemin Xtream), par la règle UNIQUE de `XtreamCredentials.tryExtract`.
  static ReplayCredentials? fromStreamUrl(String url) {
    final creds = XtreamCredentials.tryExtract(url);
    if (creds == null) return null;
    return ReplayCredentials(
        server: creds.host, username: creds.username, password: creds.password);
  }
}

/// Option de stream disponible pour le replay (qualité / URL).
/// Utilisé pour passer les flux à [ReplayDatePickerSheet] sans dépendre de M3uEntry.
class ReplayStreamOption {
  final String label;       // ex: "FHD", "HD", "4K", "Flux 1"
  final int streamId;
  final String streamUrl;
  final String? catchupSource;
  final int? catchupDays;

  const ReplayStreamOption({
    required this.label,
    required this.streamId,
    required this.streamUrl,
    this.catchupSource,
    this.catchupDays,
  });
}

class ReplayProgram {
  final String title;
  final DateTime start;
  final DateTime end;
  final String description;
  /// Indique si ce programme est disponible en replay côté serveur.
  final bool hasArchive;
  /// Stream sélectionné dans le picker (override de l'entrée par défaut).
  final int? selectedStreamId;
  final String? selectedStreamUrl;
  final String? selectedCatchupSource;

  ReplayProgram({
    required this.title,
    required this.start,
    required this.end,
    required this.description,
    this.hasArchive = false,
    this.selectedStreamId,
    this.selectedStreamUrl,
    this.selectedCatchupSource,
  });

  /// Revue 2026-09-11, D1B-19 — jour et mois dans l'ORDRE de la langue de
  /// l'écran (« 11/09 » en français, « 9/11 » en anglais) ; `dd/MM` était
  /// figé dans l'ordre français.
  String get startLabel =>
      DateFormat.Md(L10n.current.localeName).add_Hm().format(start);
  String get durationLabel => formatShortDuration(end.difference(start));
}

class ReplayService {
  /// §iptvUaCompat — revue 2026-09-11, D1B-06 / D5A-03 — Borne de la requête
  /// `get_short_epg` : l'ancien `http.get` n'en avait aucune (feuille Replay
  /// qui tourne sans fin face à un panel muet).
  static const Duration epgReceiveTimeout = Duration(seconds: 15);
  static const Duration epgConnectTimeout = Duration(seconds: 10);

  /// Attente maximale dans la file §hostGate : un rafraîchissement de liste
  /// peut occuper le panel des minutes, la feuille ne l'attend pas.
  static const Duration epgQueueTimeout = Duration(seconds: 20);

  Future<ReplayCredentials?> _resolveCreds({String? streamUrl}) async {
    // Priorité 1 : l'URL du stream — elle contient le BON serveur pour cette qualité.
    // Les variants FHD/4K peuvent être servis par un serveur différent du compte principal.
    // Utiliser le compte en priorité enverrait le timeshift au mauvais serveur.
    if (streamUrl != null) {
      final fromStream = ReplayCredentials.fromStreamUrl(streamUrl);
      if (fromStream != null) {
        debugPrint('🔑 ReplayService: Crédentiels résolus depuis l\'URL du stream → serveur: ${redactServer(fromStream.server)}');
        return fromStream;
      }
    }
    // Priorité 2 : compte courant (fallback si l'URL ne contient pas de crédentiels lisibles).
    final acc = await StreamAccountService.getCurrentAccount();
    final fromAcc = ReplayCredentials.fromAccount(acc);
    if (fromAcc != null) {
      debugPrint('🔑 ReplayService: Crédentiels résolus depuis le compte courant → serveur: ${redactServer(fromAcc.server)}');
      return fromAcc;
    }
    debugPrint('❌ ReplayService: Aucuns crédentiels Xtream trouvés.');
    return null;
  }

  /// Récupère un EPG court pour un stream (si le serveur le supporte).
  Future<List<ReplayProgram>> fetchShortEpg(int streamId, {int limit = 50, String? streamUrl}) async {
    debugPrint('📡 ReplayService: Récupération EPG — streamId: $streamId, limit: $limit');
    final creds = await _resolveCreds(streamUrl: streamUrl);
    if (creds == null) {
      debugPrint('⛔ ReplayService: fetchShortEpg annulé, pas de crédentiels.');
      return [];
    }

    final uri = creds.buildPlayerApiUri({
      'action': 'get_short_epg',
      'stream_id': streamId.toString(),
      'limit': limit.toString(),
    });

    debugPrint('🌐 ReplayService: Appel → ${redactUrl(uri.toString())}');
    final ({int? status, String body}) response = await _getEpg(uri);
    debugPrint('📨 ReplayService: Réponse HTTP ${response.status}');

    if (response.status != 200) {
      debugPrint('❌ ReplayService: Échec HTTP statut ${response.status}');
      return [];
    }

    try {
      final data = jsonDecode(response.body);
      if (data is! Map || data['epg_listings'] is! List) {
        debugPrint('⚠️ ReplayService: Réponse inattendue ou "epg_listings" manquant. Corps: ${response.body.substring(0, response.body.length.clamp(0, 200))}');
        return [];
      }

      final list = data['epg_listings'] as List<dynamic>;
      debugPrint('✅ ReplayService: ${list.length} programmes EPG trouvés.');
      return list.map<ReplayProgram>((item) {
        // Xtream Codes encode les champs texte en Base64
        final title = _decodeBase64Field(item['title']);
        final desc = _decodeBase64Field(item['description']);

        // Priorité aux timestamps Unix entiers (start_timestamp / stop_timestamp)
        // Fallback sur le parsing de la string datetime "2024-01-15 20:00:00"
        final startTs = item['start_timestamp'];
        final stopTs = item['stop_timestamp'];
        final start = startTs is int && startTs > 0
            ? DateTime.fromMillisecondsSinceEpoch(startTs * 1000, isUtc: true).toLocal()
            : _parseDateTimeString(item['start']?.toString());
        final end = stopTs is int && stopTs > 0
            ? DateTime.fromMillisecondsSinceEpoch(stopTs * 1000, isUtc: true).toLocal()
            : _parseDateTimeString(item['end']?.toString());

        if (start == null || end == null) {
          debugPrint('⚠️ ReplayService: Timestamps invalides pour "$title". start=${item['start']}, end=${item['end']}');
        }

        // has_archive: 1 = replay disponible côté serveur pour ce programme
        final hasArchive = (item['has_archive'] == 1 || item['has_archive'] == '1' || item['has_archive'] == true);
        debugPrint('📋 EPG | "$title" | ${start != null ? DateFormat('dd/MM HH:mm').format(start) : '?'} | archive=$hasArchive');

        return ReplayProgram(
          title: title,
          start: start ?? DateTime.now(),
          end: end ?? DateTime.now().add(const Duration(hours: 1)),
          description: desc,
          hasArchive: hasArchive,
        );
      }).toList();
    } catch (e) {
      debugPrint('💀 ReplayService: Erreur parsing EPG: $e');
      return [];
    }
  }

  /// §iptvUaCompat + §hostGate + §cookieScope — revue 2026-09-11, D1B-06 /
  /// D5A-03 — La requête `get_short_epg`, par la pile réseau IPTV.
  ///
  /// **Le défaut réparé.** C'était le SEUL appel au panel fait par un
  /// `package:http` nu : ni l'UA `IPTVSmartersPro` (un panel qui filtre l'UA
  /// répond 500 → feuille « vide » sans un mot), ni la tolérance de
  /// certificat (panel auto-signé → `HandshakeException` alors que le direct
  /// marche), ni les cookies du compte, ni délai (serveur muet → la feuille
  /// tourne à vie), ni la file par hôte. Tout le reste de l'app passe par
  /// `NetworkUtils.buildDio` ; `buildDio` le disait lui-même (« replay… »).
  ///
  /// Même comportement que l'ancien appel pour l'appelant : un statut ≠ 200
  /// rend une liste vide, une panne réseau lève (la feuille affiche « guide
  /// indisponible » par `describeError`) — mais en temps borné.
  /// ⚠️ Le `Dio` est fermé AVANT de rendre le jeton de la file, comme
  /// `XtreamApiService._fetch` : sinon le socket keep-alive compterait encore
  /// comme une connexion côté panel.
  Future<({int? status, String body})> _getEpg(Uri uri) async {
    final String url = uri.toString();
    try {
      return await HostGate.run(url, () async {
        final Dio dio = await NetworkUtils.buildDio(url);
        dio.options.connectTimeout = epgConnectTimeout;
        try {
          final Response<String> r = await dio.getUri<String>(
            uri,
            options: Options(
              responseType: ResponseType.plain,
              receiveTimeout: epgReceiveTimeout,
              // Tout statut est LU (l'ancien `http.get` ne levait sur aucun) :
              // l'appelant garde sa règle « ≠ 200 → liste vide ».
              validateStatus: (int? s) => s != null,
            ),
          );
          return (status: r.statusCode, body: r.data ?? '');
        } finally {
          dio.close(force: true);
        }
      }, timeout: epgQueueTimeout);
    } on HostGateTimeoutException {
      // `toString()` porte l'hôte : jamais à l'écran. Une attente trop longue
      // se dit comme un délai dépassé (`describeError` → errTimeout).
      throw TimeoutException(null, epgQueueTimeout);
    }
  }

  /// Construit une URL timeshift pour un programme donné.
  ///
  /// Supporte deux formats selon le [catchupSource] M3U :
  ///
  /// 1. **Mode append / Flussonic** — si [catchupSource] contient `{utc}` ou `{lutc}` :
  ///    Le template est appliqué directement sur l'URL du stream (UTC timestamps en secondes).
  ///    Ex : `catchup-source="?utc={utc}&lutc={lutc}"` → stream_url + "?utc=1234&lutc=1294"
  ///
  /// 2. **Mode Xtream Codes path-based** (par défaut) :
  ///    `{server}/timeshift/{user}/{pass}/{duration_min}/{YYYY-MM-DD:HH-mm}/{stream_id}.m3u8`
  ///    Utilise l'heure **locale** (pas UTC) — la grande majorité des serveurs IPTV
  ///    régionaux configurés en CET/CEST interprètent le timestamp en heure locale.
  Future<String?> buildTimeshiftUrl({
    required int streamId,
    required DateTime start,
    required DateTime end,
    String? streamUrl,
    String? catchupSource,
  }) async {
    final durationMinutes = end.difference(start).inMinutes;

    // --- Mode append (Flussonic / Wowza / catchup-source template) ---
    if (catchupSource != null &&
        (catchupSource.contains('{utc}') || catchupSource.contains('{lutc}'))) {
      if (streamUrl == null) {
        debugPrint('❌ ReplayService: buildTimeshiftUrl append — streamUrl requis.');
        return null;
      }
      final utcTs = (start.toUtc().millisecondsSinceEpoch ~/ 1000).toString();
      final lutcTs = (end.toUtc().millisecondsSinceEpoch ~/ 1000).toString();
      final appendedUrl = streamUrl +
          catchupSource
              .replaceAll('{utc}', utcTs)
              .replaceAll('{lutc}', lutcTs)
              .replaceAll('{duration}', durationMinutes.toString());
      debugPrint('⏪ ReplayService (append): utc=$utcTs, lutc=$lutcTs, durée=${durationMinutes}min → ${redactUrl(appendedUrl)}');
      return appendedUrl;
    }

    // --- Mode Xtream Codes path-based ---
    final creds = await _resolveCreds(streamUrl: streamUrl);
    if (creds == null) {
      debugPrint('❌ ReplayService: buildTimeshiftUrl — pas de crédentiels Xtream.');
      return null;
    }

    // Utilisation de l'heure LOCALE (pas UTC).
    // Les serveurs IPTV régionaux (CET/CEST) interprètent le timestamp en heure locale :
    // envoyer UTC provoquerait un décalage de +1h/+2h selon la saison.
    final startFormatted = DateFormat('yyyy-MM-dd:HH-mm').format(start);

    // .ts en priorité : plus compatible avec les serveurs Xtream (FHD/4K notamment).
    // Si le serveur ne supporte pas .ts, le retry dans PlayerPage bascule sur .m3u8.
    final url = creds.buildTimeshiftPathUrl(
      streamId: streamId,
      startFormatted: startFormatted,
      durationMinutes: durationMinutes,
      ext: 'ts',
    );
    debugPrint('⏪ ReplayService (xtream): start=$startFormatted, durée=${durationMinutes}min → ${redactUrl(url)}');
    return url;
  }

  /// Décode un champ Base64 Xtream Codes (titre, description).
  /// Retourne la valeur brute si le décodage échoue (compatibilité).
  static String _decodeBase64Field(dynamic value) {
    if (value == null) return '';
    try {
      return utf8.decode(base64.decode(value.toString()));
    } catch (_) {
      return value.toString();
    }
  }

  /// Parse une string datetime Xtream Codes ("2024-01-15 20:00:00") en DateTime local.
  static DateTime? _parseDateTimeString(String? s) {
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s)?.toLocal();
  }

  // Revue 2026-09-11, D5L-02 / D1B-20 — `hasReplay` (détection de replay par
  // `get_short_epg`) n'avait aucun appelant : retirée. Une détection future
  // devra repasser par le client IPTV corrigé (D5A-03), pas la ressusciter.
}
