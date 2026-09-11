import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/core/navigation/focus_route_memory.dart';
import 'package:aetherStream/main.dart' show navigatorKey;

/// §dpadBack — Un appui sur Retour ne dépile qu'UNE route.
///
/// ## Le défaut, mesuré sur émulateur TV le 2026-09-10 (5 fois sur 5)
///
/// Un seul appui physique produisait DEUX dépilements : la voie clavier (captée
/// par `dpad` → `AppBack.pop`) **et** la voie plateforme (`onBackPressed` →
/// `popRoute` → `didPopRoute` → `maybePop` sur le navigateur racine), qui ne
/// passait par aucun garde-fou. D'où le signalement du 2026-09-08 : « on fait
/// retour et ça sort de la vidéo au lieu de revenir dessus ».
///
/// ⚠️ Le défaut dépassait le lecteur : depuis une fiche, DEUX appuis
/// suffisaient à quitter l'application au lieu de trois.
///
/// ⚠️ Ce test n'a pas besoin d'appareil, alors que le défaut n'a été visible
/// que sur appareil pendant deux jours. C'est le seul filet qui reste quand
/// personne n'a de téléviseur sous la main.
void main() {
  setUp(() {
    AppBack.resetDebounceForTest();
    AppBack.resetPlatformTokenForTest();
    // ⚠️ `main()` n'est pas exécuté sous `flutter test` : sans cette ligne,
    // `handlePopRoute` n'atteignait jamais l'observateur et les tests
    // mesuraient le comportement de Flutter, pas le nôtre.
    // ⚠️ L'inscription doit avoir lieu AVANT le premier `pumpWidget`, comme en
    // production (avant `runApp`) : `handlePopRoute` s'arrête au premier
    // observateur qui rend `true`, et `_WidgetsAppState` s'inscrit à son
    // `initState`.
    WidgetsBinding.instance.addObserver(AppBack.platformObserver);
  });

  tearDown(() =>
      WidgetsBinding.instance.removeObserver(AppBack.platformObserver));

  /// Une pile de deux routes ; rend le nombre de routes encore empilées.
  Future<int Function()> pileDeDeux(WidgetTester tester) async {
    int profondeur = 1;
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: Text('racine')),
    ));
    navigatorKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('seconde')),
    ));
    await tester.pumpAndSettle();
    profondeur = 2;
    return () {
      // `canPop()` est faux quand il ne reste que la racine.
      return navigatorKey.currentState!.canPop() ? profondeur : 1;
    };
  }

  testWidgets('⚠️ LE défaut : touche PUIS plateforme ne dépile qu\'une route',
      (WidgetTester tester) async {
    await pileDeDeux(tester);
    expect(navigatorKey.currentState!.canPop(), isTrue);

    // 1. La voie clavier : c'est elle qui dépile.
    expect(AppBack.pop(), isTrue);
    await tester.pumpAndSettle();
    expect(navigatorKey.currentState!.canPop(), isFalse,
        reason: 'la voie clavier doit avoir dépilé la seconde route');

    // 2. Le pop FANTÔME de la plateforme, qui suit chaque appui physique.
    //    Il doit être avalé — sinon il dépilerait une route de plus.
    final bool consomme = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(consomme, isTrue,
        reason: 'le doublon doit être consommé, pas propagé');
    expect(find.text('racine'), findsOneWidget,
        reason: 'la racine ne doit PAS avoir été dépilée par le doublon');
  });

  testWidgets('le jeton ne sert QU\'UNE fois', (WidgetTester tester) async {
    await pileDeDeux(tester);
    AppBack.pop();
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute(); // avalé
    await tester.pumpAndSettle();

    // Un SECOND événement plateforme n'est plus un doublon : plus rien à
    // dépiler, donc il doit rendre la main au système.
    final bool second = await tester.binding.handlePopRoute();
    expect(second, isFalse,
        reason: 'le jeton est à un coup — sinon Retour ne quitte plus jamais');
  });

  testWidgets(
      '⛔ sans appui touche, la plateforme dépile NORMALEMENT (geste système)',
      (WidgetTester tester) async {
    await pileDeDeux(tester);
    // Aucun `AppBack.pop()` : c'est un balayage de retour, ou un appareil qui
    // n'envoie que la voie plateforme. Il doit fonctionner.
    final bool consomme = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(consomme, isTrue);
    expect(find.text('racine'), findsOneWidget);
  });

  testWidgets('⛔ rien à dépiler : on rend la main pour QUITTER l\'app',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: Text('racine')),
    ));
    // C'est aussi la seule issue de l'écran de chargement, qui n'a aucun
    // `PopScope` (§bootEscape).
    expect(await tester.binding.handlePopRoute(), isFalse);
    expect(AppBack.pop(), isFalse);
  });

  testWidgets('⛔ un Retour d\'INTERFACE n\'arme pas le jeton',
      (WidgetTester tester) async {
    await pileDeDeux(tester);
    // Bouton retour du lecteur / télécommande web : aucun événement plateforme
    // ne suit. Armer le jeton ici avalerait le prochain VRAI Retour.
    AppBack.popFromUi();
    await tester.pumpAndSettle();
    expect(find.text('racine'), findsOneWidget);

    // La plateforme doit donc encore être opérante… et n'a plus rien à faire.
    expect(await tester.binding.handlePopRoute(), isFalse);
  });
}
