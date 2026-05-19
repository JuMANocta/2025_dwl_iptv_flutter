import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart'; // Import pour debugPrint
import 'package:aetherStream/core/utils/log_sanitizer.dart';
import 'stream_account_service.dart';
import '../models/stream_account.dart';

class XtreamCredentials {
  final String server; // https://host:port
  final String username;
  final String password;

  XtreamCredentials({required this.server, required this.username, required this.password});

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

  static XtreamCredentials? fromAccount(StreamAccount? acc) {
    if (acc == null || acc.baseUrl == null || acc.username == null || acc.password == null) return null;
    final uri = Uri.parse(acc.baseUrl!);
    final server = uri.hasPort && uri.port != 0 ? '${uri.scheme}://${uri.host}:${uri.port}' : '${uri.scheme}://${uri.host}';
    return XtreamCredentials(server: server, username: acc.username!, password: acc.password!);
  }

  static XtreamCredentials? fromStreamUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final server = uri.hasPort && uri.port != 0
          ? '${uri.scheme}://${uri.host}:${uri.port}'
          : '${uri.scheme}://${uri.host}';

      // Format 1 : query params (?username=...&password=...)
      final usernameQp = uri.queryParameters['username'];
      final passwordQp = uri.queryParameters['password'];
      if (usernameQp != null && passwordQp != null) {
        return XtreamCredentials(server: server, username: usernameQp, password: passwordQp);
      }

      // Format 2 : path Xtream Codes (/{type}/{username}/{password}/{stream_id})
      // Le premier segment peut être un préfixe de type : live, movie, series → à ignorer.
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      const typePrefixes = {'live', 'movie', 'series', 'timeshift'};
      final start = (segments.isNotEmpty && typePrefixes.contains(segments[0])) ? 1 : 0;
      if (segments.length >= start + 3) {
        return XtreamCredentials(server: server, username: segments[start], password: segments[start + 1]);
      }
    } catch (_) {}
    return null;
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

  String get startLabel => DateFormat('dd/MM HH:mm').format(start);
  String get durationLabel {
    final duration = end.difference(start);
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    return h > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '$m min';
  }
}

class ReplayService {
  Future<XtreamCredentials?> _resolveCreds({String? streamUrl}) async {
    // Priorité 1 : l'URL du stream — elle contient le BON serveur pour cette qualité.
    // Les variants FHD/4K peuvent être servis par un serveur différent du compte principal.
    // Utiliser le compte en priorité enverrait le timeshift au mauvais serveur.
    if (streamUrl != null) {
      final fromStream = XtreamCredentials.fromStreamUrl(streamUrl);
      if (fromStream != null) {
        debugPrint('🔑 ReplayService: Crédentiels résolus depuis l\'URL du stream → serveur: ${redactServer(fromStream.server)}');
        return fromStream;
      }
    }
    // Priorité 2 : compte courant (fallback si l'URL ne contient pas de crédentiels lisibles).
    final acc = await StreamAccountService.getCurrentAccount();
    final fromAcc = XtreamCredentials.fromAccount(acc);
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
    final response = await http.get(uri);
    debugPrint('📨 ReplayService: Réponse HTTP ${response.statusCode}');

    if (response.statusCode != 200) {
      debugPrint('❌ ReplayService: Échec HTTP statut ${response.statusCode}');
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

  /// Vérifie si un flux a du replay : au moins un programme avec has_archive=true.
  /// get_short_epg retourne les programmes à venir — si le serveur y indique has_archive,
  /// c'est que le stream supporte le catchup de façon générale.
  Future<bool> hasReplay(int streamId, {String? streamUrl}) async {
    debugPrint('🔍 ReplayService: Vérification replay — streamId: $streamId');
    final programs = await fetchShortEpg(streamId, limit: 10, streamUrl: streamUrl);
    final supported = programs.any((p) => p.hasArchive);
    debugPrint(supported ? '✅ ReplayService: Replay supporté (has_archive=true trouvé).' : '📭 ReplayService: Pas de replay (has_archive=false sur tous les programmes).');
    return supported;
  }
}
