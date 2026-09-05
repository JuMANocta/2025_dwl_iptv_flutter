import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/widgets/tv/section_beacon.dart';

/// §navBlind — « Tu pensais être à cet endroit mais tu es sur un autre » :
/// quatre erreurs de navigation en dix minutes, dont une sur une action
/// destructrice. Le principe tranché : UN repère, au même endroit sur toutes
/// les pages longues, qui nomme la section regardée.
///
/// ⚠️ Le bandeau ne s'affiche que sur téléviseur (`PlatformTv.isTv`, un cache
/// natif toujours faux sous `flutter test`) : d'où la couture `forceVisible`,
/// sans laquelle la moitié qui corrige le défaut ne serait vérifiable que sur
/// un appareil. Même idiome que `confirmOrUndo(isTv:)`.
void main() {
  Widget page({required bool visible, ScrollController? ctrl}) {
    return MaterialApp(
      home: Scaffold(
        body: SectionBeacon(
          pageTitle: 'Optimisation',
          forceVisible: visible,
          child: SingleChildScrollView(
            controller: ctrl,
            child: const Column(
              children: [
                SizedBox(height: 300),
                SectionMark('Profils'),
                SizedBox(height: 600),
                SectionMark('Mémoire'),
                SizedBox(height: 600),
                SectionMark('Stockage'),
                SizedBox(height: 600),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('sans TV, aucun bandeau — le tactile ne change pas d\'aspect',
      (tester) async {
    await tester.pumpWidget(page(visible: false));
    // Le libellé de section reste rendu (c'est l'ancien `_sectionLabel`),
    // mais il n'existe qu'UNE fois : pas de bandeau qui le répète.
    expect(find.text('PROFILS'), findsOneWidget);
    expect(find.text('OPTIMISATION'), findsNothing);
  });

  testWidgets('sur TV, le bandeau existe et ne nomme rien en tête de page',
      (tester) async {
    await tester.pumpWidget(page(visible: true));
    // En haut de page, aucune section n'est encore passée sous la ligne :
    // le bandeau ne montre que le nom de la page.
    expect(find.text('OPTIMISATION'), findsOneWidget);
    expect(find.text('OPTIMISATION  ·  PROFILS'), findsNothing);
  });

  testWidgets('en défilant, le bandeau nomme la section atteinte',
      (tester) async {
    final ctrl = ScrollController();
    await tester.pumpWidget(page(visible: true, ctrl: ctrl));

    ctrl.jumpTo(400); // « Profils » est passé au-dessus de la ligne
    await tester.pump();
    expect(find.text('OPTIMISATION  ·  PROFILS'), findsOneWidget);

    ctrl.jumpTo(1100); // ... puis « Mémoire »
    await tester.pump();
    expect(find.text('OPTIMISATION  ·  MÉMOIRE'), findsOneWidget);

    // ⚠️ Et on redescend : le repère doit REVENIR en arrière, sinon il ment
    // dès qu'on remonte la page — exactement le défaut qu'il corrige.
    ctrl.jumpTo(400);
    await tester.pump();
    expect(find.text('OPTIMISATION  ·  PROFILS'), findsOneWidget);
  });

  testWidgets('thresholdFraction descend la ligne de lecture', (tester) async {
    // ⚠️ Constaté à l'AVD TV : avec une ligne au bord HAUT, la pastille de
    // l'accueil annonçait « COUP DE CŒUR » alors que la carte focalisée était
    // dans « Sélection ». Une rangée fait ~400 px : l'en-tête sorti par le
    // haut n'est plus celui qu'on pilote. Le repère reproduisait le défaut.
    final ctrl = ScrollController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SectionBeacon(
          // Un nom de page pour distinguer le texte du REPÈRE de celui du
          // libellé de section, qui portent sinon la même chaîne.
          pageTitle: 'Accueil',
          forceVisible: true,
          thresholdFraction: 0.45,
          child: SingleChildScrollView(
            controller: ctrl,
            child: const Column(
              children: [
                SectionMark('Première'),
                SizedBox(height: 400),
                SectionMark('Seconde'),
                SizedBox(height: 1200),
              ],
            ),
          ),
        ),
      ),
    ));

    // ⚠️ Rien n'est nommé tant qu'on n'a pas défilé : le repère se calcule sur
    // les notifications de défilement. C'est voulu — en tête d'accueil, la
    // pastille doit rester invisible pour laisser le hero seul.
    await tester.pump();
    expect(find.text('ACCUEIL  ·  PREMIÈRE'), findsNothing);

    // Au premier mouvement, « Première » est sous la ligne, « Seconde » (à
    // ~430 px) ne l'est pas encore : la ligne est à ~45 % de 600 = 270.
    ctrl.jumpTo(1);
    await tester.pump();
    expect(find.text('ACCUEIL  ·  PREMIÈRE'), findsOneWidget);

    // Un petit défilement suffit à la faire passer sous la ligne — alors
    // qu'avec une ligne au bord haut il aurait fallu défiler 430 px de plus.
    ctrl.jumpTo(200);
    await tester.pump();
    expect(find.text('ACCUEIL  ·  SECONDE'), findsOneWidget);
  });

  _focusDrivenTests();

  group('SectionBeaconController — le cœur, sans widget', () {
    test('setCurrent ne notifie que sur un vrai changement', () {
      final c = SectionBeaconController();
      var n = 0;
      c.addListener(() => n++);
      c.setCurrent('A');
      c.setCurrent('A');
      c.setCurrent('B');
      expect(n, 2);
    });

    test('une même clé ne s\'inscrit pas deux fois', () {
      // ⚠️ `didChangeDependencies` peut être rappelé : sans cette garde, la
      // liste des sections grossirait sans fin.
      final c = SectionBeaconController();
      final k = GlobalKey();
      c.register('A', k);
      c.register('A', k);
      expect(c.markCount, 1);
      c.unregister(k);
      expect(c.markCount, 0);
    });
  });
}

/// §navBlind — Le repère se pilote par le FOCUS, pas par le défilement.
///
/// ⚠️ Ce test verrouille la correction la plus chère de la journée : deux
/// contre-exemples ont été relevés à l'AVD (accueil et Optimisation) où la
/// pastille nommait une section que l'utilisateur ne pilotait pas — parce que
/// l'auto-scroll D-pad gare l'élément focalisé près du BAS du viewport.
void _focusDrivenTests() {
  testWidgets('le repère suit le focus, même sans défiler', (tester) async {
    final f1 = FocusNode(debugLabel: 'dansPremiere');
    final f2 = FocusNode(debugLabel: 'dansSeconde');
    addTearDown(f1.dispose);
    addTearDown(f2.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SectionBeacon(
          pageTitle: 'Page',
          forceVisible: true,
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SectionMark('Première'),
                SizedBox(height: 100, child: Focus(focusNode: f1, child: const SizedBox())),
                const SectionMark('Seconde'),
                SizedBox(height: 100, child: Focus(focusNode: f2, child: const SizedBox())),
              ],
            ),
          ),
        ),
      ),
    ));

    // ⚠️ DEUX `pump` : `FocusManager` notifie ses écouteurs pendant la frame,
    // donc le repère se marque sale APRÈS avoir été construit. En vrai les
    // frames s'enchaînent et ça ne se voit pas ; en test il faut la suivante.
    f1.requestFocus();
    await tester.pump();
    await tester.pump();
    expect(find.text('PAGE  ·  PREMIÈRE'), findsOneWidget);

    // ⚠️ Aucun défilement entre les deux : c'est tout l'objet du correctif.
    f2.requestFocus();
    await tester.pump();
    await tester.pump();
    expect(find.text('PAGE  ·  SECONDE'), findsOneWidget);
  });

  // §beaconScope (2026-09-05) — La pastille a été retirée de la fiche
  // film/série (« des badges en surplus », signalement utilisateur) alors que
  // ses `SectionMark` y RESTENT. Ce test verrouille le contrat qui rend ce
  // retrait sûr : hors de toute portée, un `SectionMark` doit rendre son
  // contenu sans rien inscrire et sans lever.
  testWidgets('§beaconScope — un SectionMark SANS repère rend son enfant',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            SectionMark('Synopsis', child: Text('le résumé du film')),
            SectionMark('Infos'),
          ],
        ),
      ),
    ));

    // L'enfant fourni est rendu tel quel…
    expect(find.text('le résumé du film'), findsOneWidget);
    // …et sans enfant, le libellé de repli s'affiche quand même.
    expect(find.text('INFOS'), findsOneWidget);
    // Aucune pastille : il n'y a pas de repère au-dessus.
    expect(find.textContaining('·'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
