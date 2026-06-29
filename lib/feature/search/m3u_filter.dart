import 'package:aetherStream/data/models/m3u_entry.dart';

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

/// §langFilter — Régions/langues que l'utilisateur peut choisir de MASQUER
/// (cases à cocher dans les réglages). Ordre alpha + VO en fin.
const List<String> kHideableRegionLabels = [
  'Algérie', 'Allemagne', 'Arabe', 'Arménie', 'Albanie', 'Belgique', 'Brésil',
  'Croatie', 'Espagne', 'Grèce', 'Indien', 'Italie', 'Maghrébin', 'Novidades',
  'Pays-Bas', 'Pologne', 'Portugal', 'Roumanie', 'Russie', 'Scandinavie',
  'Tchéquie', 'Turc', 'UK', 'USA', kVoRegionLabel,
];

/// §langFilter — Région d'une entrée À DES FINS DE FILTRAGE, déduite du préfixe
/// `|XX|` de son NOM (rawTitle). Retourne `null` pour FR / sans préfixe /
/// VOSTFR / Québec (jamais masqués). Sert au filtre "langues à masquer".
String? entryRegionLabel(String rawTitle) {
  final m = RegExp(r'^\s*\|([^|]{1,14})\|').firstMatch(rawTitle);
  if (m == null) return null; // pas de préfixe → FR / MULTI / sans tag → gardé
  final upper = rawTitle.toUpperCase();
  // VOSTFR (éclaté |VO|STFR| ou compact) → gardé (sous-titres FR).
  if (upper.contains('STFR') || upper.contains('VOSTFR')) return null;
  final firstSeg = m.group(1)!.trim().toUpperCase();
  // 1er token du segment → gère "FR-4K", "FR-4K DV", "IT-4K".
  final code = firstSeg.split(RegExp(r'[-\s]')).first;
  if (code == 'FR' || code == 'QC') return null; // FR + Québec (français) gardés
  if (code == 'VO' || code == 'LEG.' || code == 'LEG') return kVoRegionLabel;
  return _foreignRegionByCode[code]; // null si code inconnu → gardé
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

/// Retourne un label d'affichage depuis le group-title M3U.
/// Priorité : région étrangère (|XX|) → mappings sémantiques → fallback nettoyage.
String? contentCategoryLabel(String? groupTitle) {
  if (groupTitle == null || groupTitle.isEmpty) return null;

  // §Ultimate — contenu d'une région étrangère → catégorie = la région
  // (regroupé hors des rangées de genre FR). Le |FR| / sans préfixe poursuit
  // vers le classement par genre ci-dessous.
  final foreign = _foreignRegionLabel(groupTitle);
  if (foreign != null) return foreign;

  final g = groupTitle.toUpperCase();

  if (g.contains('MANGA') || g.contains('ANIMÉ') || g.contains('ANIME')) return 'Manga';
  if (g.contains('ANIMAT') || g.contains('CARTOON')) return 'Animation';
  if (g.contains('DOCU')) return 'Documentaire';
  if (g.contains('BIOPIC')) return 'Biopic';
  if (g.contains('ENFANT') || g.contains('KIDS') || g.contains('JEUNESSE') ||
      g.contains('FAMILIALE') || g.contains('FAMILLE')) { return 'Jeunesse'; }
  if (g.contains('CORÉEN') || g.contains('KOREAN') || g.contains('KOREA')) return 'Coréen';
  if (g.contains('TURC') || g.contains('TURQU') || g.contains('TÜRK') || g.contains('TURK')) return 'Turc';
  // Algérie AVANT Maghrébin : « Films Algériens » → catégorie dédiée (l'user
  // veut un filtre distinct) ; le reste du Maghreb tombe dans 'Maghrébin'.
  if (g.contains('ALGÉRI') || g.contains('ALGERI') || g.contains('ALGERIAN')) return 'Algérie';
  if (g.contains('MAGHRÉB') || g.contains('MAGHRÈB') || g.contains('MAGHREB')) return 'Maghrébin';
  // « NOVIDADES LEG. » / « NOVIDADES DUB. » (catalogues lusophones) → label dédié.
  if (g.contains('NOVIDADES')) return 'Novidades';
  if (g.contains('RAMADAN')) return 'Ramadan';
  if (g.contains('ARAB') || g.contains('العربية') || g.contains('عربية')) return 'Arabe';
  if (g.contains('INDIA') || g.contains('INDE') || g.contains('भारतीय')) return 'Indien';
  if (g.contains('DISNEY')) return 'Disney+';
  if (g.contains('PARAMOUNT')) return 'Paramount+';
  if (g.contains('BRUTX')) return 'BrutX';
  if (g.startsWith('3D')) return '3D';
  if (g.contains('IMAX')) return 'IMAX';
  if (g.contains('4K HDR') || (g.contains('4K') && g.contains('HDR'))) return '4K HDR';
  if (g.contains('SUPER-HÉR') || g.contains('SUPER-HER')) return 'Super-Héros';
  if (g.contains('SCIENCE FICTION') || g.contains('SC FICTION') || g.contains('SCI-FI')) return 'Sci-Fi';
  if (g.contains('FANTASTIQUE') || g.contains('FANTASY')) return 'Fantastique';
  if (g.contains('HORREUR') || g.contains('HORROR') || g.contains('ÉPOUVANTE')) return 'Horreur';
  if (g.contains('THRILLER')) return 'Thriller';
  if (g.contains('ACTION')) return 'Action';
  if (g.contains('AVENTURE') || g.contains('ADVENTURE')) return 'Aventure';
  if (g.contains('COMÉDIE') || g.contains('COMEDIE') || g.contains('COMEDY')) return 'Comédie';
  if (g.contains('DRAME') || g.contains('DRAMA')) return 'Drame';
  if (g.contains('ROMANCE')) return 'Romance';
  if (g.contains('WESTERN')) return 'Western';
  if (g.contains('POLICIER')) return 'Policier';
  if (g.contains('MAFIA') || g.contains('GANG')) return 'Mafia';
  if (g.contains('ESPIONNAGE') || g.contains('ESPIONN')) return 'Espionnage';
  if (g.contains('JURIDIQUE')) return 'Juridique';
  if (g.contains('PRISON')) return 'Prison';
  if (g.contains('MEDIEVAL') || g.contains('MÉDIÉVAL') || g.contains('MOYEN AGE')) return 'Médiéval';
  if (g.contains('MUSICAL')) return 'Musical';
  if (g.contains('BRAQUAGE') || g.contains('ARNAQUE')) return 'Braquage';
  if (g.contains('TUEUR EN SERIE') || g.contains('TUEUR EN SÉRIE')) return 'Tueur en série';
  if (g.contains('SURVIVAL') || g.contains('SURVIE')) return 'Survie';
  if (g.contains('CATASTROPHE')) return 'Catastrophe';
  if (g.contains('VENGEANCE')) return 'Vengeance';
  if (g.contains('MARITIME')) return 'Maritime';
  if (g.contains('SPECTACLE') || g.contains('CONCERT')) return 'Spectacle';
  if (g.contains('TÉLÉFILM') || g.contains('TELEFILM')) return 'Téléfilm';
  if (g.contains('VOITURE') || g.contains('CARS')) return 'Voitures';
  if (g.contains('LÉGENDAIRE') || g.contains('LEGENDAIRE') || g.contains('CULTE')) return 'Cultes';
  if (g.contains('CLASSIQUE') || g.contains('CLASSIC') || g.contains("70'S") || g.contains("80'S")) return 'Classiques';
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
  if (g.contains('SÉLECTION') || g.contains('SELECTION')) return 'Sélection';
  if (g.contains('COUP DE COEUR')) return 'Coup de cœur';
  if (g.contains('FIN D\'AN') || g.contains('FIN D\'ANN')) return 'Fêtes';
  if (g.contains('MÉDECINE') || g.contains('MEDECINE')) return 'Médecine';
  if (g.contains('COMÉDIE MUSICAL') || g.contains('COMEDIE MUSICAL')) return 'Comédie musicale';
  if (g.contains('RÉALITÉ') || g.contains('REALITE')) return 'Téléréalité';
  if (g.contains('CRIME')) return 'Crime';
  if (g.contains('ARTS MARTIAUX')) return 'Arts martiaux';
  if (g.contains('DANSE') || g.contains('DANCE')) return 'Danse';
  if (g.contains('WORKOUT') || g.contains('SPORT')) return 'Sport';
  if (g.contains('GUERRE') || g.contains('WAR')) return 'Guerre';
  if (g.contains('HISTOIRE') || g.contains('HISTORIQUE')) return 'Histoire';
  if (g.contains('RAKUTEN')) return 'Rakuten TV';
  if (g.contains('ALLEMAND') || g.contains('DEUTSCH')) return 'Allemagne';
  if (g.contains('ANGLAIS') || g.contains(' UK') || g.contains('(UK)')) return 'UK';
  if (g.contains('ESPAGNOL') || g.contains('ESPAÑA') || g.contains('SPAIN')) return 'Espagne';
  if (g.contains('ITALIEN')) return 'Italie';
  if (g.contains('RUSSE') || g.contains('РОССИЯ')) return 'Russie';
  if (g.contains('BRÉSIL') || g.contains('BRESIL') || g.contains('BRASILEIRO')) return 'Brésil';
  if (g.contains('BELG')) return 'Belgique';
  if (g.contains('POLONAIS') || g.contains('POLONEZ')) return 'Pologne';
  if (g.contains('PORTUGAIS') || g.contains('PORTUGUÊS')) return 'Portugal';
  if (g.contains('SUISSE') || g.contains('SWITZERLAND')) return 'Suisse';
  if (g.contains('SCANDINAV') || g.contains('DANEMARK') || g.contains('NORWAY') || g.contains('SWEDEN')) return 'Scandinavie';
  if (g.contains('TCHÈQU') || g.contains('TCHEQU') || g.contains('ČESKO')) return 'Tchéquie';
  if (g.contains('CROAT') || g.contains('HRVAT')) return 'Croatie';
  if (g.contains('GREC') || g.contains('ΕΛΛΗΝΙΚ')) return 'Grèce';
  if (g.contains('ALBANI') || g.contains('SHQIPTAR')) return 'Albanie';
  if (g.contains('ARMÉNI') || g.contains('ARMENI') || g.contains('ՀԱՅԵՐԵՆ')) return 'Arménie';
  if (g.contains('ROUMAIN') || g.contains('ROMANIAN')) return 'Roumanie';
  if (g.contains('BOSNIAK') || g.contains('BOSNIAQUE') || g.contains('BOSNA')) return 'Bosnie';
  if (g.contains('CANADA') || g.contains(' CA ') || g.contains('( CA )')) return 'Canada';
  if (g.contains('USA') || g.contains('ETATS-UNIS') || g.contains('ÉTATS-UNIS')) return 'USA';
  if (g.contains('PAYS-BAS') || g.contains('NETHERLANDS')) return 'Pays-Bas';

  String clean = groupTitle.replaceAll(RegExp(r'\s*\([^)]*\)'), '');
  // §Ultimate — retire un préfixe langue "|XX|" en TÊTE (group-titles type
  // "|FR| SERIES ANCIENNES", "|IT| ITALIAN SERIES", "|TR| YERLI DIZILER") AVANT
  // le découpage sur "|" : sinon split('|').first == "" → catégorie nulle → des
  // dizaines de milliers d'entrées Ultimate tombaient dans "Autres".
  // No-op sur Premium/VOD (leurs group-titles ne commencent pas par "|XX|").
  clean = clean.replaceFirst(RegExp(r'^\s*\|[^|]{1,8}\|\s*'), '');
  clean = clean.split('|').first.trim();
  if (clean.length > 20) clean = '${clean.substring(0, 18)}…';
  return clean.isNotEmpty ? clean : null;
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
String contentGroupKey(M3uEntry e) => e.title.groupKey.isNotEmpty
    ? e.title.groupKey
    : TitleMetadata.computeGroupKey(e.displayName);

/// Clé de regroupement pour les chaînes TV.
String tvGroupKey(String name) {
  var key = name;
  key = key.replaceAll(
    RegExp(r'\s+(R[eé]solution\b.*|Exclu[a-z]*|Backup|Bkp|Bak|Back)\s*$', caseSensitive: false),
    '',
  );
  key = key.replaceAll(
    RegExp(r'\s+(4K|UHD|FHD|HD|SD|1080p|720p|480p)\s*$', caseSensitive: false),
    '',
  );
  return key.trim().replaceAll(RegExp(r'\s+'), ' ');
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
