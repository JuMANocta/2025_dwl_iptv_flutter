// Obfuscation (revue 2026-09-11, lot 9) — Le build de production passe
// `--obfuscate` : les noms de classes Dart y deviennent des suites de lettres.
// Tout `runtimeType` qui atteint l'ÉCRAN (ou une comparaison) devient donc du
// charabia — c'était le cas du détail d'échec d'une liste dans la page
// Comptes (`playlist_fleet_service.dart`, remplacé par `describeError`).
//
// Ce test tient la liste des SEULS fichiers où `runtimeType` reste permis, et
// pourquoi. Ajouter un fichier ici = justifier que le nom n'est jamais montré
// à l'utilisateur ni comparé à une chaîne écrite en dur.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const Map<String, String> _allowed = {
  // §tvLogs — traces de focus du journal de diagnostic : illisibles dans un
  // APK obfusqué (on diagnostique sur un build local non obfusqué), jamais
  // montrées dans l'interface.
  'lib/core/diagnostics/log_buffer.dart': 'diagnostic',
  // §dpadRestore — identifiant de route pour la mémoire de focus : seule
  // l'UNICITÉ compte, et l'obfuscation la préserve.
  'lib/core/navigation/focus_route_memory.dart': 'identité',
  // `ValueKey(screen.runtimeType.toString())` du sélecteur de lancement :
  // une clé, jamais affichée ; l'obfuscation garde des noms distincts.
  'lib/main.dart': 'identité',
};

void main() {
  test('runtimeType n\'apparaît que dans les fichiers autorisés', () {
    final List<String> offenders = [];
    for (final FileSystemEntity f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final String path = f.path.replaceAll(r'\', '/');
      if (path.startsWith('lib/l10n/')) continue; // généré
      if (_allowed.containsKey(path)) continue;
      final List<String> lines = f.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final String t = lines[i].trimLeft();
        if (t.startsWith('//')) continue; // un commentaire n'exécute rien
        if (t.contains('runtimeType')) offenders.add('$path:${i + 1}');
      }
    }
    expect(offenders, isEmpty,
        reason: 'Un nom de classe devient illisible dans l\'APK obfusqué. '
            'Montrer describeError(e) plutôt que e.runtimeType ; sinon, '
            'justifier le fichier dans _allowed.');
  });
}
