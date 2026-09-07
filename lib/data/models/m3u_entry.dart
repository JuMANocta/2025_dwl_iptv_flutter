import 'package:aetherStream/core/utils/string_pool.dart';

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

  /// §providerTag — Marqueur de tête du fournisseur (`|FR| TF1`, `US| CNN`).
  ///
  /// Le plus souvent un code pays/langue (FR, US, IT, RU…), parfois une
  /// rubrique du bouquet (PPV, XXX, DSTV, 24/7-AR). **Ce n'est JAMAIS une
  /// qualité** — c'est tout le point de ce champ : §xenoFormat versait ce
  /// marqueur dans [versionLabel], un fourre-tout que l'UI lit comme une
  /// qualité, d'où le « Regarder · FR » vu à l'écran. Le typer à part permet
  /// de garder l'information (elle distingue deux versions d'un même titre)
  /// sans la faire passer pour ce qu'elle n'est pas.
  final String? providerTag;

  bool get isSeriesEpisode => seasonNumber != null && episodeNumber != null;

  /// §watchContext — Libellé court « S01 E04 » si saison + épisode connus,
  /// sinon null. Sert au badge contextuel du player (et autres affichages).
  String? get seasonEpisodeLabel => isSeriesEpisode
      ? 'S${seasonNumber!.toString().padLeft(2, '0')} '
          'E${episodeNumber!.toString().padLeft(2, '0')}'
      : null;

  /// §watchContext — Qualité affichable avec défaut « FHD » quand aucun tag
  /// n'a été détecté dans le nom (plus parlant que « Standard » / aucun badge).
  String get qualityOrDefault => quality ?? 'FHD';

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
    this.providerTag,
  });

  /// §23b — Normalisation de la clé de regroupement (unicode-aware : les
  /// lettres accentuées sont CONSERVÉES, seule la ponctuation saute).
  static final _reKeyNorm = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
  static String computeGroupKey(String title) =>
      foldAccents(title.toLowerCase()).replaceAll(_reKeyNorm, ' ').trim();

  /// §searchAccents — Replie les caractères accentués sur leur lettre de base
  /// (`é`→`e`, `ç`→`c`, `ù`→`u`…).
  ///
  /// **Pourquoi c'est dans la CLÉ et pas dans la recherche.** Le filtre
  /// comparait `displayName.toLowerCase().contains(requête)` : taper
  /// « piece montee » ne trouvait donc pas « Pièce Montée ». Mesuré sur les
  /// listes réelles : **18 % des titres portent au moins un accent** — près
  /// d'un titre sur cinq était inatteignable sans clavier accentué, ce que
  /// personne ne fait, et surtout pas à la télécommande.
  ///
  /// ⚠️ Replier à la volée était exclu : la recherche parcourt 320 000 entrées
  /// à chaque frappe. En le faisant **au parse**, dans une clé déjà calculée et
  /// déjà stockée, le repli ne coûte rien à l'exécution et **aucune mémoire
  /// supplémentaire**.
  ///
  /// ⚠️ Effet de bord voulu mais MODESTE : deux listes qui écrivent le même
  /// titre avec et sans accents fusionnent enfin. Mesuré : +91 titres au mieux
  /// (PLATINIUM ∩ XENO), soit ~0,5 %. **Ce n'est pas ce gain qui justifie le
  /// changement de schéma** — c'est la recherche.
  ///
  /// ⚠️ La table est volontairement explicite plutôt qu'une normalisation
  /// Unicode NFD : Dart n'expose pas NFD sans dépendance, et une table couvre
  /// exactement les langues des catalogues (français, espagnol, portugais,
  /// italien, allemand, turc, nordique).
  static String foldAccents(String input) {
    if (!_reAccented.hasMatch(input)) return input; // cas courant : rien à faire
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final c = String.fromCharCode(rune);
      buffer.write(_accentFolding[c] ?? c);
    }
    return buffer.toString();
  }

  /// Court-circuit : la très grande majorité des titres n'a aucun accent, on
  /// évite de reconstruire la chaîne pour rien.
  static final _reAccented = RegExp(r'[^\x00-\x7F]');

  static const Map<String, String> _accentFolding = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a',
    'ă': 'a', 'ą': 'a',
    'ç': 'c', 'ć': 'c', 'č': 'c', 'ĉ': 'c',
    'ď': 'd', 'đ': 'd',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ĕ': 'e', 'ė': 'e',
    'ę': 'e', 'ě': 'e',
    'ĝ': 'g', 'ğ': 'g', 'ġ': 'g', 'ģ': 'g',
    'ĥ': 'h',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ĩ': 'i', 'ī': 'i', 'į': 'i',
    'ı': 'i',
    'ĵ': 'j',
    'ķ': 'k',
    'ł': 'l', 'ĺ': 'l', 'ļ': 'l', 'ľ': 'l',
    'ñ': 'n', 'ń': 'n', 'ņ': 'n', 'ň': 'n',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o',
    'ŏ': 'o', 'ő': 'o',
    'ŕ': 'r', 'ř': 'r',
    'ś': 's', 'ş': 's', 'š': 's', 'ŝ': 's',
    'ţ': 't', 'ť': 't', 'ŧ': 't',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ũ': 'u', 'ū': 'u', 'ŭ': 'u',
    'ů': 'u', 'ű': 'u', 'ų': 'u',
    'ŵ': 'w',
    'ý': 'y', 'ÿ': 'y', 'ŷ': 'y',
    'ź': 'z', 'ż': 'z', 'ž': 'z',
    'æ': 'ae', 'œ': 'oe', 'ß': 'ss', 'þ': 'th', 'ð': 'd',
  };

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
  // §camQuality — Rips de salle : HDTS (TeleSync), HDCAM, CAMRIP, TELECINE,
  // DVDSCR. C'EST une qualité — et la plus basse — mais aucune des quatre
  // regex de résolution ne la voyait : `\bhd\b` ne matche pas « HDTS » (pas de
  // frontière de mot après « HD »), donc `Spider-Man … |HDTS]` ressortait sans
  // qualité du tout. ~190 titres réels sur les 4 listes.
  //
  // ⚠️ `TS` et `TC` NUS sont volontairement exclus : trop de faux positifs sur
  // de vrais mots de titres. On ne garde que les formes non ambiguës.
  static final _reQCam         = RegExp(
    r'\b(hdts|hdcam|camrip|cam|telesync|telecine|dvdscr)\b',
    caseSensitive: false,
  );
  static final _reQ4K          = RegExp(r'\b(4k|uhd|2160p)\b', caseSensitive: false);
  static final _reQFhd         = RegExp(r'\b(fhd|1080p)\b', caseSensitive: false);
  static final _reQHd          = RegExp(r'\b(hd|720p)\b', caseSensitive: false);
  static final _reQSd          = RegExp(r'\b(sd|480p)\b', caseSensitive: false);
  static final _reLangMulti    = RegExp(r'\bmulti\b', caseSensitive: false);
  static final _reLangVostfr   = RegExp(r'\bvostfr\b', caseSensitive: false);
  static final _reLangVf       = RegExp(r'\b(vf|vff|truefrench|french)\b', caseSensitive: false);
  /// §legLang — « Legendado » (portugais : sous-titré). Mesuré sur une liste
  /// réelle : **3 215 entrées**, TOUJOURS en préfixe, sous six formes —
  /// `|LEG.|` (1 801), `|VO-LEG.|` (1 356), `|VO-LEG|` (51), `|LEG|` (3),
  /// `|VO.LEG.|` (2), `|4K-LEG.|` (1). C'est une LANGUE, au même titre que
  /// MULTI / VOSTFR / VF, et elle n'en était pas une : le contenu lusophone
  /// n'avait donc aucune pastille et rien ne le distinguait d'une VO.
  ///
  /// ⚠️ Frontières obligatoires des deux côtés : sans elles, **LEGO** Marvel
  /// Super Heroes devient du portugais sous-titré (contre-exemple gardé en
  /// test). Les séparateurs admis autour du jeton sont ceux réellement
  /// observés dans les préfixes : espace, `-`, `.`, `|`.
  static final _reLangLeg = RegExp(
    r'(?:^|[\s.\-|])LEG(?:ENDAD[OA]|ENDA)?\.?(?=$|[\s.\-|])',
    caseSensitive: false,
  );

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
  // §parseAudit2026-06-30 — caseSensitive: false ajouté : des providers réels
  // encodent le préfixe en casse mixte (`|FR-4k|`, `|Fr-4K DV|`, `|AR-4k|`,
  // `|it|`) — avant ce fix, la MOINDRE minuscule dans le préfixe faisait
  // échouer TOUT le bloc (pas juste la lettre fautive), laissant le préfixe
  // brut visible dans le titre affiché et empêchant la fusion cross-listes
  // avec la variante correctement casée d'un autre provider.
  // ⚠️ Le 2e segment (optionnel) doit couvrir DEUX formes réelles distinctes
  // sans avaler un vrai mot du titre :
  //   (a) collé, SANS espace  → `|VO|STFR|` (segments partageant le pipe
  //       médian, contenu ne commençant PAS par un espace)
  //   (b) séparé par un espace suivi d'un NOUVEAU `|` → `|DE| |DE|` (code
  //       région dupliqué, le 2e bloc rouvre son propre pipe)
  // Un texte-avant-pipe non contraint avalait "Midterm" dans le cas réel
  // `|AR-4k| Midterm | 2025 | ميد تيرم` (espace + mot de 7+ caractères suivi
  // d'un pipe, syntaxiquement indiscernable d'un (a)/(b) mal bornés). En
  // interdisant à (a) de commencer par un espace ET en exigeant que (b) rouvre
  // un `|` immédiatement après l'espace, aucune des deux formes ne matche
  // "Midterm" (espace suivi directement d'une lettre, pas d'un pipe) →
  // préservé. Plafond 6 sur le contenu du 2e segment (couvre "STFR"/"DE"/
  // "US"), 12 sur le 1er (couvre `|LIGUE 1+|`/`|FR-4K DV|`).
  static final _rePrefix       = RegExp(
    r'^\s*\|[A-Za-z0-9 .+\-]{1,12}\|'
    r'(?:[A-Za-z0-9.+\-][A-Za-z0-9 .+\-]{0,5}\||\s+\|[A-Za-z0-9 .+\-]{1,6}\|)?'
    r'\s*',
    caseSensitive: false,
  );

  // §xenoFormat — Préfixe à pipe FERMANT SEUL : `FR| Lanterns`, `US| CNN HD`.
  //
  // Forme du fournisseur xenoIptv, que `_rePrefix` ratait entièrement puisqu'il
  // exige un pipe OUVRANT. Résultat : `FR| Lanterns` gardait sa clé `fr lanterns`
  // et ne fusionnait jamais avec le `Lanterns` des autres listes → doublon.
  // Mesuré sur cette liste : 62 % des films, 66 % des séries, 97 % des chaînes.
  //
  // ⚠️ **L'ESPACE APRÈS LE PIPE EST LE GARDE-FOU, PAS UN DÉTAIL.** Sans elle, la
  // règle mange de vrais titres : PREMIUM contient `Sneakers|BRUTX|(FR) FHD 2022`
  // et `Requin|BRUTX| (FR) FHD 2021`, où le TITRE est « Sneakers »/« Requin ».
  // Mesures sur les 4 dumps réels :
  //     forme « XXX| » suivie d'une espace : 48 956 (xenoIptv) + 8 (PLATINIUM)
  //                                          + 0 (PREMIUM) + 0 (VOD)
  //     forme « XXX| » SANS espace         : 18 + 0 + **7** + 0
  // Les 7 sans espace sont exactement les titres à ne pas casser. Les 18 ratés
  // (`KU|Aro Drama`, `CAR|(FLOW) CBN HD`) sont sciemment abandonnés : les
  // rattraper obligerait à accepter `Pone|BRUTX|`, donc à détruire un titre.
  //
  // Le charset autorise `/` et `-` pour couvrir les codes composés réels
  // (`24/7-AR`), et la casse est libre (`Fr|` existe dans les données).
  static final _reNewPrefix    = RegExp(
    r'^\s*[A-Za-z0-9/.+\-]{1,8}\|[ \t]+',
    caseSensitive: false,
  );
  static final _reLabelPrefix  = RegExp(
    r'^\s*\|[A-Za-z0-9 .+\-]{1,12}\|'
    r'(?:[A-Za-z0-9.+\-][A-Za-z0-9 .+\-]{0,5}\||\s+\|[A-Za-z0-9 .+\-]{1,6}\|)?',
    caseSensitive: false,
  );

  // §23 — Suffixe "_sub" (liste VOD : "Incredibles 2_sub", "Nancy_sub") :
  // marqueur sous-titres du provider, à retirer du titre de base.
  static final _reSubSuffix    = RegExp(r'[_\s]+subs?\s*$', caseSensitive: false);

  // §23 — Tags qualité en exposants Unicode (live : "NATIONAL GEO ᶠᴴᴰ").
  // Normalisés vers leur équivalent ASCII AVANT toute détection.
  // §parseAudit2026-06-30 — ᴴ²⁶⁵/ᴴ²⁶⁴ (codec HEVC/H264 en exposant) ajoutés :
  // 568 occurrences réelles mesurées (chaînes italiennes RAI/Sky), non
  // couvertes par les 5 combos précédents → restaient en garbage visible
  // dans baseTitle (les caractères exposants sont \p{L}/\p{N} valides, donc
  // JAMAIS nettoyés par computeGroupKey).
  // §invisibleLead — Caractères de contrôle bidi / espaces exotiques trouvés en
  // tête de titre dans les dumps réels (LRM, RLM, BOM, ZWSP, NBSP, isolats).
  static final _reInvisibleLead =
      RegExp(r'^[\u200B\u200E\u200F\u202A-\u202E\u2066-\u2069\uFEFF\u00A0]+');

  static const _superscripts = {
    'ᶠᴴᴰ': ' FHD', 'ᴴᴰ': ' HD', 'ˢᴰ': ' SD', '⁴ᴷ': ' 4K', 'ᵁᴴᴰ': ' UHD',
    'ᴴ²⁶⁵': ' H265', 'ᴴ²⁶⁴': ' H264',
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
    r'4K|UHD|2160p|1080p|720p|480p|FHD|HD|SD|IMAX'
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
  // §tagResidue — Jetons AJOUTÉS le 2026-08-30, tous mesurés sur le corpus
  // rafraîchi (353 475 titres) : `SUBAR` 705, `LIGHT` 270, `SUB-AR` 144,
  // `VQF` 8, plus `LEG`/`LEGENDADO` (sous-titres portugais) qui polluaient la
  // pastille de qualité (« 4K · - LEG »).
  //
  // ⚠️ `LEG` est court et dangereux : le corpus contient `LEGO Marvel Super
  // Heroes`. La frontière `\b` suffit ici (LEGO ≠ LEG), mais ce titre reste le
  // contre-exemple à faire tourner à chaque modification.
  static final _reLangTags     = RegExp(
      r'\b(MULTI|VOSTFR|VOST|VF\d?|VO|VFF|VQF|VFQ|VIP|RAW|TRUEFRENCH|FRENCH'
      r'|SUB[-_]?AR|SUBAR|SUBS?|AUDIO|LEGENDADO|LEGENDA|LEG|LIGHT'
      r'|MUTLI)\b',
      caseSensitive: false);

  // Codes langue/version entre délimiteurs : (FR), (EN), (AR), (MULTI), (VOST FR)…
  //
  // ⚠️ **§tagResidue (2026-08-30) — cette regex était un piège.** Elle s'écrivait
  // `[A-Z]{2,6}` en `caseSensitive: false`, ce qui ne veut PAS dire « un code en
  // majuscules » mais **n'importe quel mot de 2 à 6 lettres**. Elle mangeait donc
  // `[Light]`, `(Suite)`, et surtout `[REC]` — qui EST le titre du film. Le titre
  // devenait vide, et le repli rendait alors le titre BRUT, tags compris :
  // `[REC] (2007) [MULTi]` s'affichait tel quel. La liste est désormais FERMÉE.
  //
  // ⚠️ Ne pas y remettre de joker : ce qui doit disparaître sans figurer ici est
  // pris en charge par [_cleanTagGroups], qui raisonne sur « le strip a-t-il
  // entamé ce groupe ? » au lieu de deviner sur la longueur d'un mot.
  static final _reLangParens   = RegExp(
      r'[\(\[]\s*(?:FR|EN|ES|IT|DE|PT|NL|RU|TR|PL|AR|JP|KR|CN|BR|US|UK|CA|BE'
      r'|CH|MA|DZ|TN|GR|SE|NO|DK|FI|HU|RO|CZ|IN|VF\d?|VO|VOST|VOSTFR|VFF|VQF'
      r'|VFQ|MULTI|MUET|SUB|SUBAR|LEG|LEGENDADO)'
      r'(?:\s+(?:FR|EN|AR|SUB|VF\d?|VO|VOST|VOSTFR|MULTI))?\s*[\)\]]',
      caseSensitive: false);

  // §xenoFormat — Tag composé `[MULTI-SUB]` et sa famille.
  //
  // ⚠️ **Doit passer AVANT `_reLangTags`**, sinon celui-ci retire `MULTI` seul et
  // laisse `[-SUB]` dans le titre : `Lanterns [MULTI-SUB]` donnait la clé
  // `lanterns sub`, qui ne fusionnait pas avec `lanterns` — le doublon signalé.
  //
  // Volontairement CIBLÉ sur les formes réellement mesurées plutôt que
  // généralisé aux séparateurs : une règle « jetons séparés par un tiret entre
  // parenthèses » mangerait aussi un vrai intitulé du genre « (Jean-Pierre) ».
  // Couverture : `MULTI-SUB` (10 331 occurrences), `MULTI-SUB-AUDIO` (584),
  // `MULTI-SUB/AUDIO` (56), `MULTI-AUDIO` (30), `MULTI_SUB` (18).
  static final _reMultiSubTag  = RegExp(
    r'[\(\[]\s*MULTI[\-_/](?:SUB|AUDIO)(?:[\-_/](?:SUB|AUDIO))?\s*[\)\]]',
    caseSensitive: false,
  );

  // §parseAudit2026-06-30 — Tag "(50 FPS)"/"(60FPS)" (chaînes sport type BEIN
  // SPORTS, quelques VOD) : 35 occurrences réelles mesurées. `_reLangParens`
  // exige un contenu 100% alphabétique donc ne matche jamais un chiffre en tête.
  static final _reFpsParens    = RegExp(r'[\(\[]\s*\d{2,3}\s*fps\s*[\)\]]', caseSensitive: false);

  // §midYear — Une année AVEC ses délimiteurs éventuels. Distinguer `(2025)` de
  // `2025` est ce qui permet de savoir si l'année est une date de sortie ou un
  // morceau du titre (cf. [_isReleaseDate]).
  static final _reYearToken = RegExp(
    r'[(\[]\s*(?:19|20)\d{2}\s*[)\]]|(?<!\d)(?:19|20)\d{2}(?!\d)');
  static final _reAlnum = RegExp(r'[\p{L}\p{N}]', unicode: true);
  static final _reYearClean    = RegExp(r'\(?(19|20)\d{2}\)?');
  // §23b — Paires de parenthèses/crochets vidées par le strip des tags
  // ("[4K DV HDR MULTi]" → "[ ]") : à effacer du titre d'affichage.
  static final _reEmptyBrackets = RegExp(r'[\(\[]\s*[\)\]]');
  static final _reSeasonClean  = RegExp(r'S\s*\d{1,2}\s*E\s*\d{1,2}', caseSensitive: false);
  static final _reSpaces       = RegExp(r'\s+');
  static final _reSeasonFb     = RegExp(r'S\s*\d{1,2}', caseSensitive: false);
  static final _reAllTags      = RegExp(
    r'(?<!\w)('
    r'4K|UHD|2160p|1080p|720p|480p|FHD|HD|SD|IMAX'
    r'|HEVC|H\.?265|H\.?264|X\.?265|X\.?264|AVC|AV1'
    r'|AAC|EAC3|AC3|DTS(?:[-.](?:HD|MA|X))?|TrueHD|TRUEHD'
    r'|HDR10\+|HDR10|HDR|DV|HLG|SDR|ATMOS|DOLBY'
    r'|REMUX|PROPER|REPACK|EXTENDED|UNRATED|THEATRICAL'
    r'|BLURAY|BLU[-.]RAY|BDRIP|BRRIP'
    r'|WEB[-.]?DL|WEBRIP|HDRIP'
    r'|DVDRIP|DVDSCR|HDCAM|HDTS'
    r'|MULTI|VOSTFR|VOST|VF\d?|VO|VFF|VQF|VFQ|VIP|RAW|TRUEFRENCH|FRENCH'
    r'|SUB[-_]?AR|SUBAR|SUBS?|AUDIO|LEGENDADO|LEGENDA|LEG|LIGHT'
    // §tagResidue — `MUTLI` est une COQUILLE du fournisseur pour `MULTi`
    // (`Tous en scène 2 (FHD MUTLi)`). Elle est dans le corpus, donc elle
    // existe ; la corriger ici coûte un mot et évite une vignette orpheline.
    r'|MUTLI'
    r')(?!\w)',
    caseSensitive: false,
  );
  /// §parseSpeed (2026-09-06) — Était construite À CHAQUE titre dans
  /// [parse] (une regex Unicode compilée 153 000 fois : 4 % du parsing).
  static final _reHasWord = RegExp(r'[\p{L}]{2,}', unicode: true);

  /// §parseSpeed — Rogne les deux bouts sans regex ; même jeu de caractères
  /// que les `_reTrim*` correspondantes.
  static String _trimChars(String v, String chars) {
    int start = 0;
    int end = v.length;
    while (start < end && chars.contains(v[start])) {
      start++;
    }
    while (end > start && chars.contains(v[end - 1])) {
      end--;
    }
    return (start == 0 && end == v.length) ? v : v.substring(start, end);
  }

  static const String _trimSetBase = ' \t-_.';
  static const String _trimSetLabel = ' \t-_.()[]';

  /// §parseSpeed — `replaceAll(_reSpaces, ' ')` ne change rien quand la chaîne
  /// n'a que des espaces ASCII simples : on ne lance la regex que s'il y a
  /// un blanc d'une autre nature (tabulation, insécable, espace Unicode) ou
  /// deux blancs de suite. Le jeu est celui de `\s` en ECMAScript.
  static bool _needsSpaceCollapse(String v) {
    int prev = -1;
    for (int i = 0; i < v.length; i++) {
      final int c = v.codeUnitAt(i);
      final bool ws = c == 32 ||
          (c >= 9 && c <= 13) ||
          c == 0xA0 ||
          c == 0x1680 ||
          (c >= 0x2000 && c <= 0x200A) ||
          c == 0x2028 ||
          c == 0x2029 ||
          c == 0x202F ||
          c == 0x205F ||
          c == 0x3000 ||
          c == 0xFEFF;
      if (ws && (c != 32 || prev == 32)) return true;
      prev = c;
    }
    return false;
  }

  static String _collapseSpaces(String v) =>
      _needsSpaceCollapse(v) ? v.replaceAll(_reSpaces, ' ') : v;

  // §23b — Trim du TITRE D'AFFICHAGE : ne mange PAS les parenthèses/crochets
  // (sinon "Totally Killer (Dezesseis Facadas)" perdait sa fermante — les
  // paires vides résiduelles sont déjà traitées par _reEmptyBrackets).

  /// §orphanBracket — Retire les parenthèses/crochets SANS partenaire.
  ///
  /// Certains fournisseurs referment un tag avec un délimiteur qu'ils n'ont
  /// jamais ouvert (`Spider-Man : Brand New Day - 2026 |HDTS]` : un pipe pour
  /// ouvrir, un crochet pour fermer). Une fois `HDTS` puis les pipes retirés,
  /// il reste un `]` seul — que rien ne ramasse : [_reEmptyBrackets] exige une
  /// PAIRE, et [_reTrimBaseEnd] épargne volontairement les crochets (§23b,
  /// sinon « Totally Killer (Dezesseis Facadas) » perdrait sa fermante).
  ///
  /// D'où ce nettoyage à la pince : on n'enlève QUE les délimiteurs non
  /// appariés, les paires légitimes restent intactes. Effet de bord utile : le
  /// titre affiché redevient une sous-chaîne exacte du titre brut, donc le
  /// calcul de `versionLabel` (une soustraction littérale) retrouve prise — un
  /// résidu ici laissait TOUT le titre dans le libellé (« FR Spider-Man… »).

  // §tagResidue (2026-08-30) — Un groupe de délimiteurs se traite EN BLOC.
  //
  // **Le défaut.** Le strip de tags travaille jeton par jeton sur toute la
  // chaîne. Quand un groupe contient un jeton INCONNU, il n'est ni vide ni
  // intact : `[MULTi VO/VQF]` devient `[ /VQF]`, `[4K HDR10+ Dolby A/V]`
  // devient `[ A/V]`. `_reEmptyBrackets` ne les ramasse pas — il exige une
  // paire ne contenant que des espaces. Le débris part alors dans le titre
  // affiché ET dans `groupKey`, donc le titre ne fusionne plus entre listes :
  // ce sont les doublons signalés. Mesuré : **1 266 titres** sur 353 475.
  //
  // **La règle.** Un groupe est soit un bloc de tags — on le retire
  // ENTIÈREMENT — soit du texte — on n'y touche PAS. Jamais de demi-strip.
  // Il est jugé « bloc de tags » si le strip l'a ENTAMÉ et que le reste ne
  // contient plus de mot.
  //
  // ⚠️ La garantie tient dans la première condition : un groupe que le strip
  // n'a pas touché est laissé strictement intact. `(Hold The Dark)`,
  // `(Dezesseis Facadas)`, `(mé)chant`, `(3D)` (§keep3d), les `(H)`/`(F)` des
  // chaînes US ne peuvent pas être emportés — aucun jeton connu dedans.
  //
  // ⚠️ La seconde condition n'est PAS « c'est court » : `(The HD Story)` est
  // entamé par `HD` et laisserait `The Story`, 8 caractères. On exige donc
  // qu'aucun mot d'au moins 3 lettres contenant une minuscule ne subsiste.
  static final _reGroupToken = RegExp(r'[\p{L}\p{N}]+', unicode: true);
  static final _reYearOnlyGroup = RegExp(r'^\s*(?:19|20)\d{2}\s*$');

  static bool _isTagGroup(String whole, String inner) {
    if (inner.trim().isEmpty) return true;
    // ⚠️ Les groupes que les regex DÉDIÉES savent déjà retirer entièrement
    // doivent être reconnus ici, sinon le masque les leur soustrait : `(FR)`
    // n'est pas dans `_reAllTags`, il est dans `_reLangParens`. Sans ce test,
    // `2067 (FR) FHD 2020` redonnait `2067 (FR)` — régression de §yearTitle.
    if (_reLangParens.hasMatch(whole) ||
        _reFpsParens.hasMatch(whole) ||
        _reMultiSubTag.hasMatch(whole)) {
      return true;
    }
    var rest = inner
        .replaceAll(_reDolby, ' ')
        .replaceAll(_reAllTags, ' ')
        // ⚠️ `_reQualityTags` n'est PAS inclus dans `_reAllTags` : il porte seul
        // `DIRECTORS?\.?CUT`. Sans lui, `(Directors.Cut)` passait pour de la
        // prose et restait dans le titre affiché.
        .replaceAll(_reQualityTags, ' ')
        .replaceAll(_reYearClean, ' ');
    if (rest == inner) return false; // rien retiré → ce n'est pas un bloc de tags
    var alnum = 0;
    for (final m in _reGroupToken.allMatches(rest)) {
      final t = m.group(0)!;
      alnum += t.length;
      if (t.length >= 3 && t.toUpperCase() != t) return false; // un vrai mot
    }
    return alnum <= 10;
  }

  // ⚠️ Sentinelles en zone à usage privé : ni lettre, ni chiffre, ni espace, ni
  // délimiteur. Aucune des regex de la chaîne (`\b`, `[A-Z]`, `\d`, `\s`,
  // `[\p{L}\p{N}]`) ne peut les accrocher, donc un groupe masqué traverse le
  // strip sans une égratignure.
  static const String _maskOpen = '';
  static const String _maskUnit = '';
  static const String _maskClose = '';

  /// Retire les groupes de tags, **masque** les autres.
  ///
  /// ⚠️ Le masquage n'est pas un détail : sans lui, un groupe qu'on a décidé de
  /// GARDER se fait quand même entamer par les `replaceAll` globaux qui suivent
  /// — `(MULTI AUDIO StadiumFX)` devenait `( AUDIO StadiumFX)`. « Soit on retire
  /// tout, soit on ne touche à rien » n'a de sens que si le « rien » est protégé.
  /// Les groupes conservés sont restaurés par [_unmaskGroups].
  static String _cleanTagGroups(String value, List<String> kept) {
    final out = StringBuffer();
    var i = 0;
    while (i < value.length) {
      final c = value[i];
      if (c == '(' || c == '[') {
        final close = c == '(' ? ')' : ']';
        final end = value.indexOf(close, i + 1);
        // Pas de fermante → délimiteur mal formé côté fournisseur : on laisse
        // faire `_dropOrphanBrackets` (§orphanBracket), qui sait le traiter.
        if (end > i) {
          final whole = value.substring(i, end + 1);
          final inner = value.substring(i + 1, end);
          // ⚠️ Un groupe réduit à une ANNÉE est laissé VERBATIM : ni retiré, ni
          // masqué. C'est `_stripYears` qui doit le voir — la règle §midYear /
          // §midYearFix décide « date de sortie ou morceau du titre » en
          // regardant précisément ces délimiteurs. Le retirer ici cassait
          // `|FR| Valensole 1965 (2025)` : privé de son `(2025)`, le `1965`
          // devenait une année nue en fin de titre, donc une date, et le titre
          // perdait son nombre.
          if (_reYearOnlyGroup.hasMatch(inner)) {
            out.write(whole);
            i = end + 1;
            continue;
          }
          if (_isTagGroup(whole, inner)) {
            out.write(' ');
          } else {
            kept.add(whole);
            out..write(_maskOpen)
               ..write(_maskUnit * kept.length)
               ..write(_maskClose);
          }
          i = end + 1;
          continue;
        }
      }
      out.write(c);
      i++;
    }
    return out.toString();
  }

  static String _unmaskGroups(String value, List<String> kept) {
    if (kept.isEmpty) return value;
    var out = value;
    for (var i = kept.length; i >= 1; i--) {
      out = out.replaceAll(
          '$_maskOpen${_maskUnit * i}$_maskClose', kept[i - 1]);
    }
    return out;
  }

  static String _dropOrphanBrackets(String value) {
    final orphans = <int>{};
    final round = <int>[];
    final square = <int>[];
    for (var i = 0; i < value.length; i++) {
      switch (value[i]) {
        case '(':
          round.add(i);
        case '[':
          square.add(i);
        case ')':
          round.isEmpty ? orphans.add(i) : round.removeLast();
        case ']':
          square.isEmpty ? orphans.add(i) : square.removeLast();
      }
    }
    orphans.addAll(round); // ouvrants jamais refermés
    orphans.addAll(square);
    if (orphans.isEmpty) return value;
    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      if (!orphans.contains(i)) buffer.write(value[i]);
    }
    return buffer.toString();
  }

  /// §yearTitle — Retire les années d'un titre, SAUF une qui l'ouvre.
  ///
  /// L'ancien `replaceAll(_reYearClean, '')` effaçait tout : sur
  /// `2067 (FR) FHD 2020`, il emportait le titre en même temps que la date, ne
  /// laissant que des tags — d'où l'affichage « (FR HD) ».
  static String _stripYears(String value) => value.replaceAllMapped(
      _reYearToken, (m) => _isReleaseDate(value, m) ? '' : m.group(0)!);

  // §midYear — Suffixe « PART n » : c'est un marqueur de découpage du
  // fournisseur, pas la suite du titre (`… FHD 2024 PART 1`). Sans lui,
  // l'année passait pour être au milieu du titre et la date était perdue.
  static final _rePartSuffix =
      RegExp(r'\bPART\s*\d+\b', caseSensitive: false);

  // §midYear — Deux séparateurs identiques que seule l'année séparait.
  static final _reDupSeparator = RegExp(r'([-.])\s*\1');

  // §midYear — Groupe entre crochets/parenthèses qui ne contient PAS d'année :
  // c'est de la métadonnée fournisseur (`[Prelims]`, `[VOSTFR]`, `[4K]`), pas
  // la suite du titre. On ne peut pas se contenter de la liste des tags connus :
  // les fournisseurs en inventent (et les écrivent avec des typos).
  //
  // ⚠️ Un groupe QUI contient une année est conservé — sinon, sur
  // `Île d'Amrum, 1945 (2025)`, le « (2025)` disparaîtrait du reste et 1945
  // passerait pour la date de sortie.
  static final _reBracketGroup = RegExp(r'[\(\[][^()\[\]]*[\)\]]');
  static String _dropMetaBrackets(String value) =>
      value.replaceAllMapped(_reBracketGroup,
          (m) => _reYear.hasMatch(m.group(0)!) ? m.group(0)! : ' ');

  /// §midYear — Une année fait-elle partie du TITRE, ou est-ce la date ?
  ///
  /// Règle, tirée des dumps réels : une date de sortie est **entre
  /// délimiteurs** (`(2025)`, `[2025]`) ou **nue en fin de chaîne**
  /// (`Adios Amigos | 2016`, 16 128 cas). Une année nue au MILIEU appartient au
  /// titre — 4 603 cas, sans contre-exemple : `Valensole 1965`,
  /// `Île d'Amrum, 1945`, `WWE SummerSlam 2025 - Sunday`,
  /// `Roland-Garros, une édition 2025 inoubliable`. L'ancienne règle les
  /// amputait toutes (`Star Ac Tour 2026, le concert` → `Star Ac Tour , le
  /// concert`).
  ///
  /// Une année qui OUVRE le titre reste le titre (§yearTitle : `1917`) — sauf
  /// si elle est délimitée, auquel cas c'est bien une date (`(2023)ملك الحلبة`).
  static bool _isReleaseDate(String source, Match m) {
    final token = m.group(0)!;
    if (token.startsWith('(') || token.startsWith('[')) return true;
    // Délimiteur non apparié juste avant/après (`(2020 - DOC)`).
    final before = source.substring(0, m.start).trimRight();
    if (before.endsWith('(') || before.endsWith('[')) return true;
    final after = source.substring(m.end);
    final afterTrimmed = after.trimLeft();
    if (afterTrimmed.startsWith(')') || afterTrimmed.startsWith(']')) {
      return true;
    }
    // Encadrée par des PIPES : dans ces playlists le pipe est un séparateur de
    // CHAMPS, jamais de la prose (`Midterm | 2025 | ميد تيرم` = titre, année,
    // titre arabe). C'est le seul contre-exemple réel à la règle « année nue au
    // milieu = titre » — et il se reconnaît à son délimiteur.
    if (before.endsWith('|') || afterTrimmed.startsWith('|')) return true;
    // Même raisonnement pour un SÉPARATEUR SYMÉTRIQUE : `Lees Baghdad - 2020 -
    // لص بغداد` (titre, année, titre arabe) ou `Wrong.Place.2022.lati`. Le
    // séparateur doit encadrer l'année DES DEUX CÔTÉS — sinon la règle mange
    // `WWE SummerSlam 2025 - Sunday`, où le tiret ne suit que l'année.
    for (final sep in const ['-', '.']) {
      if (before.endsWith(sep) && afterTrimmed.startsWith(sep)) return true;
    }
    if (m.start == 0) return false; // le titre EST l'année
    // Nue : date de sortie seulement si plus rien de signifiant ne suit. Les
    // tags peuvent encore être présents à ce stade (`Film 2020 MULTi`) — on les
    // neutralise avant de juger.
    //
    // ⚠️ Cette liste doit couvrir TOUT ce que le pipeline de `baseTitle` retire
    // AVANT `_stripYears` — sinon les deux appelants de cette fonction jugent
    // la même année différemment : `_stripYears` reçoit un titre déjà nettoyé,
    // `_extractYear` le titre BRUT. C'est exactement ce qui s'est produit en
    // oubliant `_reMultiSubTag` : sur `The Whisper Man - 2026 [MULTI-SUB]`,
    // `_reAllTags` retirait `MULTI` mais laissait `-SUB]`, donc « du texte
    // suit » → année ignorée. 94 % des films d'une liste perdaient leur date,
    // et avec elle la désambiguïsation des recherches TMDB.
    final rest = _dropMetaBrackets(after)
        .replaceAll(_rePartSuffix, ' ')
        .replaceAll(_reMultiSubTag, ' ')
        .replaceAll(_reSubSuffix, ' ')
        .replaceAll(_reAllTags, '')
        .replaceAll(_reDolby, '')
        .replaceAll(_reLangParens, ' ')
        .replaceAll(_reFpsParens, ' ');
    return !_reAlnum.hasMatch(rest);
  }

  /// §yearTitle — Année de SORTIE, en ignorant une année qui ouvre le titre.
  ///
  /// [source] est le titre brut (préfixe compris) : on retire le préfixe ici
  /// pour savoir ce qui est réellement « en tête » — sur `|FR| 2067 (2020)`,
  /// c'est bien 2067 qui ouvre le titre, pas le code pays.
  ///
  /// Renvoie `null` quand le seul candidat est ce nombre de tête : le titre EST
  /// l'année (`1917`), il n'y a pas de date de sortie à afficher.
  static String? _extractYear(String source) {
    final core = source
        .replaceFirst(_rePrefix, '')
        .replaceFirst(_reNewPrefix, '')
        .trimLeft();
    for (final m in _reYearToken.allMatches(core)) {
      if (_isReleaseDate(core, m)) {
        // Le jeton peut porter ses délimiteurs : on ne rend que les 4 chiffres.
        return _reYear.firstMatch(m.group(0)!)?.group(0);
      }
    }
    return null;
  }

  // §providerTag — Bruit de QUALITÉ à retirer d'un marqueur de tête. Sous-
  // ensemble strict de `_reAllTags` : résolutions, HDR, codecs — jamais les
  // langues, qui sont l'information utile d'un marqueur.
  static final _reTagNoise = RegExp(
    r'(?<!\w)(4K|UHD|2160P|1080P|720P|480P|FHD|HD|SD|HDR10\+|HDR10|HDR|DV|HLG'
    r'|SDR|HEVC|H\.?265|H\.?264|X\.?265|X\.?264|AVC|AV1)(?!\w)',
    caseSensitive: false,
  );

  // §labelLeak — Ponctuation de BORD d'un mot, ignorée pour la comparaison :
  // le titre affiché perd son point final (`_reTrimBaseEnd`) là où le titre
  // brut le garde, donc « Franz K. » vs « Franz K » ne s'appariaient pas et le
  // « K » ressortait en libellé de version. 1 154 titres réels.
  static final _reWordEdge = RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true);
  static bool _isAsciiAlnum(int c) =>
      (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122);

  /// §parseSpeed — Voie rapide ASCII : les bords se rognent sans regex (pour
  /// de l'ASCII pur, `\p{L}\p{N}` = lettres et chiffres ASCII). Un jeton
  /// non-ASCII garde la regex Unicode.
  static String _wordKey(String token) {
    for (int i = 0; i < token.length; i++) {
      if (token.codeUnitAt(i) > 127) {
        return token.replaceAll(_reWordEdge, '').toLowerCase();
      }
    }
    int start = 0;
    int end = token.length;
    while (start < end && !_isAsciiAlnum(token.codeUnitAt(start))) {
      start++;
    }
    while (end > start && !_isAsciiAlnum(token.codeUnitAt(end - 1))) {
      end--;
    }
    return token.substring(start, end).toLowerCase();
  }

  /// §parseSpeed — Découpe sur les blancs : `split(' ')` quand il n'y a que
  /// des espaces ASCII simples (le cas courant), la regex sinon. Les jetons
  /// vides sont ignorés par l'appelant dans les deux cas.
  static Iterable<String> _splitWords(String v) =>
      _needsSpaceCollapse(v) ? v.split(_reSpaces) : v.split(' ');

  /// §labelLeak — Retire de [label] les mots de [base], en différence de
  /// multiensemble (ordre indifférent, casse ignorée).
  ///
  /// Robuste à tout ce qui casse une comparaison littérale : espaces
  /// recollapsés, année ou tag retirés au MILIEU du titre. Ce qui subsiste est
  /// ce que le titre ne contenait pas — la définition même d'un libellé de
  /// version.
  static String _subtractWords(String label, String base) {
    final pending = _splitWords(base)
        .map(_wordKey)
        .where((t) => t.isNotEmpty)
        .toList();
    final kept = <String>[];
    for (final token in _splitWords(label)) {
      final key = _wordKey(token);
      // Miette de ponctuation isolée (« , », « - ») : jamais un libellé de
      // version, et elle survivrait à toute soustraction. On la jette.
      if (key.isEmpty) continue;
      final i = pending.indexOf(key);
      if (i >= 0) {
        pending.removeAt(i); // consommé : un mot du titre ne compte qu'une fois
        continue;
      }
      kept.add(token);
    }
    return kept.join(' ');
  }

  /// §providerTag — Isole le marqueur de tête du fournisseur.
  ///
  /// Couvre les DEUX formes reconnues par le parseur : encadrée (`|FR| TF1`,
  /// historique) et à pipe fermant seul (`FR| CNN`, §xenoFormat). Elles étaient
  /// traitées de façon incohérente — la première perdait le code, la seconde le
  /// laissait filer dans `versionLabel` — donc deux versions d'un même titre
  /// n'étaient distinguables que dans un cas sur deux.
  ///
  /// Sur un préfixe à plusieurs segments (`|FR|VOST|`), seul le PREMIER est
  /// retenu : les suivants sont des langues/qualités, déjà extraites ailleurs.
  /// §parseSpeed — Le préfixe est reconnu UNE fois dans [parse] (pour la
  /// langue LEG) et réutilisé ici, au lieu de deux `matchAsPrefix` de plus.
  static String? _providerTagFrom(String? prefix) {
    if (prefix == null) return null;
    var tag = prefix.trim();
    while (tag.startsWith('|')) {
      tag = tag.substring(1);
    }
    final cut = tag.indexOf('|');
    if (cut >= 0) tag = tag.substring(0, cut);
    // §providerTag — On retire du marqueur les tokens de QUALITÉ/HDR/codec :
    // `|FR-4K DV|` doit donner « FR », pas « FR-4K DV ». Sans ça le même
    // fournisseur produisait trois marqueurs distincts (FR, FR-4K, FR-4K DV,
    // ~4 200 titres) qui fragmentaient l'affichage — et la résolution est de
    // toute façon déjà extraite dans [quality].
    //
    // ⚠️ Volontairement PAS `_reAllTags` : il emporterait VO, MULTI, VF, qui
    // sont ici de vrais marqueurs de version (4 528 titres en `VO|`) et que
    // rien d'autre ne capterait.
    tag = tag.replaceAll(_reTagNoise, ' ');
    // §legLang — « LEG » est une LANGUE depuis 2026-09-05, pas un marqueur de
    // fournisseur : le laisser ici affichait DEUX pastilles pour la même
    // information. Retiré du marqueur, il reste dans `languages`.
    tag = tag.replaceAll(_reLangLeg, ' ');
    tag = tag.replaceAll(_reSpaces, ' ').trim();
    // ⚠️ **Rogner les deux BOUTS, pas seulement la fin.** `|4K-LEG.|` perdait
    // son `4K` (bruit de qualité) et laissait « -LEG » : le tiret de TÊTE
    // survivait, et la vignette portait deux pastilles distinctes — `LEG` et
    // `-LEG` — que le `Set` de `media_chips` ne pouvait pas dédoublonner.
    // C'est ce que l'utilisateur voyait sur « Mission : Impossible ».
    while (tag.isNotEmpty &&
        (tag.endsWith('-') || tag.endsWith('.') ||
         tag.startsWith('-') || tag.startsWith('.'))) {
      tag = (tag.endsWith('-') || tag.endsWith('.'))
          ? tag.substring(0, tag.length - 1).trim()
          : tag.substring(1).trim();
    }
    tag = tag.toUpperCase();
    return tag.isEmpty ? null : tag;
  }

  /// §ramDiet — [pool] interne les champs à faible cardinalité (qualité, année,
  /// libellé de version, marqueur fournisseur, langues) : quelques centaines de
  /// valeurs distinctes pour des centaines de milliers d'entrées. Facultatif —
  /// par défaut [StringPool.none] rend chaque valeur telle quelle, donc les
  /// appels isolés (fiche détail, tests) sont inchangés.
  /// §parseSpeed — Chronos par étape de [parse], pour le banc
  /// (`test/parse_bench_test.dart`). Inactifs en production (`profileStages`
  /// faux : aucun `Stopwatch` créé).
  static bool profileStages = false;
  static final Map<String, int> stageUs = <String, int>{};

  factory TitleMetadata.parse(String rawTitle,
      [StringPool pool = StringPool.none]) {
    final Stopwatch? sw = profileStages ? (Stopwatch()..start()) : null;
    int lapAt = 0;
    void lap(String k) {
      if (sw == null) return;
      final int now = sw.elapsedMicroseconds;
      stageUs[k] = (stageUs[k] ?? 0) + (now - lapAt);
      lapAt = now;
    }
    // §23 — Pré-normalisation : superscripts Unicode → ASCII (live "GEO ᶠᴴᴰ")
    // pour que la détection qualité/le nettoyage fonctionnent dessus.
    String work = rawTitle;
    // §invisibleLead — Marques de direction/BOM en TÊTE (U+200E, U+202B…) :
    // Dart ne les considère pas comme des espaces, donc le `^\s*` des regex de
    // préfixe ne les franchit pas et le préfixe n'est plus reconnu du tout
    // (`‎|FR-4K DV| On s'attache ?` gardait « FR- » dans son titre). 9 titres
    // réels, mais le symptôme est illisible sans inspection hexadécimale.
    work = work.replaceAll(_reInvisibleLead, '');
    for (final e in _superscripts.entries) {
      if (work.contains(e.key)) work = work.replaceAll(e.key, e.value);
    }
    final lower = work.toLowerCase();
    lap('A prenorm');

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
    // §yearTitle — Une année EN TÊTE de titre n'est PAS une date de sortie.
    //
    // Le film « 2067 » s'affichait « (FR HD) » : sur `2067 (FR) FHD 2020`,
    // `firstMatch` retenait 2067 comme année, puis le nettoyage effaçait par
    // `replaceAll` le titre ET la vraie année — il ne restait que les tags.
    // 215 titres réels commencent ainsi par un nombre de forme année (`1917`,
    // `1992`, `2046`, `2001 Maniacs`, `1941 (1979)`…) et, sur TOUS, le nombre
    // de tête est le titre : la date, elle, est entre parenthèses ou en fin.
    final year = _extractYear(work);
    lap('B saison+annee');

    String? quality;
    // §camQuality — Testé EN PREMIER : sur un rip de salle, la résolution
    // annoncée ne veut rien dire (un « 1080p HDCAM » reste filmé dans une
    // salle). C'est l'information que l'utilisateur doit voir en premier.
    if (_reQCam.hasMatch(lower))      { quality = 'CAM'; }
    else if (_reQ4K.hasMatch(lower))       { quality = '4K'; }
    else if (_reQFhd.hasMatch(lower)) { quality = 'FHD'; }
    else if (_reQHd.hasMatch(lower))  { quality = 'HD'; }
    else if (_reQSd.hasMatch(lower))  { quality = 'SD'; }

    final langs = <String>[];
    if (_reLangMulti.hasMatch(lower))  langs.add('MULTI');
    // §23 — VOSTFR : forme compacte ("vostfr") OU éclatée dans le préfixe
    // PLATINIUM (`|VO|STFR|`).
    // §parseSpeed — Pré-tests par caractère : une regex qui ne peut rien
    // trouver n'est pas lancée. Chaque test est EXACT (le motif exige ce
    // caractère / ce mot), et `base`/`label` ne dérivent de `work` que par
    // retraits : ce que `work` n'a pas, ils ne l'ont pas.
    final bool hasPipe = work.contains('|');
    final bool hasBracket = work.contains('(') || work.contains('[');
    // Une fermante ORPHELINE (« Drishyam 2015) ») n'a pas d'ouvrante : le
    // nettoyage des orphelines regarde les quatre caractères (le filet
    // d'instantané a attrapé ce cas au premier passage).
    final bool hasAnyBracket =
        hasBracket || work.contains(')') || work.contains(']');
    final bool hasDolby = lower.contains('dolby');
    final bool hasFps = lower.contains('fps');
    final bool hasSub = lower.contains('sub');
    final bool hasYearDigits = lower.contains('19') || lower.contains('20');
    final bool hasDupSep = work.contains('-') || work.contains('.');
    if (_reLangVostfr.hasMatch(lower) || (hasPipe && _reVoStfr.hasMatch(work))) {
      langs.add('VOSTFR');
    }
    if (_reLangVf.hasMatch(lower))     langs.add('VF');
    // §legLang — Cherché UNIQUEMENT dans le préfixe `|…|`, jamais dans le
    // titre : « LEGENDA » peut apparaître dans un vrai titre, et le marqueur
    // du fournisseur est toujours en tête.
    final legPrefix = _rePrefix.matchAsPrefix(work)?.group(0) ??
        _reNewPrefix.matchAsPrefix(work)?.group(0);
    if (legPrefix != null && _reLangLeg.hasMatch(legPrefix)) {
      langs.add('LEG');
    }
    lap('C qualite+langues');

    String base = work;
    base = base.replaceAll(_rePrefix, '');
    base = base.replaceAll(_reNewPrefix, ''); // §xenoFormat
    if (hasSub) base = base.replaceAll(_reSubSuffix, '');
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
    // §tagResidue — EN BLOC, et **AVANT** les strips globaux.
    //
    // ⚠️ L'ordre est la moitié du correctif. Placé après, ce nettoyage arrive
    // sur des groupes déjà vidés (`[ /]`, `[ A/V]`) : il ne peut plus répondre à
    // sa propre question — « le strip a-t-il entamé ce groupe ? » — puisque le
    // strip est déjà passé. Mesuré : 1 266 résidus avant, 1 266 après. Placé
    // ici, il voit `[MULTi VQF/VO]` entier et tranche.
    lap('D1 prefixes+saison');
    final keptGroups = <String>[];
    base = _cleanTagGroups(base, keptGroups);
    lap('D2 cleanTagGroups');
    if (hasBracket) base = base.replaceAll(_reMultiSubTag, ' '); // §xenoFormat — avant _reLangTags
    if (hasDolby) base = base.replaceAll(_reDolby, '');        // multi-mots en premier
    base = base.replaceAll(_reQualityTags, '');
    base = base.replaceAll(_reLangTags, '');
    if (hasBracket) base = base.replaceAll(_reLangParens, ' '); // (FR), (AR), (VOST FR), (MUET)…
    if (hasBracket && hasFps) base = base.replaceAll(_reFpsParens, ' ');  // §parseAudit2026-06-30 — (50 FPS), (60FPS)
    lap('D3 tags (6 replaceAll)');
    base = _stripYears(base); // §yearTitle — préserve une année de tête
    lap('D4 stripYears');
    // §midYear — Retirer une année ENCADRÉE par un séparateur laisse les deux
    // délimiteurs collés (`Lees Baghdad - - لص بغداد`, `Wrong.Place..lati`).
    // (`replaceAll` ne fait PAS de rétro-référence en Dart, d'où le Mapped.)
    if (hasDupSep) {
      base = base.replaceAllMapped(_reDupSeparator, (m) => m.group(1)!);
    }
    // §23b — La PONCTUATION INTERNE est CONSERVÉE pour l'affichage
    // ("M.A.S.H", "Cape Fear - Les Nerfs à vif", "Narcos: Mexico").
    // L'ancien `_rePunct → espace` produisait "M A S H" à l'écran. Le
    // matching cross-listes insensible à la ponctuation est désormais porté
    // par [groupKey] (voir computeGroupKey). On ne retire ici que les
    // artefacts laissés par le strip des tags : paires de parenthèses/
    // crochets VIDES ("Michael [ ]" après retrait de "[4K DV HDR MULTi]").
    if (hasBracket) base = base.replaceAll(_reEmptyBrackets, ' ');
    base = base.replaceAll(_reSeasonClean, ' ');
    // §parseAudit2026-06-30 — Tout `|` restant à ce stade n'est JAMAIS un vrai
    // caractère de titre (le seul usage légitime, le préfixe région en tête,
    // est déjà retiré par `_rePrefix`) : SUPPRIMÉ (pas remplacé par un espace)
    // pour reconstituer les mots coupés par une corruption provider amont
    // ("CORP|US| CHRISTI" → "CORPUS CHRISTI", "COLUMB|US|" → "COLUMBUS") et
    // nettoyer les séparateurs pipe résiduels ("All My Life || MULTI" →
    // "All My Life" une fois MULTI retiré). ~6 900 titres réels concernés.
    if (hasPipe) base = base.replaceAll('|', '');
    base = _unmaskGroups(base, keptGroups); // §tagResidue — groupes conservés
    if (hasAnyBracket) base = _dropOrphanBrackets(base); // §orphanBracket
    base = _collapseSpaces(base).trim();
    base = _trimChars(base, _trimSetBase);
    lap('D5 fin base');
    if (base.isEmpty) {
      // §23b — Fallback RÉPARÉ : l'ancien `length < 2` rejetait les titres
      // légitimes d'1 caractère (séries "H", "V") et retombait sur le titre
      // BRUT (préfixe `|FR|` + année inclus) → clé "|fr| h (1998)" → tuile
      // moche + zéro fusion. Nouveau repli : version post-préfixe/année,
      // ponctuation conservée ; brut seulement en dernier recours.
      var fb = _collapseSpaces(work
              .replaceAll(_rePrefix, '')
              .replaceAll(_reNewPrefix, '') // §xenoFormat
              .replaceAll('|', ''))
          .trim();
      fb = _dropOrphanBrackets(fb); // §orphanBracket
      fb = _trimChars(fb, _trimSetBase);
      base = fb.isNotEmpty ? fb : work.trim();
    }

    // §parseSpeed — la clé de la base, calculée UNE fois (elle servait deux
    // fois : le test du libellé, puis le champ).
    final String groupKey = computeGroupKey(base);
    String? versionLabel;
    if (base.isNotEmpty) {
      String label = work;
      label = label.replaceAll(_reLabelPrefix, '');
      // §providerTag — Le marqueur de tête part dans son propre champ :
      // le laisser ici le faisait afficher comme une QUALITÉ.
      label = label.replaceAll(_reNewPrefix, '');
      if (hasSub) label = label.replaceAll(_reSubSuffix, '');
      if (hasYearDigits) label = label.replaceAll(_reYearClean, '');
      // §tagResidue — Même traitement EN BLOC que `baseTitle`, sinon on nettoie
      // le titre et le débris ressort dans la pastille de version : mesuré,
      // `Superman (2025) [4K HDR10+ Dolby A/V]` donnait `label=A/V`. C'est
      // exactement le motif de §labelLeak.
      if (hasBracket) label = label.replaceAll(_reMultiSubTag, ' '); // §xenoFormat
      if (hasDolby) label = label.replaceAll(_reDolby, '');    // multi-mots en premier
      label = label.replaceAll(_reAllTags, '');
      if (hasBracket) label = label.replaceAll(_reLangParens, ' ');
      if (hasBracket && hasFps) label = label.replaceAll(_reFpsParens, ' '); // §parseAudit2026-06-30
      if (hasPipe) label = label.replaceAll('|', '');            // §parseAudit2026-06-30
      // §labelLeak — Soustraction du titre par MOTS, et non par sous-chaîne
      // littérale. L'ancien `replaceAll(RegExp.escape(base))` supposait que le
      // titre nettoyé soit resté une sous-chaîne EXACTE du brut : un double
      // espace (« Flicka 3  Meilleures amies »), une année en MILIEU de titre
      // (« Star Ac Tour 2026, le concert ») ou un tag interne (« Winx Club
      // 3D: … ») suffisaient à la faire échouer — et le titre ENTIER restait
      // dans le libellé. 11 375 des 11 389 libellés restants étaient dans ce
      // cas.
      //
      // ⚠️ Placée EN DERNIER, pas en tête : sur le titre encore brut, les mots
      // portent leur ponctuation collée (« 2026, ») et ne correspondent à aucun
      // mot du titre nettoyé — la soustraction laissait alors des miettes.
      lap('E1 label replaceAll');
      label = _subtractWords(label, base);
      lap('E2 subtractWords');
      label = _trimChars(label, _trimSetLabel);
      label = _collapseSpaces(label.trim());
      // §labelLeak — Filet final : un libellé de VERSION ne répète jamais le
      // titre. Il reste quelques tokenisations impossibles à apparier mot à mot
      // (titres arabes dont l'année est collée au 1er mot : « (2023)ملك الحلبة »
      // — 11 titres réels). Plutôt qu'une règle de plus, on vérifie l'invariant
      // sur la clé normalisée : si le libellé est déjà dans le titre, ce n'est
      // pas un libellé.
      // §tagResidue — Un libellé fait uniquement de DÉBRIS n'en est pas un.
      // `Superman (2025) [4K HDR10+ Dolby A/V]` laissait `label=A/V`, qui
      // s'affichait tel quel sur la pastille de version. On exige au moins un
      // mot de 2 lettres — ce qui laisse passer `Directors.Cut` (§labelLeak,
      // le seul libellé authentique du corpus) et rejette `A/V`, `/`, `-`.
      final hasWord = _reHasWord.hasMatch(label);
      lap('E3 hasWord');
      if (label.isNotEmpty &&
          hasWord &&
          !groupKey.contains(computeGroupKey(label))) {
        versionLabel = label;
      }
      lap('E4 groupKey label');
    }

    // §ramDiet — `rawTitle`, `baseTitle` et `groupKey` ne sont PAS internés :
    // ils sont quasiment uniques par entrée, la table ne ferait que doubler
    // l'empreinte. Seuls les champs à vocabulaire fermé passent par le pool.
    final String? providerTag = _providerTagFrom(legPrefix);
    lap('F providerTag');
    return TitleMetadata(
      rawTitle: rawTitle,
      baseTitle: base,
      groupKey: groupKey,
      year: pool.of(year),
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      quality: pool.of(quality),
      languages: pool.ofList(langs),
      versionLabel: pool.of(versionLabel),
      providerTag: pool.of(providerTag),
    );
  }

  /// Désérialisation depuis le cache JSON — aucune regex, lecture directe des
  /// champs pré-calculés (le `groupKey` absent d'un vieux cache est recalculé).
  ///
  /// §ramDiet — C'est ICI que l'internement compte le plus : ce chemin est celui
  /// de CHAQUE démarrage (cache disque), là où `parse` ne tourne qu'au premier
  /// chargement d'une liste.
  factory TitleMetadata.fromJson(Map<String, dynamic> j,
          [StringPool pool = StringPool.none]) =>
      TitleMetadata(
    rawTitle:      j['r']  as String,
    baseTitle:     j['b']  as String,
    groupKey:      j['k']  as String? ?? computeGroupKey(j['b'] as String),
    year:          pool.of(j['y'] as String?),
    seasonNumber:  j['s']  as int?,
    episodeNumber: j['e']  as int?,
    quality:       pool.of(j['q'] as String?),
    // §ramDiet — `List<String>.from` et non `.cast<String>()` : `cast` renvoie
    // une VUE qui retient la `List<dynamic>` sortie de `jsonDecode`, donc la
    // liste brute du cache survivait au chargement, une par entrée.
    languages:     _langsFromJson(j['l'], pool),
    versionLabel:  pool.of(j['v'] as String?),
    providerTag:   pool.of(j['p'] as String?),
  );

  static List<String> _langsFromJson(Object? raw, StringPool pool) {
    if (raw is! List || raw.isEmpty) return const [];
    return List<String>.generate(
        raw.length, (i) => pool.of(raw[i] as String)!,
        growable: false);
  }

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
    if (providerTag   != null) 'p': providerTag,
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
  /// §heavyFields — ⚠️ `castNames` (clé JSON `'ca'`) a été RETIRÉ : il était
  /// désérialisé, gardé en mémoire pour chaque entrée, et **lu nulle part**.
  /// Mesuré sur les listes réelles : ~20 octets par entrée, soit ~13 Mo de
  /// heap Dart (UTF-16) sur 323 373 entrées, pour rien. Les anciens caches
  /// contiennent encore la clé `'ca'` : elle est simplement ignorée à la
  /// lecture, aucun changement de `schemaVersion` n'est nécessaire.
  ///
  /// ⚠️ `plot` et `genre`, eux, sont CONSERVÉS malgré leur poids (~79 et
  /// ~6 o/entrée) : ce sont les replis documentés §23b quand TMDB ne rend rien
  /// — ce qui arrive aussi **avec** une clé configurée, quand le titre n'est
  /// pas trouvé. Les décharger ferait disparaître le synopsis dans exactement
  /// les cas où c'est la seule source disponible.
  final String? plot;
  /// §epTitleProvider — Titre d'ÉPISODE fourni par le panel (champ `title` de
  /// `get_series_info`, nettoyé du nom de série/SxxExx). Fallback du nom TMDB
  /// dans la fiche/action sheet/player. Rempli uniquement par `fetchEpisodes`
  /// (épisodes lazy — jamais présent sur les stubs/films).
  final String? episodeTitle;
  /// Genres bruts provider (ex: "Science-Fiction / Action / Drame").
  final String? genre;
  /// Casting brut provider (noms séparés par des virgules).
  /// Note /10 (champ `rating` provider).
  final double? rating;
  /// Date de sortie ISO (ex: "2018-04-13").
  final String? releaseDate;
  /// Première image backdrop (séries — `backdrop_path[0]`).
  final String? backdropUrl;
  /// §newByAdded (schema v8) — Timestamp Unix (secondes) d'ajout au panel Xtream
  /// (champ `added` de l'action VOD). Présent sur TOUTES les listes Xtream →
  /// signal fiable et cross-listes pour la catégorie « New » (récemment ajouté),
  /// bien meilleur que le match texte `group-title` « Récemment ajouté ». Null
  /// sur le fallback get.php / M3U (le format M3U ne transporte pas ce champ).
  final int? addedAt;

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
    this.episodeTitle,
    this.genre,
    this.rating,
    this.releaseDate,
    this.backdropUrl,
    this.addedAt,
  });

  bool get supportsCatchup => catchupDays != null && catchupDays! > 0;

  String get rawTitle    => title.rawTitle;
  String get displayName => title.baseTitle;
  bool   get isSerie     => type == M3uContentType.series;
  String? get saison     => title.seasonNumber?.toString().padLeft(2, '0');
  String? get episode    => title.episodeNumber?.toString().padLeft(2, '0');

  /// §ramDiet — [pool] partage les champs à vocabulaire fermé entre toutes les
  /// entrées d'un même chargement. `accountId` est le cas d'école : une poignée
  /// de valeurs, mais `jsonDecode` en fabriquait une copie neuve par ligne, soit
  /// des centaines de milliers de chaînes identiques et résidentes.
  ///
  /// Non internés à dessein : `url`, `tmdbId`, `plot`, `episodeTitle`,
  /// `backdropUrl`, `logoUrl` — quasi uniques par entrée, la table coûterait
  /// plus qu'elle ne rend.
  factory M3uEntry.fromJson(Map<String, dynamic> j,
          [StringPool pool = StringPool.none]) =>
      M3uEntry(
    url:           j['u']   as String,
    type:          M3uContentType.values[j['t'] as int],
    title:         TitleMetadata.fromJson(j['ti'] as Map<String, dynamic>, pool),
    accountId:     pool.of(j['aid'] as String)!,
    logoUrl:       j['l']   as String?,
    streamId:      j['sid'] as int?,
    tvgId:         j['tid'] as String?,
    catchupDays:   j['cd']  as int?,
    catchupSource: pool.of(j['cs']  as String?),
    groupTitle:    pool.of(j['g']   as String?),
    category:      pool.of(j['cat'] as String?),
    tmdbId:        j['tm']  as String?,
    plot:          j['p']   as String?,
    episodeTitle:  j['et']  as String?,
    genre:         pool.of(j['ge']  as String?),
    rating:        (j['ra'] as num?)?.toDouble(),
    releaseDate:   pool.of(j['rd']  as String?),
    backdropUrl:   j['bd']  as String?,
    addedAt:       j['ad']  as int?,
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
    if (episodeTitle  != null) 'et':  episodeTitle,
    if (genre         != null) 'ge':  genre,
    if (rating        != null) 'ra':  rating,
    if (releaseDate   != null) 'rd':  releaseDate,
    if (backdropUrl   != null) 'bd':  backdropUrl,
    if (addedAt       != null) 'ad':  addedAt,
  };
}
