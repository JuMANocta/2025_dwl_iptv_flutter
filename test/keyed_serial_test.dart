// revue 2026-09-11, D1A-02 + D1A-04 — La file PAR CLÉ qui empêche deux
// téléchargements de liste (ou deux sauvegardes du cache analysé) du MÊME
// compte de se chevaucher dans le même `.part`, sans jamais retenir un autre
// compte.
import 'dart:async';

import 'package:aetherStream/core/utils/keyed_serial.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('même clé : le second travail attend la FIN du premier', () async {
    final KeyedSerial s = KeyedSerial();
    final List<String> log = <String>[];
    final Completer<void> gate = Completer<void>();

    final Future<int> f1 = s.run('compte', () async {
      log.add('1 début');
      await gate.future;
      log.add('1 fin');
      return 1;
    });
    final Future<int> f2 = s.run('compte', () async {
      log.add('2 début');
      return 2;
    });

    await _settle();
    expect(log, <String>['1 début'],
        reason: 'le second ne doit pas démarrer tant que le premier écrit');
    expect(s.isBusy('compte'), isTrue);

    gate.complete();
    expect(await f1, 1);
    expect(await f2, 2);
    expect(log, <String>['1 début', '1 fin', '2 début']);
    expect(s.isBusy('compte'), isFalse, reason: 'la file se vide derrière');
  });

  test('clés différentes : aucun travail n\'attend l\'autre', () async {
    final KeyedSerial s = KeyedSerial();
    final Completer<void> gate = Completer<void>();
    final List<String> log = <String>[];

    final Future<void> a = s.run('a', () async {
      log.add('a début');
      await gate.future;
    });
    final Future<void> b = s.run('b', () async {
      log.add('b début');
    });

    await b;
    expect(log, containsAll(<String>['a début', 'b début']),
        reason: 'un compte lent ne doit jamais retenir un autre compte');
    gate.complete();
    await a;
  });

  test('une erreur remonte à SON appelant et ne bloque pas la file', () async {
    final KeyedSerial s = KeyedSerial();
    final Future<void> f1 =
        s.run<void>('compte', () async => throw StateError('panne'));
    final Future<String> f2 = s.run('compte', () async => 'suivant');

    await expectLater(f1, throwsStateError);
    expect(await f2, 'suivant');
    expect(s.isBusy('compte'), isFalse);
  });

  test('l\'ordre d\'arrivée est respecté (FIFO)', () async {
    final KeyedSerial s = KeyedSerial();
    final List<int> ordre = <int>[];
    await Future.wait(<Future<void>>[
      for (var i = 0; i < 5; i++)
        s.run('compte', () async {
          await Future<void>.delayed(Duration(milliseconds: 5 - i));
          ordre.add(i);
        }),
    ]);
    expect(ordre, <int>[0, 1, 2, 3, 4]);
  });
}
