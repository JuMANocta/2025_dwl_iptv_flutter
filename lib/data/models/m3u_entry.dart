enum M3uContentType { movie, series, tv }

/// Métadonnées complètes extraites d'un titre M3U (qualité, année, langues, etc.).
class TitleMetadata {
  final String rawTitle;
  final String baseTitle;
  final String? year;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? quality;
  final List<String> languages;
  final String? versionLabel;

  bool get isSeriesEpisode => seasonNumber != null && episodeNumber != null;

  const TitleMetadata({
    required this.rawTitle,
    required this.baseTitle,
    this.year,
    this.seasonNumber,
    this.episodeNumber,
    this.quality,
    this.languages = const [],
    this.versionLabel,
  });

  // Patterns compilés une seule fois pour toute la durée de l'app.
  static final _reSeason       = RegExp(r's\s*(\d{1,2})\s*e\s*(\d{1,2})', caseSensitive: false);
  static final _reYear         = RegExp(r'\b(19|20)\d{2}\b');
  static final _reQ4K          = RegExp(r'\b(4k|uhd|2160p)\b');
  static final _reQFhd         = RegExp(r'\b(fhd|1080p)\b');
  static final _reQHd          = RegExp(r'\b(hd|720p)\b');
  static final _reQSd          = RegExp(r'\b(sd|480p)\b');
  static final _reLangMulti    = RegExp(r'\bmulti\b');
  static final _reLangVostfr   = RegExp(r'\bvostfr\b');
  static final _reLangVf       = RegExp(r'\b(vf|vff|truefrench|french)\b');
  static final _rePrefix       = RegExp(r'^(\|[A-Z0-9\s]+\||\w{2,}\s*[:-])\s*', caseSensitive: false);
  static final _reQualityTags  = RegExp(r'\b(4K|UHD|2160p|1080p|720p|480p|FHD|HD|SD|HEVC|H265|H\.265|X265|AAC|DTS|HDR|DV|HLG)\b', caseSensitive: false);
  static final _reLangTags     = RegExp(r'\b(MULTI|VOSTFR|VOST|VF|VO|VFF|VIP|RAW|TRUEFRENCH|FRENCH)\b', caseSensitive: false);
  static final _reFrEn         = RegExp(r'[\(\[]\s*(FR|EN)\s*[\)\]]', caseSensitive: false);
  static final _reYearClean    = RegExp(r'\(?(19|20)\d{2}\)?');
  static final _rePunct        = RegExp(r'[\(\)\[\]\.\-_/]');
  static final _reSeasonClean  = RegExp(r'S\s*\d{1,2}\s*E\s*\d{1,2}', caseSensitive: false);
  static final _reSpaces       = RegExp(r'\s+');
  static final _reSeasonFb     = RegExp(r'S\s*\d{1,2}', caseSensitive: false);
  static final _reLabelPrefix  = RegExp(r'^(\|[A-Z0-9\s]+\||\w{2,}\s*[:-])', caseSensitive: false);
  static final _reAllTags      = RegExp(r'\b(4K|UHD|2160p|1080p|720p|480p|FHD|HD|SD|HEVC|H265|X265|HDR|DV|HLG|MULTI|VOSTFR|VOST|VF|VO|VFF|VIP|RAW|TRUEFRENCH|FRENCH)\b', caseSensitive: false);
  static final _reTrimStart    = RegExp(r'^[ \t\-_.\(\)\[\]]+');
  static final _reTrimEnd      = RegExp(r'[ \t\-_.\(\)\[\]]+$');

  factory TitleMetadata.parse(String rawTitle) {
    final lower = rawTitle.toLowerCase();

    final seasonMatch   = _reSeason.firstMatch(rawTitle);
    final seasonNumber  = seasonMatch != null ? int.tryParse(seasonMatch.group(1) ?? '') : null;
    final episodeNumber = seasonMatch != null ? int.tryParse(seasonMatch.group(2) ?? '') : null;
    final year          = _reYear.firstMatch(rawTitle)?.group(0);

    String? quality;
    if (_reQ4K.hasMatch(lower))       { quality = '4K'; }
    else if (_reQFhd.hasMatch(lower)) { quality = 'FHD'; }
    else if (_reQHd.hasMatch(lower))  { quality = 'HD'; }
    else if (_reQSd.hasMatch(lower))  { quality = 'SD'; }

    final langs = <String>[];
    if (_reLangMulti.hasMatch(lower))  langs.add('MULTI');
    if (_reLangVostfr.hasMatch(lower)) langs.add('VOSTFR');
    if (_reLangVf.hasMatch(lower))     langs.add('VF');

    String base = rawTitle;
    base = base.replaceAll(_rePrefix, '');
    if (seasonMatch != null && seasonMatch.start <= base.length) {
      base = base.substring(0, seasonMatch.start).trim();
    }
    base = base.replaceAll(_reQualityTags, '');
    base = base.replaceAll(_reLangTags, '');
    base = base.replaceAll(_reFrEn, ' ');
    base = base.replaceAll(_reYearClean, '');
    base = base.replaceAll(_rePunct, ' ');
    base = base.replaceAll(_reSeasonClean, ' ');
    base = base.replaceAll(_reSpaces, ' ').trim();
    if (base.length < 2) {
      base = rawTitle.split(_reSeasonFb).first;
    }
    if (base.isEmpty) base = rawTitle.trim();

    String? versionLabel;
    if (base.isNotEmpty) {
      String label = rawTitle;
      label = label.replaceAll(RegExp(RegExp.escape(base), caseSensitive: false), '');
      label = label.replaceAll(_reLabelPrefix, '');
      label = label.replaceAll(_reYearClean, '');
      label = label.replaceAll(_reAllTags, '');
      label = label.replaceAll(_reFrEn, ' ');
      label = label.replaceAll(_reTrimStart, '');
      label = label.replaceAll(_reTrimEnd, '');
      label = label.trim().replaceAll(_reSpaces, ' ');
      if (label.isNotEmpty) versionLabel = label;
    }

    return TitleMetadata(
      rawTitle: rawTitle,
      baseTitle: base,
      year: year,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      quality: quality,
      languages: langs,
      versionLabel: versionLabel,
    );
  }
}

class M3uEntry {
  final String url;
  final M3uContentType type;
  final TitleMetadata title;
  final String? logoUrl;
  final int? streamId;
  final String? tvgId;
  final int? catchupDays;
  final String? catchupSource;
  final String? groupTitle;

  const M3uEntry({
    required this.url,
    required this.type,
    required this.title,
    this.logoUrl,
    this.streamId,
    this.tvgId,
    this.catchupDays,
    this.catchupSource,
    this.groupTitle,
  });

  bool get supportsCatchup => catchupDays != null && catchupDays! > 0;

  String get rawTitle    => title.rawTitle;
  String get displayName => title.baseTitle;
  bool   get isSerie     => type == M3uContentType.series;
  String? get saison     => title.seasonNumber?.toString().padLeft(2, '0');
  String? get episode    => title.episodeNumber?.toString().padLeft(2, '0');
}
