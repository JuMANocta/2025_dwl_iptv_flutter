import 'package:flutter/material.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/core/themes/colors.dart';

Widget tagChip(String text, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    decoration: BoxDecoration(
      color: color.withAlpha(25),
      border: Border.all(color: color.withAlpha(25)),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
  );
}

Widget qualityChip(TitleMetadata meta) {
  switch (meta.quality) {
    case '4K':   return tagChip('4K',  kQuality4K);
    case 'FHD':  return tagChip('FHD', kQualityFHD);
    case 'HD':   return tagChip('HD',  kQualityHD);
    case 'SD':   return tagChip('SD',  kQualitySD);
    default:     return const SizedBox.shrink();
  }
}

List<Widget> languageChips(TitleMetadata meta) {
  final chips = <Widget>[];
  final seen = <String>{};
  for (final lang in meta.languages) {
    if (!seen.add(lang)) continue;
    if (lang == 'MULTI')  chips.add(tagChip('MULTI',  kLangMulti));
    if (lang == 'VOSTFR') chips.add(tagChip('VOSTFR', kLangVOSTFR));
    if (lang == 'VF')     chips.add(tagChip('VF',     kLangVF));
  }
  return chips;
}

Widget episodeMetaChip(TitleMetadata meta) {
  final season  = meta.seasonNumber?.toString().padLeft(2, '0') ?? '--';
  final episode = meta.episodeNumber?.toString().padLeft(2, '0') ?? '--';
  return tagChip('S$season E$episode', kLangEpisode);
}

Chip episodeChip(M3uEntry ep) {
  return Chip(
    label: Text("S${ep.saison} E${ep.episode}"),
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
    backgroundColor: Colors.grey.withAlpha(25),
  );
}

/// Extrait le titre lisible d'un épisode depuis le rawTitle (ce qui suit SxxExx).
String episodeName(M3uEntry entry) {
  final regex = RegExp(r"S\s*\d{1,2}\s*E\s*\d{1,2}", caseSensitive: false);
  final match = regex.firstMatch(entry.rawTitle);
  if (match != null && match.end < entry.rawTitle.length) {
    String rest = entry.rawTitle.substring(match.end).trim();
    rest = rest.replaceAll(RegExp(r'\.(mkv|mp4|avi)$', caseSensitive: false), '');
    if (rest.isNotEmpty && rest.length > 2) return rest.replaceAll(RegExp(r'^[-_.]'), '').trim();
  }
  return entry.displayName;
}

/// Chips qualité + langue dédupliqués pour un groupe de versions.
/// Corrige le problème multi-comptes : Widget != par identité, on déduplique
/// donc par valeur (label) avant de construire les widgets.
List<Widget> uniqueChipsForVersions(List<M3uEntry> versions) {
  final qualities = versions.map((v) => v.title.quality).whereType<String>().toSet();
  final languages = versions.expand((v) => v.title.languages).toSet();
  return [
    for (final q in qualities)
      switch (q) {
        '4K'  => tagChip('4K',  kQuality4K),
        'FHD' => tagChip('FHD', kQualityFHD),
        'HD'  => tagChip('HD',  kQualityHD),
        'SD'  => tagChip('SD',  kQualitySD),
        _     => null,
      },
    for (final l in languages)
      switch (l) {
        'MULTI'  => tagChip('MULTI',  kLangMulti),
        'VOSTFR' => tagChip('VOSTFR', kLangVOSTFR),
        'VF'     => tagChip('VF',     kLangVF),
        _        => null,
      },
  ].whereType<Widget>().toList();
}

/// Construit un nom de fichier riche pour le téléchargement.
String buildDownloadName(M3uEntry entry) {
  final parts = <String>[entry.displayName];
  if (entry.type == M3uContentType.series && entry.title.isSeriesEpisode) {
    parts.add('S${entry.saison ?? '00'} E${entry.episode ?? '00'}');
  }
  if (entry.title.versionLabel != null && entry.title.versionLabel!.isNotEmpty) {
    parts.add(entry.title.versionLabel!);
  }
  return parts.join(' ').trim();
}
