import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/widgets/confirm_or_undo.dart';

/// §undoTv — Une annulation ne doit pas être décorative.
///
/// Le défaut payé : les annulations livrées le 2026-09-03 passaient toutes par
/// l'action d'une `SnackBar`. Vérifié à l'AVD TV, **cette action n'est pas
/// atteignable à la télécommande** — ↓ depuis la barre du haut va à la tuile
/// suivante, jamais dans la snackbar. Sur téléviseur, l'action était donc
/// irréversible sans que rien ne le dise.
///
/// Ces tests verrouillent la RÈGLE, pas les écrans :
///   * au doigt, on agit PUIS on propose « Annuler » (le geste n'est pas coupé) ;
///   * à la télécommande, on DEMANDE avant, et **rien n'a lieu** tant que la
///     réponse n'est pas donnée ;
///   * le focus s'ouvre sur le bouton SÛR (§safeFocus) — à la télécommande, OK
///     est le geste réflexe, il ne doit pas déclencher la destruction.
///
/// ⚠️ La branche TV n'est testable que grâce à la couture `isTv:` :
/// `PlatformTv.isTv` est un cache statique alimenté par un channel natif, donc
/// toujours faux sous `flutter test`. Sans elle, la moitié qui corrige le
/// défaut ne serait vérifiable que sur un appareil.
void main() {
  /// Monte un écran avec un seul bouton qui déclenche [confirmOrUndo] et
  /// enregistre ce qui s'est réellement passé.
  Future<_Trace> pumpHarness(
    WidgetTester tester, {
    required bool isTv,
  }) async {
    final trace = _Trace();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () async {
                trace.result = await confirmOrUndo(
                  ctx,
                  title: 'Oublier la reprise ?',
                  question: 'La position de lecture de ce titre sera oubliée.',
                  confirmLabel: 'Oublier',
                  doneMessage: 'Reprise oubliée',
                  isTv: isTv,
                  action: () async => trace.actions++,
                  onUndo: () => trace.undos++,
                );
              },
              child: const Text('déclencher'),
            ),
          ),
        ),
      ),
    ));
    return trace;
  }

  group('tactile', () {
    testWidgets('agit tout de suite, puis propose « Annuler »',
        (tester) async {
      final trace = await pumpHarness(tester, isTv: false);

      await tester.tap(find.text('déclencher'));
      await tester.pumpAndSettle();

      // Pas de question posée : le geste tactile n'est pas coupé.
      expect(find.text('Oublier la reprise ?'), findsNothing);
      expect(trace.actions, 1);
      expect(trace.result, isTrue);

      // …mais l'annulation est offerte pendant cinq secondes.
      expect(find.text('Reprise oubliée'), findsOneWidget);
      expect(find.widgetWithText(SnackBarAction, 'Annuler'), findsOneWidget);

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(trace.undos, 1);

      // Purge du filet de sécurité d'AppSnackBar (Timer de fermeture forcée).
      await tester.pump(const Duration(seconds: 7));
    });
  });

  group('télécommande', () {
    testWidgets('demande AVANT : refuser ne détruit rien', (tester) async {
      final trace = await pumpHarness(tester, isTv: true);

      await tester.tap(find.text('déclencher'));
      await tester.pumpAndSettle();

      // La question est posée, et rien n'a encore eu lieu.
      expect(find.text('Oublier la reprise ?'), findsOneWidget);
      expect(find.text('La position de lecture de ce titre sera oubliée.'),
          findsOneWidget);
      expect(trace.actions, 0);

      await tester.tap(find.widgetWithText(TextButton, 'Annuler'));
      await tester.pumpAndSettle();

      expect(trace.actions, 0, reason: 'un refus ne doit RIEN exécuter');
      expect(trace.undos, 0, reason: 'rien à défaire : rien n\'a eu lieu');
      expect(trace.result, isFalse);
      // Et aucune snackbar « Annuler » — celle-là serait hors de portée.
      expect(find.byType(SnackBarAction), findsNothing);
    });

    testWidgets('confirmer exécute une fois, sans « Annuler » injoignable',
        (tester) async {
      final trace = await pumpHarness(tester, isTv: true);

      await tester.tap(find.text('déclencher'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Oublier'));
      await tester.pumpAndSettle();

      expect(trace.actions, 1);
      expect(trace.undos, 0);
      expect(trace.result, isTrue);
      expect(find.text('Reprise oubliée'), findsOneWidget);
      // Le message de fin est un simple accusé de réception : pas d'action
      // dedans, donc rien d'atteignable à ne pas rater.
      expect(find.byType(SnackBarAction), findsNothing);

      await tester.pump(const Duration(seconds: 7));
    });

    testWidgets('§safeFocus — le focus s\'ouvre sur « Annuler »',
        (tester) async {
      await pumpHarness(tester, isTv: true);

      await tester.tap(find.text('déclencher'));
      await tester.pumpAndSettle();

      final FocusNode? focused = FocusManager.instance.primaryFocus;
      expect(focused, isNotNull);
      expect(focused!.context, isNotNull);

      final focusedFinder =
          find.byElementPredicate((e) => identical(e, focused.context));
      expect(
        find.ancestor(
          of: focusedFinder,
          matching: find.widgetWithText(TextButton, 'Annuler'),
        ),
        findsOneWidget,
        reason: 'à la télécommande, OK est le geste réflexe : il doit tomber '
            'sur le bouton SÛR, jamais sur la destruction',
      );
    });
  });
}

/// Ce qui s'est réellement passé pendant un scénario.
class _Trace {
  int actions = 0;
  int undos = 0;
  bool? result;
}
