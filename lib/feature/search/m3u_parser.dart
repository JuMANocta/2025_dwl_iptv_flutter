import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:aetherStream/core/utils/string_pool.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/feature/search/m3u_filter.dart';

class M3uParser {
  /// Parse le fichier M3U et alimente les trois listes.
  /// [onProgress] est appelé avec une valeur entre 0.0 et 1.0 pendant le parsing.
  ///
  /// §ramDiet (2026-09-02) — Lecture **streamée**, sur le thread UI mais sans
  /// jamais matérialiser le fichier.
  ///
  /// Ce que faisait la version précédente, sur une liste réelle de 121 000
  /// entrées (fichier de 35 Mo) : `readAsBytes` (35 Mo) **puis** `utf8.decode`
  /// (70 Mo — les `String` Dart sont en UTF-16) **puis** `LineSplitter.convert`
  /// (75 Mo de sous-chaînes) — les trois **vivants en même temps**, soit ~180 Mo
  /// de pic sur l'isolate principal. Sur un Fire Stick (512 Mo à 1 Go de tas
  /// utilisable), c'est la marche qui déclenchait les OOM silencieux.
  ///
  /// Désormais : `openRead` → décodeur → `LineSplitter`, une ligne à la fois.
  /// Le pic ne dépend plus de la taille du fichier, seulement des entrées
  /// produites — qui sont le résultat, pas un intermédiaire.
  ///
  /// ⚠️ Le fallback d'encodage est PRÉSERVÉ mais déplacé : en streaming, l'échec
  /// UTF-8 ne survient qu'au milieu du flux, après avoir déjà produit des
  /// entrées. On parse donc dans des listes locales et on ne les publie qu'une
  /// fois le fichier entièrement lu ; si l'UTF-8 casse, on jette et on relit
  /// tout en Latin-1. Le coût de la relecture ne se paie que dans ce cas rare.
  static Future<void> parseFile(
    String filePath,
    List<M3uEntry> filmsList,
    List<M3uEntry> seriesList,
    List<M3uEntry> tvList, {
    required String accountId,
    void Function(double progress)? onProgress,
    Set<String> hidden = const {},
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Fichier introuvable: $filePath');
    }

    final films = <M3uEntry>[];
    final series = <M3uEntry>[];
    final tv = <M3uEntry>[];
    try {
      await _parseStream(file, const Utf8Decoder(allowMalformed: false),
          accountId: accountId,
          hidden: hidden,
          onProgress: onProgress,
          filmsList: films,
          seriesList: series,
          tvList: tv);
      debugPrint('✅ M3U: encodage UTF-8 détecté');
    } on FormatException {
      films.clear();
      series.clear();
      tv.clear();
      debugPrint('⚠️ M3U: fallback Latin-1 (fichier non-UTF-8) — relecture');
      await _parseStream(file, const Latin1Decoder(),
          accountId: accountId,
          hidden: hidden,
          onProgress: onProgress,
          filmsList: films,
          seriesList: series,
          tvList: tv);
    }

    filmsList.addAll(films);
    seriesList.addAll(series);
    tvList.addAll(tv);
    onProgress?.call(1.0);
  }

  static Future<void> _parseStream(
    File file,
    Converter<List<int>, String> decoder, {
    required String accountId,
    required Set<String> hidden,
    required void Function(double progress)? onProgress,
    required List<M3uEntry> filmsList,
    required List<M3uEntry> seriesList,
    required List<M3uEntry> tvList,
  }) async {
    // §ramDiet — Progression en OCTETS LUS, plus en entrées.
    //
    // L'ancien calcul avait besoin du total d'entrées, obtenu en re-parcourant
    // toutes les lignes avant même de commencer — un second passage complet sur
    // 75 Mo pour afficher un pourcentage. La taille du fichier, elle, est connue
    // d'avance et gratuite.
    final totalBytes = await file.length();
    int readBytes = 0;

    // §ramDiet — Un pool par parsing, jeté à la sortie (cf. `StringPool`).
    final pool = StringPool();

    final regExpSerie       = RegExp(r"S\s*(\d{1,2})\s*E\s*(\d{1,2})", caseSensitive: false);
    final regExpLogo        = RegExp(r'tvg-logo="([^"]*)"');
    final regExpTvgId       = RegExp(r'tvg-id="([^"]*)"');
    final regExpGroupTitle  = RegExp(r'group-title="([^"]*)"');
    final regExpCatchup     = RegExp(r'catchup="([^"]*)"', caseSensitive: false);
    final regExpCatchupDays = RegExp(r'catchup-days="(\d+)"', caseSensitive: false);
    final regExpCatchupSrc  = RegExp(r'catchup-source="([^"]*)"', caseSensitive: false);

    String? pendingMetadata;
    final lines = file
        .openRead()
        .map((chunk) {
          readBytes += chunk.length;
          return chunk;
        })
        .transform(decoder)
        .transform(const LineSplitter());

    final sw = Stopwatch()..start();

    await for (final line in lines) {
      // Le rendement au thread UI reste indispensable : `LineSplitter` pousse
      // toutes les lignes d'un même bloc de 64 Ko d'affilée, et une micro-tâche
      // ne laisse pas Flutter dessiner une frame.
      if (sw.elapsedMilliseconds > 8) {
        await Future.delayed(Duration.zero);
        sw.reset();
        onProgress?.call(totalBytes > 0 ? readBytes / totalBytes : 0.0);
      }

      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('#EXTINF')) {
        pendingMetadata = trimmed;
      } else if (trimmed.startsWith('http')) {
        String url = trimmed;
        String? title;
        String? logoUrl;
        String? tvgId;
        String? groupTitle;
        int?    catchupDays;
        String? catchupSource;

        if (pendingMetadata != null) {
          final meta = pendingMetadata;
          // On cherche la première virgule qui n'est PAS à l'intérieur d'une
          // valeur entre guillemets (ex: group-title="Action, Thriller").
          // lastIndexOf(',') était incorrect pour les titres contenant une virgule
          // (ex: "Star Trek, le film" → extrayait seulement "le film").
          final commaIndex = _findSeparatorComma(meta);
          if (commaIndex != -1) {
            title      = meta.substring(commaIndex + 1).trim();
            logoUrl    = regExpLogo.firstMatch(meta)?.group(1);
            tvgId      = regExpTvgId.firstMatch(meta)?.group(1)?.trim();
            groupTitle = regExpGroupTitle.firstMatch(meta)?.group(1)?.trim();
            // §m3uAttrAudit — Diagnostic : quand AUCUN `group-title` n'est
            // trouvé, on journalise les NOMS d'attributs présents sur la ligne
            // (jamais leurs valeurs).
            //
            // Question à laquelle rien ne répondait : une liste sans aucune
            // catégorie (mesuré : 153 062 entrées sur 153 062) est-elle un M3U
            // réellement dépourvu de groupes, ou un M3U qui les écrit
            // autrement — `tvg-group`, ou `group-title=Action` sans guillemets,
            // que la regex actuelle exige ? Les deux appellent des correctifs
            // opposés : inférer une catégorie, ou simplement lire le bon champ.
            //
            // ⚠️ On ne logue QUE les noms d'attributs : une valeur peut porter
            // une URL de logo du fournisseur, et le journal est servi sur le
            // LAN par la console web (§tvLogs).
            if (groupTitle == null && _attrAuditRemaining > 0) {
              _attrAuditRemaining--;
              final attrs = _reAttrName
                  .allMatches(meta)
                  .map((m) => m.group(1))
                  .toSet()
                  .join(', ');
              debugPrint('🔎 §m3uAttrAudit — ligne sans group-title, '
                  'attributs présents : [$attrs]');
            }
            final catchupValue = regExpCatchup.firstMatch(meta)?.group(1)?.toLowerCase() ?? '';
            final hasCatchup = catchupValue.isNotEmpty
                && catchupValue != 'false'
                && catchupValue != 'no'
                && catchupValue != '0';
            if (hasCatchup) {
              final daysStr = regExpCatchupDays.firstMatch(meta)?.group(1);
              catchupDays   = int.tryParse(daysStr ?? '') ?? 7;
              catchupSource = regExpCatchupSrc.firstMatch(meta)?.group(1);
            }
          }
          pendingMetadata = null;
        } else if (trimmed.contains('#Name:')) {
          final parts = trimmed.split('#Name:');
          url   = parts[0].trim();
          title = parts.length > 1 ? parts[1].trim() : null;
        }

        // §langFilter + §langFilterCat — saute les entrées d'une région masquée :
        // région détectée par le préfixe `|XX|` du TITRE OU par la CATÉGORIE
        // (`contentCategoryLabel(groupTitle)` ; certains providers encodent la
        // région dans le group-title). Court-circuit si rien n'est masqué.
        final hiddenEntry = hidden.isNotEmpty &&
            () {
              final r = entryRegionLabel(title ?? '');
              if (r != null && hidden.contains(r)) return true;
              final cat = contentCategoryLabel(groupTitle);
              return cat != null && hidden.contains(cat);
            }();
        if (title != null && title.isNotEmpty && !hiddenEntry) {
          _addEntry(
            rawTitle: title,
            url: url,
            accountId: accountId,
            regExpSerie: regExpSerie,
            logoUrl: logoUrl,
            tvgId: tvgId,
            groupTitle: groupTitle,
            catchupDays: catchupDays,
            catchupSource: catchupSource,
            filmsList: filmsList,
            seriesList: seriesList,
            tvList: tvList,
            pool: pool,
          );
        }
      }
    }

    debugPrint('🧵 M3U: ${pool.distinct} valeurs distinctes mutualisées '
        '(§ramDiet)');
  }

  /// Retourne l'index de la virgule séparatrice entre les attributs EXTINF et le titre.
  /// Parcourt la ligne caractère par caractère pour ignorer les virgules à l'intérieur
  /// §m3uAttrAudit — Noms d'attributs d'une ligne `#EXTINF` (`clef=`).
  static final RegExp _reAttrName = RegExp(r'([a-zA-Z0-9_-]+)=');

  /// §m3uAttrAudit — Nombre d'exemples restant à journaliser. Volontairement
  /// minuscule : trois lignes suffisent à identifier la convention d'un
  /// fournisseur, et une playlist en compte des centaines de milliers.
  static int _attrAuditRemaining = 3;

  /// des valeurs entre guillemets (ex: group-title="Action, Thriller").
  static int _findSeparatorComma(String meta) {
    bool inQuotes = false;
    for (int i = 0; i < meta.length; i++) {
      final c = meta[i];
      if (c == '"') {
        inQuotes = !inQuotes;
      } else if (c == ',' && !inQuotes) {
        return i;
      }
    }
    return -1;
  }

  static void _addEntry({
    required String rawTitle,
    required String url,
    required String accountId,
    required RegExp regExpSerie,
    String? logoUrl,
    String? tvgId,
    String? groupTitle,
    int? catchupDays,
    String? catchupSource,
    required List<M3uEntry> filmsList,
    required List<M3uEntry> seriesList,
    required List<M3uEntry> tvList,
    StringPool pool = StringPool.none,
  }) {
    final lowerUrl = url.toLowerCase();
    final metadata = TitleMetadata.parse(rawTitle, pool);

    M3uContentType type;
    if (lowerUrl.contains('/movie/')) {
      type = M3uContentType.movie;
    } else if (lowerUrl.contains('/series/')) {
      type = M3uContentType.series;
    } else if (regExpSerie.firstMatch(rawTitle) != null) {
      // Classification série basée UNIQUEMENT sur le format strict SxxExx
      // (regExpSerie). On n'utilise PAS `metadata.isSeriesEpisode` car celui-ci
      // inclut désormais le format NNxNN (§Ultimate) — or une chaîne TV comme
      // "ARENA SPORT 1x2" (URL nue, sans /series/) ne doit JAMAIS devenir une
      // série. Comportement strictement identique à l'ancien code pour les
      // listes existantes (l'ancien isSeriesEpisode == match SxxExx).
      type = M3uContentType.series;
    } else {
      type = M3uContentType.tv;
    }

    final streamId = _extractStreamId(url);

    final entry = M3uEntry(
      url: url,
      type: type,
      title: metadata,
      accountId: accountId,
      logoUrl: logoUrl,
      streamId: streamId,
      tvgId: tvgId,
      groupTitle: pool.of(groupTitle),
      catchupDays: catchupDays,
      catchupSource: pool.of(catchupSource),
      category: pool.of(contentCategoryLabel(groupTitle)), // §1c
    );

    if (type == M3uContentType.series) {
      seriesList.add(entry);
    } else if (type == M3uContentType.movie) {
      filmsList.add(entry);
    } else {
      tvList.add(entry);
    }
  }

  static int? _extractStreamId(String url) {
    try {
      final uri = Uri.parse(url);
      final qpId = int.tryParse(uri.queryParameters['stream'] ?? '');
      if (qpId != null) return qpId;

      for (final segment in uri.pathSegments.reversed) {
        final base = segment.split('.').first;
        final id = int.tryParse(base);
        if (id != null) return id;
      }
    } catch (_) {}
    final m = RegExp(r'/live/[^/]+/[^/]+/(\d+)', caseSensitive: false).firstMatch(url);
    if (m != null) return int.tryParse(m.group(1) ?? '');
    return null;
  }
}
