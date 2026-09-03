import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/widgets/tv/focusable_card.dart';
import 'package:aetherStream/widgets/tv/focusable_chip.dart';

/// §dpadChildFocus — Un bouton IMBRIQUÉ dans une `FocusableCard` n'existe pas
/// pour le D-pad ; une chip FRÈRE, si.
///
/// Le piège payé : sous dpad 2.x, « Recharger » et ⋯ vivaient dans la carte du
/// compte et restaient atteignables. Depuis dpad 3.0, `DpadFocusable` enveloppe
/// son enfant d'un `ExcludeFocus` (`excludeChildFocus: true` par défaut) →
/// supprimer un compte ou arrêter un téléchargement était impossible à la
/// télécommande. Ces tests verrouillent la RÈGLE (pas les écrans) : ce qui
/// doit rester actionnable au D-pad doit être un frère de la carte.
///
/// ⚠️ On n'asserte PAS via `nextFocus()` : sans candidat, Flutter garde le focus
/// courant, et un `isFalse` passerait pour de mauvaises raisons. On lit
/// `canRequestFocus`, qui remonte les ancêtres (`descendantsAreFocusable`).
///
/// `DpadFocusable` n'exige pas de racine `Dpad(` : `DpadRegion.maybeOf` et
/// `DpadTheme.of` ont un repli, un simple `MaterialApp(home:)` suffit.
void main() {
  testWidgets('un bouton imbriqué dans une FocusableCard est hors traversée',
      (tester) async {
    final node = FocusNode(debugLabel: 'nestedButton');
    addTearDown(node.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FocusableCard(
          decorateOnly: true,
          onTap: () {},
          child: IconButton(
            focusNode: node,
            icon: const Icon(Icons.more_vert),
            onPressed: () {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(node.canRequestFocus, isFalse,
        reason: 'l\'ExcludeFocus posé par DpadFocusable rend le bouton '
            'inatteignable : il ne doit JAMAIS porter une action TV');

    // Et une demande explicite ne change rien : le focus ne s'y pose pas.
    node.requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, isNot(node));
  });

  testWidgets('une chip FRÈRE de la carte reste focusable', (tester) async {
    late BuildContext chipChildCtx;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            FocusableCard(
              decorateOnly: true,
              onTap: () {},
              child: const SizedBox(width: 200, height: 80),
            ),
            FocusableChip(
              onTap: () {},
              child: Builder(builder: (ctx) {
                chipChildCtx = ctx;
                return const SizedBox(width: 120, height: 40);
              }),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Le nœud dpad de la chip est le premier `Focus` sous `FocusableChip`
    // (le second est l'`ExcludeFocus` qui entoure l'enfant).
    final chipFocus = tester.widget<Focus>(find
        .descendant(of: find.byType(FocusableChip), matching: find.byType(Focus))
        .first);
    final chipNode = chipFocus.focusNode;
    expect(chipNode, isNotNull);
    expect(chipNode!.canRequestFocus, isTrue,
        reason: 'frère de la carte, hors de tout ExcludeFocus');

    chipNode.requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, chipNode);

    // Le focus est bien DANS la chip (l'ancêtre Focus de son enfant, en
    // remontant au-delà de l'ExcludeFocus, est le nœud focalisé).
    expect(
      Focus.of(chipChildCtx).ancestors.contains(chipNode) ||
          Focus.of(chipChildCtx) == chipNode,
      isTrue,
    );
  });
}
