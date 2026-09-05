// §catMeter (2026-09-05) — Mesure du RANGEMENT des catégories sur la liste
// RÉELLE, et garde-fou contre les régressions.
//
// **Pourquoi ce fichier existe, et pourquoi c'est un test et pas un outil.**
// La mesure devait aller dans `tool/validate_parse.dart` (lancé par
// `driver.sh catalog`). Impossible : `contentCategoryMatch` vit dans
// `m3u_filter.dart`, qui importe `TmdbGroupAliasService` → `ValueNotifier` →
// `package:flutter/foundation` → `dart:ui`. Un `dart run` en VM pure ne peut
// pas le charger (« 'Image' isn't a type », mesuré). Sous `flutter test`, si.
//
// **Ce que ça mesure, et pourquoi ces deux compteurs-là.** La mémoire du projet
// disait « `contentCategoryLabel` traduit déjà 100 % de ce qu'on lui donne » —
// mais « classé » y voulait dire « a reçu un libellé », pas « le bon ». Deux
// angles morts en découlaient, tous deux invisibles d'un compteur classé/non
// classé :
//   1. **le repli littéral** — un group-title qu'aucun mot-clé ne reconnaît
//      devient une rangée en majuscules. Ensemble OUVERT : chaque valeur
//      nouvelle du fournisseur ajoute une rangée à l'accueil.
//   2. **la plus grosse rangée** — un test trop large et trop haut dans la
//      cascade avale tout le reste. Mesuré avant correctif : `PARAMOUNT`,
//      testé avant les genres, captait **51 % des séries** dans une seule
//      rangée parce que ce fournisseur suffixe TOUS ses group-titles séries
//      par `( NETFLIX| … | PARAMOUNT+ )`.
//
// ⚠️ Le dump `lib/iptv_exemple/playlist_racine_2025-12.m3u` n'est **pas
// versionné** : sur un clone frais, l'audit s'annonce ignoré au lieu d'échouer.
// C'est le SEUL dump exploitable — les 4 caches JSON ne portent qu'un
// `category_id` numérique (le nom est injecté à l'exécution par
// `XtreamCatalogService._injectCategoryNames`), et `VOD_get.m3u` (format
// « Ultimate ») n'a aucun `group-title`.

import 'dart:convert';
import 'dart:io';

import 'package:aetherStream/feature/search/m3u_filter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Un group-title réel + le type d'entrée, tels que lus dans le dump.
typedef _Row = ({String kind, String group});

/// Lit le dump. `null` si absent (clone frais).
List<_Row>? _readDump() {
  final file = File('lib/iptv_exemple/playlist_racine_2025-12.m3u');
  if (!file.existsSync()) return null;

  final rows = <_Row>[];
  final groupRe = RegExp(r'group-title="([^"]*)"');
  String? pendingGroup;
  var pendingHasExtinf = false;

  for (final line in file
      .readAsLinesSync(encoding: const Utf8Codec(allowMalformed: true))) {
    if (line.startsWith('#EXTINF')) {
      pendingGroup = groupRe.firstMatch(line)?.group(1);
      pendingHasExtinf = true;
      continue;
    }
    if (!pendingHasExtinf || line.isEmpty || line.startsWith('#')) continue;
    pendingHasExtinf = false;
    // ⚠️ Le TYPE vient du CHEMIN de l'URL, jamais du titre : c'est la
    // convention Xtream (`/movie/`, `/series/`), et c'est aussi ce que fait
    // `testbed/make_playlist.py`.
    final url = line.toLowerCase();
    rows.add((
      kind: url.contains('/movie/')
          ? 'films'
          : (url.contains('/series/') ? 'series' : 'tv'),
      group: pendingGroup ?? '',
    ));
  }
  return rows;
}

void main() {
  final rows = _readDump();

  test('§catMeter — audit du rangement des catégories (liste réelle)', () {
    if (rows == null) {
      // ignore: avoid_print
      print('⏭️  playlist_racine_2025-12.m3u absent — audit ignoré '
          '(dump non versionné).');
      return;
    }

    final counts = <String, Map<String, int>>{
      'films': {},
      'series': {},
      'tv': {},
    };
    final literals = <String, Map<String, int>>{
      'films': {},
      'series': {},
      'tv': {},
    };
    final sources = <CategorySource, int>{};
    var noGroup = 0;

    for (final row in rows) {
      final match =
          row.group.isEmpty ? null : contentCategoryMatch(row.group);
      if (match == null) {
        noGroup++;
        continue;
      }
      sources[match.source] = (sources[match.source] ?? 0) + 1;
      counts[row.kind]![match.label] =
          (counts[row.kind]![match.label] ?? 0) + 1;
      if (match.source == CategorySource.literal) {
        literals[row.kind]![row.group] =
            (literals[row.kind]![row.group] ?? 0) + 1;
      }
    }

    final buf = StringBuffer()
      ..writeln('')
      ..writeln('== §catMeter — catégories (playlist_racine, '
          '${rows.length} entrées) ==');
    final total = sources.values.fold<int>(0, (a, b) => a + b);
    buf.writeln('  classées : $total   (sans group-title : $noGroup)');
    buf.writeln('  par provenance :');
    for (final s in CategorySource.values) {
      final n = sources[s] ?? 0;
      final pct = total == 0 ? 0.0 : n * 100 / total;
      buf.writeln('    ${s.name.padRight(9)} ${n.toString().padLeft(7)}'
          '  ${pct.toStringAsFixed(1).padLeft(5)} %');
    }

    // ── Compteur 1 : repli littéral ──────────────────────────────────────
    buf
      ..writeln('')
      ..writeln('  -- Repli littéral (chaque valeur = une rangée de plus) --');
    var litEntries = 0, litDistinct = 0;
    for (final kind in const ['films', 'series', 'tv']) {
      final m = literals[kind]!;
      final n = m.values.fold<int>(0, (a, b) => a + b);
      litEntries += n;
      litDistinct += m.length;
      buf.writeln('    ${kind.padRight(7)} ${n.toString().padLeft(7)} entrées '
          'dans ${m.length} group-titles distincts');
    }
    buf.writeln('    TOTAL   ${litEntries.toString().padLeft(7)} entrées '
        'dans $litDistinct group-titles distincts');
    final allLiterals = <String, int>{};
    for (final m in literals.values) {
      m.forEach((k, v) => allLiterals[k] = (allLiterals[k] ?? 0) + v);
    }
    final topLiterals = allLiterals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in topLiterals.take(30)) {
      buf.writeln('      ${e.value.toString().padLeft(6)}  ${e.key}');
    }

    // ── Compteur 2 : plus grosse rangée ──────────────────────────────────
    buf
      ..writeln('')
      ..writeln('  -- Plus grosse rangée par type (cible : < 15 %) --');
    for (final kind in const ['films', 'series', 'tv']) {
      final m = counts[kind]!;
      if (m.isEmpty) {
        buf.writeln('    ${kind.padRight(7)} (aucune)');
        continue;
      }
      final n = m.values.fold<int>(0, (a, b) => a + b);
      final top = m.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final pct = top.first.value * 100 / n;
      buf.writeln('    ${kind.padRight(7)} '
          '${m.length.toString().padLeft(3)} rangées · la plus grosse '
          '« ${top.first.key} » ${top.first.value}/$n '
          '(${pct.toStringAsFixed(1)} %)${pct >= 15 ? '  ⚠️' : ''}');
      for (final e in top.take(6)) {
        buf.writeln('        ${e.value.toString().padLeft(6)}  ${e.key}');
      }
    }

    // ── Bonus : régions reléguées mais non masquables ────────────────────
    final relegatedNotHideable = kForeignRegionLabels
        .where((r) => !kHideableRegionLabels.contains(r))
        .toList()
      ..sort();
    buf
      ..writeln('')
      ..writeln('  -- Régions reléguées mais NON masquables (cible : 0) --')
      ..writeln(relegatedNotHideable.isEmpty
          ? '    aucune (attendu)'
          : '    ${relegatedNotHideable.length} : '
              '${relegatedNotHideable.join(', ')}');

    // ignore: avoid_print
    print(buf);
  });

  // ── Garde-fous chiffrés ────────────────────────────────────────────────
  // Ils échouent si le rangement se remet à écraser tout dans un seau, ou si
  // le repli littéral repart à la hausse. Les seuils viennent de la mesure
  // APRÈS §catFix, avec de la marge : ce sont des garde-fous, pas des cibles.
  test('§catFix — aucune rangée n\'avale plus de 15 % des séries', () {
    if (rows == null) return;
    final counts = <String, int>{};
    for (final row in rows.where((r) => r.kind == 'series')) {
      final match =
          row.group.isEmpty ? null : contentCategoryMatch(row.group);
      if (match == null) continue;
      counts[match.label] = (counts[match.label] ?? 0) + 1;
    }
    if (counts.isEmpty) return;
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final pct = top.value * 100 / total;
    expect(
      pct,
      lessThan(15),
      reason: 'La rangée « ${top.key} » capte ${pct.toStringAsFixed(1)} % des '
          'séries ($top.value/$total). Un test trop large et trop haut dans '
          'la cascade de contentCategoryLabel avale les genres — c\'était le '
          'cas de PARAMOUNT (51 %) avant §catFix.',
    );
  });

  test('§catFix — une plateforme ne classe que si elle est seule', () {
    // Le cas RÉEL qui a produit les 51 % : le suffixe fournisseur.
    expect(
      contentCategoryLabel(
          'COMEDIE ( NETFLIX| PRIME | HBO | APPLE TV+ | STARZ | PARAMOUNT+ )'),
      'Comédie',
    );
    expect(
      contentCategoryLabel(
          'DRAME ( NETFLIX| PRIME | HBO | APPLE TV+ | STARZ | PARAMOUNT+ )'),
      'Drame',
    );
    // Une plateforme SEULE reste une catégorie légitime.
    expect(contentCategoryLabel('PARAMOUNT+'), 'Paramount+');
    expect(contentCategoryLabel('DISNEY +'), 'Disney+');
    // ⚠️ Régression constatée : une chaîne de SPORT capturée par « DISNEY ».
    expect(
      contentCategoryLabel(
          "FR CANAL+ LIVE | DISNEY+ WOMEN'S CHAMPION'S LEAGUE (France)"),
      'Sport',
    );
  });
}
