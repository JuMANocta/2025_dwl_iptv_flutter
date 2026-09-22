// §tvPlayerPanel — Sur TV, chaque option du lecteur est un bouton de la barre
// du bas, et sa liste s'ouvre au-dessus de lui, dans l'image. La vidéo est UN
// focusable racine qui délègue ses touches à un automate pur : ces tests
// tiennent l'automate (qui consomme quoi, où va le focus, où mène Retour) et
// le dessin de la rangée (étiquettes d'état, anneau sur l'élément courant).
import 'dart:async';

import 'package:aetherStream/feature/player/widgets/tv_option_bar.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Une rangée type : Épisode suivant, Audio (liste), Vitesse (liste),
/// Infos vidéo (action directe).
class _Rig {
  final applied = <String>[];
  int nextCalls = 0;
  int statsCalls = 0;
  bool failApply = false;
  Completer<bool>? pending;

  TvOptionItem item(String label, {bool selected = false}) => TvOptionItem(
        label: label,
        selected: selected,
        onSelect: () async {
          if (pending != null) return pending!.future;
          if (failApply) return false;
          applied.add(label);
          return true;
        },
      );

  List<TvOptionButton> buttons({bool withNext = true}) => [
        if (withNext)
          TvOptionButton(
            kind: TvOptionKind.nextEpisode,
            icon: Icons.skip_next,
            title: 'Suivant',
            onAction: () => nextCalls++,
            leavesRow: true,
          ),
        TvOptionButton(
          kind: TvOptionKind.audio,
          icon: Icons.graphic_eq,
          title: 'Audio',
          value: 'Français',
          items: () => [item('Français', selected: true), item('English')],
        ),
        TvOptionButton(
          kind: TvOptionKind.speed,
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
        TvOptionButton(
          kind: TvOptionKind.stats,
          icon: Icons.query_stats,
          title: 'Infos vidéo',
          value: 'Masquées',
          onAction: () => statsCalls++,
        ),
      ];
}

TvOptionsController _ctrl(_Rig rig, {bool withNext = true}) =>
    TvOptionsController()..syncButtons(rig.buttons(withNext: withNext));

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
      expect(c.current!.kind, TvOptionKind.audio);
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
      expect(c.current!.kind, TvOptionKind.speed);
    });

    test('sans « Audio », ouverture sur le premier bouton', () {
      final c = TvOptionsController()
        ..syncButtons([
          TvOptionButton(
            kind: TvOptionKind.fit,
            icon: Icons.fit_screen,
            title: 'Format',
            items: () => const [],
          ),
        ]);
      c.open();
      expect(c.index, 0);
    });

    test('aucun bouton : la rangée ne s\'ouvre pas', () {
      final c = TvOptionsController();
      expect(c.open(), isFalse);
      expect(c.active, isFalse);
    });

    test('←/→ parcourent la rangée, bornés aux deux bouts', () {
      final c = _ctrl(_Rig());
      c.open(); // Audio, index 1
      expect(c.move(TraversalDirection.left), isTrue);
      expect(c.current!.kind, TvOptionKind.nextEpisode);
      expect(c.move(TraversalDirection.left), isTrue,
          reason: 'consommée même au bord : jamais un seek');
      expect(c.index, 0);
      c.move(TraversalDirection.right);
      c.move(TraversalDirection.right);
      c.move(TraversalDirection.right);
      c.move(TraversalDirection.right);
      expect(c.current!.kind, TvOptionKind.stats);
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
      expect(c.current!.kind, TvOptionKind.speed,
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
      expect(c.current!.kind, TvOptionKind.speed);
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
      expect(c.current!.kind, TvOptionKind.speed);
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
      expect(c.current!.kind, TvOptionKind.audio);
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
      c.replaceList(TvOptionKind.speed, [rig.item('x')]);
      expect(c.items.length, 2, reason: 'pas la liste de ce bouton');
      c.replaceList(TvOptionKind.audio, [rig.item('résultat')]);
      expect(c.items.single.label, 'résultat');
      expect(c.listIndex, 0);
      c.back();
      c.select();
      expect(c.items.length, 2, reason: 'refermer rend la liste d\'origine');
    });
  });

  group('rangée', () {
    Future<TvOptionsController> pump(WidgetTester tester, _Rig rig) async {
      final c = _ctrl(rig);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Align(
            alignment: Alignment.bottomCenter,
            child: TvOptionBar(controller: c),
          ),
        ),
      ));
      return c;
    }

    Finder ringOn(String text) => find.descendant(
        of: find.byKey(TvOptionBar.focusRingKey), matching: find.text(text));

    testWidgets('libellés d\'état sous chaque bouton, sans anneau au repos',
        (tester) async {
      await pump(tester, _Rig());
      expect(find.text('Audio'), findsOneWidget);
      expect(find.text('Français'), findsOneWidget);
      expect(find.text('1×'), findsOneWidget);
      expect(find.text('Masquées'), findsOneWidget);
      expect(find.byKey(TvOptionBar.focusRingKey), findsNothing);
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
      expect(find.byKey(TvOptionBar.focusRingKey), findsOneWidget);
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
  });

  group('§tvSeekBar — pas croissant (pur)', () {
    test('appui simple 10 s, puis 30 s, 1 min, 5 min en maintenant', () {
      expect(tvSeekStep(Duration.zero), const Duration(seconds: 10));
      expect(tvSeekStep(const Duration(milliseconds: 499)),
          const Duration(seconds: 10));
      expect(tvSeekStep(const Duration(milliseconds: 500)),
          const Duration(seconds: 30));
      expect(tvSeekStep(const Duration(milliseconds: 1500)),
          const Duration(minutes: 1));
      expect(tvSeekStep(const Duration(milliseconds: 2500)),
          const Duration(minutes: 5));
      expect(tvSeekStep(const Duration(seconds: 30)),
          const Duration(minutes: 5));
    });

    test('bornes : jamais avant 0, jamais après la durée', () {
      const total = Duration(minutes: 90);
      expect(tvSeekClamp(const Duration(seconds: -5), total), Duration.zero);
      expect(tvSeekClamp(const Duration(minutes: 95), total), total);
      expect(tvSeekClamp(const Duration(minutes: 30), total),
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

    TvOptionsController seekCtrl({bool live = false}) {
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
          : TvSeekSource(
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
          reason: 'moins de ${TvOptionsController.seekRepeatGap.inMilliseconds} ms');
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

    testWidgets('le repère : anneau et heure visée au-dessus de la barre',
        (tester) async {
      final c = seekCtrl();
      c.open();
      c.move(TraversalDirection.down);
      held = Duration.zero;
      for (var i = 0; i < 3; i++) {
        c.move(TraversalDirection.right);
      }
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: SizedBox(
              width: 800,
              height: 28,
              child: TvSeekMarker(
                controller: c,
                position: pos,
                duration: total,
              ),
            ),
          ),
        ),
      ));
      expect(find.byKey(TvOptionBar.focusRingKey), findsOneWidget);
      expect(find.text('10:30  +0:30'), findsOneWidget);
      final ring = tester.getCenter(find.byKey(TvOptionBar.focusRingKey));
      final label = tester.getCenter(find.text('10:30  +0:30'));
      expect(label.dy, lessThan(ring.dy), reason: 'l\'heure est AU-DESSUS');
      // 10 min 30 s sur 90 min, piste marge 14 px de chaque côté.
      final double left = tester.getTopLeft(find.byType(SizedBox).last).dx;
      expect(ring.dx - left, closeTo(14 + (630 / 5400) * (800 - 28), 1));
      c.back();
      await tester.pump();
      expect(find.byKey(TvOptionBar.focusRingKey), findsNothing);
    });
  });
}
