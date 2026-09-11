import 'package:aetherStream/core/diagnostics/prefs_probe.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Revue 2026-09-11, lot 8a (D1B-14) — Les sondes des préférences ne changent
/// rien à ce qui est écrit, et l'empreinte compte ce qu'elle annonce.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('footprintOf : total et plus grosses clés', () {
    final r = PrefsProbe.footprintOf(<String, Object?>{
      'petit': 'ab',
      'gros': 'x' * 1000,
      'liste': <String>['abc', 'de'],
      'nombre': 42,
      'booleen': true,
    }, top: 2);
    expect(r.total, 2 + 1000 + 5 + 8 + 8);
    expect(r.biggest, <(String, int)>[('gros', 1000), ('nombre', 8)]);
  });

  test('setStringTimed écrit exactement la valeur encodée', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool ok = await PrefsProbe.setStringTimed(
        prefs, 'k', () => '{"a":1}',
        tag: 'test');
    expect(ok, isTrue);
    expect(prefs.getString('k'), '{"a":1}');
  });

  test('logFootprint ne lève pas (hors Android : taille du fichier inconnue)',
      () async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{'a': 'x', 'b': 3, 'c': <String>['y']});
    final List<String?> lines = <String?>[];
    final DebugPrintCallback previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => lines.add(message);
    try {
      await PrefsProbe.logFootprint(await SharedPreferences.getInstance());
    } finally {
      debugPrint = previous;
    }
    expect(lines, hasLength(1));
    expect(lines.single, contains('taille inconnue'));
    expect(lines.single, contains('3 clés'));
  });
}
