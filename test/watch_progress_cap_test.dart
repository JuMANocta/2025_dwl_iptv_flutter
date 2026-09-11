import 'dart:convert';

import 'package:aetherStream/data/services/watch_progress_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Revue 2026-09-11, D1A-17 — La table des reprises a un plafond
/// (`WatchProgressService.maxEntries`) : elle grossissait à vie et était
/// réécrite en entier toutes les 10 s de lecture. On garde les plus RÉCENTES
/// (`lastWatched`) : le hero « Reprendre » ne montre qu'elles.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const int cap = WatchProgressService.maxEntries;
  const Duration dur = Duration(minutes: 90);
  const Duration pos = Duration(minutes: 10);

  WatchProgress wp(String url, int minutesAgo) => WatchProgress(
        url: url,
        position: pos,
        duration: dur,
        lastWatched: DateTime(2026, 9, 11).subtract(Duration(minutes: minutesAgo)),
      );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    WatchProgressService.resetForTest();
  });

  test('plafond + 1 sauvegardes de titres distincts : $cap gardées, la plus '
      'ancienne oubliée', () async {
    for (int i = 0; i <= cap; i++) {
      await WatchProgressService.saveProgress('u$i', pos, dur);
    }
    expect(WatchProgressService.all.length, cap);
    expect(WatchProgressService.getProgress('u0'), isNull);
    expect(WatchProgressService.getProgress('u1'), isNotNull);
    expect(WatchProgressService.getProgress('u$cap'), isNotNull);

    // Ce qui part au disque est la table réduite.
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> stored =
        jsonDecode(prefs.getString('watch_progress_v1')!) as Map<String, dynamic>;
    expect(stored.length, cap);
    expect(stored.containsKey('u0'), isFalse);
  });

  test('mettre à jour une reprise EXISTANTE au plafond n\'oublie rien', () async {
    for (int i = 0; i < cap; i++) {
      await WatchProgressService.saveProgress('u$i', pos, dur);
    }
    await WatchProgressService.saveProgress('u0', pos * 2, dur);
    expect(WatchProgressService.all.length, cap);
    expect(WatchProgressService.getProgress('u0')!.position, pos * 2);
    expect(WatchProgressService.getProgress('u1'), isNotNull);
  });

  test('restauration d\'une sauvegarde plus grosse : les plus récentes gardées',
      () async {
    final Map<String, WatchProgress> big = <String, WatchProgress>{
      // i = 0 est la plus RÉCENTE, i = 599 la plus ancienne.
      for (int i = 0; i < 600; i++) 'u$i': wp('u$i', i),
    };
    await WatchProgressService.replaceAll(big);
    expect(WatchProgressService.all.length, cap);
    for (int i = 0; i < cap; i++) {
      expect(WatchProgressService.getProgress('u$i'), isNotNull, reason: 'u$i');
    }
    for (int i = cap; i < 600; i++) {
      expect(WatchProgressService.getProgress('u$i'), isNull, reason: 'u$i');
    }
    // Le hero « Reprendre » : les 5 plus récentes, intactes.
    final List<WatchProgress> recent = WatchProgressService.all
      ..sort((WatchProgress a, WatchProgress b) =>
          b.lastWatched.compareTo(a.lastWatched));
    expect(recent.take(5).map((WatchProgress p) => p.url).toList(),
        <String>['u0', 'u1', 'u2', 'u3', 'u4']);
  });

  test('table héritée d\'avant le plafond : réduite au chargement', () async {
    final Map<String, Object> json = <String, Object>{
      for (int i = 0; i < cap + 20; i++) 'u$i': wp('u$i', i).toJson(),
    };
    SharedPreferences.setMockInitialValues(
        <String, Object>{'watch_progress_v1': jsonEncode(json)});
    WatchProgressService.resetForTest();
    await WatchProgressService.init();
    expect(WatchProgressService.all.length, cap);
    expect(WatchProgressService.getProgress('u0'), isNotNull);
    expect(WatchProgressService.getProgress('u${cap + 19}'), isNull);
  });

  group('keysBeyondCap (pure)', () {
    test('sous le plafond : rien', () {
      expect(
          WatchProgressService.keysBeyondCap(
              <String, WatchProgress>{'a': wp('a', 1)}, 1),
          isEmpty);
    });

    test('à égalité de date : la première insérée part', () {
      final Map<String, WatchProgress> m = <String, WatchProgress>{
        'a': wp('a', 0),
        'b': wp('b', 0),
        'c': wp('c', 0),
      };
      expect(WatchProgressService.keysBeyondCap(m, 2), <String>['a']);
    });

    test('la plus ancienne part, jamais la clé protégée', () {
      final Map<String, WatchProgress> m = <String, WatchProgress>{
        'recent': wp('recent', 0),
        'old': wp('old', 100),
        'mid': wp('mid', 50),
      };
      expect(WatchProgressService.keysBeyondCap(m, 2), <String>['old']);
      // Horloge reculée : la reprise qu'on vient d'écrire paraît la plus
      // ancienne — elle reste, c'est la suivante qui part.
      expect(WatchProgressService.keysBeyondCap(m, 2, keep: 'old'),
          <String>['mid']);
    });
  });
}
