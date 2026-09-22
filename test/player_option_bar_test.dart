// §tvPlayerPanel — Sur TV, chaque option du lecteur est un bouton de la barre
// du bas, et sa liste s'ouvre au-dessus de lui, dans l'image. La vidéo est UN
// focusable racine qui délègue ses touches à un automate pur : ces tests
// tiennent l'automate (qui consomme quoi, où va le focus, où mène Retour) et
// le dessin de la rangée (étiquettes d'état, anneau sur l'élément courant).
//
// §playerPanel — La même rangée sert au doigt (téléphone) : boutons tous de la
// même taille, rayon planché, rangée centrée ; tap sur un bouton, une ligne ou
// à côté. ⚠️ `PlatformTv.isTv` est toujours faux sous `flutter test` : la
// branche TV passe par la couture `PlayerOptionBar(isTv:)`.
import 'dart:async';

import 'package:aetherStream/core/themes/aether_theme_extension.dart';
import 'package:aetherStream/feature/player/widgets/player_option_bar.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Un thème au rayon [radius] (le reste n'est pas lu par la rangée).
AetherThemeExtension _ext(double radius) => AetherThemeExtension(
      primaryColor: Colors.cyan,
      accentColor: Colors.pink,
      tertiaryColor: Colors.amber,
      favoriteColor: Colors.red,
      warningColor: Colors.orange,
      errorColor: Colors.red,
      successColor: Colors.green,
      glowIntensity: 0,
      borderRadius: radius,
      focusGlowColor: Colors.cyan,
    );

/// Le rayon d'une surface décorée (le `DecoratedBox` le plus proche).
double _radiusOf(WidgetTester tester, Finder f) {
  final deco = tester.widget<DecoratedBox>(f).decoration as BoxDecoration;
  final r = deco.borderRadius! as BorderRadius;
  expect(r.topLeft, r.bottomRight, reason: 'rayon uniforme');
  return r.topLeft.x;
}

Finder _decoAbove(Finder f) =>
    find.ancestor(of: f, matching: find.byType(DecoratedBox)).first;

/// Une rangée type : Épisode suivant, Audio (liste), Vitesse (liste),
/// Infos vidéo (action directe).
class _Rig {
  final applied = <String>[];
  int nextCalls = 0;
  int statsCalls = 0;
  bool failApply = false;
  Completer<bool>? pending;

  PlayerOptionItem item(String label, {bool selected = false}) => PlayerOptionItem(
        label: label,
        selected: selected,
        onSelect: () async {
          if (pending != null) return pending!.future;
          if (failApply) return false;
          applied.add(label);
          return true;
        },
      );

  List<PlayerOptionButton> buttons({bool withNext = true}) => [
        if (withNext)
          PlayerOptionButton(
            kind: PlayerOptionKind.nextEpisode,
            icon: Icons.skip_next,
            title: 'Suivant',
            onAction: () => nextCalls++,
            leavesRow: true,
          ),
        PlayerOptionButton(
          kind: PlayerOptionKind.audio,
          icon: Icons.graphic_eq,
          title: 'Audio',
          value: 'Français',
          items: () => [item('Français', selected: true), item('English')],
        ),
        PlayerOptionButton(
          kind: PlayerOptionKind.speed,
          icon: Icons.speed,
          title: 'Vitesse',
          value: '1×',
          items: () => [
            item('0,5×'),
            item('1×', selected: true),
            item('1,5×'),
            item('2×'),
          ],
        ),
        PlayerOptionButton(
          kind: PlayerOptionKind.stats,
          icon: Icons.query_stats,
          title: 'Infos vidéo',
          value: 'Masquées',
          onAction: () => statsCalls++,
        ),
      ];
}

PlayerOptionsController _ctrl(_Rig rig, {bool withNext = true}) =>
    PlayerOptionsController()..syncButtons(rig.buttons(withNext: withNext));

void main() {
  group('automate', () {
    test('inactif : rien n\'est consommé (la vidéo garde OK et ←/→)', () {
      final c = _ctrl(_Rig());
      expect(c.active, isFalse);
      for (final d in TraversalDirection.values) {
        expect(c.move(d), isFalse, reason: '$d');
      }
      expect(c.select(), isFalse);
      expect(c.back(), isFalse,
          reason: 'Retour depuis la vidéo appartient au lecteur (sortie)');
    });

    test('ouverture sur « Audio » quand rien n\'a encore servi', () {
      final c = _ctrl(_Rig());
      expect(c.open(), isTrue);
      expect(c.active, isTrue);
      expect(c.current!.kind, PlayerOptionKind.audio);
      expect(c.listOpen, isFalse);
    });

    test('ouverture sur le DERNIER bouton utilisé', () {
      final c = _ctrl(_Rig());
      c.open();
      c.move(TraversalDirection.right); // Vitesse
      c.select(); // ouvre sa liste → Vitesse devient le dernier utilisé
      c.back();
      c.back();
      expect(c.active, isFalse);
      c.open();
      expect(c.current!.kind, PlayerOptionKind.speed);
    });

    test('sans « Audio », ouverture sur le premier bouton', () {
      final c = PlayerOptionsController()
        ..syncButtons([
          PlayerOptionButton(
            kind: PlayerOptionKind.fit,
            icon: Icons.fit_screen,
            title: 'Format',
            items: () => const [],
          ),
        ]);
      c.open();
      expect(c.index, 0);
    });

    test('aucun bouton : la rangée ne s\'ouvre pas', () {
      final c = PlayerOptionsController();
      expect(c.open(), isFalse);
      expect(c.active, isFalse);
    });

    test('←/→ parcourent la rangée, bornés aux deux bouts', () {
      final c = _ctrl(_Rig());
      c.open(); // Audio, index 1
      expect(c.move(TraversalDirection.left), isTrue);
      expect(c.current!.kind, PlayerOptionKind.nextEpisode);
      expect(c.move(TraversalDirection.left), isTrue,
          reason: 'consommée même au bord : jamais un seek');
      expect(c.index, 0);
      c.move(TraversalDirection.right);
      c.move(TraversalDirection.right);
      c.move(TraversalDirection.right);
      c.move(TraversalDirection.right);
      expect(c.current!.kind, PlayerOptionKind.stats);
      expect(c.index, 3);
    });

    test('↑ depuis la rangée = retour à la vidéo ; ↓ ne fait rien', () {
      final c = _ctrl(_Rig());
      c.open();
      expect(c.move(TraversalDirection.down), isTrue);
      expect(c.active, isTrue);
      expect(c.move(TraversalDirection.up), isTrue);
      expect(c.active, isFalse);
    });

    test('OK ouvre la liste, sur la ligne COCHÉE (l\'état courant)', () {
      final c = _ctrl(_Rig());
      c.open();
      c.move(TraversalDirection.right); // Vitesse
      expect(c.select(), isTrue);
      expect(c.listOpen, isTrue);
      expect(c.listIndex, 1, reason: '« 1× » est la vitesse courante');
    });

    test('dans la liste : ↑/↓ bornés, ←/→ consommées sans effet', () {
      final c = _ctrl(_Rig());
      c.open();
      c.move(TraversalDirection.right);
      c.select();
      c.move(TraversalDirection.up);
      c.move(TraversalDirection.up);
      expect(c.listIndex, 0);
      for (var i = 0; i < 6; i++) {
        c.move(TraversalDirection.down);
      }
      expect(c.listIndex, 3);
      expect(c.move(TraversalDirection.left), isTrue);
      expect(c.move(TraversalDirection.right), isTrue);
      expect(c.current!.kind, PlayerOptionKind.speed,
          reason: 'la liste ouverte ne change pas de bouton');
    });

    test('OK dans la liste applique puis referme, focus rendu au bouton',
        () async {
      final rig = _Rig();
      final c = _ctrl(rig);
      c.open();
      c.move(TraversalDirection.right);
      c.select();
      c.move(TraversalDirection.down); // 1,5×
      c.select();
      await Future<void>.delayed(Duration.zero);
      expect(rig.applied, ['1,5×']);
      expect(c.listOpen, isFalse);
      expect(c.active, isTrue);
      expect(c.current!.kind, PlayerOptionKind.speed);
    });

    test('un échec laisse la liste OUVERTE (R42 : l\'échec se dit)', () async {
      final rig = _Rig()..failApply = true;
      final c = _ctrl(rig);
      c.open();
      c.select();
      c.select();
      await Future<void>.delayed(Duration.zero);
      expect(c.listOpen, isTrue);
    });

    test('une application tardive ne referme pas une AUTRE liste', () async {
      final lente = Completer<bool>();
      final rig = _Rig()..pending = lente;
      final c = _ctrl(rig);
      c.open(); // Audio
      c.select(); // liste Audio
      c.select(); // application en attente
      c.back(); // referme
      c.move(TraversalDirection.right); // Vitesse
      c.select(); // liste Vitesse
      // L'application audio aboutit maintenant : la liste Vitesse reste.
      lente.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(c.listOpen, isTrue);
      expect(c.current!.kind, PlayerOptionKind.speed);
    });

    test('Retour à deux niveaux : la liste, puis la rangée', () {
      final c = _ctrl(_Rig());
      c.open();
      c.select();
      expect(c.back(), isTrue);
      expect(c.listOpen, isFalse);
      expect(c.active, isTrue, reason: 'Retour ne quitte pas la rangée');
      expect(c.back(), isTrue);
      expect(c.active, isFalse);
      expect(c.back(), isFalse,
          reason: 'au niveau vidéo, Retour revient au lecteur');
    });

    test('Infos vidéo agit tout de suite et reste dans la rangée', () {
      final rig = _Rig();
      final c = _ctrl(rig);
      c.open();
      c.move(TraversalDirection.right);
      c.move(TraversalDirection.right); // Infos vidéo
      c.select();
      expect(rig.statsCalls, 1);
      expect(c.listOpen, isFalse);
      expect(c.active, isTrue);
    });

    test('Épisode suivant agit tout de suite et rend la vidéo', () {
      final rig = _Rig();
      final c = _ctrl(rig);
      c.open();
      c.move(TraversalDirection.left);
      c.select();
      expect(rig.nextCalls, 1);
      expect(c.active, isFalse);
    });

    test('le bouton courant suit son GENRE quand la rangée change', () {
      final rig = _Rig();
      final c = _ctrl(rig, withNext: false);
      c.open();
      expect(c.index, 0);
      c.syncButtons(rig.buttons()); // « Suivant » apparaît devant
      expect(c.current!.kind, PlayerOptionKind.audio);
      expect(c.index, 1);
    });

    test('rangée vidée (verrou, diffusion) : tout se ferme', () async {
      final c = _ctrl(_Rig());
      var notified = 0;
      c.addListener(() => notified++);
      c.open();
      c.select();
      notified = 0;
      c.syncButtons(const []);
      expect(c.active, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(notified, 1, reason: 'le lecteur doit relancer son minuteur');
    });

    test('replaceList remplace la liste ouverte de CE bouton seulement', () {
      final rig = _Rig();
      final c = _ctrl(rig);
      c.open();
      c.select(); // liste Audio
      c.replaceList(PlayerOptionKind.speed, [rig.item('x')]);
      expect(c.items.length, 2, reason: 'pas la liste de ce bouton');
      c.replaceList(PlayerOptionKind.audio, [rig.item('résultat')]);
      expect(c.items.single.label, 'résultat');
      expect(c.listIndex, 0);
      c.back();
      c.select();
      expect(c.items.length, 2, reason: 'refermer rend la liste d\'origine');
    });
  });

  /// Monte la rangée en bas d'un écran de 800 × 600 (TV par défaut).
  Future<PlayerOptionsController> pump(
    WidgetTester tester,
    _Rig rig, {
    bool isTv = true,
    double? radius,
  }) async {
    final c = _ctrl(rig);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: radius == null ? null : ThemeData(extensions: [_ext(radius)]),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Align(
          alignment: Alignment.bottomCenter,
          child: PlayerOptionBar(controller: c, isTv: isTv),
        ),
      ),
    ));
    return c;
  }

  Finder ringOn(String text) => find.descendant(
      of: find.byKey(PlayerOptionBar.focusRingKey), matching: find.text(text));

  group('rangée', () {
    testWidgets('libellés d\'état sous chaque bouton, sans anneau au repos',
        (tester) async {
      await pump(tester, _Rig());
      expect(find.text('Audio'), findsOneWidget);
      expect(find.text('Français'), findsOneWidget);
      expect(find.text('1×'), findsOneWidget);
      expect(find.text('Masquées'), findsOneWidget);
      expect(find.byKey(PlayerOptionBar.focusRingKey), findsNothing);
    });

    testWidgets('l\'anneau suit le bouton courant', (tester) async {
      final c = await pump(tester, _Rig());
      c.open();
      await tester.pump();
      expect(ringOn('Audio'), findsOneWidget);
      c.move(TraversalDirection.right);
      await tester.pump();
      expect(ringOn('Audio'), findsNothing);
      expect(ringOn('Vitesse'), findsOneWidget);
    });

    testWidgets('OK ouvre la liste AU-DESSUS du bouton, anneau sur la ligne',
        (tester) async {
      final c = await pump(tester, _Rig());
      c.open();
      c.move(TraversalDirection.right);
      c.select();
      await tester.pump();
      expect(find.text('0,5×'), findsOneWidget);
      expect(find.byKey(PlayerOptionBar.focusRingKey), findsOneWidget);
      expect(ringOn('1×'), findsOneWidget);
      expect(
        tester.getBottomLeft(find.text('2×')).dy,
        lessThan(tester.getTopLeft(find.text('Vitesse')).dy),
        reason: 'la liste s\'ouvre au-dessus de la rangée',
      );
      c.back();
      await tester.pump();
      expect(find.text('0,5×'), findsNothing);
      expect(ringOn('Vitesse'), findsOneWidget);
    });

    testWidgets(
        '§touchNoFocus : sur TV, la rangée n\'ajoute ni GestureDetector, ni '
        'InkWell, ni Focus — liste ouverte comprise', (tester) async {
      final c = await pump(tester, _Rig());
      c.open();
      c.move(TraversalDirection.right);
      c.select();
      await tester.pumpAndSettle();
      // Témoin : la liste (dans l'Overlay) est bien vue sous la rangée.
      expect(
          find.descendant(
              of: find.byType(PlayerOptionBar), matching: find.text('0,5×')),
          findsOneWidget);
      for (final t in [GestureDetector, InkWell, Focus, FocusScope]) {
        expect(
          find.descendant(
              of: find.byType(PlayerOptionBar), matching: find.byType(t)),
          findsNothing,
          reason: '$t',
        );
      }
    });
  });

  group('§playerPanel — automate au doigt', () {
    test('tap sur un bouton à liste : ouverte sur la ligne cochée', () {
      final c = _ctrl(_Rig());
      c.tapButton(2); // Vitesse
      expect(c.active, isTrue);
      expect(c.byTouch, isTrue);
      expect(c.listOpen, isTrue);
      expect(c.current!.kind, PlayerOptionKind.speed);
      expect(c.listIndex, 1, reason: '« 1× » est la vitesse courante');
    });

    test('tap sur une ligne : appliquée, refermée, la VIDÉO reprend la main',
        () async {
      final rig = _Rig();
      final c = _ctrl(rig);
      c.tapButton(2);
      c.tapItem(2); // 1,5×
      await Future<void>.delayed(Duration.zero);
      expect(rig.applied, ['1,5×']);
      expect(c.listOpen, isFalse);
      expect(c.active, isFalse,
          reason: 'sinon PopScope(canPop: !active) avalerait le Retour');
      expect(c.byTouch, isFalse);
      expect(c.lastUsed, PlayerOptionKind.speed);
    });

    test('tap sur le bouton dont la liste est ouverte : refermée', () {
      final rig = _Rig();
      final c = _ctrl(rig);
      c.tapButton(1);
      c.tapButton(1);
      expect(c.listOpen, isFalse);
      expect(c.active, isFalse);
      expect(rig.applied, isEmpty);
    });

    test('tap sur un AUTRE bouton : sa liste remplace la première', () {
      final c = _ctrl(_Rig());
      c.tapButton(1); // Audio
      c.tapButton(2); // Vitesse
      expect(c.listOpen, isTrue);
      expect(c.current!.kind, PlayerOptionKind.speed);
      expect(c.items.length, 4);
    });

    test('tap sur un bouton à action : agit, et la vidéo garde la main', () {
      final rig = _Rig();
      final c = _ctrl(rig);
      c.tapButton(3); // Infos vidéo
      expect(rig.statsCalls, 1);
      expect(c.active, isFalse);
      c.tapButton(0); // Suivant
      expect(rig.nextCalls, 1);
      expect(c.active, isFalse);
    });

    test('Retour au doigt : UN niveau — la liste refermée, c\'est la vidéo', () {
      final c = _ctrl(_Rig());
      c.tapButton(1);
      expect(c.back(), isTrue);
      expect(c.active, isFalse);
      expect(c.back(), isFalse, reason: 'au niveau vidéo, le lecteur décide');
    });

    test('dismiss (tap à côté) : refermée sans rien appliquer', () {
      final rig = _Rig();
      final c = _ctrl(rig);
      c.tapButton(2);
      c.dismiss();
      expect(c.active, isFalse);
      expect(c.listOpen, isFalse);
      expect(rig.applied, isEmpty);
    });

    test('un échec laisse la liste ouverte (R42), au doigt aussi', () async {
      final rig = _Rig()..failApply = true;
      final c = _ctrl(rig);
      c.tapButton(1);
      c.tapItem(1);
      await Future<void>.delayed(Duration.zero);
      expect(c.listOpen, isTrue);
      expect(c.active, isTrue);
    });

    test('liste remplacée (sous-titres en ligne) puis résultat posé', () async {
      final rig = _Rig();
      final c = _ctrl(rig);
      final search = PlayerOptionItem(
        label: 'Rechercher en ligne',
        onSelect: () async {
          c.replaceList(PlayerOptionKind.audio, [rig.item('Résultat')]);
          return false; // la liste reste ouverte, remplacée
        },
      );
      c.syncButtons([
        PlayerOptionButton(
          kind: PlayerOptionKind.audio,
          icon: Icons.graphic_eq,
          title: 'Audio',
          items: () => [rig.item('Français', selected: true), search],
        ),
      ]);
      c.tapButton(0);
      c.tapItem(1);
      await Future<void>.delayed(Duration.zero);
      expect(c.listOpen, isTrue);
      expect(c.items.single.label, 'Résultat');
      c.tapItem(0);
      await Future<void>.delayed(Duration.zero);
      expect(rig.applied, ['Résultat']);
      expect(c.listOpen, isFalse);
      expect(c.active, isFalse);
    });

    test('lignes et boutons hors bornes : sans effet', () {
      final rig = _Rig();
      final c = _ctrl(rig);
      c.tapButton(9);
      expect(c.active, isFalse);
      c.tapItem(0);
      expect(c.active, isFalse, reason: 'aucune liste ouverte');
      c.tapButton(2);
      c.tapItem(9);
      expect(c.listOpen, isTrue);
      expect(rig.applied, isEmpty);
    });

    test('une touche après un tap rend la main à la télécommande', () {
      final c = _ctrl(_Rig());
      c.tapButton(2);
      c.move(TraversalDirection.down);
      expect(c.byTouch, isFalse, reason: 'l\'anneau revient');
      expect(c.listIndex, 2);
      expect(c.back(), isTrue);
      expect(c.active, isTrue, reason: 'Retour retrouve ses deux niveaux');
      expect(c.listOpen, isFalse);
    });
  });

  group('§playerPanel — forme', () {
    test('taille commune : préférée, réduite pour tenir, plancher au doigt', () {
      expect(playerOptionChipSize(isTv: true), const Size(146, 58));
      expect(playerOptionChipSize(isTv: false), const Size(120, 52));
      expect(playerOptionChipSize(isTv: true, count: 5, maxWidth: 936),
          const Size(146, 58));
      // TV de 960 dp, sept boutons : ils rétrécissent, la rangée tient.
      final Size tv7 =
          playerOptionChipSize(isTv: true, count: 7, maxWidth: 936);
      expect(tv7, const Size(126, 58));
      expect(7 * tv7.width + 6 * kPlayerOptionGap, lessThanOrEqualTo(936));
      // Téléphone en paysage, sept boutons : (800 - 48) / 7, arrondi dessous.
      expect(playerOptionChipSize(isTv: false, count: 7, maxWidth: 800).width,
          107);
      // Téléphone en portrait : plancher 104, la rangée défile.
      expect(playerOptionChipSize(isTv: false, count: 7, maxWidth: 380),
          const Size(104, 52));
    });

    for (final isTv in [true, false]) {
      final String mode = isTv ? 'TV' : 'doigt';

      testWidgets('$mode : tous les boutons ont la MÊME taille, valeur ou pas',
          (tester) async {
        await pump(tester, _Rig(), isTv: isTv);
        final Size want = playerOptionChipSize(isTv: isTv);
        for (final kind in [
          PlayerOptionKind.nextEpisode, // sans valeur
          PlayerOptionKind.audio,
          PlayerOptionKind.speed,
          PlayerOptionKind.stats,
        ]) {
          expect(tester.getSize(find.byKey(PlayerOptionBar.chipKey(kind))),
              want,
              reason: '$kind');
        }
        expect(want.height, greaterThanOrEqualTo(48), reason: 'cible tactile');
      });

      testWidgets('$mode : la rangée est CENTRÉE', (tester) async {
        await pump(tester, _Rig(), isTv: isTv);
        final double width = tester.getSize(find.byType(Scaffold)).width;
        final Rect first = tester.getRect(
            find.byKey(PlayerOptionBar.chipKey(PlayerOptionKind.nextEpisode)));
        final Rect last = tester
            .getRect(find.byKey(PlayerOptionBar.chipKey(PlayerOptionKind.stats)));
        expect(first.left, closeTo(width - last.right, 1));
        // Écart constant.
        final Rect audio = tester
            .getRect(find.byKey(PlayerOptionBar.chipKey(PlayerOptionKind.audio)));
        expect(audio.left - first.right, kPlayerOptionGap);
      });
    }

    testWidgets('playerSurfaceRadius : plancher 12, le thème garde la main',
        (tester) async {
      for (final (double? theme, double want) in [
        (2.0, 12.0),
        (12.0, 12.0),
        (20.0, 20.0),
        (null, 12.0), // sans extension
      ]) {
        late double got;
        await tester.pumpWidget(MaterialApp(
          theme: theme == null ? null : ThemeData(extensions: [_ext(theme)]),
          home: Builder(builder: (context) {
            got = playerSurfaceRadius(context);
            return const SizedBox();
          }),
        ));
        // `MaterialApp` passe d'un thème à l'autre en animation.
        await tester.pumpAndSettle();
        expect(got, want, reason: 'thème $theme');
      }
    });

    for (final (double theme, double want) in [(2.0, 12.0), (20.0, 20.0)]) {
      testWidgets(
          'thème à $theme : bouton, liste et ligne au même rayon ($want)',
          (tester) async {
        final c = await pump(tester, _Rig(), radius: theme);
        c.open();
        c.move(TraversalDirection.right);
        c.select(); // liste Vitesse
        await tester.pumpAndSettle();
        expect(_radiusOf(tester, _decoAbove(find.text('Vitesse'))), want,
            reason: 'bouton');
        expect(_radiusOf(tester, _decoAbove(find.text('Audio'))), want,
            reason: 'bouton');
        expect(_radiusOf(tester, _decoAbove(find.text('VITESSE'))), want,
            reason: 'liste');
        expect(_radiusOf(tester, _decoAbove(find.text('0,5×'))), want,
            reason: 'ligne');
        expect(
            _radiusOf(
                tester,
                find.descendant(
                    of: find.byKey(PlayerOptionBar.focusRingKey),
                    matching: find.byType(DecoratedBox)).first),
            want,
            reason: 'anneau de la ligne courante');
      });
    }
  });

  group('§playerPanel — au doigt (widgets)', () {
    Finder chip(PlayerOptionKind k) => find.byKey(PlayerOptionBar.chipKey(k));

    testWidgets('tap bouton → liste ; tap ligne → appliquée, refermée, vidéo',
        (tester) async {
      final rig = _Rig();
      final c = await pump(tester, rig, isTv: false);
      await tester.tap(chip(PlayerOptionKind.speed));
      await tester.pumpAndSettle();
      expect(c.listOpen, isTrue);
      expect(find.text('0,5×'), findsOneWidget);
      expect(find.byKey(PlayerOptionBar.focusRingKey), findsNothing,
          reason: 'au doigt, rien n\'a le focus : pas d\'anneau');
      expect(
        tester.getBottomLeft(find.text('2×')).dy,
        lessThan(tester.getTopLeft(chip(PlayerOptionKind.speed)).dy),
        reason: 'la liste s\'ouvre au-dessus du bouton',
      );
      // Cible tactile d'une ligne : 48 dp au moins.
      expect(tester.getSize(_decoAbove(find.text('0,5×'))).height,
          greaterThanOrEqualTo(48));
      await tester.tap(find.text('1,5×'));
      await tester.pumpAndSettle();
      expect(rig.applied, ['1,5×']);
      expect(c.active, isFalse);
      expect(find.text('0,5×'), findsNothing);
    });

    testWidgets('tap à côté de la liste : refermée sans rien appliquer',
        (tester) async {
      final rig = _Rig();
      final c = await pump(tester, rig, isTv: false);
      await tester.tap(chip(PlayerOptionKind.audio));
      await tester.pumpAndSettle();
      expect(find.text('English'), findsOneWidget);
      // Un tap DANS la liste, hors d'une ligne (son titre), ne ferme rien.
      await tester.tap(find.text('AUDIO'));
      await tester.pumpAndSettle();
      expect(c.listOpen, isTrue);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(c.active, isFalse);
      expect(find.text('English'), findsNothing);
      expect(rig.applied, isEmpty);
    });

    testWidgets('tap sur un bouton à action : l\'action, sans liste',
        (tester) async {
      final rig = _Rig();
      final c = await pump(tester, rig, isTv: false);
      await tester.tap(chip(PlayerOptionKind.stats));
      await tester.pump();
      expect(rig.statsCalls, 1);
      expect(c.active, isFalse);
      await tester.tap(chip(PlayerOptionKind.nextEpisode));
      await tester.pump();
      expect(rig.nextCalls, 1);
    });

    testWidgets(
        'rangée plus large que l\'écran : elle défile, et la liste reste '
        'dans l\'écran', (tester) async {
      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = await pump(tester, _Rig(), isTv: false);
      expect(tester.takeException(), isNull, reason: 'aucun débordement');
      expect(tester.getSize(chip(PlayerOptionKind.stats)).width, 104);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      // Audio (112 → 216) est dans la moitié gauche : alignée sur son bord
      // gauche, la liste de 340 sortirait à droite (452 > 400).
      await tester.tap(chip(PlayerOptionKind.audio));
      await tester.pumpAndSettle();
      expect(c.listOpen, isTrue);
      final Rect list = tester.getRect(_decoAbove(find.text('AUDIO')));
      expect(list.left, greaterThanOrEqualTo(8));
      expect(list.right, lessThanOrEqualTo(392));
      expect(list.bottom,
          lessThan(tester.getTopLeft(chip(PlayerOptionKind.audio)).dy));
    });
  });

  group('§tvSeekBar — pas croissant (pur)', () {
    test('appui simple 10 s, puis 30 s, 1 min, 5 min en maintenant', () {
      expect(playerSeekStep(Duration.zero), const Duration(seconds: 10));
      expect(playerSeekStep(const Duration(milliseconds: 499)),
          const Duration(seconds: 10));
      expect(playerSeekStep(const Duration(milliseconds: 500)),
          const Duration(seconds: 30));
      expect(playerSeekStep(const Duration(milliseconds: 1500)),
          const Duration(minutes: 1));
      expect(playerSeekStep(const Duration(milliseconds: 2500)),
          const Duration(minutes: 5));
      expect(playerSeekStep(const Duration(seconds: 30)),
          const Duration(minutes: 5));
    });

    test('bornes : jamais avant 0, jamais après la durée', () {
      const total = Duration(minutes: 90);
      expect(playerSeekClamp(const Duration(seconds: -5), total), Duration.zero);
      expect(playerSeekClamp(const Duration(minutes: 95), total), total);
      expect(playerSeekClamp(const Duration(minutes: 30), total),
          const Duration(minutes: 30));
    });

    test('temps et écart formatés', () {
      expect(formatPlayerTime(const Duration(minutes: 42, seconds: 10)),
          '42:10');
      expect(formatPlayerTime(const Duration(hours: 1, minutes: 2, seconds: 5)),
          '1:02:05');
      expect(formatSeekDelta(const Duration(minutes: 3, seconds: 20)), '+3:20');
      expect(formatSeekDelta(const Duration(seconds: -40)), '-0:40');
      expect(formatSeekDelta(const Duration(milliseconds: 400)), '',
          reason: 'repère sur la lecture : rien à dire');
    });
  });

  group('§tvSeekBar — automate', () {
    late Duration pos;
    late Duration total;
    late List<Duration> commits;
    late Duration held;
    late DateTime now;

    PlayerOptionsController seekCtrl({bool live = false}) {
      pos = const Duration(minutes: 10);
      total = const Duration(minutes: 90);
      commits = [];
      held = Duration.zero;
      now = DateTime(2026, 9, 22, 10);
      final c = _ctrl(_Rig())
        ..heldFor = (() => held)
        ..clock = (() => now);
      c.seekSource = live
          ? null
          : PlayerSeekSource(
              position: () => pos,
              duration: () => total,
              commit: commits.add,
            );
      return c;
    }

    test('↓ depuis la rangée : la barre, repère sur la lecture', () {
      final c = seekCtrl();
      c.open();
      expect(c.move(TraversalDirection.down), isTrue);
      expect(c.seekOpen, isTrue);
      expect(c.seekTarget, pos);
      expect(c.active, isTrue);
    });

    test('un direct (sans source) : ↓ ne mène nulle part', () {
      final c = seekCtrl(live: true);
      c.open();
      c.move(TraversalDirection.down);
      expect(c.seekOpen, isFalse);
    });

    test('←/→ déplacent le REPÈRE, sans jamais sauter tout seuls', () {
      final c = seekCtrl();
      c.open();
      c.move(TraversalDirection.down);
      c.move(TraversalDirection.right);
      c.move(TraversalDirection.right);
      c.move(TraversalDirection.left);
      expect(c.seekTarget, const Duration(minutes: 10, seconds: 10));
      expect(commits, isEmpty, reason: 'la lecture continue, aucun saut');
    });

    test('maintenir accélère ; les répétitions trop serrées sont avalées', () {
      final c = seekCtrl();
      c.open();
      c.move(TraversalDirection.down);
      held = const Duration(seconds: 3); // 5 min par pas
      c.move(TraversalDirection.right);
      expect(c.seekTarget, const Duration(minutes: 15));
      now = now.add(const Duration(milliseconds: 50));
      c.move(TraversalDirection.right);
      expect(c.seekTarget, const Duration(minutes: 15),
          reason: 'moins de ${PlayerOptionsController.seekRepeatGap.inMilliseconds} ms');
      now = now.add(const Duration(milliseconds: 200));
      c.move(TraversalDirection.right);
      expect(c.seekTarget, const Duration(minutes: 20));
      held = Duration.zero; // relâchée : retour à 10 s
      c.move(TraversalDirection.right);
      expect(c.seekTarget, const Duration(minutes: 20, seconds: 10));
    });

    test('borné entre 0 et la durée', () {
      final c = seekCtrl();
      c.open();
      c.move(TraversalDirection.down);
      held = const Duration(seconds: 3);
      for (var i = 0; i < 40; i++) {
        now = now.add(const Duration(seconds: 1));
        c.move(TraversalDirection.right);
      }
      expect(c.seekTarget, total);
      for (var i = 0; i < 40; i++) {
        now = now.add(const Duration(seconds: 1));
        c.move(TraversalDirection.left);
      }
      expect(c.seekTarget, Duration.zero);
    });

    test('OK saute au repère et le focus RESTE sur la barre', () {
      final c = seekCtrl();
      c.open();
      c.move(TraversalDirection.down);
      c.move(TraversalDirection.right);
      expect(c.select(), isTrue);
      expect(commits, [const Duration(minutes: 10, seconds: 10)]);
      expect(c.seekOpen, isTrue);
      expect(c.active, isTrue);
    });

    test('↑ revient à la rangée sans sauter', () {
      final c = seekCtrl();
      c.open();
      c.move(TraversalDirection.down);
      c.move(TraversalDirection.right);
      c.move(TraversalDirection.up);
      expect(c.seekOpen, isFalse);
      expect(c.active, isTrue);
      expect(commits, isEmpty);
    });

    test('Retour annule et rend la vidéo, jamais au-delà', () {
      final c = seekCtrl();
      c.open();
      c.move(TraversalDirection.down);
      c.move(TraversalDirection.right);
      expect(c.back(), isTrue);
      expect(c.active, isFalse);
      expect(c.seekOpen, isFalse);
      expect(commits, isEmpty, reason: 'le déplacement est abandonné');
      expect(c.back(), isFalse, reason: 'au niveau vidéo, le lecteur décide');
    });

    testWidgets('le repère : anneau et heure visée À CÔTÉ, sur la barre',
        (tester) async {
      final c = seekCtrl();
      c.open();
      c.move(TraversalDirection.down);
      held = Duration.zero;
      for (var i = 0; i < 3; i++) {
        c.move(TraversalDirection.right);
      }
      const barKey = ValueKey<String>('barre');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: SizedBox(
              key: barKey,
              width: 800,
              height: 28,
              child: PlayerSeekMarker(
                controller: c,
                position: pos,
                duration: total,
              ),
            ),
          ),
        ),
      ));
      expect(find.byKey(PlayerOptionBar.focusRingKey), findsOneWidget);
      expect(find.text('10:30  +0:30'), findsOneWidget);
      final ring = tester.getCenter(find.byKey(PlayerOptionBar.focusRingKey));
      final label = tester.getCenter(find.text('10:30  +0:30'));
      expect(label.dy, closeTo(ring.dy, 0.5), reason: 'même ligne que le repère');
      expect(label.dx, greaterThan(ring.dx),
          reason: 'visée APRÈS la lecture : la pastille à droite, le curseur '
              'blanc (à gauche) reste visible');
      // 10 min 30 s sur 90 min, piste marge 14 px de chaque côté.
      final double left = tester.getTopLeft(find.byKey(barKey)).dx;
      expect(ring.dx - left, closeTo(14 + (630 / 5400) * (800 - 28), 1));
      c.back();
      await tester.pump();
      expect(find.byKey(PlayerOptionBar.focusRingKey), findsNothing);
    });

    // Recette TV du 2026-09-22 : la pastille, posée AU-DESSUS du repère,
    // masquait le bas du bouton « Infos vidéo » (6 px plus haut).
    testWidgets(
        '§playerPanel — la pastille ne chevauche jamais la rangée au-dessus, '
        'ni le temps et le cadenas au-dessous, ni ne sort de la barre',
        (tester) async {
      const rowKey = ValueKey<String>('rangée');
      const barKey = ValueKey<String>('barre');
      const timeKey = ValueKey<String>('temps');
      const playing = Duration(minutes: 10);
      for (final Duration aim in [
        Duration.zero, // tout à gauche, en arrière : bascule à droite
        const Duration(minutes: 5), // en arrière, trop près du bord gauche
        const Duration(minutes: 40), // en avant : à droite
        const Duration(minutes: 70), // en avant mais à droite de l'écran
        const Duration(minutes: 90), // tout à droite : bascule à gauche
      ]) {
        final c = seekCtrl();
        pos = aim; // ↓ pose le repère sur la position lue par la source
        c.open();
        c.move(TraversalDirection.down);
        expect(c.seekTarget, aim);
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            // Comme `PlayerControls` : rangée, 6 px, barre, temps + cadenas.
            body: Align(
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(key: rowKey, width: 800, height: 58),
                  const SizedBox(height: 6),
                  SizedBox(
                    key: barKey,
                    width: 800,
                    height: 28,
                    child: PlayerSeekMarker(
                        controller: c, position: playing, duration: total),
                  ),
                  const SizedBox(key: timeKey, width: 800, height: 48),
                ],
              ),
            ),
          ),
        ));
        final String label = formatSeekDelta(aim - playing).isEmpty
            ? formatPlayerTime(aim)
            : '${formatPlayerTime(aim)}  ${formatSeekDelta(aim - playing)}';
        final Rect pill = tester.getRect(_decoAbove(find.text(label)));
        final Rect bar = tester.getRect(find.byKey(barKey));
        final Rect ringRect =
            tester.getRect(find.byKey(PlayerOptionBar.focusRingKey));
        expect(pill.overlaps(tester.getRect(find.byKey(rowKey))), isFalse,
            reason: '$aim : rangée recouverte');
        expect(pill.overlaps(tester.getRect(find.byKey(timeKey))), isFalse,
            reason: '$aim : temps / cadenas recouverts');
        expect(pill.top, greaterThanOrEqualTo(bar.top), reason: '$aim');
        expect(pill.bottom, lessThanOrEqualTo(bar.bottom), reason: '$aim');
        expect(pill.left, greaterThanOrEqualTo(bar.left), reason: '$aim');
        expect(pill.right, lessThanOrEqualTo(bar.right), reason: '$aim');
        expect(pill.overlaps(ringRect), isFalse,
            reason: '$aim : le repère reste visible');
      }
    });

    for (final (double theme, double want) in [(2.0, 12.0), (20.0, 20.0)]) {
      testWidgets(
          '§playerPanel — thème à $theme : la pastille au rayon des boutons '
          '($want), le repère borné à un cercle', (tester) async {
        final c = seekCtrl();
        c.open();
        c.move(TraversalDirection.down);
        c.move(TraversalDirection.right);
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(extensions: [_ext(theme)]),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 800,
                height: 28,
                child: PlayerSeekMarker(
                    controller: c, position: pos, duration: total),
              ),
            ),
          ),
        ));
        expect(_radiusOf(tester, _decoAbove(find.text('10:10  +0:10'))), want,
            reason: 'pastille');
        expect(
            _radiusOf(
                tester,
                find.descendant(
                    of: find.byKey(PlayerOptionBar.focusRingKey),
                    matching: find.byType(DecoratedBox)).first),
            11,
            reason: 'repère de 22 px : jamais plus qu\'un cercle');
      });
    }
  });
}
