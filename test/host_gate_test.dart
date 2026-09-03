import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/core/utils/host_gate.dart';

/// §hostGate — Le portillon qui sérialise les requêtes vers un même panel.
///
/// Les abonnements IPTV de l'utilisateur sont en « Connexions 1 / 1 » : deux
/// requêtes simultanées vers le même serveur et le panel en refuse une par un
/// `403 Too many connections`. Ce fichier verrouille les propriétés dont tout
/// le reste dépend — en particulier **la restitution du jeton en cas
/// d'exception** : sans elle, un seul échec réseau bloquerait l'hôte jusqu'au
/// prochain démarrage de l'application.
void main() {
  const a = 'http://panel-a.tv:8080/player_api.php?username=u&password=p';
  const b = 'http://panel-b.tv:8080/player_api.php?username=u&password=p';

  setUp(HostGate.resetForTest);
  tearDown(HostGate.resetForTest);

  /// Laisse tourner les microtâches et les timers à échéance nulle.
  Future<void> settle([int rounds = 8]) async {
    for (var i = 0; i < rounds; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  group('profondeur', () {
    test('un seul corps tourne à la fois par hôte', () async {
      final c1 = Completer<String>();
      final c2 = Completer<String>();
      final started = <int>[];

      final f1 = HostGate.run<String>(a, () {
        started.add(1);
        return c1.future;
      });
      final f2 = HostGate.run<String>(a, () {
        started.add(2);
        return c2.future;
      });
      await settle();

      expect(started, [1], reason: 'le 2e doit attendre son tour');
      expect(HostGate.queueDepth(a), 1);
      expect(HostGate.activeCount(a), 1);

      c1.complete('un');
      await settle();
      expect(started, [1, 2]);
      expect(HostGate.queueDepth(a), 0);

      c2.complete('deux');
      expect(await f1, 'un');
      expect(await f2, 'deux');
      expect(HostGate.activeCount(a), 0, reason: 'tous les jetons sont rendus');
    });

    test('ordre FIFO — pas de resquillage', () async {
      final gate = Completer<void>();
      final order = <int>[];
      final futures = <Future<void>>[];

      futures.add(HostGate.run<void>(a, () => gate.future));
      await settle();
      for (var i = 1; i <= 4; i++) {
        futures.add(HostGate.run<void>(a, () async => order.add(i)));
        // Une attente entre chaque inscription : l'ordre d'arrivée est net.
        await settle(2);
      }

      expect(HostGate.queueDepth(a), 4);
      gate.complete();
      await settle(20);
      await Future.wait(futures);
      expect(order, [1, 2, 3, 4]);
    });

    test('deux hôtes différents ne se bloquent pas', () async {
      final ca = Completer<void>();
      final cb = Completer<void>();
      var startedB = false;

      HostGate.run<void>(a, () => ca.future);
      final fb = HostGate.run<void>(b, () async {
        startedB = true;
        return cb.future;
      });
      await settle();

      expect(startedB, isTrue, reason: 'panel-b n\'attend pas panel-a');
      expect(HostGate.queueDepth(b), 0);
      cb.complete();
      await fb;
      ca.complete();
    });
  });

  group('setLimit', () {
    test('une limite de 2 laisse passer deux corps', () async {
      HostGate.setLimit('http://panel-a.tv:8080', 2);
      expect(HostGate.limitFor(a), 2);

      final started = <int>[];
      final c = List.generate(3, (_) => Completer<void>());
      for (var i = 0; i < 3; i++) {
        HostGate.run<void>(a, () {
          started.add(i);
          return c[i].future;
        });
      }
      await settle();

      expect(started, [0, 1]);
      expect(HostGate.queueDepth(a), 1);
      c[0].complete();
      await settle();
      expect(started, [0, 1, 2]);
      c[1].complete();
      c[2].complete();
      await settle();
    });

    test('relever la limite libère immédiatement les appels en attente',
        () async {
      final gate = Completer<void>();
      var second = false;
      HostGate.run<void>(a, () => gate.future);
      await settle();
      HostGate.run<void>(a, () async => second = true);
      await settle();
      expect(second, isFalse);

      HostGate.setLimit(a, 2);
      await settle();
      expect(second, isTrue, reason: 'le drain doit suivre le setLimit');
      gate.complete();
      await settle();
    });

    test('une limite < 1 est ramenée à 1 (jamais de file bloquée)', () {
      HostGate.setLimit(a, 0);
      expect(HostGate.limitFor(a), 1);
      HostGate.setLimit(a, -5);
      expect(HostGate.limitFor(a), 1);
    });

    test('URL complète et hôte nu partagent la MÊME file', () async {
      // Sinon `setLimit(creds.host, …)` réglerait une file que `run(url, …)`
      // n'utilise jamais — le portillon serait décoratif.
      HostGate.setLimit('panel-a.tv:8080', 3);
      expect(HostGate.limitFor(a), 3);
      expect(HostGate.hostKeyOf(a), HostGate.hostKeyOf('panel-a.tv:8080'));
      expect(HostGate.hostKeyOf('HTTP://Panel-A.TV:8080/x'),
          HostGate.hostKeyOf(a));
      // Le port implicite est explicité : http → 80, https → 443.
      expect(HostGate.hostKeyOf('http://x.tv/a'), 'http://x.tv:80');
      expect(HostGate.hostKeyOf('https://x.tv/a'), 'https://x.tv:443');
    });
  });

  group('robustesse', () {
    test('⚠️ une exception REND le jeton (sinon l\'hôte est mort à vie)',
        () async {
      await expectLater(
        HostGate.run<void>(a, () async => throw StateError('boum')),
        throwsA(isA<StateError>()),
      );
      expect(HostGate.activeCount(a), 0);

      // La preuve : un appel suivant doit passer immédiatement.
      var passed = false;
      await HostGate.run<void>(a, () async => passed = true);
      expect(passed, isTrue);
    });

    test('une exception dans un corps en file ne bloque pas la suite',
        () async {
      final gate = Completer<void>();
      HostGate.run<void>(a, () => gate.future);
      await settle();
      final boom = HostGate.run<void>(a, () async => throw StateError('boum'));
      var third = false;
      final f3 = HostGate.run<void>(a, () async => third = true);

      gate.complete();
      await expectLater(boom, throwsA(isA<StateError>()));
      await f3;
      expect(third, isTrue);
      expect(HostGate.activeCount(a), 0);
      expect(HostGate.queueDepth(a), 0);
    });

    test('attente trop longue → HostGateTimeoutException, file propre',
        () async {
      final gate = Completer<void>();
      HostGate.run<void>(a, () => gate.future);
      await settle();

      await expectLater(
        HostGate.run<void>(a, () async {}, timeout: const Duration(milliseconds: 30)),
        throwsA(isA<HostGateTimeoutException>()),
      );
      // Le candidat abandonné ne doit pas rester dans la file, sinon il volerait
      // le jeton du suivant.
      expect(HostGate.queueDepth(a), 0);

      gate.complete();
      await settle();
      var after = false;
      await HostGate.run<void>(a, () async => after = true);
      expect(after, isTrue);
    });

    test('URL non analysable → exécutée SANS garde', () async {
      const bad = 'pas une url du tout';
      expect(HostGate.hostKeyOf(bad), isNull);
      expect(HostGate.hostKeyOf(''), isNull);

      final c1 = Completer<void>();
      var started2 = false;
      HostGate.run<void>(bad, () => c1.future);
      final f2 = HostGate.run<void>(bad, () async => started2 = true);
      await settle();

      expect(started2, isTrue,
          reason: 'on ne bloque jamais sur un cas qu\'on ne sait pas nommer');
      await f2;
      c1.complete();
    });
  });
}
