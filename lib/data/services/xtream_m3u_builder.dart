import 'package:flutter/foundation.dart';

import '../models/stream_account.dart';
import 'xtream_api_service.dart';

/// §xtreamApi — Construit un fichier M3U Plus à partir des appels JSON API
/// Xtream (`player_api.php?action=…`).
///
/// Le pipeline existant de l'app (parser M3U, ParsedPlaylistService, etc.)
/// continue de consommer un M3U file → on garde la compatibilité totale.
/// Seule la SOURCE des données change : on lit la JSON API au lieu de tirer
/// `get.php` qui plante sur certains panels (PHP timeout sur grosses listes).
class XtreamM3uBuilder {
  XtreamM3uBuilder._();

  /// Construit le contenu M3U Plus complet (Live + Films + Séries) pour
  /// [account]. Retourne `null` si :
  /// - le compte n'a pas de credentials Xtream extractibles
  /// - tous les appels API ont échoué (rien à mettre dedans)
  ///
  /// Sinon retourne un `String` UTF-8 prêt à être écrit sur disque.
  static Future<String?> build(StreamAccount account) async {
    final creds = XtreamApiService.credentialsOf(account);
    if (creds == null) return null;

    // Fetch tout en parallèle pour gagner du temps réseau.
    final results = await Future.wait([
      XtreamApiService.getLiveCategories(account),
      XtreamApiService.getLiveStreams(account),
      XtreamApiService.getVodCategories(account),
      XtreamApiService.getVodStreams(account),
      XtreamApiService.getSeriesCategories(account),
      XtreamApiService.getSeries(account),
    ]);

    final liveCats = results[0];
    final liveStreams = results[1];
    final vodCats = results[2];
    final vodStreams = results[3];
    final seriesCats = results[4];
    final seriesList = results[5];

    debugPrint(
        '📡 XtreamApi: live=${liveStreams.length} vod=${vodStreams.length} '
        'series=${seriesList.length}');

    if (liveStreams.isEmpty && vodStreams.isEmpty && seriesList.isEmpty) {
      return null;
    }

    // Maps `category_id` → nom de catégorie, pour générer les `group-title`.
    final liveCatNames = _categoryNames(liveCats);
    final vodCatNames = _categoryNames(vodCats);
    final seriesCatNames = _categoryNames(seriesCats);

    final buf = StringBuffer('#EXTM3U\n');

    // ── Live TV ────────────────────────────────────────────────────────────
    for (final s in liveStreams) {
      _writeLive(buf, s, liveCatNames, creds);
    }

    // ── Films (VOD) ────────────────────────────────────────────────────────
    for (final m in vodStreams) {
      _writeMovie(buf, m, vodCatNames, creds);
    }

    // ── Séries ─────────────────────────────────────────────────────────────
    // §xtreamSeriesNote — On écrit UN item M3U par série (pas par épisode).
    // Les épisodes seront récupérés à la demande via
    // `XtreamApiService.getSeriesInfo(seriesId)` quand l'utilisateur ouvre
    // la fiche détail. Sinon il faudrait N appels API au boot (N = nb
    // séries) → trop lent. Le parser existant traite ces lignes comme des
    // "groupes séries" et la fiche détail va chercher les épisodes.
    for (final ser in seriesList) {
      _writeSeries(buf, ser, seriesCatNames, creds);
    }

    return buf.toString();
  }

  /// Map `category_id` → nom de catégorie.
  static Map<String, String> _categoryNames(List<Map<String, dynamic>> cats) {
    final out = <String, String>{};
    for (final c in cats) {
      final id = (c['category_id'] ?? '').toString();
      final name = (c['category_name'] ?? 'Sans catégorie').toString();
      if (id.isNotEmpty) out[id] = name;
    }
    return out;
  }

  // ── Écriture des lignes M3U ─────────────────────────────────────────────

  static void _writeLive(
    StringBuffer buf,
    Map<String, dynamic> s,
    Map<String, String> catNames,
    ({String host, String username, String password}) creds,
  ) {
    final id = (s['stream_id'] ?? '').toString();
    if (id.isEmpty) return;
    final name = (s['name'] ?? '').toString();
    final logo = (s['stream_icon'] ?? '').toString();
    final tvgId = (s['epg_channel_id'] ?? '').toString();
    final catId = (s['category_id'] ?? '').toString();
    final group = catNames[catId] ?? 'Sans catégorie';
    final url = '${creds.host}/live/${Uri.encodeComponent(creds.username)}/'
        '${Uri.encodeComponent(creds.password)}/$id.m3u8';
    buf.writeln(
      '#EXTINF:-1 tvg-id="${_q(tvgId)}" tvg-name="${_q(name)}" '
      'tvg-logo="${_q(logo)}" group-title="${_q(group)}",$name',
    );
    buf.writeln(url);
  }

  static void _writeMovie(
    StringBuffer buf,
    Map<String, dynamic> m,
    Map<String, String> catNames,
    ({String host, String username, String password}) creds,
  ) {
    final id = (m['stream_id'] ?? '').toString();
    if (id.isEmpty) return;
    final name = (m['name'] ?? '').toString();
    final logo = (m['stream_icon'] ?? '').toString();
    final ext = (m['container_extension'] ?? 'mp4').toString();
    final catId = (m['category_id'] ?? '').toString();
    final group = catNames[catId] ?? 'Films';
    final url = '${creds.host}/movie/${Uri.encodeComponent(creds.username)}/'
        '${Uri.encodeComponent(creds.password)}/$id.$ext';
    buf.writeln(
      '#EXTINF:-1 tvg-name="${_q(name)}" tvg-logo="${_q(logo)}" '
      'group-title="${_q(group)}",$name',
    );
    buf.writeln(url);
  }

  /// Écrit une entrée série SANS ses épisodes. Le marqueur dans `tvg-name`
  /// permet à la fiche détail (`DetailsPage`) de retrouver le `series_id`
  /// pour aller chercher les épisodes via `get_series_info` à la demande.
  static void _writeSeries(
    StringBuffer buf,
    Map<String, dynamic> ser,
    Map<String, String> catNames,
    ({String host, String username, String password}) creds,
  ) {
    final id = (ser['series_id'] ?? '').toString();
    if (id.isEmpty) return;
    final name = (ser['name'] ?? '').toString();
    final logo = (ser['cover'] ?? '').toString();
    final catId = (ser['category_id'] ?? '').toString();
    final group = catNames[catId] ?? 'Séries';
    // URL "stub" — `series/{user}/{pass}/{series_id}` n'est PAS un endpoint
    // de stream valide (les épisodes ont chacun leur stream_id). Cette URL
    // est juste un marqueur unique reconnu par le code séries existant ; le
    // vrai contenu est chargé via `getSeriesInfo(seriesId)` à l'ouverture
    // de la fiche.
    final url = '${creds.host}/series/${Uri.encodeComponent(creds.username)}/'
        '${Uri.encodeComponent(creds.password)}/$id';
    buf.writeln(
      '#EXTINF:-1 tvg-name="${_q(name)}" tvg-logo="${_q(logo)}" '
      'group-title="${_q(group)}",$name',
    );
    buf.writeln(url);
  }

  /// Quote-escape les valeurs d'attributs M3U (remplace " et retours ligne).
  static String _q(String s) =>
      s.replaceAll('"', '\\"').replaceAll('\n', ' ').replaceAll('\r', ' ');
}
