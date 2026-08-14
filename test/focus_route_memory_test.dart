import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/core/navigation/focus_route_memory.dart';

/// §dpadRestore — Régression du « rechargement » ressenti au retour.
///
/// Le package `dpad` force un focus de secours dès que le nœud focalisé meurt.
/// Son repli choisit le premier item marqué `entry` du scope — et comme chaque
/// rangée de l'accueil marque sa 1re carte comme `entry`, on atterrissait
/// toujours sur la toute première carte, avec un auto-scroll qui remontait la
/// liste en haut. Ces tests verrouillent le contrat inverse : **le focus revient
/// là où l'utilisateur l'a laissé**, et la mémoire ne fuit pas.

class _FirstPage extends StatelessWidget {
  final FocusNode decoy;
  final FocusNode origin;
  const _FirstPage({required this.decoy, required this.origin});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Placé en premier : c'est la cible qu'un repli « premier focusable »
          // choisirait. S'il gagne, la restauration a échoué.
          Focus(focusNode: decoy, child: const SizedBox(width: 40, height: 40)),
          Focus(focusNode: origin, child: const SizedBox(width: 40, height: 40)),
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () => Navigator.of(ctx).push(
                MaterialPageRoute<void>(builder: (_) => const _SecondPage()),
              ),
              child: const Text('ouvrir'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecondPage extends StatelessWidget {
  const _SecondPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Builder(
        builder: (ctx) => TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('fermer'),
        ),
      ),
    );
  }
}

void main() {
  group('FocusRouteMemory', () {
    testWidgets('le focus revient sur le nœud d\'origine après un pop',
        (tester) async {
      final observer = FocusRouteMemory();
      final decoy = FocusNode(debugLabel: 'decoy');
      final origin = FocusNode(debugLabel: 'origin');
      addTearDown(decoy.dispose);
      addTearDown(origin.dispose);

      await tester.pumpWidget(MaterialApp(
        navigatorObservers: <NavigatorObserver>[observer],
        home: _FirstPage(decoy: decoy, origin: origin),
      ));

      origin.requestFocus();
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, origin);

      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      expect(observer.trackedRouteCount, 1);
      expect(FocusManager.instance.primaryFocus, isNot(origin));

      await tester.tap(find.text('fermer'));
      await tester.pumpAndSettle();

      expect(FocusManager.instance.primaryFocus, origin,
          reason: 'le focus doit revenir sur la carte d\'où l\'on est parti');
      expect(FocusManager.instance.primaryFocus, isNot(decoy));
      expect(observer.trackedRouteCount, 0,
          reason: 'la mémoire de la route est libérée après restauration');
    });

    testWidgets('rien de focalisé au push → rien à mémoriser', (tester) async {
      final observer = FocusRouteMemory();
      final decoy = FocusNode(debugLabel: 'decoy');
      final origin = FocusNode(debugLabel: 'origin');
      addTearDown(decoy.dispose);
      addTearDown(origin.dispose);

      await tester.pumpWidget(MaterialApp(
        navigatorObservers: <NavigatorObserver>[observer],
        home: _FirstPage(decoy: decoy, origin: origin),
      ));

      // On pousse sans avoir donné de focus réel au préalable.
      final BuildContext ctx = tester.element(find.text('ouvrir'));
      Navigator.of(ctx).push(
        MaterialPageRoute<void>(builder: (_) => const _SecondPage()),
      );
      await tester.pumpAndSettle();
      expect(observer.trackedRouteCount, 0);
    });

    test('didRemove et didReplace purgent la mémoire', () {
      final observer = FocusRouteMemory();
      final a = MaterialPageRoute<void>(builder: (_) => const SizedBox());
      final b = MaterialPageRoute<void>(builder: (_) => const SizedBox());

      // Aucun focus réel en test pur → didPush ne mémorise rien, mais les
      // purges doivent rester sûres (pas d'exception, pas de fuite).
      observer.didPush(b, a);
      observer.didRemove(a, null);
      expect(observer.trackedRouteCount, 0);

      observer.didReplace(newRoute: b, oldRoute: a);
      expect(observer.trackedRouteCount, 0);
    });
  });

  group('FocusSnapshot', () {
    testWidgets('restaure le nœud capturé après une bascule d\'onglet',
        (tester) async {
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Column(children: [
          Focus(focusNode: a, child: const SizedBox(width: 10, height: 10)),
          Focus(focusNode: b, child: const SizedBox(width: 10, height: 10)),
        ]),
      ));

      a.requestFocus();
      await tester.pump();
      final snap = FocusSnapshot.capture();

      b.requestFocus();
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, b);

      snap.restore();
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, a);
    });

    testWidgets('capture sans focus réel → restore ne fait rien',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final snap = FocusSnapshot.capture();
      snap.restore();
      await tester.pumpAndSettle();
      // Pas d'exception, pas de focus arbitraire volé.
      expect(FocusManager.instance.primaryFocus, isA<FocusScopeNode?>());
    });
  });
}
