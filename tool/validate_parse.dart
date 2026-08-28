// §23 — Script de validation de TitleMetadata.parse sur les catalogues réels.
// Usage : dart run tool/validate_parse.dart
// Charge les 3 dumps lib/iptv_exemple/*_vod_cache.json, parse tous les noms,
// mesure la convergence cross-listes des baseTitle (= fusion en une vignette)
// et imprime des échantillons pour contrôle visuel.
//
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:aetherStream/data/models/m3u_entry.dart';

void main() {
  const dir = 'lib/iptv_exemple';
  final files = {
    'PLATINIUM': '$dir/PLATINIUM_vod_cache.json',
    'PREMIUM': '$dir/PREMIUM_vod_cache.json',
    'VOD': '$dir/VOD_vod_cache.json',
    // §xenoFormat — 4e fournisseur, format de nommage distinct (préfixe à pipe
    // fermant seul `FR| Titre`, tags `[MULTI-SUB]`). Sans lui dans ce script,
    // la validation ne voyait tout simplement pas le format qu'on gère.
    'XENO': '$dir/xenoIptv.json',
  };

  final parsed = <String, Map<String, List<String>>>{}; // provider → kind → baseTitles
  // §yearTitle — Une base réduite à un tag (« (FR HD) », « SD », « FHD ») est un
  // titre PERDU à l'écran. Ce compteur doit rester à ZÉRO.
  final degenerate = <String, List<String>>{};
  final orphan = <String, List<String>>{};
  final tagOnly = RegExp(
    r'^[\s\(\)\[\]\-_.]*'
    r'(?:FR|EN|VO|VF|VOST|VOSTFR|MULTI|SUB|AUDIO|4K|UHD|FHD|HD|SD|'
    r'HDR|DV|MULTi)'
    r'[\s\(\)\[\]\-_.]*$',
    caseSensitive: false,
  );
  final samples = <String>[];

  for (final e in files.entries) {
    final data = jsonDecode(File(e.value).readAsStringSync()) as Map<String, dynamic>;
    parsed[e.key] = {};
    for (final kind in ['live', 'vod', 'series']) {
      final list = (data[kind] as List? ?? const []);
      final bases = <String>[];
      var i = 0;
      for (final item in list) {
        if (item is! Map) continue;
        final name = (item['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        final meta = TitleMetadata.parse(name);
        bases.add(meta.groupKey); // §23b — la vraie clé de regroupement
        // §orphanBracket — Crochet/parenthèse FERMANT sans ouvrant (ou
        // l'inverse) : résidu du strip des tags sur un délimiteur MAL FORMÉ
        // côté fournisseur (`… - 2026 |HDTS]` → `… - ]`). Visible à l'écran.
        if (_unbalanced(meta.baseTitle)) {
          (orphan[e.key] ??= <String>[]).add('$name  ->  "${meta.baseTitle}"');
        }
        if (meta.baseTitle.trim().isEmpty || tagOnly.hasMatch(meta.baseTitle)) {
          (degenerate[e.key] ??= <String>[]).add('$name  ->  "${meta.baseTitle}"');
        }
        if (kind != 'live' && i < 8) {
          samples.add('[${e.key}/$kind] ${name.padRight(60).substring(0, 60)} '
              '→ base="${meta.baseTitle}" q=${meta.quality} y=${meta.year} '
              'langs=${meta.languages}');
        }
        i++;
      }
      parsed[e.key]![kind] = bases;
    }
  }

  print('── Échantillons parse ──');
  samples.forEach(print);

  print('\n── Convergence cross-listes (baseTitle, lowercase) ──');
  for (final kind in ['vod', 'series']) {
    final p = parsed['PLATINIUM']![kind]!.toSet();
    final r = parsed['PREMIUM']![kind]!.toSet();
    final v = parsed['VOD']![kind]!.toSet();
    print('$kind: PLATINIUM=${p.length} PREMIUM=${r.length} VOD=${v.length}');
    print('  P∩R=${p.intersection(r).length}  P∩V=${p.intersection(v).length}'
        '  R∩V=${r.intersection(v).length}  P∩R∩V=${p.intersection(r).intersection(v).length}');
    // §xenoFormat — Le 4e fournisseur : c'est SA convergence qui mesure le gain.
    // Avant le correctif, ses clés portaient le préfixe (`fr lanterns`) et ne
    // rencontraient donc presque jamais celles des autres listes.
    final x = parsed['XENO']![kind]!;
    final xs = x.toSet();
    print('  XENO=${xs.length} (sur ${x.length} titres, '
        '${x.length - xs.length} doublons internes fusionnés)');
    print('  X∩P=${xs.intersection(p).length}  X∩R=${xs.intersection(r).length}'
        '  X∩V=${xs.intersection(v).length}');
  }

  // Contrôles ciblés : préfixes composés qui cassaient l'ancienne regex.
  print('\n── Cas critiques ──');
  final cases = [
    // §scaryMovie — chiffre de fin du titre mangé ?
    '|FR| Scary Movie 6 (2026)',
    'Scary Movie 6 (2026)',
    'Scary Movie 6',
    'Vengeance 2 (2022)',
    'Taxi 5 (2018)',
    'Ocean\'s 8 (2018)',
    // §23b — bugs device : titre 1 char (fallback) + ponctuation préservée
    '|FR| H (1998)',
    '|FR| M.A.S.H. (1972)',
    'M.A.S.H.',
    '|VOD| V',
    '|FR| Cape Fear - Les Nerfs à vif (MULTI) FHD',
    'Cape Fear - Les Nerfs à vif (MULTI) FHD',
    'Narcos: Mexico',
    'Michael (2026) [4K DV HDR MULTi]',
    '|FR| Michael Collins (1996) (MULTI)',
    '|FR-4K| Honey Don\'t! - VOSTFR (2025)',
    '|FR-4K DV| Tant qu\'il y aura des hommes (1953)',
    '|VO|STFR| Teefa in Trouble (2018)',
    '|LEG.| Totally Killer (Dezesseis Facadas) (2023) ',
    '|VO-LEG.| Film Test (2020)',
    '|4K HDR DV| Les Dinosaures',
    'Vol à haut risque (MULTI) FHD 2025',
    'Shrek 2 (2004) [MULTi]',
    'Incredibles 2_sub',
    'Je suis une légende (2007) (4K)',
    '|DE| NATIONAL GEO ᶠᴴᴰ',
    '|FR| CANAL+ LIVE 15 HD',
    'Le voyage de Chihiro (FR) FHD 2001',
    '|FR| Le Voyage de Chihiro (2001)',
    // §parseAudit2026-06-30 — Bug A : préfixe |XX| en casse mixte (11 occ. réelles)
    "|FR-4k| L'amour dans l'objectif (2025)",
    '|Fr-4K DV| Sens unique (1987)',
    '|it| Il sentiero azzurro (2025)',
    // §parseAudit2026-06-30 — Bug B : pipes résiduels (~6 900 occ. réelles)
    '|US| ABC 3 (KIII) CORP|US| CHRISTI (H)',
    '|US| CBS 4 (WCBI) COLUMB|US| (F)',
    '|US| FOX SPORTS OHIO PL|US| (H)',
    '|DE| |DE| SKY SPORT GOLF ᶠᴴᴰ',
    '|FR-4K| All My Life || MULTI',
    // §vigilance — série arabe Titre|Année|Titre arabe : "Midterm" doit rester
    // visible (pas avalé comme faux segment de préfixe).
    '|AR-4k| Midterm | 2025 | ميد تيرم',
    // §parseAudit2026-06-30 — Bug C : exposant H265 (568 occ. réelles)
    '|IT| RAI 1 UHD ᴴ²⁶⁵',
    // §parseAudit2026-06-30 — Bug D : tag "(NN FPS)" (35 occ. réelles)
    '|AR| BEIN SPORTS MAX 1 SD (50 FPS)  (World Cup 2026™)',
    "Avatar (60FPS) ᴴ²⁶⁵ (2009) VFF",
  ];
  for (final c in cases) {
    final m = TitleMetadata.parse(c);
    print('  ${c.padRight(48)} → base="${m.baseTitle}" key="${m.groupKey}" '
        'q=${m.quality} y=${m.year} langs=${m.languages} label=${m.versionLabel}');
  }

  // §orphanBracket — Bilan des titres à délimiteur orphelin.
  print('');
  print('== Bases à crochet/parenthèse orphelin ==');
  var totalOrphan = 0;
  for (final e in orphan.entries) {
    totalOrphan += e.value.length;
    print('  ${e.key.padRight(11)} ${e.value.length}');
    for (final sample in e.value.take(5)) {
      print('      $sample');
    }
  }
  if (orphan.isEmpty) print('  aucun (attendu)');
  print('  TOTAL: $totalOrphan');

  // §yearTitle — Bilan des titres PERDUS (base vide ou réduite à un tag).
  print('');
  print('== Titres dégénérés (base vide ou réduite à un tag) ==');
  var totalDegenerate = 0;
  for (final e in degenerate.entries) {
    totalDegenerate += e.value.length;
    print('  ${e.key.padRight(11)} ${e.value.length}');
    for (final sample in e.value.take(6)) {
      print('      $sample');
    }
  }
  if (degenerate.isEmpty) print('  aucun (attendu)');
  print('  TOTAL: $totalDegenerate');
}

/// §orphanBracket — Vrai si les crochets/parenthèses ne s'équilibrent pas.
bool _unbalanced(String s) {
  var sq = 0, rd = 0;
  for (final c in s.codeUnits) {
    if (c == 0x5B) sq++;      // [
    if (c == 0x5D) sq--;      // ]
    if (c == 0x28) rd++;      // (
    if (c == 0x29) rd--;      // )
    if (sq < 0 || rd < 0) return true;
  }
  return sq != 0 || rd != 0;
}
