import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/feature/search/m3u_filter.dart';

/// §23 — Parse un **catalogue JSON brut** (`playlist_<id>.json`, produit par
/// `XtreamCatalogService`) directement en `M3uEntry`, **sans round-trip M3U
/// texte ni regex de structure**. Seule `TitleMetadata.parse` (nettoyage du
/// nom) reste appliquée — c'est elle qui fait converger les 3 formats de noms
/// providers vers le même `baseTitle` (fusion cross-listes).
///
/// Gains vs l'ancien pipeline JSON → M3U → regex :
///   - zéro perte : `tmdb_id`, synopsis, note, genres, casting, backdrops,
///     `tv_archive` (replay) passent dans les entrées ;
///   - zéro fragilité d'échappement (guillemets dans les noms) ;
///   - parsing en **isolate** (`compute`) : le `jsonDecode` d'un catalogue de
///     60+ Mo ne bloque jamais le thread UI.
///
/// Même signature que `M3uParser.parseFile` pour rester interchangeable côté
/// `ParsedPlaylistService` (le choix se fait sur l'extension du fichier).
class XtreamCatalogParser {
  XtreamCatalogParser._();

  static Future<void> parseFile(
    String filePath,
    List<M3uEntry> filmsList,
    List<M3uEntry> seriesList,
    List<M3uEntry> tvList, {
    required String accountId,
    void Function(double)? onProgress,
    Set<String> hidden = const {},
  }) async {
    onProgress?.call(0.05);
    final result = await compute(
      _parseCatalogIsolate,
      (path: filePath, accountId: accountId, hidden: hidden),
    );
    filmsList.addAll(result.films);
    seriesList.addAll(result.series);
    tvList.addAll(result.tv);
    onProgress?.call(1.0);
    debugPrint('✅ XtreamCatalogParser: films=${result.films.length} '
        'séries=${result.series.length} tv=${result.tv.length}');
  }
}

/// Fonction top-level exécutée dans l'isolate `compute`.
({List<M3uEntry> films, List<M3uEntry> series, List<M3uEntry> tv})
    _parseCatalogIsolate(
        ({String path, String accountId, Set<String> hidden}) args) {
  final films = <M3uEntry>[];
  final series = <M3uEntry>[];
  final tv = <M3uEntry>[];

  final raw = File(args.path).readAsStringSync();
  final data = jsonDecode(raw) as Map<String, dynamic>;

  final host = (data['host'] ?? '').toString();
  final user = Uri.encodeComponent((data['user'] ?? '').toString());
  final pass = Uri.encodeComponent((data['pass'] ?? '').toString());

  // §langFilter — Une entrée dont la région (préfixe `|XX|` du nom) est masquée
  // est SAUTÉE → jamais stockée. Court-circuit si rien n'est masqué.
  final filterOn = args.hidden.isNotEmpty;
  bool isHidden(String name) {
    if (!filterOn) return false;
    final r = entryRegionLabel(name);
    return r != null && args.hidden.contains(r);
  }

  // ── Live (chaînes TV) ─────────────────────────────────────────────────────
  for (final item in (data['live'] as List? ?? const [])) {
    if (item is! Map<String, dynamic>) continue;
    final id = (item['stream_id'] ?? '').toString();
    final name = (item['name'] ?? '').toString().trim();
    if (id.isEmpty || name.isEmpty || isHidden(name)) continue;
    final groupTitle = _str(item['_cat']);
    // Replay Xtream : `tv_archive` = 1 + durée en jours → alimente le même
    // champ `catchupDays` que l'attribut M3U `catchup-days` (bonus vs l'ancien
    // builder M3U qui perdait cette info).
    final archive = (item['tv_archive'] ?? 0).toString();
    final archiveDays =
        int.tryParse((item['tv_archive_duration'] ?? '').toString());
    final catchupDays =
        (archive == '1' && (archiveDays ?? 0) > 0) ? archiveDays : null;

    tv.add(M3uEntry(
      url: '$host/live/$user/$pass/$id.m3u8',
      type: M3uContentType.tv,
      title: TitleMetadata.parse(name),
      accountId: args.accountId,
      logoUrl: _str(item['stream_icon']),
      streamId: int.tryParse(id),
      tvgId: _str(item['epg_channel_id']),
      catchupDays: catchupDays,
      groupTitle: groupTitle,
      category: contentCategoryLabel(groupTitle),
    ));
  }

  // ── Films (VOD) ───────────────────────────────────────────────────────────
  for (final item in (data['vod'] as List? ?? const [])) {
    if (item is! Map<String, dynamic>) continue;
    final id = (item['stream_id'] ?? '').toString();
    final name = (item['name'] ?? '').toString().trim();
    if (id.isEmpty || name.isEmpty || isHidden(name)) continue;
    final ext = (item['container_extension'] ?? 'mp4').toString();
    final groupTitle = _str(item['_cat']);

    films.add(M3uEntry(
      url: '$host/movie/$user/$pass/$id.$ext',
      type: M3uContentType.movie,
      title: TitleMetadata.parse(name),
      accountId: args.accountId,
      logoUrl: _str(item['stream_icon']),
      streamId: int.tryParse(id),
      groupTitle: groupTitle,
      category: contentCategoryLabel(groupTitle),
      tmdbId: _str(item['tmdb_id']),
      rating: _rating(item['rating']),
    ));
  }

  // ── Séries (1 stub par série, épisodes lazy via get_series_info) ─────────
  for (final item in (data['series'] as List? ?? const [])) {
    if (item is! Map<String, dynamic>) continue;
    final id = (item['series_id'] ?? '').toString();
    final name = (item['name'] ?? '').toString().trim();
    if (id.isEmpty || name.isEmpty || isHidden(name)) continue;
    final groupTitle = _str(item['_cat']);
    final backdrops = item['backdrop_path'];

    series.add(M3uEntry(
      // URL stub — PAS un endpoint de stream : marqueur unique dont
      // `DetailsPage._extractSeriesIdFromUrl` extrait le series_id pour
      // fetcher les épisodes à la demande (inchangé vs pipeline M3U).
      url: '$host/series/$user/$pass/$id',
      type: M3uContentType.series,
      title: TitleMetadata.parse(name),
      accountId: args.accountId,
      logoUrl: _str(item['cover']),
      streamId: int.tryParse(id),
      groupTitle: groupTitle,
      category: contentCategoryLabel(groupTitle),
      tmdbId: _str(item['tmdb_id']),
      plot: _str(item['plot']),
      genre: _htmlDecode(_str(item['genre'])),
      castNames: _str(item['cast']),
      rating: _rating(item['rating']),
      releaseDate: _str(item['releaseDate']) ?? _str(item['release_date']),
      backdropUrl: (backdrops is List && backdrops.isNotEmpty)
          ? _str(backdrops.first)
          : null,
    ));
  }

  return (films: films, series: series, tv: tv);
}

/// Valeur string non vide ou null (les panels renvoient "", null, ou 0 mélangés).
String? _str(Object? v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty || s == 'null' ? null : s;
}

/// Rating provider : num (7.357) ou string ("8") → double, null si invalide/0.
double? _rating(Object? v) {
  if (v == null) return null;
  final d = v is num ? v.toDouble() : double.tryParse(v.toString());
  return (d == null || d <= 0) ? null : d;
}

/// Décode les entités HTML courantes des champs provider ("Action &amp; Drame").
String? _htmlDecode(String? s) => s
    ?.replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'");
