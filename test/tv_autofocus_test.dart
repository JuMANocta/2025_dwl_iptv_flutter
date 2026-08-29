import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/widgets/tv/tv_adaptive_modal.dart';

/// §dpadAlign — Sémantique du garde-fou d'autofocus.
///
/// Le garde-fou doit répondre à « le focus est-il **chez moi** ? », et non à
/// « y a-t-il un focus quelque part ? » : un nœud encore vivant sur un écran en
/// train de se fermer ne doit pas empêcher le nouvel écran de prendre le focus.
///
/// ⚠️ **Ces tests ne reproduisent PAS le blocage constaté sur appareil** dans le
/// sélecteur de pistes du player — vérifié en remettant l'ancien garde-fou : ils
/// passent quand même. La cause réelle reste à confirmer par le traceur
/// touches + focus (§focusTrace) sur la TV. Ils verrouillent uniquement la
/// sémantique du helper, qui est correcte en soi.
void main() {
  group('hasFocusInside', () {
    testWidgets('focus dans le sous-arbre → vrai', (tester) async {
      final inside = FocusNode(debugLabel: 'inside');
      addTearDown(inside.dispose);
      late BuildContext subtree;

      await tester.pumpWidget(MaterialApp(
        home: FocusScope(
          child: Builder(builder: (ctx) {
            subtree = ctx;
            return Focus(
              focusNode: inside,
              child: const SizedBox(width: 10, height: 10),
            );
          }),
        ),
      ));
      inside.requestFocus();
      await tester.pump();

      expect(hasFocusInside(subtree), isTrue);
    });

    testWidgets('aucun focus réel → faux', (tester) async {
      late BuildContext subtree;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          subtree = ctx;
          return const SizedBox();
        }),
      ));
      expect(hasFocusInside(subtree), isFalse);
    });
  });

  group('TvAutofocusFirst', () {
    testWidgets('prend le focus quand rien n\'est focalisé', (tester) async {
      final target = FocusNode(debugLabel: 'target');
      addTearDown(target.dispose);

      await tester.pumpWidget(MaterialApp(
        home: TvAutofocusFirst(
          enabled: true,
          child: Focus(
            focusNode: target,
            child: const SizedBox(width: 10, height: 10),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(FocusManager.instance.primaryFocus, target);
    });

    testWidgets(
        'un dialog se ferme et un autre s\'ouvre dans la même frame → le '
        'nouveau prend le focus', (tester) async {
      // Chemin du player : panneau d'options → « Pistes audio » fait
      // `Navigator.pop()` PUIS ouvre le sélecteur immédiatement.
      final dying = FocusNode(debugLabel: 'optionRow');
      final target = FocusNode(debugLabel: 'trackRow');
      addTearDown(dying.dispose);
      addTearDown(target.dispose);

      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
      final NavigatorState nav =
          tester.state<NavigatorState>(find.byType(Navigator));

      // 1. Le panneau d'options, avec un élément focalisé.
      nav.push(DialogRoute<void>(
        context: nav.context,
        builder: (_) => Focus(
          focusNode: dying,
          autofocus: true,
          child: const SizedBox(width: 10, height: 10),
        ),
      ));
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, dying);

      // 2. Fermeture + ouverture du sélecteur dans la MÊME frame.
      nav.pop();
      nav.push(DialogRoute<void>(
        context: nav.context,
        builder: (_) => TvAutofocusFirst(
          enabled: true,
          child: Focus(
            focusNode: target,
            child: const SizedBox(width: 10, height: 10),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(FocusManager.instance.primaryFocus, target,
          reason: 'sinon le panneau s\'ouvre sans focus et le D-pad est mort');
    });

    testWidgets('un focus INTÉRIEUR déjà posé est respecté', (tester) async {
      // Cas inverse : un champ en `autofocus` dans le modal ne doit pas se
      // faire voler le focus par le helper.
      final field = FocusNode(debugLabel: 'field');
      final other = FocusNode(debugLabel: 'other');
      addTearDown(field.dispose);
      addTearDown(other.dispose);

      await tester.pumpWidget(MaterialApp(
        home: TvAutofocusFirst(
          enabled: true,
          child: Column(
            children: [
              Focus(
                focusNode: other,
                child: const SizedBox(width: 10, height: 10),
              ),
              Focus(
                focusNode: field,
                autofocus: true,
                child: const SizedBox(width: 10, height: 10),
              ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(FocusManager.instance.primaryFocus, field);
    });

    testWidgets('désactivé → ne touche à rien', (tester) async {
      final target = FocusNode(debugLabel: 'target');
      addTearDown(target.dispose);

      await tester.pumpWidget(MaterialApp(
        home: TvAutofocusFirst(
          enabled: false,
          child: Focus(
            focusNode: target,
            child: const SizedBox(width: 10, height: 10),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(FocusManager.instance.primaryFocus, isNot(target));
    });
  });
}
