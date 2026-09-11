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
    case 'CAM':  return tagChip('CAM', kQualityCam); // §camQuality
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
    // §legLang — Le portugais sous-titré est une langue comme les autres.
    if (lang == 'LEG')    chips.add(tagChip('LEG',    kLangLeg));
  }
  return chips;
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

/// Construit un nom de fichier riche pour le téléchargement.
String buildDownloadName(M3uEntry entry) {
  final parts = <String>[entry.displayName];
  if (entry.type == M3uContentType.series && entry.title.isSeriesEpisode) {
    parts.add('S${entry.saison ?? '00'} E${entry.episode ?? '00'}');
  }
  if (entry.title.versionLabel != null && entry.title.versionLabel!.isNotEmpty) {
    parts.add(entry.title.versionLabel!);
  }
  // §providerTag — Conserve le marqueur dans le NOM DE FICHIER : il portait
  // l'info de langue/région et vivait dans versionLabel avant d'être typé.
  if (entry.title.providerTag != null) parts.add(entry.title.providerTag!);
  return parts.join(' ').trim();
}
