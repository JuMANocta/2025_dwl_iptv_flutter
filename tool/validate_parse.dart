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
  };

  final parsed = <String, Map<String, List<String>>>{}; // provider → kind → baseTitles
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
  }

  // Contrôles ciblés : préfixes composés qui cassaient l'ancienne regex.
  print('\n── Cas critiques ──');
  final cases = [
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
  ];
  for (final c in cases) {
    final m = TitleMetadata.parse(c);
    print('  ${c.padRight(48)} → base="${m.baseTitle}" key="${m.groupKey}" '
        'q=${m.quality} y=${m.year} langs=${m.languages} label=${m.versionLabel}');
  }
}
