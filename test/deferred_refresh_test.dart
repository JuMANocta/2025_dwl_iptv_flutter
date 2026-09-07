import 'package:aetherStream/feature/home/deferred_refresh.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('§pageTick — DeferredRefresh', () {
    test('un signal sur une page visible est appliqué tout de suite', () {
      int applied = 0;
      final r = DeferredRefresh(apply: () => applied++);
      r.signal();
      expect(applied, 1);
      expect(r.stale, isFalse);
    });

    test('un signal sur une page cachée est retenu, pas appliqué', () {
      int applied = 0;
      final r = DeferredRefresh(apply: () => applied++, visible: false);
      r.signal();
      expect(applied, 0);
      expect(r.stale, isTrue);
    });

    test('N signaux cachés = UNE application au retour à l’écran', () {
      int applied = 0;
      final r = DeferredRefresh(apply: () => applied++, visible: false);
      r.signal();
      r.signal();
      r.signal();
      expect(applied, 0);
      r.visible = true;
      expect(applied, 1);
      expect(r.stale, isFalse);
      // Rester visible ne réapplique rien.
      r.visible = true;
      expect(applied, 1);
    });

    test('sortir de l’écran n’applique rien', () {
      int applied = 0;
      final r = DeferredRefresh(apply: () => applied++);
      r.visible = false;
      expect(applied, 0);
      expect(r.stale, isFalse);
    });

    test('revenir à l’écran sans signal retenu ne reconstruit pas '
        '(la bascule d’onglet ordinaire reste à zéro)', () {
      int applied = 0;
      final r = DeferredRefresh(apply: () => applied++, visible: false);
      r.visible = true;
      r.visible = false;
      r.visible = true;
      expect(applied, 0);
    });
  });
}
