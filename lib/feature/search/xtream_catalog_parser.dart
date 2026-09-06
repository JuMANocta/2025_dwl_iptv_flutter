import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:aetherStream/core/utils/formatters.dart';
import 'package:aetherStream/core/utils/string_pool.dart';
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
///   - parsing en **isolate** (`Isolate.run`) : le `jsonDecode` d'un catalogue
///     de 60+ Mo ne bloque jamais le thread UI.
///
/// Même signature que `M3uParser.parseFile` pour rester interchangeable côté
/// `ParsedPlaylistService` (le choix se fait sur l'extension du fichier).
class XtreamCatalogParser {
  XtreamCatalogParser._();

  /// §bootPercent — Part du travail consommée par la **lecture + le décodage
  /// JSON**, avant que la moindre entrée soit construite.
  ///
  /// ⚠️ **Chiffre MESURÉ, pas estimé** (`test/boot_phase_probe.dart`, dump réel
  /// PLATINIUM de 61,5 Mo / 83 711 entrées) :
  ///
  ///     lecture disque          36 ms   0,8 %
  ///     décodage JSON          377 ms   8,3 %
  ///     construction entrées  4122 ms  90,9 %
  ///
  /// Il contredit l'intuition — on suppose volontiers que décoder 61 Mo de JSON
  /// est LE coût — et c'est ce qui a évité d'instrumenter la mauvaise phase :
  /// un décodage *chunked*, capable de publier une progression pendant le
  /// décodage, a été mesuré à **+34 %** de temps sur une phase qui ne pèse que
  /// 9 %. Il a donc été écarté. Les secondes d'écran figé sont dans les
  /// boucles, et les boucles sont exactement ce qu'on sait compter.
  static const double _decodeWeight = 0.09;

  /// Parse un catalogue JSON en isolate.
  ///
  /// [onProgress] reçoit une progression **réelle** de 0 à 1 : le poids fixe du
  /// décodage, puis une fraction exacte des entrées construites. [onDetail]
  /// reçoit le compteur vivant (« films · 24 100/53 781 ») — un pourcentage
  /// AFFIRME qu'on avance, un compteur qui monte le PROUVE.
  static Future<void> parseFile(
    String filePath,
    List<M3uEntry> filmsList,
    List<M3uEntry> seriesList,
    List<M3uEntry> tvList, {
    required String accountId,
    void Function(double)? onProgress,
    void Function(String)? onDetail,
    Set<String> hidden = const {},
  }) async {
    // §bootPercent — `compute()` a été remplacé par `Isolate.run` pour UNE
    // raison : `compute` n'offre aucun canal de retour, donc l'isolate ne
    // pouvait rien dire avant d'avoir tout fini. C'est ce qui produisait les
    // « 5 % puis 100 % » avec 16 s d'immobilité au milieu.
    //
    // ⚠️ On garde `Isolate.run` (et NON `Isolate.spawn` + port de résultat) :
    // `Isolate.run` rend son résultat par `Isolate.exit`, qui **transfère** le
    // graphe d'objets sans le copier. Faire transiter 350 000 `M3uEntry` par un
    // `SendPort` ordinaire les recopierait intégralement — l'inverse de
    // §ramDiet. Le port ci-dessous ne porte donc QUE la progression : quelques
    // dizaines de petits messages.
    final bool wantsProgress = onProgress != null || onDetail != null;
    final ReceivePort? port = wantsProgress ? ReceivePort() : null;
    bool finished = false;

    port?.listen((Object? message) {
      // ⚠️ Un message peut encore être en vol quand l'isolate a rendu son
      // résultat : sans ce garde-fou, la barre reviendrait de 100 % à 97 %.
      if (finished) return;
      if (message is! (double, String?)) return;
      onProgress?.call(message.$1);
      final String? detail = message.$2;
      if (detail != null) onDetail?.call(detail);
    });

    try {
      // §isolateLeak — Constaté sur appareil réel : `Isolate.run` a planté
      // avec « object is unsendable » en pointant vers CE `onProgress` —
      // pourtant jamais lu par `_parseCatalogIsolate`. Cause : la fermeture
      // `port?.listen((message) { ... onProgress?.call(...) ... })`
      // ci-dessus et celle envoyée à `Isolate.run` vivaient dans la MÊME
      // portée de méthode ; le compilateur Dart peut fusionner leurs
      // variables capturées dans un seul `Context` partagé — donc envoyer
      // l'une revient à tenter d'envoyer l'autre aussi, même sans lecture
      // directe. De simples `final` locaux (l'ancienne défense ici) ne
      // suffisent pas : seule une portée de méthode SÉPARÉE, sans aucune
      // variable capturant `this` (`onProgress`/`onDetail` viennent d'un
      // appelant qui ferme sur `_LaunchDeciderState`), garantit un contexte
      // isolé. D'où `_launchParseIsolate`, qui ne connaît que des valeurs
      // transmissibles.
      final result = await _launchParseIsolate(
        path: filePath,
        accountId: accountId,
        hidden: hidden,
        progress: port?.sendPort,
      );
      finished = true;
      filmsList.addAll(result.films);
      seriesList.addAll(result.series);
      tvList.addAll(result.tv);
      onProgress?.call(1.0);
      debugPrint('✅ XtreamCatalogParser: films=${result.films.length} '
          'séries=${result.series.length} tv=${result.tv.length}');
    } finally {
      finished = true;
      port?.close();
    }
  }

  /// §isolateLeak — Portée dédiée : AUCUNE variable ici ne capture `this` ni
  /// un callback appelant. Voir le commentaire dans [parseFile].
  static Future<
      ({
        List<M3uEntry> films,
        List<M3uEntry> series,
        List<M3uEntry> tv
      })> _launchParseIsolate({
    required String path,
    required String accountId,
    required Set<String> hidden,
    required SendPort? progress,
  }) {
    return Isolate.run(
      () => _parseCatalogIsolate((
        path: path,
        accountId: accountId,
        hidden: hidden,
        progress: progress,
      )),
    );
  }
}

/// Fonction top-level exécutée dans l'isolate.
({List<M3uEntry> films, List<M3uEntry> series, List<M3uEntry> tv})
    _parseCatalogIsolate(
        ({
          String path,
          String accountId,
          Set<String> hidden,
          SendPort? progress,
        }) args) {
  final films = <M3uEntry>[];
  final series = <M3uEntry>[];
  final tv = <M3uEntry>[];

  // §ramDiet — Décodage UTF-8 **fusionné** au décodage JSON.
  //
  // `readAsStringSync()` produisait d'abord la chaîne entière du catalogue en
  // UTF-16 (~120 Mo pour un fichier de 60 Mo) et la gardait vivante pendant tout
  // le `jsonDecode`, en plus du graphe d'objets. Le décodeur fusionné consomme
  // les octets et n'émet que le résultat : l'intermédiaire disparaît.
  // On reste dans l'isolate, donc rien de tout cela n'a jamais touché le thread
  // UI — mais un Fire Stick compte la mémoire du PROCESSUS.
  final bytes = File(args.path).readAsBytesSync();
  final data = const Utf8Decoder().fuse(const JsonDecoder()).convert(bytes)
      as Map<String, dynamic>;

  // §ramDiet — Un pool par parsing (cf. `StringPool`). Les catégories, genres
  // et qualités d'un catalogue de 350 000 entrées tiennent en quelques
  // centaines de valeurs distinctes.
  final pool = StringPool();

  final host = (data['host'] ?? '').toString();
  final user = Uri.encodeComponent((data['user'] ?? '').toString());
  final pass = Uri.encodeComponent((data['pass'] ?? '').toString());

  // §langFilter + §langFilterCat — Une entrée dont la région est masquée est
  // SAUTÉE → jamais stockée. La région est détectée par le **préfixe `|XX|` du
  // titre** (`entryRegionLabel`) OU par sa **catégorie** ([cat] =
  // `contentCategoryLabel(groupTitle)`) : certains providers encodent la région
  // dans la CATÉGORIE (ex. « Films Italiens ») et pas dans le titre → sans ce
  // 2e test, la rangée région réapparaissait. Court-circuit si rien n'est masqué.
  // §legLang — prédicat PARTAGÉ avec le parseur M3U et le téléchargement.
  // ⚠️ `cat` est ici la CATÉGORIE DÉJÀ RÉSOLUE (`_cat`), pas un group-title
  // brut : on la teste donc directement au lieu de la recalculer.
  final filterOn = args.hidden.isNotEmpty;
  bool isHidden(String name, String? cat) {
    if (!filterOn) return false;
    if (cat != null && args.hidden.contains(cat)) return true;
    return isRegionHidden(name: name, hidden: args.hidden);
  }

  // §bootPercent — La progression RÉELLE commence ici : le décodage est fini,
  // donc les trois tailles sont connues et chaque entrée construite est un
  // avancement qu'on peut prouver.
  final List liveRaw = data['live'] as List? ?? const [];
  final List vodRaw = data['vod'] as List? ?? const [];
  final List seriesRaw = data['series'] as List? ?? const [];
  final int total = liveRaw.length + vodRaw.length + seriesRaw.length;

  final SendPort? sink = args.progress;
  int done = 0;
  int lastBucket = -1;

  /// Publie au changement de **pourcentage entier** seulement.
  ///
  /// ⚠️ Sans ce filtre, une liste de 350 000 entrées enverrait 350 000
  /// messages inter-isolates pour faire bouger une barre de 100 pixels.
  void tick(String section) {
    if (sink == null) return;
    final double value = total == 0
        ? 1.0
        : XtreamCatalogParser._decodeWeight +
            (1 - XtreamCatalogParser._decodeWeight) * (done / total);
    final int bucket = (value * 100).round();
    if (bucket == lastBucket) return;
    lastBucket = bucket;
    sink.send((
      value,
      '$section · ${formatCount(done)}/${formatCount(total)}',
    ));
  }

  // Premier repère : le décodage est derrière nous, et on annonce l'ampleur du
  // travail restant AVANT de le commencer.
  if (sink != null) {
    lastBucket = (XtreamCatalogParser._decodeWeight * 100).round();
    sink.send((
      XtreamCatalogParser._decodeWeight,
      '${formatCount(total)} entrées',
    ));
  }

  // ── Live (chaînes TV) ─────────────────────────────────────────────────────
  for (final item in liveRaw) {
    done++;
    tick('chaînes');
    if (item is! Map<String, dynamic>) continue;
    final id = (item['stream_id'] ?? '').toString();
    final name = (item['name'] ?? '').toString().trim();
    final groupTitle = pool.of(_str(item['_cat']));
    final cat = pool.of(contentCategoryLabel(groupTitle));
    if (id.isEmpty || name.isEmpty || isHidden(name, cat)) continue;
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
      title: TitleMetadata.parse(name, pool),
      accountId: args.accountId,
      logoUrl: _str(item['stream_icon']),
      streamId: int.tryParse(id),
      tvgId: _str(item['epg_channel_id']),
      catchupDays: catchupDays,
      groupTitle: groupTitle,
      category: cat,
    ));
  }

  // ── Films (VOD) ───────────────────────────────────────────────────────────
  for (final item in vodRaw) {
    done++;
    tick('films');
    if (item is! Map<String, dynamic>) continue;
    final id = (item['stream_id'] ?? '').toString();
    final name = (item['name'] ?? '').toString().trim();
    final groupTitle = pool.of(_str(item['_cat']));
    final cat = pool.of(contentCategoryLabel(groupTitle));
    if (id.isEmpty || name.isEmpty || isHidden(name, cat)) continue;
    final ext = (item['container_extension'] ?? 'mp4').toString();

    films.add(M3uEntry(
      url: '$host/movie/$user/$pass/$id.$ext',
      type: M3uContentType.movie,
      title: TitleMetadata.parse(name, pool),
      accountId: args.accountId,
      logoUrl: _str(item['stream_icon']),
      streamId: int.tryParse(id),
      groupTitle: groupTitle,
      category: cat,
      tmdbId: _tmdbId(item),
      rating: _rating(item['rating']),
      addedAt: _unixSeconds(item['added']),
    ));
  }

  // ── Séries (1 stub par série, épisodes lazy via get_series_info) ─────────
  for (final item in seriesRaw) {
    done++;
    tick('séries');
    if (item is! Map<String, dynamic>) continue;
    final id = (item['series_id'] ?? '').toString();
    final name = (item['name'] ?? '').toString().trim();
    final groupTitle = pool.of(_str(item['_cat']));
    final cat = pool.of(contentCategoryLabel(groupTitle));
    if (id.isEmpty || name.isEmpty || isHidden(name, cat)) continue;
    final backdrops = item['backdrop_path'];

    series.add(M3uEntry(
      // URL stub — PAS un endpoint de stream : marqueur unique dont
      // `DetailsPage._extractSeriesIdFromUrl` extrait le series_id pour
      // fetcher les épisodes à la demande (inchangé vs pipeline M3U).
      url: '$host/series/$user/$pass/$id',
      type: M3uContentType.series,
      title: TitleMetadata.parse(name, pool),
      accountId: args.accountId,
      logoUrl: _str(item['cover']),
      streamId: int.tryParse(id),
      groupTitle: groupTitle,
      category: cat,
      tmdbId: _tmdbId(item),
      plot: _str(item['plot']),
      genre: pool.of(_htmlDecode(_str(item['genre']))),
      rating: _rating(item['rating']),
      releaseDate: _str(item['releaseDate']) ?? _str(item['release_date']),
      backdropUrl: (backdrops is List && backdrops.isNotEmpty)
          ? _str(backdrops.first)
          : null,
      // Séries : `last_modified` (dernière MAJ d'épisodes) fait office de date
      // d'ajout/récence ; fallback `added` si présent.
      addedAt: _unixSeconds(item['last_modified'] ?? item['added']),
    ));
  }

  debugPrint('🧵 Catalogue: ${pool.distinct} valeurs distinctes mutualisées '
      '(§ramDiet)');
  return (films: films, series: series, tv: tv);
}

/// Valeur string non vide ou null (les panels renvoient "", null, ou 0 mélangés).
/// §tmdbField — L'identifiant TMDB n'a pas le même nom d'un panel à l'autre.
///
/// ⚠️ Mesuré sur le corpus du 2026-08-30 : PLATINIUM l'envoie sous `tmdb_id`
/// (93 % des films), **PREMIUM sous `tmdb`** (99 %). Le parseur ne lisait que
/// le premier : **16 650 identifiants** (12 651 films + 3 999 séries) partaient
/// à la poubelle, et ces titres retombaient sur la recherche TMDB par NOM —
/// c'est-à-dire sur le chemin qui perd des affiches (§cleanQuery).
///
/// ⚠️ Ne pas se contenter de `??` : certains panels renvoient la chaîne vide ou
/// `"0"` plutôt que d'omettre le champ.
String? _tmdbId(Map item) {
  for (final k in const ['tmdb_id', 'tmdb', 'tmdbId']) {
    final v = _str(item[k]);
    if (v != null && v.isNotEmpty && v != '0') return v;
  }
  return null;
}

String? _str(Object? v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty || s == 'null' ? null : s;
}

/// §newByAdded — Timestamp Unix EN SECONDES depuis un champ provider
/// (`added` / `last_modified`), string "1781108002" ou num. Null si absent ou
/// invalide. Tolère un timestamp en millisecondes (>1e12) en le ramenant en s.
int? _unixSeconds(Object? v) {
  if (v == null) return null;
  final n = v is num ? v.toInt() : int.tryParse(v.toString().trim());
  if (n == null || n <= 0) return null;
  return n > 1000000000000 ? n ~/ 1000 : n;
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
