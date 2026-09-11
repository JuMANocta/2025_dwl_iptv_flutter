import 'dart:async';

import 'package:aetherStream/feature/player/next_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

/// Revue 2026-09-11, D2A-13 — « épisode suivant » demandé deux fois (⏭
/// pendant la résolution, puis fin de lecture) : la requête, qui fait AVANCER
/// la fiche, ne doit partir qu'une fois.
void main() {
  test('deux appels en parallèle : la requête ne part qu’UNE fois', () async {
    final resolver = NextResolver<int?>();
    final gate = Completer<int?>();
    var calls = 0;
    Future<int?> task() {
      calls++;
      return gate.future;
    }

    final a = resolver.run(task); // ⏭ dans la dernière seconde
    final b = resolver.run(task); // puis `completed`
    expect(identical(a, b), isTrue);
    expect(resolver.busy, isTrue);

    gate.complete(2);
    expect(await a, 2);
    expect(await b, 2);
    expect(calls, 1);
  });

  test('après la fin, un nouvel appel relance la requête (null redemandable)',
      () async {
    final resolver = NextResolver<int?>();
    var calls = 0;
    Future<int?> task() async {
      calls++;
      return null; // fin de série, ou réseau muet
    }

    expect(await resolver.run(task), isNull);
    expect(resolver.busy, isFalse);
    expect(await resolver.run(task), isNull);
    expect(calls, 2);
  });

  test('le mémo est déjà effacé quand l’appelant reprend la main', () async {
    final resolver = NextResolver<int>();
    final value = await resolver.run(() async => 7);
    expect(value, 7);
    expect(resolver.busy, isFalse);
  });

  test('une erreur remonte à l’appelant, puis le mémo s’efface', () async {
    final resolver = NextResolver<int>();
    await expectLater(
      resolver.run(() async => throw StateError('réseau')),
      throwsStateError,
    );
    expect(resolver.busy, isFalse);
    expect(await resolver.run(() async => 3), 3);
  });

  test('erreur synchrone de la tâche : même contrat', () async {
    final resolver = NextResolver<int>();
    await expectLater(
      resolver.run(() => throw StateError('immédiat')),
      throwsStateError,
    );
    expect(resolver.busy, isFalse);
  });

  test('reset() oublie l’appel en vol : le suivant repart à neuf', () async {
    final resolver = NextResolver<int>();
    final gate = Completer<int>();
    var calls = 0;
    final first = resolver.run(() {
      calls++;
      return gate.future;
    });
    resolver.reset(); // bascule d'épisode
    expect(resolver.busy, isFalse);
    final second = resolver.run(() async {
      calls++;
      return 9;
    });
    expect(identical(first, second), isFalse);
    expect(await second, 9);
    gate.complete(1);
    expect(await first, 1);
    expect(calls, 2);
    // L'ancien appel qui se termine après coup n'efface pas le mémo d'un
    // appel plus récent.
    final gate2 = Completer<int>();
    final third = resolver.run(() => gate2.future);
    expect(resolver.busy, isTrue);
    gate2.complete(4);
    expect(await third, 4);
  });
}
