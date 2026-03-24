import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';

class M3uParser {
  /// Parse le fichier M3U et alimente les trois listes.
  /// [onProgress] est appelé avec une valeur entre 0.0 et 1.0 pendant le parsing.
  static Future<void> parseFile(
    String filePath,
    List<M3uEntry> filmsList,
    List<M3uEntry> seriesList,
    List<M3uEntry> tvList, {
    void Function(double progress)? onProgress,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Fichier introuvable: $filePath');
    }

    final bytes = await file.readAsBytes();
    String content;
    try {
      content = utf8.decode(bytes);
      debugPrint('✅ M3U: encodage UTF-8 détecté');
    } catch (_) {
      content = latin1.decode(bytes);
      debugPrint('⚠️ M3U: fallback Latin-1 (fichier non-UTF-8)');
    }

    final regExpSerie       = RegExp(r"S\s*(\d{1,2})\s*E\s*(\d{1,2})", caseSensitive: false);
    final regExpLogo        = RegExp(r'tvg-logo="([^"]*)"');
    final regExpTvgId       = RegExp(r'tvg-id="([^"]*)"');
    final regExpGroupTitle  = RegExp(r'group-title="([^"]*)"');
    final regExpCatchup     = RegExp(r'catchup="([^"]*)"', caseSensitive: false);
    final regExpCatchupDays = RegExp(r'catchup-days="(\d+)"', caseSensitive: false);
    final regExpCatchupSrc  = RegExp(r'catchup-source="([^"]*)"', caseSensitive: false);

    String? pendingMetadata;
    final lines = const LineSplitter().convert(content);
    final totalEntries = lines.where((l) => l.trimLeft().startsWith('#EXTINF')).length;
    int parsedEntries = 0;

    final sw = Stopwatch()..start();

    for (final line in lines) {
      if (sw.elapsedMilliseconds > 8) {
        await Future.delayed(Duration.zero);
        sw.reset();
        onProgress?.call(totalEntries > 0 ? parsedEntries / totalEntries : 0.0);
      }

      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('#EXTINF')) {
        pendingMetadata = trimmed;
        parsedEntries++;
      } else if (trimmed.startsWith('http')) {
        String url = trimmed;
        String? title;
        String? logoUrl;
        String? tvgId;
        String? groupTitle;
        int?    catchupDays;
        String? catchupSource;

        if (pendingMetadata != null) {
          final commaIndex = pendingMetadata!.lastIndexOf(',');
          if (commaIndex != -1) {
            title      = pendingMetadata!.substring(commaIndex + 1).trim();
            logoUrl    = regExpLogo.firstMatch(pendingMetadata!)?.group(1);
            tvgId      = regExpTvgId.firstMatch(pendingMetadata!)?.group(1)?.trim();
            groupTitle = regExpGroupTitle.firstMatch(pendingMetadata!)?.group(1)?.trim();
            final catchupValue = regExpCatchup.firstMatch(pendingMetadata!)?.group(1)?.toLowerCase() ?? '';
            final hasCatchup = catchupValue.isNotEmpty
                && catchupValue != 'false'
                && catchupValue != 'no'
                && catchupValue != '0';
            if (hasCatchup) {
              final daysStr = regExpCatchupDays.firstMatch(pendingMetadata!)?.group(1);
              catchupDays   = int.tryParse(daysStr ?? '') ?? 7;
              catchupSource = regExpCatchupSrc.firstMatch(pendingMetadata!)?.group(1);
            }
          }
          pendingMetadata = null;
        } else if (trimmed.contains('#Name:')) {
          final parts = trimmed.split('#Name:');
          url   = parts[0].trim();
          title = parts.length > 1 ? parts[1].trim() : null;
        }

        if (title != null && title.isNotEmpty) {
          _addEntry(
            rawTitle: title,
            url: url,
            regExpSerie: regExpSerie,
            logoUrl: logoUrl,
            tvgId: tvgId,
            groupTitle: groupTitle,
            catchupDays: catchupDays,
            catchupSource: catchupSource,
            filmsList: filmsList,
            seriesList: seriesList,
            tvList: tvList,
          );
        }
      }
    }

    onProgress?.call(1.0);
  }

  static void _addEntry({
    required String rawTitle,
    required String url,
    required RegExp regExpSerie,
    String? logoUrl,
    String? tvgId,
    String? groupTitle,
    int? catchupDays,
    String? catchupSource,
    required List<M3uEntry> filmsList,
    required List<M3uEntry> seriesList,
    required List<M3uEntry> tvList,
  }) {
    final lowerUrl = url.toLowerCase();
    final metadata = TitleMetadata.parse(rawTitle);

    M3uContentType type;
    if (lowerUrl.contains('/movie/')) {
      type = M3uContentType.movie;
    } else if (lowerUrl.contains('/series/')) {
      type = M3uContentType.series;
    } else if (metadata.isSeriesEpisode || regExpSerie.firstMatch(rawTitle) != null) {
      type = M3uContentType.series;
    } else {
      type = M3uContentType.tv;
    }

    final streamId = _extractStreamId(url);

    final entry = M3uEntry(
      url: url,
      type: type,
      title: metadata,
      logoUrl: logoUrl,
      streamId: streamId,
      tvgId: tvgId,
      groupTitle: groupTitle,
      catchupDays: catchupDays,
      catchupSource: catchupSource,
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
