import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/stream_account.dart';
import 'xtream_api_service.dart';

/// §23 — Téléchargement du **catalogue JSON brut** (`player_api.php`).
///
/// Remplace `XtreamM3uBuilder` : au lieu d'assembler un M3U texte (puis de le
/// re-parser à coup de regex), on sauvegarde directement les réponses JSON de
/// la JSON API dans `playlist_<id>.json`. Le fichier est ensuite consommé par
/// `XtreamCatalogParser` qui produit les `M3uEntry` **sans round-trip ni perte
/// d'information** (tmdb_id, synopsis, rating, backdrops… que le M3U ne
/// transportait pas).
///
/// Format du fichier :
/// ```json
/// {
///   "v": 1,
///   "host": "http://…", "user": "…", "pass": "…",
///   "live":   [ {…stream + "_cat": "Nom catégorie"}, … ],
///   "vod":    [ … ],
///   "series": [ … ]
/// }
/// ```
/// Les noms de catégories sont **dénormalisés** dans chaque item (`_cat`) pour
/// que le parser n'ait pas besoin des listes de catégories.
///
/// ⚠️ Le fichier contient les credentials (comme l'ancien .m3u dont chaque URL
/// les embarquait) — répertoire privé app, même niveau d'exposition qu'avant.
class XtreamCatalogService {
  XtreamCatalogService._();

  /// Version du format de fichier catalogue (invalidation si évolution).
  static const int fileVersion = 1;

  /// Télécharge le catalogue complet de [account] et l'écrit dans [destPath]
  /// (écriture atomique via fichier temporaire). Retourne `true` si le
  /// catalogue contient au moins une entrée, `false` si l'API n'a rien donné
  /// (compte non-Xtream / API HS) → l'appelant dégrade vers `get.php`.
  static Future<bool> downloadCatalog(StreamAccount account, String destPath) async {
    final creds = XtreamApiService.credentialsOf(account);
    if (creds == null) return false;

    // Fetch tout en parallèle pour gagner du temps réseau (mêmes 6 actions
    // que l'ancien XtreamM3uBuilder).
    final results = await Future.wait([
      XtreamApiService.getLiveCategories(account),
      XtreamApiService.getLiveStreams(account),
      XtreamApiService.getVodCategories(account),
      XtreamApiService.getVodStreams(account),
      XtreamApiService.getSeriesCategories(account),
      XtreamApiService.getSeries(account),
    ]);

    final liveCats = results[0];
    final live = results[1];
    final vodCats = results[2];
    final vod = results[3];
    final seriesCats = results[4];
    final series = results[5];

    debugPrint('📡 XtreamCatalog: live=${live.length} vod=${vod.length} '
        'series=${series.length}');

    if (live.isEmpty && vod.isEmpty && series.isEmpty) return false;

    // Dénormalisation : injecte le nom de catégorie dans chaque item.
    _injectCategoryNames(live, _categoryNames(liveCats));
    _injectCategoryNames(vod, _categoryNames(vodCats));
    _injectCategoryNames(series, _categoryNames(seriesCats));

    final payload = <String, dynamic>{
      'v': fileVersion,
      'host': creds.host,
      'user': creds.username,
      'pass': creds.password,
      'live': live,
      'vod': vod,
      'series': series,
    };

    final tempPath = '$destPath.part';
    final temp = File(tempPath);
    await temp.writeAsString(jsonEncode(payload), flush: true);
    await temp.rename(destPath);
    return true;
  }

  /// Map `category_id` → nom de catégorie.
  static Map<String, String> _categoryNames(List<Map<String, dynamic>> cats) {
    final out = <String, String>{};
    for (final c in cats) {
      final id = (c['category_id'] ?? '').toString();
      final name = (c['category_name'] ?? '').toString();
      if (id.isNotEmpty && name.isNotEmpty) out[id] = name;
    }
    return out;
  }

  static void _injectCategoryNames(
    List<Map<String, dynamic>> items,
    Map<String, String> catNames,
  ) {
    for (final it in items) {
      final catId = (it['category_id'] ?? '').toString();
      final name = catNames[catId];
      if (name != null) it['_cat'] = name;
    }
  }
}
