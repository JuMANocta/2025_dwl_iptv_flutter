// §homeVertical (R2) + R51 (2026-09-25) — Navigation verticale de l'accueil TV.
//
// R2, rejoué sur l'AVD TV : une rangée Favoris à UNE carte était sautée à la
// verticale dans les deux sens, parce que `dpad` fait gagner catégoriquement un
// candidat « dans le faisceau » (chevauchement de colonne). Décision
// utilisateur : ↑/↓ vont de rangée en rangée et arrivent TOUJOURS sur
// l'élément le plus à gauche ; ↓ depuis les onglets → 1re rangée ; ↑ depuis la
// 1re rangée → l'onglet de la page ; hero ↔ onglets inchangé.
//
// R51 : OK sur un onglet envoyait le focus dans le rail (ExcludeFocus de
// l'ancienne page → historique du scope, puis `nextFocus()`).
import 'package:aetherStream/feature/home/home_vertical_nav.dart';
import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Géométrie d'une page TV (logique 960 px de large).
Rect _card(int col, double top, {double w = 130, double h = 195}) =>
    Rect.fromLTWH(16 + col * (w + 16), top, w, h);

final List<Rect> _tabs = <Rect>[
  const Rect.fromLTWH(16, 400, 300, 48), // Séries
  const Rect.fromLTWH(316, 400, 300, 48), // Films
  const Rect.fromLTWH(616, 400, 300, 48), // Chaînes
];

List<Rect> _row(double top, int n) =>
    List<Rect>.generate(n, (int i) => _card(i, top));

/// Page Films : hero (0), onglets (1), Favoris à UNE carte (2), New (3),
/// Action (4). Dernier indice : 4.
Map<int, HomeNavSlotShape> _filmsPage() => <int, HomeNavSlotShape>{
      0: HomeNavSlotShape(HomeSlotKind.hero, <Rect>[const Rect.fromLTWH(200, 40, 400, 300)]),
      1: HomeNavSlotShape(HomeSlotKind.tabs, _tabs, preferred: 1),
      2: HomeNavSlotShape(HomeSlotKind.row, _row(500, 1)),
      3: HomeNavSlotShape(HomeSlotKind.row, _row(760, 12)),
      4: HomeNavSlotShape(HomeSlotKind.row, _row(1020, 12)),
    };

HomeNavTarget? _go(Map<int, HomeNavSlotShape> page, int from, int item,
        {required bool down, int? lastIndex = 4}) =>
    homeVerticalTarget(
      slotAt: (int i) => page[i],
      lastIndex: lastIndex,
      from: from,
      focusedItem: item,
      down: down,
    );

/// Le nœud d'un `DpadFocusable` par son `debugLabel` (`Focus.of` rendrait le
/// nœud de l'`ExcludeFocus` interne, pas celui de l'élément).
FocusNode _byLabel(String label) => FocusManager.instance.rootScope.descendants
    .firstWhere((FocusNode n) => n.debugLabel == label);

void main() {
  group('R2 — la rangée à UNE carte n\'est plus sautée', () {
    test('↑ depuis la 5e carte de New → la carte seule de Favoris', () {
      expect(_go(_filmsPage(), 3, 4, down: false), const HomeNavTarget(2, 0));
    });

    test('↓ depuis l\'onglet Films → la carte seule de Favoris', () {
      expect(_go(_filmsPage(), 1, 1, down: true), const HomeNavTarget(2, 0));
    });

    test('↓ depuis Favoris → la 1re affiche de New, quelle que soit la colonne', () {
      expect(_go(_filmsPage(), 2, 0, down: true), const HomeNavTarget(3, 0));
    });

    test('↑ depuis la 1re rangée → l\'onglet de la PAGE COURANTE', () {
      expect(_go(_filmsPage(), 2, 0, down: false), const HomeNavTarget(1, 1));
      final Map<int, HomeNavSlotShape> tv = _filmsPage()
        ..[1] = HomeNavSlotShape(HomeSlotKind.tabs, _tabs, preferred: 2);
      expect(_go(tv, 2, 0, down: false), const HomeNavTarget(1, 2));
    });
  });

  group('arrivée TOUJOURS sur l\'élément le plus à gauche', () {
    test('rangée longue : depuis la 9e carte, ↓ → 1re affiche de la suivante', () {
      expect(_go(_filmsPage(), 3, 8, down: true), const HomeNavTarget(4, 0));
      expect(_go(_filmsPage(), 4, 11, down: false), const HomeNavTarget(3, 0));
    });

    test('l\'ordre des focusables ne compte pas, seule la géométrie', () {
      final List<Rect> shuffled = _row(760, 6).reversed.toList();
      final Map<int, HomeNavSlotShape> page = _filmsPage()
        ..[3] = HomeNavSlotShape(HomeSlotKind.row, shuffled);
      expect(_go(page, 2, 0, down: true), const HomeNavTarget(3, 5));
    });

    test('« Voir tout » en BOUT de rangée n\'est jamais la cible d\'arrivée', () {
      final List<Rect> withSeeAll = <Rect>[..._row(760, 5), _card(5, 760)];
      final Map<int, HomeNavSlotShape> page = _filmsPage()
        ..[3] = HomeNavSlotShape(HomeSlotKind.row, withSeeAll);
      expect(homeNavEntry(page[3]!), 0);
    });

    test('la carte focalisée (agrandie de 5 %) reste sur sa ligne', () {
      final List<Rect> row = _row(760, 5);
      row[2] = Rect.fromCenter(center: row[2].center, width: row[2].width * 1.05, height: row[2].height * 1.05);
      expect(homeNavLines(row), <List<int>>[<int>[0, 1, 2, 3, 4]]);
    });
  });

  group('inchangé : hero ↔ onglets, et ce qui n\'est pas construit', () {
    test('↑ depuis les onglets → dpad (hero)', () {
      expect(_go(_filmsPage(), 1, 1, down: false), isNull);
    });

    test('depuis le hero → dpad, dans les deux sens', () {
      expect(_go(_filmsPage(), 0, 0, down: true), isNull);
      expect(_go(_filmsPage(), 0, 0, down: false), isNull);
    });

    test('sans onglets, ↑ depuis la 1re rangée vers le hero → dpad', () {
      final Map<int, HomeNavSlotShape> page = <int, HomeNavSlotShape>{
        0: HomeNavSlotShape(HomeSlotKind.hero, <Rect>[const Rect.fromLTWH(200, 40, 400, 300)]),
        1: HomeNavSlotShape(HomeSlotKind.row, _row(400, 5)),
      };
      expect(_go(page, 1, 3, down: false, lastIndex: 1), isNull);
    });

    test('emplacement voisin pas encore construit → dpad (qui sait faire défiler)', () {
      final Map<int, HomeNavSlotShape> page = _filmsPage()..remove(4);
      expect(_go(page, 3, 2, down: true), isNull);
    });

    test('haut de liste sans rien au-dessus → dpad', () {
      final Map<int, HomeNavSlotShape> page = <int, HomeNavSlotShape>{
        0: HomeNavSlotShape(HomeSlotKind.row, _row(100, 5)),
      };
      expect(_go(page, 0, 2, down: false, lastIndex: 0), isNull);
    });

    test('focus hors des éléments connus → dpad', () {
      expect(_go(_filmsPage(), 3, 99, down: true), isNull);
      expect(_go(_filmsPage(), 7, 0, down: true), isNull);
    });
  });

  group('bords de liste et emplacements vides', () {
    test('↓ sous la dernière rangée : le focus reste (plus de fuite vers le rail)', () {
      expect(_go(_filmsPage(), 4, 3, down: true), const HomeNavTarget.stay());
    });

    test('dernier indice inconnu (état vide) : ↓ reste à dpad', () {
      final Map<int, HomeNavSlotShape> empty = <int, HomeNavSlotShape>{
        0: HomeNavSlotShape(HomeSlotKind.tabs, _tabs, preferred: 1),
      };
      expect(_go(empty, 0, 1, down: true, lastIndex: null), isNull);
    });

    test('un emplacement sans focusable est sauté', () {
      final Map<int, HomeNavSlotShape> page = _filmsPage()
        ..[3] = const HomeNavSlotShape(HomeSlotKind.row, <Rect>[]);
      expect(_go(page, 2, 0, down: true), const HomeNavTarget(4, 0));
      expect(_go(page, 4, 5, down: false), const HomeNavTarget(2, 0));
    });

    test('page Chaînes : onglets ↓ → « Reprendre la chaîne », sinon la 1re rangée', () {
      final Map<int, HomeNavSlotShape> tv = <int, HomeNavSlotShape>{
        0: HomeNavSlotShape(HomeSlotKind.tabs, _tabs, preferred: 2),
        1: HomeNavSlotShape(HomeSlotKind.lastWatched, <Rect>[const Rect.fromLTWH(12, 470, 900, 70)]),
        2: HomeNavSlotShape(HomeSlotKind.row, _row(560, 6)),
      };
      expect(_go(tv, 0, 2, down: true, lastIndex: 2), const HomeNavTarget(1, 0));
      expect(_go(tv, 2, 3, down: false, lastIndex: 2), const HomeNavTarget(1, 0));
      expect(_go(tv, 1, 0, down: false, lastIndex: 2), const HomeNavTarget(0, 2));
      tv[1] = const HomeNavSlotShape(HomeSlotKind.lastWatched, <Rect>[]);
      expect(_go(tv, 0, 2, down: true, lastIndex: 2), const HomeNavTarget(2, 0));
    });

    test('onglet préféré hors bornes : ramené dans la barre', () {
      expect(homeNavEntry(HomeNavSlotShape(HomeSlotKind.tabs, _tabs, preferred: 9)), 2);
    });
  });

  group('grille des Chaînes : naturel DANS la grille, sortie vers la catégorie voisine', () {
    // 3 lignes : 7, 7 puis 2 tuiles CENTRÉES (WrapAlignment.center).
    List<Rect> grid(double top) => <Rect>[
          for (int c = 0; c < 7; c++) Rect.fromLTWH(12 + c * 130.0, top, 120, 120),
          for (int c = 0; c < 7; c++) Rect.fromLTWH(12 + c * 130.0, top + 128, 120, 120),
          const Rect.fromLTWH(337, 0, 120, 120).translate(0, top + 256),
          const Rect.fromLTWH(467, 0, 120, 120).translate(0, top + 256),
        ];
    Map<int, HomeNavSlotShape> page() => <int, HomeNavSlotShape>{
          0: HomeNavSlotShape(HomeSlotKind.tabs, _tabs, preferred: 2),
          1: HomeNavSlotShape(HomeSlotKind.row, grid(500)),
          2: HomeNavSlotShape(HomeSlotKind.row, grid(900)),
        };

    test('↓ dans la grille : la ligne suivante, même colonne', () {
      expect(_go(page(), 1, 3, down: true, lastIndex: 2), const HomeNavTarget(1, 10));
      expect(_go(page(), 1, 10, down: false, lastIndex: 2), const HomeNavTarget(1, 3));
    });

    test('la dernière ligne, courte et centrée, n\'est PAS sautée', () {
      // Tuile tout à gauche de la 2e ligne : aucune tuile de la 3e ligne dans
      // sa colonne — la plus proche, pas la grille suivante.
      expect(_go(page(), 1, 7, down: true, lastIndex: 2), const HomeNavTarget(1, 14));
    });

    test('depuis la dernière ligne, ↓ → 1re tuile de la catégorie suivante', () {
      expect(_go(page(), 1, 15, down: true, lastIndex: 2), const HomeNavTarget(2, 0));
    });

    test('depuis la 1re ligne, ↑ → la catégorie du dessus (ici l\'onglet Chaînes)', () {
      expect(_go(page(), 1, 5, down: false, lastIndex: 2), const HomeNavTarget(0, 2));
      expect(_go(page(), 2, 6, down: false, lastIndex: 2), const HomeNavTarget(1, 0));
    });
  });

  group('HomeNavSlot + dpad réel', () {
    // Une page réduite : onglets (3), Favoris à UNE carte, New (6 cartes).
    Widget harness(HomeVerticalNav? nav) {
      Widget slot(int index, HomeSlotKind kind, Widget child) => nav == null
          ? child
          : HomeNavSlot(nav: nav, index: index, kind: kind, preferred: 2, child: child);
      Widget cell(String label, double width) => SizedBox(
            width: width,
            height: 60,
            child: DpadFocusable(debugLabel: label, child: Text(label)),
          );
      nav?.lastIndex = 2;
      return MaterialApp(
        builder: Dpad.wrap(),
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              slot(0, HomeSlotKind.tabs, DpadRegion(child: Row(children: <Widget>[cell('Séries', 260), cell('Films', 260), cell('Chaînes', 260)]))),
              const SizedBox(height: 20),
              slot(1, HomeSlotKind.row, DpadRegion(enter: DpadEnterBehavior.entry, child: Row(children: <Widget>[cell('fav0', 120)]))),
              const SizedBox(height: 20),
              slot(2, HomeSlotKind.row, DpadRegion(enter: DpadEnterBehavior.entry, child: Row(children: <Widget>[for (int i = 0; i < 6; i++) cell('new$i', 120)]))),
            ],
          ),
        ),
      );
    }

    FocusNode node(WidgetTester tester, String label) => _byLabel(label);

    String? focused() => FocusManager.instance.primaryFocus?.debugLabel;

    testWidgets('témoin : dpad SEUL saute la carte seule de Favoris (R2)', (WidgetTester tester) async {
      await tester.pumpWidget(harness(null));
      node(tester, 'new5').requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      // « Chaînes » est dans le faisceau et gagne ; la région des onglets
      // restaure ensuite SA mémoire (le focus initial). Favoris est sauté.
      expect(focused(), isNot('fav0'));
      expect(<String>['Séries', 'Films', 'Chaînes'], contains(focused()));
    });

    testWidgets('avec HomeNavSlot : ↑ depuis new5 → fav0 → onglet de la page', (WidgetTester tester) async {
      await tester.pumpWidget(harness(HomeVerticalNav()));
      node(tester, 'new5').requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(focused(), 'fav0');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(focused(), 'Chaînes'); // preferred: 2 = l'onglet de CETTE page
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(focused(), 'fav0');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(focused(), 'new0');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(focused(), 'new0', reason: 'bas de liste : le focus reste');
    });

    testWidgets('← / → restent à dpad', (WidgetTester tester) async {
      await tester.pumpWidget(harness(HomeVerticalNav()));
      node(tester, 'new2').requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(focused(), 'new3');
    });
  });

  group('R51 — le focus reste sur l\'onglet choisi', () {
    // Rail + deux pages, chacune avec SA barre d'onglets ; la page non
    // courante est exclue du focus, comme `_pageFocusWrap`.
    Widget harness(ValueNotifier<int> current, List<HomeVerticalNav> navs) {
      Widget cell(String label) => SizedBox(
            width: 120,
            height: 50,
            child: DpadFocusable(debugLabel: label, child: Text(label)),
          );
      Widget page(int p) => ValueListenableBuilder<int>(
            valueListenable: current,
            builder: (_, int c, _) => ExcludeFocus(
              excluding: c != p,
              child: HomeNavSlot(
                nav: navs[p],
                index: 0,
                kind: HomeSlotKind.tabs,
                preferred: p,
                child: DpadRegion(child: Row(children: <Widget>[cell('p$p-Séries'), cell('p$p-Films')])),
              ),
            ),
          );
      return MaterialApp(
        builder: Dpad.wrap(),
        home: Scaffold(
          body: Row(
            children: <Widget>[
              DpadRegion(child: Column(children: <Widget>[cell('rail-Home'), cell('rail-Downloads'), cell('rail-Settings')])),
              Expanded(child: Column(children: <Widget>[page(0), page(1)])),
            ],
          ),
        ),
      );
    }

    Future<List<String?>> switchTo(WidgetTester tester, ValueNotifier<int> current, int to, {required void Function() postFrame}) async {
      final List<String?> seen = <String?>[];
      void listener() => seen.add(FocusManager.instance.primaryFocus?.debugLabel);
      FocusManager.instance.addListener(listener);
      current.value = to;
      WidgetsBinding.instance.addPostFrameCallback((_) => postFrame());
      await tester.pump();
      await tester.pump();
      FocusManager.instance.removeListener(listener);
      return seen;
    }

    testWidgets('témoin : sans visée explicite, l\'historique du scope ramène le rail', (WidgetTester tester) async {
      final ValueNotifier<int> current = ValueNotifier<int>(0);
      final List<HomeVerticalNav> navs = <HomeVerticalNav>[HomeVerticalNav(), HomeVerticalNav()];
      await tester.pumpWidget(harness(current, navs));
      _byLabel('rail-Home').requestFocus();
      await tester.pump();
      _byLabel('p0-Films').requestFocus();
      await tester.pump();
      await switchTo(tester, current, 1, postFrame: () {});
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'rail-Home');
    });

    testWidgets('visée en post-frame : l\'onglet de la nouvelle page, jamais le rail', (WidgetTester tester) async {
      final ValueNotifier<int> current = ValueNotifier<int>(0);
      final List<HomeVerticalNav> navs = <HomeVerticalNav>[HomeVerticalNav(), HomeVerticalNav()];
      await tester.pumpWidget(harness(current, navs));
      _byLabel('rail-Home').requestFocus();
      await tester.pump();
      _byLabel('p0-Films').requestFocus();
      await tester.pump();
      final List<String?> seen = await switchTo(tester, current, 1, postFrame: () {
        navs[1].entryNodeOf(HomeSlotKind.tabs)?.requestFocus();
      });
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'p1-Films');
      expect(seen.where((String? l) => l != null && l.startsWith('rail')), isEmpty, reason: 'aucune frame de focus sur le rail : $seen');
    });
  });
}
