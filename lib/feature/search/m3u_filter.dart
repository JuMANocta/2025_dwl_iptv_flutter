import 'package:aetherStream/data/models/m3u_entry.dart';

/// Retourne un label d'affichage depuis le group-title M3U.
/// Priorité : mappings sémantiques connus → fallback nettoyage automatique.
String? contentCategoryLabel(String? groupTitle) {
  if (groupTitle == null || groupTitle.isEmpty) return null;
  final g = groupTitle.toUpperCase();

  if (g.contains('MANGA') || g.contains('ANIMÉ') || g.contains('ANIME')) return 'Manga';
  if (g.contains('ANIMAT') || g.contains('CARTOON')) return 'Animation';
  if (g.contains('DOCU')) return 'Documentaire';
  if (g.contains('BIOPIC')) return 'Biopic';
  if (g.contains('ENFANT') || g.contains('KIDS') || g.contains('JEUNESSE') ||
      g.contains('FAMILIALE') || g.contains('FAMILLE')) { return 'Jeunesse'; }
  if (g.contains('CORÉEN') || g.contains('KOREAN') || g.contains('KOREA')) return 'Coréen';
  if (g.contains('TURC') || g.contains('TURQU') || g.contains('TÜRK')) return 'Turc';
  if (g.contains('MAGHRÉB') || g.contains('MAGHRÈB') || g.contains('MAGHREB')) return 'Maghrébin';
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
  if (g.contains('RECEM') || g.contains('RÉCEMM')) return 'New';
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

  String clean = groupTitle
      .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
      .split('|').first
      .trim();
  if (clean.length > 20) clean = '${clean.substring(0, 18)}…';
  return clean.isNotEmpty ? clean : null;
}

/// Clé de regroupement partagée films ET séries.
/// N'inclut PAS la catégorie : deux entrées du même titre provenant de
/// providers différents (avec des groupTitle différents) doivent toujours
/// tomber dans le même groupe, notamment pour partager logos et versions.
String contentGroupKey(M3uEntry e) => e.displayName;

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

/// Retourne true si l'entrée TV doit être masquée.
bool isHiddenTvVariant(String name) {
  if (name.contains('▀') || name.contains('▄') ||
      name.contains('▼') || name.contains('------')) {
    return true;
  }
  return RegExp(r'\bR[eé]solutions?\b|\bExclu[a-z]*\b', caseSensitive: false).hasMatch(name);
}
