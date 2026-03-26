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
  static final _reQ4K          = RegExp(r'\b(4k|uhd|2160p)\b', caseSensitive: false);
  static final _reQFhd         = RegExp(r'\b(fhd|1080p)\b', caseSensitive: false);
  static final _reQHd          = RegExp(r'\b(hd|720p)\b', caseSensitive: false);
  static final _reQSd          = RegExp(r'\b(sd|480p)\b', caseSensitive: false);
  static final _reLangMulti    = RegExp(r'\bmulti\b', caseSensitive: false);
  static final _reLangVostfr   = RegExp(r'\bvostfr\b', caseSensitive: false);
  static final _reLangVf       = RegExp(r'\b(vf|vff|truefrench|french)\b', caseSensitive: false);

  // Préfixe provider : uniquement la forme |XX| — le pattern \w{2,}[:-] était trop large
  // et découpait des titres comme "Thor:", "Mission:", "Spider-Man:", etc.
  static final _rePrefix       = RegExp(r'^\|[A-Z0-9\s]+\|\s*');
  static final _reLabelPrefix  = RegExp(r'^\|[A-Z0-9\s]+\|', caseSensitive: false);

  // Tags DOLBY multi-mots (DOLBY VISION, DOLBY ATMOS, etc.) — appliqués avant _reQualityTags
  static final _reDolby        = RegExp(r'(?<!\w)DOLBY(?:\s+(?:VISION|ATMOS|DIGITAL(?:\s+PLUS)?|TRUEHD|SURROUND|STEREO))?(?!\w)', caseSensitive: false);

  // Tags qualité/codec/source.
  // Utilise (?<!\w)...(?!\w) plutôt que \b...\b pour gérer les tags se terminant
  // par des non-word chars comme "HDR10+" (le "+" briserait \b).
  static final _reQualityTags  = RegExp(
    r'(?<!\w)('
    r'4K|UHD|2160p|1080p|720p|480p|FHD|HD|SD|3D|IMAX'
    r'|HEVC|H\.?265|H\.?264|X\.?265|X\.?264|AVC|AV1'
    r'|AAC|EAC3|AC3|DTS(?:[-.](?:HD|MA|X))?|TrueHD|TRUEHD'
    r'|HDR10\+|HDR10|HDR|DV|HLG|SDR|ATMOS'
    r'|REMUX|PROPER|REPACK|EXTENDED|UNRATED|THEATRICAL|DIRECTORS?\.?CUT'
    r'|BLURAY|BLU[-.]RAY|BDRIP|BRRIP'
    r'|WEB[-.]?DL|WEBRIP|HDRIP'
    r'|DVDRIP|DVDSCR|HDCAM|HDTS'
    r')(?!\w)',
    caseSensitive: false,
  );

  static final _reLangTags     = RegExp(r'\b(MULTI|VOSTFR|VOST|VF|VO|VFF|VIP|RAW|TRUEFRENCH|FRENCH)\b', caseSensitive: false);

  // Codes langue/version dans parenthèses : (FR), (EN), (AR), (MULTI), (VOST FR), (MUET)…
  // Placé après _reQualityTags pour ne pas interférer avec (4K), (3D) etc. déjà retirés.
  static final _reLangParens   = RegExp(r'[\(\[]\s*[A-Z]{2,6}(?:\s+[A-Z]{2,6})?\s*[\)\]]', caseSensitive: false);

  static final _reYearClean    = RegExp(r'\(?(19|20)\d{2}\)?');
  static final _rePunct        = RegExp(r'[\(\)\[\]\.\-_/]');
  static final _reSeasonClean  = RegExp(r'S\s*\d{1,2}\s*E\s*\d{1,2}', caseSensitive: false);
  static final _reSpaces       = RegExp(r'\s+');
  static final _reSeasonFb     = RegExp(r'S\s*\d{1,2}', caseSensitive: false);
  static final _reAllTags      = RegExp(
    r'(?<!\w)('
    r'4K|UHD|2160p|1080p|720p|480p|FHD|HD|SD|3D|IMAX'
    r'|HEVC|H\.?265|H\.?264|X\.?265|X\.?264|AVC|AV1'
    r'|AAC|EAC3|AC3|DTS(?:[-.](?:HD|MA|X))?|TrueHD|TRUEHD'
    r'|HDR10\+|HDR10|HDR|DV|HLG|SDR|ATMOS|DOLBY'
    r'|REMUX|PROPER|REPACK|EXTENDED|UNRATED|THEATRICAL'
    r'|BLURAY|BLU[-.]RAY|BDRIP|BRRIP'
    r'|WEB[-.]?DL|WEBRIP|HDRIP'
    r'|DVDRIP|DVDSCR|HDCAM|HDTS'
    r'|MULTI|VOSTFR|VOST|VF|VO|VFF|VIP|RAW|TRUEFRENCH|FRENCH'
    r')(?!\w)',
    caseSensitive: false,
  );
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
    base = base.replaceAll(_reDolby, '');        // multi-mots en premier
    base = base.replaceAll(_reQualityTags, '');
    base = base.replaceAll(_reLangTags, '');
    base = base.replaceAll(_reLangParens, ' '); // (FR), (AR), (VOST FR), (MUET)…
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
      label = label.replaceAll(_reDolby, '');    // multi-mots en premier
      label = label.replaceAll(_reAllTags, '');
      label = label.replaceAll(_reLangParens, ' ');
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

  /// Désérialisation depuis le cache JSON — aucune regex, lecture directe des champs pré-calculés.
  factory TitleMetadata.fromJson(Map<String, dynamic> j) => TitleMetadata(
    rawTitle:      j['r']  as String,
    baseTitle:     j['b']  as String,
    year:          j['y']  as String?,
    seasonNumber:  j['s']  as int?,
    episodeNumber: j['e']  as int?,
    quality:       j['q']  as String?,
    languages:     (j['l'] as List?)?.cast<String>() ?? const [],
    versionLabel:  j['v']  as String?,
  );

  Map<String, dynamic> toJson() => {
    'r': rawTitle,
    'b': baseTitle,
    if (year          != null) 'y': year,
    if (seasonNumber  != null) 's': seasonNumber,
    if (episodeNumber != null) 'e': episodeNumber,
    if (quality       != null) 'q': quality,
    if (languages.isNotEmpty)  'l': languages,
    if (versionLabel  != null) 'v': versionLabel,
  };
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
  /// Identifiant du compte source — nécessaire pour les credentials de lecture et le merge multi-comptes.
  final String accountId;
  /// Catégorie M3U extraite des séparateurs provider (ex: "ACTION", "3D") — alimenté par §1c.
  final String? category;

  const M3uEntry({
    required this.url,
    required this.type,
    required this.title,
    required this.accountId,
    this.logoUrl,
    this.streamId,
    this.tvgId,
    this.catchupDays,
    this.catchupSource,
    this.groupTitle,
    this.category,
  });

  bool get supportsCatchup => catchupDays != null && catchupDays! > 0;

  String get rawTitle    => title.rawTitle;
  String get displayName => title.baseTitle;
  bool   get isSerie     => type == M3uContentType.series;
  String? get saison     => title.seasonNumber?.toString().padLeft(2, '0');
  String? get episode    => title.episodeNumber?.toString().padLeft(2, '0');

  factory M3uEntry.fromJson(Map<String, dynamic> j) => M3uEntry(
    url:           j['u']   as String,
    type:          M3uContentType.values[j['t'] as int],
    title:         TitleMetadata.fromJson(j['ti'] as Map<String, dynamic>),
    accountId:     j['aid'] as String,
    logoUrl:       j['l']   as String?,
    streamId:      j['sid'] as int?,
    tvgId:         j['tid'] as String?,
    catchupDays:   j['cd']  as int?,
    catchupSource: j['cs']  as String?,
    groupTitle:    j['g']   as String?,
    category:      j['cat'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'u':   url,
    't':   type.index,
    'ti':  title.toJson(),
    'aid': accountId,
    if (logoUrl       != null) 'l':   logoUrl,
    if (streamId      != null) 'sid': streamId,
    if (tvgId         != null) 'tid': tvgId,
    if (catchupDays   != null) 'cd':  catchupDays,
    if (catchupSource != null) 'cs':  catchupSource,
    if (groupTitle    != null) 'g':   groupTitle,
    if (category      != null) 'cat': category,
  };
}
