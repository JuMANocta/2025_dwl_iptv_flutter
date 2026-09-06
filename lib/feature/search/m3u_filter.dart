import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/services/tmdb_group_alias_service.dart';

/// §Ultimate — Labels de catégorie correspondant à une **région étrangère**
/// (préfixe `|XX|` non-FR : `|IT|`, `|AR|`, `|TR|`…). La home les relègue sous
/// les genres FR (voir `_categoryPriority`). Le contenu `|FR|` / sans préfixe
/// reste rangé par genre.
/// ⚠️ Vocabulaire UNIFIÉ : ces labels doivent être EXACTEMENT ceux émis par le
/// mapper par mots-clés ci-dessous (ITALIEN→'Italie', TURQU→'Turc', INDIA→
/// 'Indien', ANGLAIS/UK→'UK', SCANDINAV→'Scandinavie'…) pour qu'une même région
/// détectée via préfixe `|XX|` (§Ultimate) OU via pays nommé (Premium/VOD) tombe
/// dans LA MÊME catégorie. Vaut donc pour toutes les listes.
// NB : 'USA' et 'UK' sont VOLONTAIREMENT absents → contenu anglophone NON
// relégué (choix user) : il reste au niveau genre (priorité 100). Leurs labels
// existent toujours (via mots-clés / `_foreignRegionByCode`) mais ne sont pas
// poussés en bas.
const Set<String> kForeignRegionLabels = {
  'Coréen', 'Turc', 'Maghrébin', 'Algérie', 'Arabe', 'Indien', 'Ramadan',
  'Allemagne', 'Espagne', 'Italie', 'Russie', 'Brésil', 'Belgique',
  'Pologne', 'Portugal', 'Suisse', 'Scandinavie', 'Tchéquie', 'Croatie',
  'Grèce', 'Albanie', 'Arménie', 'Roumanie', 'Bosnie', 'Canada',
  'Pays-Bas', 'Ex-Yougoslavie', 'Rép. Dominicaine', 'Novidades',
  // §catWords — « SÉRIES ASIATIQUES » (734) et « FILMS ASIE » (231) étaient
  // deux rangées littérales en majuscules, parmi les genres.
  'Asie',
  // §legLang — Le portugais sous-titré se range avec les autres langues
  // étrangères, sous les genres français.
  kLegRegionLabel,
};

const Map<String, String> _foreignRegionByCode = {
  'IT': 'Italie', 'AR': 'Arabe', 'TR': 'Turc', 'DZ': 'Algérie', 'PT': 'Portugal',
  'ES': 'Espagne', 'ESP': 'Espagne', 'US': 'USA', 'UK': 'UK', 'GB': 'UK',
  'EN': 'UK', 'ENG': 'UK',
  'DE': 'Allemagne', 'RU': 'Russie', 'IN': 'Indien', 'NL': 'Pays-Bas',
  'BE': 'Belgique', 'PL': 'Pologne', 'BR': 'Brésil', 'GR': 'Grèce',
  'RO': 'Roumanie', 'AL': 'Albanie', 'AM': 'Arménie', 'HR': 'Croatie',
  'CZ': 'Tchéquie', 'SE': 'Scandinavie', 'NO': 'Scandinavie',
  'DK': 'Scandinavie', 'EX-YU': 'Ex-Yougoslavie', 'DOM': 'Rép. Dominicaine',
};

/// §langFilter — Label "VO sans FR" (préfixes `|VO|` seul, `|LEG.|`,
/// `|VO-LEG.|` = version originale / légendé non-français). Le VOSTFR
/// (`|VO|STFR|`) est EXCLU (gardé comme FR — sous-titres français).
const String kVoRegionLabel = 'VO (non-FR)';

/// §legLang — Portugais **sous-titré** (`|LEG.|`, `|VO-LEG.|`…). Case DISTINCTE
/// de [kVoRegionLabel] : on peut vouloir masquer 3 215 titres lusophones sans
/// masquer toute la VO (demande utilisateur du 2026-09-05).
const String kLegRegionLabel = 'Legendado (sous-titré PT)';

/// §langFilter — Régions/langues que l'utilisateur peut choisir de MASQUER
/// (cases à cocher dans les réglages). Ordre alpha + VO/Legendado en fin.
///
/// ⚠️ **Doit couvrir tout [kForeignRegionLabels]** : une région reléguée en bas
/// de l'accueil mais absente d'ici se voit sans pouvoir se cacher. Sept y
/// manquaient (Bosnie, Canada, Coréen, Ex-Yougoslavie, Ramadan,
/// Rép. Dominicaine, Suisse) — mesuré par `test/category_audit_test.dart`, qui
/// échoue si l'écart réapparaît.
///
/// ⚠️ L'ordre de cette liste EST l'ordre à l'écran (recette du 2026-09-05 :
/// « Arménie » précédait « Albanie », l'œil qui cherche une région dans une
/// liste censée être triée la rate). Alphabétique strict, les deux langues
/// (VO, Legendado) en fin.
const List<String> kHideableRegionLabels = [
  'Albanie', 'Algérie', 'Allemagne', 'Arabe', 'Arménie', 'Asie', 'Belgique',
  'Bosnie', 'Brésil', 'Canada', 'Coréen', 'Croatie', 'Espagne',
  'Ex-Yougoslavie', 'Grèce', 'Indien', 'Italie', 'Maghrébin', 'Novidades',
  'Pays-Bas', 'Pologne', 'Portugal', 'Ramadan', 'Rép. Dominicaine',
  'Roumanie', 'Russie', 'Scandinavie', 'Suisse', 'Tchéquie', 'Turc', 'UK',
  'USA',
  kVoRegionLabel, kLegRegionLabel,
];

/// §langFilter — Régions d'une entrée À DES FINS DE FILTRAGE, déduites du
/// préfixe `|XX|` de son NOM (rawTitle). Vide pour FR / sans préfixe / VOSTFR /
/// Québec (jamais masqués).
///
/// Rend un **ensemble** depuis §legLang : `|VO-LEG.|` est à la fois de la VO et
/// du legendado. Masquer « VO (non-FR) » continue donc de masquer les VO-LEG
/// (comportement d'avant préservé), et masquer « Legendado » seul ne touche pas
/// aux autres VO.
///
/// ⚠️ Le découpage inclut le POINT. Avec `[-\s]` seul, `|4K-LEG.|` donnait le
/// code « 4K » et `|VO.LEG.|` le code « VO.LEG. » : ni l'un ni l'autre n'était
/// reconnu, donc ces titres échappaient au filtre.
Set<String> entryRegionLabels(String rawTitle) {
  final m = RegExp(r'^\s*\|([^|]{1,14})\|').firstMatch(rawTitle);
  if (m == null) return const {}; // pas de préfixe → FR / MULTI → gardé
  final upper = rawTitle.toUpperCase();
  // VOSTFR (éclaté |VO|STFR| ou compact) → gardé (sous-titres FR).
  if (upper.contains('STFR') || upper.contains('VOSTFR')) return const {};
  final firstSeg = m.group(1)!.trim().toUpperCase();
  final tokens = firstSeg.split(RegExp(r'[-\s.]+'))
      .where((t) => t.isNotEmpty)
      .toList();
  if (tokens.isEmpty) return const {};
  final first = tokens.first;
  if (first == 'FR' || first == 'QC') return const {}; // français gardé

  final out = <String>{};
  if (tokens.contains('LEG') ||
      tokens.contains('LEGENDADO') ||
      tokens.contains('LEGENDADA')) {
    out.add(kLegRegionLabel);
    // Historique : ces titres étaient masqués par la case « VO (non-FR) ».
    out.add(kVoRegionLabel);
    return out;
  }
  if (first == 'VO') return {kVoRegionLabel};
  final byCode = _foreignRegionByCode[first];
  return byCode == null ? const {} : {byCode}; // code inconnu → gardé
}

/// Compatibilité : la PREMIÈRE région, ou `null`. Préférer [entryRegionLabels].
String? entryRegionLabel(String rawTitle) {
  final labels = entryRegionLabels(rawTitle);
  return labels.isEmpty ? null : labels.first;
}

/// §langFilter — **Le prédicat unique du filtre régions.** Les trois points
/// d'application (parse M3U, parse JSON, téléchargement Xtream) l'appellent :
/// avant, chacun avait sa copie, et celle du téléchargement avait oublié la
/// voie CATÉGORIE — une région encodée dans le `group-title` et non dans le
/// titre réapparaissait au refresh suivant.
bool isRegionHidden({
  required String name,
  String? groupTitle,
  required Set<String> hidden,
}) {
  if (hidden.isEmpty) return false;
  for (final label in entryRegionLabels(name)) {
    if (hidden.contains(label)) return true;
  }
  final cat = contentCategoryLabel(groupTitle);
  return cat != null && hidden.contains(cat);
}

/// Région étrangère depuis un préfixe `|XX|` en tête de group-title.
/// `FR` (et codes inconnus) → null : le contenu reste rangé par genre.
String? _foreignRegionLabel(String groupTitle) {
  final m = RegExp(r'^\s*\|([^|]{1,8})\|').firstMatch(groupTitle);
  if (m == null) return null;
  final code = m.group(1)!.trim().toUpperCase();
  if (code == 'FR') return null; // natif → genres
  return _foreignRegionByCode[code]; // null si code non mappé → genres/fallback
}

/// §catMeter — D'où vient un libellé de catégorie. Sert à MESURER le rangement
/// (`tool/validate_parse.dart`) : sans cette information, « classé » voulait
/// seulement dire « a reçu un libellé », pas « le bon » — c'est ce qui a laissé
/// passer 51 % des séries dans une seule rangée « Paramount+ ».
enum CategorySource {
  /// Région déduite d'un préfixe `|XX|` ou d'un pays nommé.
  region,

  /// Genre (Action, Comédie, Documentaire…).
  genre,

  /// Plateforme de diffusion (Disney+, Paramount+…) — pas un genre.
  platform,

  /// Format technique (3D, IMAX, 4K HDR) — pas un genre non plus.
  format,

  /// Aucun mot-clé reconnu : le group-title est repris tel quel (tronqué).
  /// C'est l'ensemble OUVERT — chaque valeur nouvelle crée une rangée.
  literal,
}

/// Libellé + provenance. `contentCategoryLabel` n'en garde que le libellé.
typedef CategoryMatch = ({String label, CategorySource source});

/// Libellés qui sont des PLATEFORMES, pas des genres.
const Set<String> kPlatformCategoryLabels = {
  'Disney+', 'Paramount+', 'BrutX', 'Rakuten TV',
  'Netflix', 'Prime Video', 'HBO', 'Apple TV+',
};

/// Libellés qui sont des FORMATS techniques, pas des genres.
const Set<String> kFormatCategoryLabels = {'3D', 'IMAX', '4K HDR', '4K'};

/// Régions nommées qui ne sont pas dans [kForeignRegionLabels] (volontairement
/// non reléguées, cf. commentaire en tête) mais restent des régions.
const Set<String> _kNonRelegatedRegionLabels = {'USA', 'UK'};

/// §catMeter — Classe un libellé déjà calculé. Le classement se fait sur le
/// RÉSULTAT et non dans la cascade : l'ordre des tests reste donc inchangé,
/// et ce refactor ne peut pas modifier le rangement.
CategorySource _sourceOf(String label) {
  if (kPlatformCategoryLabels.contains(label)) return CategorySource.platform;
  if (kFormatCategoryLabels.contains(label)) return CategorySource.format;
  if (kForeignRegionLabels.contains(label) ||
      _kNonRelegatedRegionLabels.contains(label) ||
      label == kVoRegionLabel) {
    return CategorySource.region;
  }
  return CategorySource.genre;
}

/// Retourne un label d'affichage depuis le group-title M3U.
/// Priorité : région étrangère (|XX|) → mappings sémantiques → fallback nettoyage.
String? contentCategoryLabel(String? groupTitle) =>
    contentCategoryMatch(groupTitle)?.label;

/// §catMeter — Comme [contentCategoryLabel], mais dit AUSSI d'où vient le
/// libellé. Utilisé par la mesure ; l'app passe par `contentCategoryLabel`.
CategoryMatch? contentCategoryMatch(String? groupTitle) {
  if (groupTitle == null || groupTitle.isEmpty) return null;

  // §Ultimate — contenu d'une région étrangère → catégorie = la région
  // (regroupé hors des rangées de genre FR). Le |FR| / sans préfixe poursuit
  // vers le classement par genre ci-dessous.
  final foreign = _foreignRegionLabel(groupTitle);
  if (foreign != null) {
    return (label: foreign, source: CategorySource.region);
  }

  // §catFix (2026-09-05) — Normalisation AVANT tout test.
  // ⚠️ L'apostrophe typographique `’` (U+2019) n'est pas l'apostrophe ASCII :
  // le test « FIN D'AN » ne voyait pas `FILMS DE FIN D’ANNÉE` (63 films, qui
  // finissaient en repli littéral). Mesuré le 2026-09-05.
  // §catWords — Et les ACCENTS SONT REPLIÉS avant tout test (É→E, Ç→C, Œ→OE,
  // même table que la clé de recherche, §searchAccents). Mesuré deux fois sur
  // le téléviseur : « THÉÂTRES » puis « THÉATRES » (É, mais A sans circonflexe)
  // restaient des rangées littérales après l'ajout du mot-clé, parce que la
  // graphie du fournisseur n'était jamais EXACTEMENT celle du code. Chaque
  // test de la cascade a sa forme ASCII ; les formes accentuées y restent par
  // lisibilité mais ne sont plus jamais celles qui décident.
  final g = TitleMetadata.foldAccents(groupTitle.toLowerCase())
      .toUpperCase()
      .replaceAll('’', "'")
      // Marques combinantes restantes (forme NFD : E + U+0301) après le repli.
      .replaceAll(RegExp(r'[\u0300-\u036F]'), '');

  // §catFix — Le SEGMENT PRINCIPAL, et pourquoi il change tout.
  //
  // Un fournisseur suffixe TOUS ses group-titles séries par la liste de ses
  // sources : `COMEDIE ( NETFLIX| PRIME | HBO | APPLE TV+ | STARZ |
  // PARAMOUNT+ )`. Comme `PARAMOUNT` était testé avant les genres, **52 991
  // séries sur 104 257 (51 %) tombaient dans la seule rangée « Paramount+ »**
  // au lieu de Comédie, Drame, Crime… (mesuré sur la liste réelle).
  //
  // La régularité qui sauve : cette annotation est TOUJOURS entre
  // parenthèses, et un group-title multi-genres annonce son genre principal
  // EN TÊTE (« POLICIER | ACTION | CRIME » est d'abord du policier). D'où :
  // on retire les parenthèses, le préfixe `|XX|`, et on ne garde que le
  // premier segment. C'est lui qui décide.
  final primary = _primarySegment(g);

  // 1) Le genre, sur le segment principal — la voie normale.
  final byPrimary = primary.isEmpty ? null : _keywordCategoryLabel(primary);
  if (byPrimary != null) {
    return (label: byPrimary, source: _sourceOf(byPrimary));
  }

  // 2) La plateforme, UNIQUEMENT si elle est dans le segment principal.
  // « DISNEY + » (935 séries) est une vraie catégorie ; « FR CANAL+ LIVE |
  // DISNEY+ WOMEN'S CHAMPION'S LEAGUE » est un bouquet de chaînes qui n'a
  // rien à faire dans la rangée Disney+.
  final platform = primary.isEmpty ? null : _platformCategoryLabel(primary);
  if (platform != null) {
    return (label: platform, source: CategorySource.platform);
  }

  // 3) Le format, sur la chaîne ENTIÈRE.
  // ⚠️ Il FAUT la chaîne entière : `|VOD| 4K (HDR)` perd son « HDR » quand on
  // retire les parenthèses. Et ces rangées sont gardées volontairement —
  // §catFix a mesuré que les supprimer ne libère que 0,7 % des entrées mais
  // renvoie 800 films vers un repli littéral sans genre, ce qui est pire.
  final format = _formatCategoryLabel(g);
  if (format != null) {
    return (label: format, source: CategorySource.format);
  }

  // 4) Dernier essai du genre sur la chaîne entière : certains fournisseurs
  // mettent la partie utile APRÈS le pipe (« افلام عربية | FILMS ARABES »).
  final keyword = _keywordCategoryLabel(g);
  if (keyword != null) {
    return (label: keyword, source: _sourceOf(keyword));
  }

  String clean = groupTitle.replaceAll(RegExp(r'\s*\([^)]*\)'), '');
  // §Ultimate — retire un préfixe langue "|XX|" en TÊTE (group-titles type
  // "|FR| SERIES ANCIENNES", "|IT| ITALIAN SERIES", "|TR| YERLI DIZILER") AVANT
  // le découpage sur "|" : sinon split('|').first == "" → catégorie nulle → des
  // dizaines de milliers d'entrées Ultimate tombaient dans "Autres".
  // No-op sur Premium/VOD (leurs group-titles ne commencent pas par "|XX|").
  clean = clean.replaceFirst(RegExp(r'^\s*\|[^|]{1,8}\|\s*'), '');
  // §catWords — Le repli aussi saute les segments qui ne sont qu'un mot de
  // type : `FILMES` seul rend `null` (→ « Autres »), plus jamais une rangée
  // nommée « films ». Le mot est retiré en respectant la casse d'origine
  // (le repli affiche le group-title tel quel, pas sa version majuscule).
  String literal = '';
  for (final seg in clean.split('|')) {
    final upper = _stripTypeWords(seg.toUpperCase());
    if (upper.isEmpty) continue;
    // Retire les mêmes mots dans la casse d'origine, sans toucher au reste.
    literal = seg
        .replaceAll(RegExp(_reTypeWords.pattern, caseSensitive: false), ' ')
        .replaceAll(RegExp(r'^[\s\-–:/]+|[\s\-–:/]+$'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    break;
  }
  if (literal.length > 20) literal = '${literal.substring(0, 18)}…';
  return literal.isNotEmpty
      ? (label: literal, source: CategorySource.literal)
      : null;
}

/// §catWords (2026-09-05) — Les MOTS DE TYPE, qui ne sont jamais un libellé.
///
/// Relevé sur le téléviseur avec un vrai catalogue (~75 rangées Films) :
/// **onze rangées** commençaient par le mot « films » — `FILMES` 3 299,
/// `FILMS ANCIENS` 2 023, `FILMS DE NOËL` 472, `FILMS` 289, `FILMS ASIE` 231,
/// `MOVIES` 137, `FILMS DUBBED AR` 122, `FILMS FAMILY` 114,
/// `FILMS ART-MARTIAUX` 103… — soit ~6 900 films hors de leur genre. Et deux
/// paires de rangées pour le MÊME genre : Arts martiaux 99 + FILMS
/// ART-MARTIAUX 103, Fêtes 15 + FILMS DE NOËL 472.
///
/// La cause, prouvée par sonde : `FILMS` passait le repli littéral comme un
/// libellé valable. Sur `FILMS | ART-MARTIAUX`, le segment principal était
/// `FILMS`, il « classait », et le genre juste derrière n'était jamais lu.
///
/// Ces mots sont donc retirés de chaque segment AVANT tout test, et un
/// segment qui n'en garde rien est sauté (on lit le suivant). ⚠️ Pas `TV` :
/// il est dans `Rakuten TV`, `FR TV SD`… et casserait l'onglet Chaînes.
final RegExp _reTypeWords = RegExp(
  r'\b(FILMS?|FILMES?|MOVIES?|S[ÉE]RIES?|VOD)\b',
);

/// §catWords — Un segment sans ses mots de type ni les séparateurs qu'ils
/// laissent derrière eux (`FILMS - ACTION` → `ACTION`, `FILMS` → ``).
String _stripTypeWords(String seg) => seg
    .replaceAll(_reTypeWords, ' ')
    .replaceAll(RegExp(r'^[\s\-–:/]+|[\s\-–:/]+$'), '')
    .replaceAll(RegExp(r'\s{2,}'), ' ')
    .trim();

/// §catFix — Le segment qui porte le genre : parenthèses retirées (annotations
/// du fournisseur), préfixe `|XX|` retiré, **premier segment qui dit quelque
/// chose** une fois ses mots de type retirés (§catWords). Chaîne vide si rien
/// ne reste — l'appelant retombe alors sur la chaîne entière.
String _primarySegment(String g) {
  final cleaned = g
      .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
      .replaceFirst(RegExp(r'^\s*\|[^|]{1,8}\|\s*'), '');
  for (final seg in cleaned.split('|')) {
    final s = _stripTypeWords(seg);
    if (s.isNotEmpty) return s;
  }
  return '';
}

/// §catFix — Plateformes de diffusion. Testées APRÈS les genres et seulement
/// sur le segment principal : ce sont des marques, pas des genres.
String? _platformCategoryLabel(String g) {
  if (g.contains('DISNEY')) return 'Disney+';
  if (g.contains('PARAMOUNT')) return 'Paramount+';
  if (g.contains('BRUTX')) return 'BrutX';
  if (g.contains('RAKUTEN')) return 'Rakuten TV';
  // §catWords — « NETFLIX FILMS » (73) devenait une rangée littérale : une
  // fois le mot de type retiré, il reste la marque. Même famille que
  // Disney+ : testée après les genres, sur le segment principal seulement
  // (le suffixe `( NETFLIX| PRIME | HBO … )` est déjà parti avec les
  // parenthèses, §catFix).
  if (g.contains('NETFLIX')) return 'Netflix';
  if (g.contains('PRIME VIDEO') || g.contains('AMAZON')) return 'Prime Video';
  if (RegExp(r'\bHBO\b').hasMatch(g)) return 'HBO';
  if (g.contains('APPLE TV')) return 'Apple TV+';
  return null;
}

/// §catFix — Formats techniques. Gardés comme rangées (le fournisseur groupe
/// réellement son catalogue ainsi, et l'utilisateur y cherche sa 4K), mais
/// testés APRÈS les genres pour qu'un « ACTION 4K » reste de l'action.
String? _formatCategoryLabel(String g) {
  if (g.startsWith('3D')) return '3D';
  if (g.contains('IMAX')) return 'IMAX';
  // §catWords — Dolby Vision EST du HDR : « 4K DOLBY VISION » (604 films) et
  // « 100% DOLBY VISION » (4) faisaient deux rangées de plus à côté de
  // « 4K HDR » (564). Une seule rangée pour tout le HDR ; la carte porte
  // déjà le badge Dolby Vision (§qualityTruth).
  if (g.contains('4K HDR') || (g.contains('4K') && g.contains('HDR')) ||
      g.contains('DOLBY VISION') || g.contains('HDR10') ||
      RegExp(r'\bDV\b').hasMatch(g)) {
    return '4K HDR';
  }
  // Une 4K sans HDR annoncé reste une rangée à part (« FILMS 4K », « 4K »,
  // « UHD ») — libellé unifié au lieu de trois repli littéraux.
  if (RegExp(r'\b(4K|UHD|2160P?)\b').hasMatch(g)) return '4K';
  return null;
}

/// La cascade de mots-clés. `null` = rien de reconnu → repli littéral.
///
/// ⚠️ **L'ORDRE FAIT LE RANGEMENT.** Chaque test gagne sur tous les suivants :
/// un `group-title` qui contient plusieurs notions (« POLICIER | ACTION |
/// CRIME », « COMEDIE ( … | PARAMOUNT+ ) ») est classé par le premier test qui
/// répond, pas par sa notion principale. Ne jamais insérer un test large en
/// haut de cette liste sans mesurer (`dart run tool/validate_parse.dart`).
String? _keywordCategoryLabel(String g) {
  // §legLang — Catégories lusophones sous-titrées (« VOD-LEGENDADA »,
  // « ANIMACAO LEGENDADA ») : même libellé que le préfixe de titre, donc même
  // case à cocher dans « Langues / régions ». ⚠️ §catWords l'a remonté EN
  // TÊTE : depuis que « ANIMAÇÃO » est reconnu comme Animation, une série
  // « ANIMACAO LEGENDADA » serait partie dans Animation et aurait échappé à la
  // case Legendado. La langue prime sur le genre, comme pour toute région.
  if (g.contains('LEGENDAD')) return kLegRegionLabel;
  if (g.contains('MANGA') || g.contains('ANIMÉ') || g.contains('ANIME')) return 'Manga';
  // §catWords — vocabulaire portugais/italien (ANIMAÇÃO, DESENHOS ANIMADOS).
  if (g.contains('ANIMAT') || g.contains('CARTOON') || g.contains('ANIMAÇ') ||
      g.contains('ANIMAC') || g.contains('ANIMAZ') || g.contains('DESENHO')) {
    return 'Animation';
  }
  if (g.contains('DOCU')) return 'Documentaire';
  // §catFix — Rayon « actualités » multilingue, jusqu'ici sans aucun test.
  if (g.contains('ACTUALIT') || RegExp(r'\bNEWS\b').hasMatch(g) ||
      g.contains('NACHRICHTEN') || g.contains('NOTIZIE') ||
      g.contains('NOTICIAS')) { return 'Actualités'; }
  if (g.contains('BIOPIC')) return 'Biopic';
  // §catFix — Vocabulaire MULTILINGUE : le même rayon jeunesse est écrit
  // « KINDER DE », « NIÑOS ES », « BAMBINI », « INFANTIL BR », « VOD
  // CRIANCAS » selon la langue du fournisseur — 11 formulations relevées sur
  // une seule liste, dont 4 qu'aucun test ne reconnaissait (autant de rangées
  // en repli littéral pour une même notion).
  if (g.contains('ENFANT') || g.contains('KIDS') || g.contains('JEUNESSE') ||
      g.contains('FAMILIALE') || g.contains('FAMILLE') ||
      g.contains('KINDER') || g.contains('NIÑOS') || g.contains('NINOS') ||
      g.contains('BAMBINI') || g.contains('CRIANÇAS') ||
      g.contains('CRIANCAS') || g.contains('INFANTIL') ||
      g.contains('CHILDREN') ||
      // §catWords — « FILMS FAMILY » (114) tombait en repli littéral.
      g.contains('FAMILY') || g.contains('FAMÍLIA') || g.contains('FAMILIA')) {
    return 'Jeunesse';
  }
  // §catWords — « SÉRIES ASIATIQUES » (734), « FILMS ASIE » (231) : une
  // région, reléguée et masquable comme les autres.
  if (g.contains('ASIATIQUE') || g.contains('ASIAT') || g.contains('ASIAN') ||
      RegExp(r'\bASIE\b').hasMatch(g)) { return 'Asie'; }
  // ⚠️ Depuis le repli des accents, c'est la forme ASCII qui décide.
  if (g.contains('CORÉEN') || g.contains('COREEN') || g.contains('KOREAN') ||
      g.contains('KOREA')) { return 'Coréen'; }
  if (g.contains('TURC') || g.contains('TURQU') || g.contains('TÜRK') || g.contains('TURK')) return 'Turc';
  // Algérie AVANT Maghrébin : « Films Algériens » → catégorie dédiée (l'user
  // veut un filtre distinct) ; le reste du Maghreb tombe dans 'Maghrébin'.
  if (g.contains('ALGÉRI') || g.contains('ALGERI') || g.contains('ALGERIAN')) return 'Algérie';
  if (g.contains('MAGHRÉB') || g.contains('MAGHRÈB') || g.contains('MAGHREB')) return 'Maghrébin';
  // « NOVIDADES LEG. » / « NOVIDADES DUB. » (catalogues lusophones) → label dédié.
  if (g.contains('NOVIDADES')) return 'Novidades';
  if (g.contains('RAMADAN')) return 'Ramadan';
  // §catWords — « FILMS DUBBED AR » (122) : doublé en arabe.
  if (g.contains('ARAB') || g.contains('العربية') || g.contains('عربية') ||
      g.contains('DUBBED AR')) { return 'Arabe'; }
  if (g.contains('INDIA') || g.contains('INDE') || g.contains('भारतीय')) return 'Indien';
  // §catFix — DISNEY / PARAMOUNT / BRUTX / RAKUTEN sont partis dans
  // `_platformCategoryLabel`, et 3D / IMAX / 4K HDR dans
  // `_formatCategoryLabel` : testés ici, ils gagnaient sur tous les genres
  // (51 % des séries dans « Paramount+ »).
  // §catWords — « COMICS » (72) et « DC/DCEU » (1) sont le rayon super-héros
  // sous un autre nom.
  if (g.contains('SUPER-HÉR') || g.contains('SUPER-HER') || g.contains('COMICS') ||
      g.contains('MARVEL') || g.contains('DCEU') || RegExp(r'\bDC\b').hasMatch(g)) {
    return 'Super-Héros';
  }
  // §catWords — « SCIENCE-FICTION » (368, avec trait d'union) coexistait avec
  // « Sci-Fi » (164) : deux rangées pour un genre. + portugais/espagnol.
  if (g.contains('SCIENCE FICTION') || g.contains('SCIENCE-FICTION') ||
      g.contains('SC FICTION') || g.contains('SCI-FI') || g.contains('FICÇÃO') ||
      g.contains('FICCAO') || g.contains('FICCIÓN') || g.contains('FICCION')) {
    return 'Sci-Fi';
  }
  if (g.contains('FANTASTIQUE') || g.contains('FANTASY')) return 'Fantastique';
  if (g.contains('HORREUR') || g.contains('HORROR') || g.contains('ÉPOUVANTE') ||
      g.contains('EPOUVANTE') || g.contains('TERROR')) { return 'Horreur'; }
  if (g.contains('THRILLER') || g.contains('SUSPENSE')) return 'Thriller';
  // §catFix — POLICIER avant ACTION : « POLICIER | ACTION | CRIME » (550
  // films) annonce le policier en tête, et c'était l'ordre du CODE qui
  // tranchait, pas le genre annoncé.
  if (g.contains('POLICIER') || g.contains('POLICIAL')) return 'Policier';
  // §catWords — Le vocabulaire PORTUGAIS manquait entièrement : ce
  // fournisseur (le même que le LEGENDADO) écrit `FILMES | AÇÃO`, et 3 299
  // films tombaient dans une rangée nommée « FILMES ».
  if (g.contains('ACTION') || g.contains('AÇÃO') || g.contains('ACAO') ||
      g.contains('ACCIÓN') || g.contains('ACCION') || g.contains('AZIONE')) {
    return 'Action';
  }
  if (g.contains('AVENTURE') || g.contains('ADVENTURE') || g.contains('AVENTURA') ||
      g.contains('AVVENTURA')) { return 'Aventure'; }
  // §catFix — « COMEDIE MUSICAL » AVANT « COMEDIE » : le test dédié vivait
  // 40 lignes plus bas et n'a donc JAMAIS pu s'exécuter (code mort mesuré).
  // Fusionné avec « MUSICAL » sous un seul libellé, aligné sur `tmdb_genres`.
  if (g.contains('COMÉDIE MUSICAL') || g.contains('COMEDIE MUSICAL')) return 'Musical';
  if (g.contains('COMÉDIE') || g.contains('COMEDIE') || g.contains('COMEDY') ||
      g.contains('COMÉDIA') || g.contains('COMEDIA') || g.contains('COMMEDIA')) {
    return 'Comédie';
  }
  if (g.contains('DRAME') || g.contains('DRAMA')) return 'Drame';
  if (g.contains('ROMANCE')) return 'Romance';
  if (g.contains('WESTERN') || g.contains('FAROESTE')) return 'Western';
  if (g.contains('MAFIA') || g.contains('GANG')) return 'Mafia';
  if (g.contains('ESPIONNAGE') || g.contains('ESPIONN')) return 'Espionnage';
  if (g.contains('JURIDIQUE')) return 'Juridique';
  if (g.contains('PRISON')) return 'Prison';
  if (g.contains('MEDIEVAL') || g.contains('MÉDIÉVAL') || g.contains('MOYEN AGE')) return 'Médiéval';
  if (g.contains('MUSICAL') || g.contains('MUSIQUE') || g.contains('MUSIC') ||
      g.contains('MUSIK') || g.contains('MUSICA')) { return 'Musical'; }
  if (g.contains('BRAQUAGE') || g.contains('ARNAQUE')) return 'Braquage';
  if (g.contains('TUEUR EN SERIE') || g.contains('TUEUR EN SÉRIE')) return 'Tueur en série';
  if (g.contains('SURVIVAL') || g.contains('SURVIE')) return 'Survie';
  if (g.contains('CATASTROPHE')) return 'Catastrophe';
  if (g.contains('VENGEANCE')) return 'Vengeance';
  if (g.contains('MARITIME')) return 'Maritime';
  // §catWords — « THÉÂTRES » (83) est du spectacle vivant.
  if (g.contains('SPECTACLE') || g.contains('CONCERT') || g.contains('THÉÂTRE') ||
      g.contains('THEATRE') || g.contains('STAND-UP') || g.contains('STAND UP')) {
    return 'Spectacle';
  }
  if (g.contains('KARAOK')) return 'Karaoké';
  if (g.contains('TÉLÉFILM') || g.contains('TELEFILM')) return 'Téléfilm';
  if (g.contains('VOITURE') || g.contains('CARS')) return 'Voitures';
  // §catFix — « Cultes » et « Classiques » étaient DEUX rangées pour la même
  // notion (5 224 + 75 entrées mesurées). Fusionnées sous « Cultes », qui a
  // déjà sa place dans `_categoryPriority` (5).
  if (g.contains('LÉGENDAIRE') || g.contains('LEGENDAIRE') || g.contains('CULTE') ||
      g.contains('CLASSIQUE') || g.contains('CLASSIC') ||
      // §catWords — « FILMS ANCIENS » (2 023 films !) était la 3e rangée du
      // catalogue, en majuscules, pour la même notion que « Cultes » (51).
      g.contains('ANCIEN') ||
      g.contains("70'S") || g.contains("80'S")) { return 'Cultes'; }
  if (g.contains('OSCAR')) return 'Oscar';
  if (g.contains('BOX OFFICE')) return 'Box Office';
  // §newCatMerge — Toutes les formulations « récemment ajouté » tombent dans le
  // même bucket « New » (sinon « Nouveauté(s) », « NEW », « Derniers ajouts »…
  // créaient des rangées séparées en doublon de la rangée New par récence).
  if (g.contains('RECEM') ||
      g.contains('RÉCEMM') ||
      g.contains('NOUVEAUT') ||
      g.contains('NOUVEAU') ||
      g.contains('DERNIERS AJOUT') ||
      g.contains('AJOUTS RÉCENT') ||
      g.contains('AJOUTS RECENT') ||
      RegExp(r'\bNEW\b').hasMatch(g)) {
    return 'New';
  }
  if (g.contains('SÉLECTION') || g.contains('SELECTION') ||
      RegExp(r'\bTOP \d+').hasMatch(g) || g.contains('BEST OF')) { return 'Sélection'; }
  if (g.contains('COUP DE COEUR')) return 'Coup de cœur';
  // §catWords — « FILMS DE NOËL » (472) à côté de « Fêtes » (15) : le même
  // rayon, écrit autrement. + anglais/portugais.
  if (g.contains('FIN D\'AN') || g.contains('FIN D\'ANN') || g.contains('NOËL') ||
      g.contains('NOEL') || g.contains('CHRISTMAS') || g.contains('NATAL') ||
      g.contains('HALLOWEEN')) { return 'Fêtes'; }
  if (g.contains('MÉDECINE') || g.contains('MEDECINE')) return 'Médecine';
  if (g.contains('RÉALITÉ') || g.contains('REALITE')) return 'Téléréalité';
  if (g.contains('CRIME')) return 'Crime';
  // §catWords — « FILMS ART-MARTIAUX » (103) faisait une rangée à côté de
  // « Arts martiaux » (99) : la graphie au singulier et au trait d'union.
  if (g.contains('ARTS MARTIAUX') || g.contains('ART-MARTIAUX') ||
      g.contains('ARTS-MARTIAUX') || g.contains('ART MARTIAUX') ||
      g.contains('MARTIAL') || g.contains('KUNG FU') || g.contains('KUNG-FU')) {
    return 'Arts martiaux';
  }
  if (g.contains('DANSE') || g.contains('DANCE')) return 'Danse';
  // §catFix — Bouquets sportifs nommés par leur compétition, jamais par le
  // mot « sport » (`LIGUE 1+ FRANCE | DAZN…`, `DAZN ITALIA SERIE A`).
  if (g.contains('WORKOUT') || g.contains('SPORT') || g.contains('DAZN') ||
      g.contains('LIGUE 1') || g.contains('CHAMPIONS LEAGUE') ||
      g.contains("CHAMPION'S LEAGUE") || g.contains('UEFA')) { return 'Sport'; }
  if (g.contains('GUERRE') || g.contains('WAR') || g.contains('GUERRA')) return 'Guerre';
  if (g.contains('HISTOIRE') || g.contains('HISTORIQUE')) return 'Histoire';
  if (g.contains('RAKUTEN')) return 'Rakuten TV';
  if (g.contains('ALLEMAND') || g.contains('DEUTSCH')) return 'Allemagne';
  // §catFix — « ENGLISH FILMS » (demande utilisateur) : le test ne connaissait
  // que ANGLAIS / UK, donc cette catégorie devenait une rangée littérale en
  // majuscules, ni reléguée ni masquable. `UK` est masquable dans
  // « Langues / régions » (mais volontairement NON reléguée — choix
  // utilisateur, cf. `kForeignRegionLabels`).
  if (g.contains('ANGLAIS') || g.contains('ENGLISH') || g.contains('ANGLOPHONE') ||
      RegExp(r'\bENG\b').hasMatch(g) ||
      g.contains(' UK') || g.contains('(UK)')) { return 'UK'; }
  if (g.contains('ESPAGNOL') || g.contains('ESPAÑA') || g.contains('ESPANA') ||
      g.contains('SPAIN')) { return 'Espagne'; }
  if (g.contains('ITALIEN')) return 'Italie';
  if (g.contains('RUSSE') || g.contains('РОССИЯ')) return 'Russie';
  if (g.contains('BRÉSIL') || g.contains('BRESIL') || g.contains('BRASILEIRO')) return 'Brésil';
  if (g.contains('BELG')) return 'Belgique';
  if (g.contains('POLONAIS') || g.contains('POLONEZ')) return 'Pologne';
  if (g.contains('PORTUGAIS') || g.contains('PORTUGUÊS') || g.contains('PORTUGUES')) {
    return 'Portugal';
  }
  if (g.contains('SUISSE') || g.contains('SWITZERLAND')) return 'Suisse';
  if (g.contains('SCANDINAV') || g.contains('DANEMARK') || g.contains('NORWAY') || g.contains('SWEDEN')) return 'Scandinavie';
  if (g.contains('TCHÈQU') || g.contains('TCHEQU') || g.contains('ČESKO') ||
      g.contains('CESKO')) { return 'Tchéquie'; }
  if (g.contains('CROAT') || g.contains('HRVAT')) return 'Croatie';
  if (g.contains('GREC') || g.contains('ΕΛΛΗΝΙΚ')) return 'Grèce';
  if (g.contains('ALBANI') || g.contains('SHQIPTAR')) return 'Albanie';
  if (g.contains('ARMÉNI') || g.contains('ARMENI') || g.contains('ՀԱՅԵՐԵՆ')) return 'Arménie';
  if (g.contains('ROUMAIN') || g.contains('ROMANIAN')) return 'Roumanie';
  if (g.contains('BOSNIAK') || g.contains('BOSNIAQUE') || g.contains('BOSNA')) return 'Bosnie';
  if (g.contains('CANADA') || g.contains(' CA ') || g.contains('( CA )')) return 'Canada';
  if (g.contains('USA') || g.contains('ETATS-UNIS') || g.contains('ÉTATS-UNIS')) return 'USA';
  if (g.contains('PAYS-BAS') || g.contains('NETHERLANDS')) return 'Pays-Bas';
  // §catFix — « FRANÇAIS » (696 films mesurés) n'avait AUCUNE règle et
  // devenait une rangée littérale en majuscules, alors que c'est la langue
  // par défaut de l'app. Libellé propre, priorité de genre (100) : jamais
  // relégué, jamais masquable.
  if (g.contains('FRANÇAIS') || g.contains('FRANCAIS') ||
      g.contains('FRENCH')) { return 'Français'; }
  // §catWords — « V.O SOUS TITRÉS » (1 635) : une LANGUE rangée en catégorie
  // littérale. Testée en tout dernier pour qu'un genre présent gagne
  // (« COMÉDIE VOSTFR » reste une comédie). Jamais masquable : le VOSTFR est
  // précisément ce que le filtre régions promet de toujours garder.
  if (g.contains('SOUS TITR') || g.contains('SOUS-TITR') || g.contains('VOST')) {
    return 'VOSTFR';
  }

  return null;
}

/// Clé de regroupement partagée films ET séries.
/// N'inclut PAS la catégorie : deux entrées du même titre provenant de
/// providers différents (avec des groupTitle différents) doivent toujours
/// tomber dans le même groupe, notamment pour partager logos et versions.
/// §23b — Clé PRÉ-CALCULÉE à parse-time (`TitleMetadata.groupKey`) :
/// minuscules + ponctuation réduite en espace. Insensible à la casse ET à la
/// ponctuation ("M.A.S.H" / "M.A.S.H." / "m a s h" → même groupe ; mesuré
/// ~470 films + ~70 séries perdus rien que sur la casse). L'affichage garde
/// la forme d'origine (`group.first.displayName`), seule la CLÉ est
/// normalisée. Fallback calcul à la volée pour les entrées construites sans
/// `parse()` (épisodes API…).
/// §tmdbMerge — La clé passe par [TmdbGroupAliasService] : deux titres qui
/// portent le MÊME identifiant TMDB partagent la même clé, même écrits dans
/// deux langues (`100 Mètres` / `100 METERS`). Sans identifiant — VOD, XENO —
/// la fonction rend la clé telle quelle, comme avant.
String contentGroupKey(M3uEntry e) => TmdbGroupAliasService.canonical(_rawGroupKey(e));

String _rawGroupKey(M3uEntry e) => e.title.groupKey.isNotEmpty
    ? e.title.groupKey
    : TitleMetadata.computeGroupKey(e.displayName);

// §favAudit — Regex de `tvGroupKey` HISSÉES en constantes de fichier : elles
// étaient reconstruites (et donc recompilées) à CHAQUE appel, or la fonction
// est appelée par `FavoritesService.keyFor` pour chaque chaîne, et par le
// groupement de la home pour chaque entrée TV.
final RegExp _kTvSuffixNoise = RegExp(
  r'\s+(R[eé]solution\b.*|Exclu[a-z]*|Backup|Bkp|Bak|Back)\s*$',
  caseSensitive: false,
);
final RegExp _kTvSuffixQuality = RegExp(
  r'\s+(4K|UHD|FHD|HD|SD|1080p|720p|480p)\s*$',
  caseSensitive: false,
);
final RegExp _kWhitespaceRun = RegExp(r'\s+');

/// Clé de regroupement pour les chaînes TV.
String tvGroupKey(String name) {
  var key = name;
  key = key.replaceAll(_kTvSuffixNoise, '');
  key = key.replaceAll(_kTvSuffixQuality, '');
  return key.trim().replaceAll(_kWhitespaceRun, ' ');
}

/// Dédoublonne les variantes d'une chaîne TV partageant la même qualité.
///
/// **Problème** : certains providers exposent plusieurs flux pour la même
/// chaîne et la même qualité (backup, miroir, multi-CDN). Sans dédup, l'action
/// sheet affiche plusieurs boutons "FHD", "HD" identiques côté utilisateur.
///
/// **Stratégie** : clé `(qualité ?? versionLabel ?? rawTitle, accountId)` —
/// on garde le premier rencontré (priorité du compte actif déjà appliquée
/// par `ParsedPlaylistService.entriesWithPriority`). Multi-comptes : on
/// conserve une variante par compte pour que l'utilisateur puisse switcher.
List<M3uEntry> dedupeTvVersions(List<M3uEntry> versions) {
  final seen = <String>{};
  final out = <M3uEntry>[];
  for (final v in versions) {
    final qualityKey = v.title.quality ??
        v.title.versionLabel ??
        v.title.rawTitle;
    final key = '${v.accountId}|$qualityKey';
    if (seen.add(key)) out.add(v);
  }
  return out;
}

/// Retourne true si l'entrée TV doit être masquée.
///
/// Cible les **séparateurs de catégorie décoratifs** insérés par les providers
/// dans leur liste à plat (ce ne sont pas de vraies chaînes). Motifs observés :
///   • Premium  : `▀▄ FR ▀▄▀▄  CINEMA ▄▀▄`, `------▼|FR|-SPORTS-|FR|▼------`
///   • Ultimate : `♣♦♣-----|FR| FRANCE FHD |FR|----♣♦♣`,
///                `•●★-----|FR| CINEMA FHD |FR|-----★●•` (nb de tirets variable
///                1→5, donc le test `------` seul ne suffisait pas)
///
/// ⚠️ Anti-faux-positif (vérifié sur les 3 listes) : on masque sur des
/// SÉQUENCES qui n'apparaissent jamais dans un vrai titre — box-drawing
/// `▀ ▄ ▼`, suits `♣ ♦`, combos `•●★`/`★●•`. On NE masque PAS sur `•`, `●`, `★`
/// ou `❤` isolés, présents dans de vrais titres VOD (ex: `無限大☆WORLD`, `❤️`).
bool isHiddenTvVariant(String name) {
  if (name.contains('▀') || name.contains('▄') ||
      name.contains('▼') || name.contains('------') ||
      name.contains('♣') || name.contains('♦') ||
      name.contains('•●★') || name.contains('★●•')) {
    return true;
  }
  return RegExp(r'\bR[eé]solutions?\b|\bExclu[a-z]*\b', caseSensitive: false).hasMatch(name);
}
