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
  // §l10nAll tranche 9 — la couche d'AFFICHAGE des catégories : ses chaînes
  // françaises sont les CLÉS métier de `m3u_filter.dart` (`case 'Comédie':`),
  // pas des textes d'interface. Le texte affiché, lui, sort de la l10n.
  'lib/feature/search/category_labels.dart',
  // Revue 2026-09-11, D1A-13 — la table des genres TMDB ne contient QUE des
  // clés de catégorie (`10763: 'Actualités'`), le vocabulaire même de
  // `m3u_filter.dart`, persisté dans `inferred_category_v3` et affiché par
  // `categoryDisplayLabel()`. Des valeurs métier, pas des textes d'interface.
  'lib/data/models/tmdb_genres.dart',
  // La console web est servie à un NAVIGATEUR : ni son HTML ni les réponses
  // JSON de son serveur ne passent par `Localizations` (surface séparée,
  // hors du système l10n de Flutter).
  'lib/feature/settings/web_console/web_console_html.dart',
  'lib/data/services/web_console_service.dart',
  'lib/data/services/remote_control_service.dart',
];

/// Marqueurs de ligne de diagnostic : jamais montré à l'utilisateur.
///
/// Revue 2026-09-11, D5A-19 — Ils sont cherchés dans la partie CODE de la
/// ligne (commentaire de fin retiré), plus dans la ligne entière : un
/// `Text('Échec'), // ignore: …` échappait au cliquet parce que le marqueur
/// vivait dans le COMMENTAIRE. `ignore:` n'est donc plus un marqueur : c'est
/// un commentaire comme un autre, retiré avec lui.
const List<String> kDiagnosticMarkers = [
  'debugPrint(',
  'NpLog.',
  'developer.log(',
  'assert(',
];

final RegExp _accented = RegExp(r'[àâäéèêëîïôöùûüçœÀÂÄÉÈÊËÎÏÔÖÙÛÜÇŒ«»]');

/// Vrai si la ligne est (au moins pour l'essentiel) un commentaire.
bool _isCommentLine(String line) {
  final t = line.trimLeft();
  return t.startsWith('//') || t.startsWith('*') || t.startsWith('/*');
}

/// Revue 2026-09-11, D3B-07 — Retire le commentaire de fin de ligne en ne
/// coupant qu'un `//` situé HORS de tout littéral.
///
/// ⚠️ L'ancien découpage coupait au PREMIER `//` de la ligne (sauf présence de
/// `://`) : `BootStatus.set('// préparation des services…')` était coupé à
/// l'intérieur même du littéral, qui n'était donc jamais examiné — tout
/// l'écran de démarrage échappait au cliquet.
///
/// Suivi des guillemets volontairement simple (une ligne à la fois) : échappe
/// `\` hors chaîne brute, ignore l'autre guillemet à l'intérieur d'un
/// littéral. Une chaîne sur plusieurs lignes laisse la fin de ligne « dans »
/// le littéral : rien n'est alors retiré, ce qui ne peut qu'AJOUTER des
/// lignes au compte, jamais en cacher.
String stripTrailingComment(String line) {
  String? quote;
  bool raw = false;
  for (int i = 0; i < line.length; i++) {
    final String c = line[i];
    if (quote != null) {
      if (!raw && c == r'\') {
        i++;
        continue;
      }
      if (c == quote) quote = null;
      continue;
    }
    if (c == "'" || c == '"') {
      raw = i > 0 && line[i - 1] == 'r';
      quote = c;
      continue;
    }
    if (c == '/' && i + 1 < line.length && line[i + 1] == '/') {
      return line.substring(0, i);
    }
  }
  return line;
}

/// Vrai si la ligne porte un littéral de chaîne contenant un accent français.
///
/// Le découpage des littéraux est volontairement grossier : on isole ce qui se
/// trouve entre guillemets simples ou doubles. Les faux positifs possibles
/// sont absorbés par le plafond, qui n'a pas besoin d'être exact.
bool hasUiFrenchLiteral(String line) {
  if (_isCommentLine(line)) return false;
  final String code = stripTrailingComment(line);
  for (final marker in kDiagnosticMarkers) {
    if (code.contains(marker)) return false;
  }
  return _hasAccentedLiteral(code);
}

bool _hasAccentedLiteral(String code) {
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

/// Le scanner d'AVANT la revue du 2026-09-11, gardé tel quel pour une seule
/// raison : prouver que le nouveau voit tout ce qu'il voyait (voir le test
/// « le scanner durci ne laisse rien passer de ce que l'ancien bloquait »).
bool legacyHasUiFrenchLiteral(String line) {
  if (_isCommentLine(line)) return false;
  for (final marker in const [...kDiagnosticMarkers, 'ignore:']) {
    if (line.contains(marker)) return false;
  }
  final int slash = line.indexOf('//');
  final String code =
      slash > 0 && !line.contains('://') ? line.substring(0, slash) : line;
  return _hasAccentedLiteral(code);
}

final RegExp _singleQuoted = RegExp(r"'([^']*)'");
final RegExp _doubleQuoted = RegExp(r'"([^"]*)"');

/// Les fichiers `.dart` examinés par le cliquet, chemin relatif en `/`.
Iterable<(String, File)> _scannedFiles() sync* {
  final dir = Directory('lib');
  if (!dir.existsSync()) return;
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final rel = entity.path.replaceAll(r'\', '/');
    if (kExcludedPaths.any(rel.contains)) continue;
    yield (rel, entity);
  }
}

/// Compte, par fichier, les lignes portant du texte français d'interface.
Map<String, int> scanLib() {
  final counts = <String, int>{};
  for (final (rel, file) in _scannedFiles()) {
    var n = 0;
    for (final line in file.readAsLinesSync()) {
      if (hasUiFrenchLiteral(line)) n++;
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

  // Revue 2026-09-11, D3B-07 + D5A-19 — le scanner a été durci. Ces deux
  // tests prouvent qu'il ne relâche RIEN : il voit tout ce que voyait
  // l'ancien, plus les deux angles morts corrigés.
  group('scanner durci (revue 2026-09-11)', () {
    test('les deux angles morts sont fermés', () {
      // D3B-07 — un `//` DANS le littéral ne coupe plus la ligne.
      const boot = "    BootStatus.set('// préparation des services…');";
      expect(legacyHasUiFrenchLiteral(boot), isFalse);
      expect(hasUiFrenchLiteral(boot), isTrue);
      // D5A-19 — un marqueur dans le COMMENTAIRE ne masque plus le code.
      const ignored = "  Text('Échec du téléchargement'), // ignore: x";
      expect(legacyHasUiFrenchLiteral(ignored), isFalse);
      expect(hasUiFrenchLiteral(ignored), isTrue);
    });

    test('ce qui n\'est pas de l\'interface reste ignoré', () {
      expect(hasUiFrenchLiteral("  debugPrint('⚠️ échec');"), isFalse);
      expect(hasUiFrenchLiteral("  assert(ok, 'état incohérent');"), isFalse);
      expect(hasUiFrenchLiteral("  foo(); // l'été 'arrivé'"), isFalse);
      expect(hasUiFrenchLiteral("// Text('Échec')"), isFalse);
    });

    test('ce que l\'ancien voyait, le nouveau le voit', () {
      for (final line in const [
        "  Text('Télécharger'), // voir http://x",
        "  final u = 'https://exemple.fr/été';",
        '  Text("l\'été"), // commentaire',
        "  label: 'Réessayer',",
      ]) {
        expect(legacyHasUiFrenchLiteral(line), isTrue, reason: line);
        expect(hasUiFrenchLiteral(line), isTrue, reason: line);
      }
    });

    test('le scanner durci ne laisse rien passer de ce que l\'ancien bloquait',
        () {
      // Sur TOUT le code réel : chaque ligne que l'ancien scanner comptait
      // doit l'être encore. Une seule exception serait un littéral
      // d'interface devenu invisible — le contraire du but.
      final escaped = <String>[];
      for (final (rel, file) in _scannedFiles()) {
        final lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          if (legacyHasUiFrenchLiteral(lines[i]) &&
              !hasUiFrenchLiteral(lines[i])) {
            escaped.add('$rel:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
      expect(escaped, isEmpty, reason: escaped.join('\n'));
    });
  });

  test('§l10nAll — les exclusions restent justifiées', () {
    // Si l'un de ces fichiers disparaît ou change de rôle, l'exclusion doit
    // être revue plutôt que traînée indéfiniment.
    expect(File('lib/feature/search/m3u_filter.dart').existsSync(), isTrue,
        reason: 'm3u_filter.dart exclu du scan : ses chaînes sont des valeurs '
            'métier persistées. Si le fichier bouge, revoir kExcludedPaths.');
    expect(File('lib/feature/search/category_labels.dart').existsSync(), isTrue,
        reason: 'category_labels.dart exclu du scan : ses chaînes sont les CLÉS '
            'de m3u_filter.dart, pas des textes. Si le fichier bouge, revoir '
            'kExcludedPaths — et verifier que les rangees de la home '
            'passent toujours par categoryDisplayLabel().');
    expect(File('lib/data/models/tmdb_genres.dart').existsSync(), isTrue,
        reason: 'tmdb_genres.dart exclu du scan : ses chaînes sont les CLÉS '
            'de catégorie de m3u_filter.dart. Si le fichier bouge, revoir '
            'kExcludedPaths.');
  });
}
