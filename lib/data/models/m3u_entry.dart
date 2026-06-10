enum M3uContentType { movie, series, tv }

/// Métadonnées complètes extraites d'un titre M3U (qualité, année, langues, etc.).
class TitleMetadata {
  final String rawTitle;
  final String baseTitle;
  /// §23b — Clé de REGROUPEMENT pré-calculée : minuscules + toute ponctuation
  /// réduite en espace ("M.A.S.H" → "m a s h", "L'affaire X" → "l affaire x").
  /// Distincte de [baseTitle] qui conserve la ponctuation pour l'AFFICHAGE.
  /// Permet la fusion cross-listes même quand les providers ponctuent
  /// différemment, sans dégrader le titre montré à l'utilisateur.
  final String groupKey;
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
    this.groupKey = '',
    this.year,
    this.seasonNumber,
    this.episodeNumber,
    this.quality,
    this.languages = const [],
    this.versionLabel,
  });

  /// §23b — Normalisation de la clé de regroupement (unicode-aware : les
  /// lettres accentuées sont CONSERVÉES, seule la ponctuation saute).
  static final _reKeyNorm = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
  static String computeGroupKey(String title) =>
      title.toLowerCase().replaceAll(_reKeyNorm, ' ').trim();

  // Patterns compilés une seule fois pour toute la durée de l'app.
  static final _reSeason       = RegExp(r's\s*(\d{1,2})\s*e\s*(\d{1,2})', caseSensitive: false);
  // §Ultimate — format épisode alternatif "NNxNN" (ex: "01x01" = saison 1
  // épisode 1), présent dans certaines playlists (titres "… S01 … 01x01 …").
  // Bornes anti-faux-positifs : `\d{1,2}` borné + pas de chiffre adjacent
  // (`(?<!\d)…(?!\d)`) → ne matche PAS "1920x1080" ni les codecs "x264".
  // ⚠️ Utilisé UNIQUEMENT pour extraire les numéros saison/épisode ; JAMAIS
  // pour la classification (sinon une chaîne TV "ARENA SPORT 1x2" deviendrait
  // une série). La classification reste sur `_reSeason` strict (voir m3u_parser).
  static final _reSeasonAlt    = RegExp(r'(?<!\d)(\d{1,2})\s*x\s*(\d{1,2})(?!\d)', caseSensitive: false);
  static final _reYear         = RegExp(r'\b(19|20)\d{2}\b');
  static final _reQ4K          = RegExp(r'\b(4k|uhd|2160p)\b', caseSensitive: false);
  static final _reQFhd         = RegExp(r'\b(fhd|1080p)\b', caseSensitive: false);
  static final _reQHd          = RegExp(r'\b(hd|720p)\b', caseSensitive: false);
  static final _reQSd          = RegExp(r'\b(sd|480p)\b', caseSensitive: false);
  static final _reLangMulti    = RegExp(r'\bmulti\b', caseSensitive: false);
  static final _reLangVostfr   = RegExp(r'\bvostfr\b', caseSensitive: false);
  static final _reLangVf       = RegExp(r'\b(vf|vff|truefrench|french)\b', caseSensitive: false);

  // §23 — Préfixe provider en BLOC : gère les formes composées observées sur
  // les listes réelles (PLATINIUM & co) que l'ancien `^\|[A-Z0-9\s]+\|` ratait :
  //   |FR|            simple (déjà géré avant)
  //   |FR-4K|         tiret (qualité dans le préfixe)
  //   |FR-4K DV|      tiret + espace + tag
  //   |LEG.|          point (legendado PT)
  //   |VO-LEG.|       combiné
  //   |VO|STFR|       DOUBLE pipe (lu comme une suite de segments)
  //   |LIGUE 1+|      chiffres + symbole +
  // Forme générale : une suite de segments `XXX|` (charset MAJ/chiffres/
  // espace/./+/-, 1-12 chars) ouverte par un pipe. Le charset exclut les
  // minuscules pour ne pas mordre un vrai titre contenant un pipe.
  static final _rePrefix       = RegExp(r'^\s*\|(?:[A-Z0-9 .+\-]{1,12}\|)+\s*');
  static final _reLabelPrefix  = RegExp(r'^\s*\|(?:[A-Z0-9 .+\-]{1,12}\|)+');

  // §23 — Suffixe "_sub" (liste VOD : "Incredibles 2_sub", "Nancy_sub") :
  // marqueur sous-titres du provider, à retirer du titre de base.
  static final _reSubSuffix    = RegExp(r'[_\s]+subs?\s*$', caseSensitive: false);

  // §23 — Tags qualité en exposants Unicode (live : "NATIONAL GEO ᶠᴴᴰ").
  // Normalisés vers leur équivalent ASCII AVANT toute détection.
  static const _superscripts = {
    'ᶠᴴᴰ': ' FHD', 'ᴴᴰ': ' HD', 'ˢᴰ': ' SD', '⁴ᴷ': ' 4K', 'ᵁᴴᴰ': ' UHD',
  };

  // §23 — VOSTFR éclaté dans le préfixe : `|VO|STFR|` → langue VOSTFR.
  static final _reVoStfr       = RegExp(r'\|\s*VO\s*\|\s*STFR\s*\|', caseSensitive: false);

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

  // §23 — `VF\d?` couvre aussi les variantes numérotées "VF2" (liste VOD :
  // "[MULTi VF2]") qui survivaient dans le titre de base.
  static final _reLangTags     = RegExp(r'\b(MULTI|VOSTFR|VOST|VF\d?|VO|VFF|VIP|RAW|TRUEFRENCH|FRENCH)\b', caseSensitive: false);

  // Codes langue/version dans parenthèses : (FR), (EN), (AR), (MULTI), (VOST FR), (MUET)…
  // Placé après _reQualityTags pour ne pas interférer avec (4K), (3D) etc. déjà retirés.
  static final _reLangParens   = RegExp(r'[\(\[]\s*[A-Z]{2,6}(?:\s+[A-Z]{2,6})?\s*[\)\]]', caseSensitive: false);

  static final _reYearClean    = RegExp(r'\(?(19|20)\d{2}\)?');
  // §23b — Paires de parenthèses/crochets vidées par le strip des tags
  // ("[4K DV HDR MULTi]" → "[ ]") : à effacer du titre d'affichage.
  static final _reEmptyBrackets = RegExp(r'[\(\[]\s*[\)\]]');
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
    r'|MULTI|VOSTFR|VOST|VF\d?|VO|VFF|VIP|RAW|TRUEFRENCH|FRENCH'
    r')(?!\w)',
    caseSensitive: false,
  );
  static final _reTrimStart    = RegExp(r'^[ \t\-_.\(\)\[\]]+');
  static final _reTrimEnd      = RegExp(r'[ \t\-_.\(\)\[\]]+$');
  // §23b — Trim du TITRE D'AFFICHAGE : ne mange PAS les parenthèses/crochets
  // (sinon "Totally Killer (Dezesseis Facadas)" perdait sa fermante — les
  // paires vides résiduelles sont déjà traitées par _reEmptyBrackets).
  static final _reTrimBaseStart = RegExp(r'^[ \t\-_.]+');
  static final _reTrimBaseEnd   = RegExp(r'[ \t\-_.]+$');

  factory TitleMetadata.parse(String rawTitle) {
    // §23 — Pré-normalisation : superscripts Unicode → ASCII (live "GEO ᶠᴴᴰ")
    // pour que la détection qualité/le nettoyage fonctionnent dessus.
    String work = rawTitle;
    for (final e in _superscripts.entries) {
      if (work.contains(e.key)) work = work.replaceAll(e.key, e.value);
    }
    final lower = work.toLowerCase();

    final seasonMatch   = _reSeason.firstMatch(work);
    // Fallback NNxNN (ex: "01x01") UNIQUEMENT pour le format série signé par un
    // marqueur "S\d" co-présent (§Ultimate : "… S01 … 01x01 …"). Cette double
    // condition évite de capter le "NxN" d'un vrai titre de film ("4x4",
    // "10x10") ou de chaîne ("2x2", "NDTV 24x7", "ARENA SPORT 1x2") → zéro
    // régression sur les titres dont le NxN fait partie du nom.
    final altMatch      = (seasonMatch == null && _reSeasonFb.hasMatch(rawTitle))
        ? _reSeasonAlt.firstMatch(rawTitle)
        : null;
    final epMatch       = seasonMatch ?? altMatch;
    final seasonNumber  = epMatch != null ? int.tryParse(epMatch.group(1) ?? '') : null;
    final episodeNumber = epMatch != null ? int.tryParse(epMatch.group(2) ?? '') : null;
    final year          = _reYear.firstMatch(rawTitle)?.group(0);

    String? quality;
    if (_reQ4K.hasMatch(lower))       { quality = '4K'; }
    else if (_reQFhd.hasMatch(lower)) { quality = 'FHD'; }
    else if (_reQHd.hasMatch(lower))  { quality = 'HD'; }
    else if (_reQSd.hasMatch(lower))  { quality = 'SD'; }

    final langs = <String>[];
    if (_reLangMulti.hasMatch(lower))  langs.add('MULTI');
    // §23 — VOSTFR : forme compacte ("vostfr") OU éclatée dans le préfixe
    // PLATINIUM (`|VO|STFR|`).
    if (_reLangVostfr.hasMatch(lower) || _reVoStfr.hasMatch(work)) {
      langs.add('VOSTFR');
    }
    if (_reLangVf.hasMatch(lower))     langs.add('VF');

    String base = work;
    base = base.replaceAll(_rePrefix, '');
    base = base.replaceAll(_reSubSuffix, '');
    // §23 — Coupe au marqueur SxxExx recalculé SUR base (post-préfixe).
    // L'ancien code réutilisait l'index calculé sur rawTitle, décalé dès que
    // le préfixe était retiré → coupe au mauvais endroit sur les préfixes longs.
    final seasonInBase = _reSeason.firstMatch(base);
    if (seasonInBase != null) {
      base = base.substring(0, seasonInBase.start).trim();
    } else if (altMatch != null) {
      // §Ultimate — altMatch implique un marqueur "S\d" co-présent. On coupe le
      // titre de base à ce marqueur → donne un nom propre, ex:
      // "… (MULTI) S01 |FR| Les Soprano 01x01 …" → "Les Soprano".
      final sFb = _reSeasonFb.firstMatch(base);
      if (sFb != null) {
        base = base.substring(0, sFb.start).trim();
      }
    }
    base = base.replaceAll(_reDolby, '');        // multi-mots en premier
    base = base.replaceAll(_reQualityTags, '');
    base = base.replaceAll(_reLangTags, '');
    base = base.replaceAll(_reLangParens, ' '); // (FR), (AR), (VOST FR), (MUET)…
    base = base.replaceAll(_reYearClean, '');
    // §23b — La PONCTUATION INTERNE est CONSERVÉE pour l'affichage
    // ("M.A.S.H", "Cape Fear - Les Nerfs à vif", "Narcos: Mexico").
    // L'ancien `_rePunct → espace` produisait "M A S H" à l'écran. Le
    // matching cross-listes insensible à la ponctuation est désormais porté
    // par [groupKey] (voir computeGroupKey). On ne retire ici que les
    // artefacts laissés par le strip des tags : paires de parenthèses/
    // crochets VIDES ("Michael [ ]" après retrait de "[4K DV HDR MULTi]").
    base = base.replaceAll(_reEmptyBrackets, ' ');
    base = base.replaceAll(_reSeasonClean, ' ');
    base = base.replaceAll(_reSpaces, ' ').trim();
    base = base.replaceAll(_reTrimBaseStart, '').replaceAll(_reTrimBaseEnd, '');
    if (base.isEmpty) {
      // §23b — Fallback RÉPARÉ : l'ancien `length < 2` rejetait les titres
      // légitimes d'1 caractère (séries "H", "V") et retombait sur le titre
      // BRUT (préfixe `|FR|` + année inclus) → clé "|fr| h (1998)" → tuile
      // moche + zéro fusion. Nouveau repli : version post-préfixe/année,
      // ponctuation conservée ; brut seulement en dernier recours.
      var fb = work
          .replaceAll(_rePrefix, '')
          .replaceAll(_reYearClean, '')
          .replaceAll(_reSpaces, ' ')
          .trim();
      fb = fb.replaceAll(_reTrimBaseStart, '').replaceAll(_reTrimBaseEnd, '');
      base = fb.isNotEmpty ? fb : work.trim();
    }

    String? versionLabel;
    if (base.isNotEmpty) {
      String label = work;
      label = label.replaceAll(RegExp(RegExp.escape(base), caseSensitive: false), '');
      label = label.replaceAll(_reLabelPrefix, '');
      label = label.replaceAll(_reSubSuffix, '');
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
      groupKey: computeGroupKey(base),
      year: year,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      quality: quality,
      languages: langs,
      versionLabel: versionLabel,
    );
  }

  /// Désérialisation depuis le cache JSON — aucune regex, lecture directe des
  /// champs pré-calculés (le `groupKey` absent d'un vieux cache est recalculé).
  factory TitleMetadata.fromJson(Map<String, dynamic> j) => TitleMetadata(
    rawTitle:      j['r']  as String,
    baseTitle:     j['b']  as String,
    groupKey:      j['k']  as String? ?? computeGroupKey(j['b'] as String),
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
    'k': groupKey,
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

  // §23 (schema v5) — Métadonnées riches issues de la JSON API `player_api.php`.
  // Disponibles uniquement quand la playlist vient du pipeline JSON direct
  // (XtreamCatalogParser) ; null sur le fallback get.php. Permettent à
  // DetailsPage d'afficher synopsis/note/genre SANS clé TMDB.
  /// ID TMDB fourni par le provider (string brute, ex: "506971"). Films + séries.
  final String? tmdbId;
  /// Synopsis (séries uniquement — la liste VOD ne le transporte pas).
  final String? plot;
  /// Genres bruts provider (ex: "Science-Fiction / Action / Drame").
  final String? genre;
  /// Casting brut provider (noms séparés par des virgules).
  final String? castNames;
  /// Note /10 (champ `rating` provider).
  final double? rating;
  /// Date de sortie ISO (ex: "2018-04-13").
  final String? releaseDate;
  /// Première image backdrop (séries — `backdrop_path[0]`).
  final String? backdropUrl;

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
    this.tmdbId,
    this.plot,
    this.genre,
    this.castNames,
    this.rating,
    this.releaseDate,
    this.backdropUrl,
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
    tmdbId:        j['tm']  as String?,
    plot:          j['p']   as String?,
    genre:         j['ge']  as String?,
    castNames:     j['ca']  as String?,
    rating:        (j['ra'] as num?)?.toDouble(),
    releaseDate:   j['rd']  as String?,
    backdropUrl:   j['bd']  as String?,
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
    if (tmdbId        != null) 'tm':  tmdbId,
    if (plot          != null) 'p':   plot,
    if (genre         != null) 'ge':  genre,
    if (castNames     != null) 'ca':  castNames,
    if (rating        != null) 'ra':  rating,
    if (releaseDate   != null) 'rd':  releaseDate,
    if (backdropUrl   != null) 'bd':  backdropUrl,
  };
}
