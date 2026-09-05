// §l10nAll (2026-09-05) — **Le cliquet.**
//
// L'app compte ≈ 870 lignes de texte français écrites en dur, pour 116 clés
// traduites. Les traduire toutes d'un coup est impossible ; les traduire par
// tranches ne sert à rien si de nouvelles apparaissent en même temps.
//
// Ce test fige donc un **plafond par fichier** (`test/l10n_allowlist.txt`) et
// échoue si :
//   1. un fichier dépasse son plafond (une chaîne en dur a été AJOUTÉE) ;
//   2. un fichier absent de la liste se met à en contenir (nouveau fichier
//      écrit sans l10n).
// Un fichier qui DESCEND sous son plafond ne fait rien échouer — c'est le sens
// du cliquet. On abaisse la liste à chaque tranche, avec `--regen`.
//
// **Régénérer après une tranche :**
//   AS_L10N_REGEN=1 flutter test test/l10n_guard_test.dart
//
// ⚠️ **Ce que ce test NE compte PAS, et pourquoi.**
// - Les **commentaires** : ils sont en français par convention de projet.
// - Les **diagnostics** (`debugPrint`, `log`, `assert`) : ils ne s'affichent
//   jamais à l'utilisateur.
// - `lib/feature/search/m3u_filter.dart` : ses chaînes sont des **valeurs
//   métier** ('Comédie', 'Turc'…), comparées, persistées dans le cache et dans
//   le `.aether`. Les traduire CASSERAIT le filtre régions et les catégories.
//   Il leur faut une couche d'AFFICHAGE (clé stable → libellé traduit), qui est
//   la tranche 9 de §l10nAll — pas une traduction en place.
// - `lib/feature/settings/web_console/web_console_html.dart` : du HTML servi à
//   un navigateur, hors du système l10n de Flutter.
// - `lib/l10n/` : les fichiers générés portent évidemment les traductions.
//
// ⚠️ La mesure est volontairement SIMPLE et déterministe (une ligne qui porte
// un littéral accentué compte pour un). Elle n'a pas à être exacte : elle doit
// être **stable** et **monotone**. Un compteur savant qui varie d'une version
// de Dart à l'autre ne serait plus un cliquet.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Fichiers dont les chaînes françaises ne sont PAS de l'interface.
const List<String> kExcludedPaths = [
  'lib/l10n/',
  'lib/feature/search/m3u_filter.dart',
  'lib/feature/settings/web_console/web_console_html.dart',
];

/// Marqueurs de ligne de diagnostic : jamais montré à l'utilisateur.
const List<String> kDiagnosticMarkers = [
  'debugPrint(',
  'NpLog.',
  'developer.log(',
  'assert(',
  'ignore:',
];

final RegExp _accented = RegExp(r'[àâäéèêëîïôöùûüçœÀÂÄÉÈÊËÎÏÔÖÙÛÜÇŒ«»]');

/// Vrai si la ligne est (au moins pour l'essentiel) un commentaire.
bool _isCommentLine(String line) {
  final t = line.trimLeft();
  return t.startsWith('//') || t.startsWith('*') || t.startsWith('/*');
}

/// Vrai si la ligne porte un littéral de chaîne contenant un accent français.
///
/// Le découpage des littéraux est volontairement grossier : on isole ce qui se
/// trouve entre guillemets simples ou doubles. Les faux positifs possibles
/// (apostrophe typographique dans un commentaire de fin de ligne) sont absorbés
/// par le plafond, qui n'a pas besoin d'être exact.
bool _hasUiFrenchLiteral(String line) {
  if (_isCommentLine(line)) return false;
  for (final marker in kDiagnosticMarkers) {
    if (line.contains(marker)) return false;
  }
  // Retire un commentaire de fin de ligne évident (pas de `//` dans une URL).
  final int slash = line.indexOf('//');
  final String code =
      slash > 0 && !line.contains('://') ? line.substring(0, slash) : line;

  // ⚠️ Deux expressions séparées, chacune délimitée par l'AUTRE guillemet :
  // une chaîne brute Dart ne peut pas contenir son propre délimiteur, même
  // échappé — un premier jet en une seule regex ne compilait pas, avec un
  // message d'erreur qui désignait la mauvaise ligne.
  for (final re in [_singleQuoted, _doubleQuoted]) {
    for (final m in re.allMatches(code)) {
      if (_accented.hasMatch(m.group(1) ?? '')) return true;
    }
  }
  return false;
}

final RegExp _singleQuoted = RegExp(r"'([^']*)'");
final RegExp _doubleQuoted = RegExp(r'"([^"]*)"');

/// Compte, par fichier, les lignes portant du texte français d'interface.
Map<String, int> scanLib() {
  final counts = <String, int>{};
  final dir = Directory('lib');
  if (!dir.existsSync()) return counts;

  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final rel = entity.path.replaceAll(r'\', '/');
    if (kExcludedPaths.any(rel.contains)) continue;

    var n = 0;
    for (final line in entity.readAsLinesSync()) {
      if (_hasUiFrenchLiteral(line)) n++;
    }
    if (n > 0) counts[rel] = n;
  }
  return counts;
}

File get _allowlistFile => File('test/l10n_allowlist.txt');

Map<String, int> _readAllowlist() {
  if (!_allowlistFile.existsSync()) return {};
  final out = <String, int>{};
  for (final line in _allowlistFile.readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final i = t.lastIndexOf(' ');
    if (i <= 0) continue;
    final n = int.tryParse(t.substring(i + 1));
    if (n != null) out[t.substring(0, i).trim()] = n;
  }
  return out;
}

void _writeAllowlist(Map<String, int> counts) {
  final keys = counts.keys.toList()..sort();
  final total = counts.values.fold<int>(0, (a, b) => a + b);
  final buf = StringBuffer()
    ..writeln('# §l10nAll — plafond de chaînes françaises en dur, par fichier.')
    ..writeln('#')
    ..writeln('# Généré par : AS_L10N_REGEN=1 flutter test test/l10n_guard_test.dart')
    ..writeln('# Ce fichier ne doit JAMAIS remonter : chaque tranche de')
    ..writeln('# traduction l\'abaisse. Un total qui augmente = une régression.')
    ..writeln('#')
    ..writeln('# TOTAL : $total lignes dans ${counts.length} fichiers.')
    ..writeln('');
  for (final k in keys) {
    buf.writeln('$k ${counts[k]}');
  }
  _allowlistFile.writeAsStringSync(buf.toString());
}

void main() {
  final counts = scanLib();

  test('§l10nAll — aucune nouvelle chaîne française en dur', () {
    if (Platform.environment['AS_L10N_REGEN'] == '1') {
      _writeAllowlist(counts);
      // ignore: avoid_print
      print('♻️  test/l10n_allowlist.txt régénéré — '
          '${counts.values.fold<int>(0, (a, b) => a + b)} lignes dans '
          '${counts.length} fichiers.');
      return;
    }

    final allowed = _readAllowlist();
    expect(allowed, isNotEmpty,
        reason: 'test/l10n_allowlist.txt manquant ou vide — le regénérer avec '
            'AS_L10N_REGEN=1 flutter test test/l10n_guard_test.dart');

    final over = <String>[];
    final newFiles = <String>[];
    counts.forEach((file, n) {
      final ceiling = allowed[file];
      if (ceiling == null) {
        newFiles.add('$file ($n)');
      } else if (n > ceiling) {
        over.add('$file : $n > $ceiling');
      }
    });

    expect(newFiles, isEmpty,
        reason: 'Fichier(s) avec du texte français en dur absent(s) de la '
            'liste. Utiliser `context.l10n` (widgets) ou `L10n.current` '
            '(services) — voir lib/l10n/l10n_ext.dart. Si la chaîne n\'est PAS '
            'de l\'interface (valeur métier, diagnostic), l\'exclure dans '
            'kExcludedPaths avec la raison.\n${newFiles.join('\n')}');

    expect(over, isEmpty,
        reason: 'Chaîne(s) française(s) AJOUTÉE(S) en dur. Le plafond ne '
            'remonte jamais : traduire, ou justifier.\n${over.join('\n')}');
  });

  test('§l10nAll — le total ne remonte pas', () {
    if (Platform.environment['AS_L10N_REGEN'] == '1') return;
    final allowed = _readAllowlist();
    if (allowed.isEmpty) return;
    final int now = counts.values.fold<int>(0, (a, b) => a + b);
    final int ceiling = allowed.values.fold<int>(0, (a, b) => a + b);
    expect(now, lessThanOrEqualTo(ceiling),
        reason: 'Total des chaînes en dur : $now (plafond $ceiling). '
            'Chaque tranche de §l10nAll doit le faire BAISSER.');
  });

  test('§l10nAll — les exclusions restent justifiées', () {
    // Si l'un de ces fichiers disparaît ou change de rôle, l'exclusion doit
    // être revue plutôt que traînée indéfiniment.
    expect(File('lib/feature/search/m3u_filter.dart').existsSync(), isTrue,
        reason: 'm3u_filter.dart exclu du scan : ses chaînes sont des valeurs '
            'métier persistées. Si le fichier bouge, revoir kExcludedPaths.');
  });
}
