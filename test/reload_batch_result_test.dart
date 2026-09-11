import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/services/playlist_reload_service.dart';

/// Revue 2026-09-11, D4B-15 — « Tout recharger » indexait les échecs par le
/// NOM du compte : deux abonnements homonymes en échec ne faisaient qu'une
/// entrée, et le bilan (« 1 échec : Xtream »), `allOk` et le total mentaient.
void main() {
  group('ReloadBatchResult — comptes homonymes (D4B-15)', () {
    test('deux « Xtream » injoignables → deux échecs comptés', () {
      const ReloadBatchResult r = ReloadBatchResult(
        succeeded: <String>['Premium'],
        failed: <String>['Xtream', 'Xtream'],
      );
      expect(r.failed.length, 2);
      expect(r.total, 3);
      expect(r.allOk, isFalse);
      // Le bilan compte bien DEUX échecs (le nombre est un paramètre ICU de
      // la phrase : il apparaît en toutes lettres dans le texte rendu).
      expect(r.summary, contains('2'));
    });

    test('tout en échec, homonymes compris → aucun succès', () {
      const ReloadBatchResult r = ReloadBatchResult(
        succeeded: <String>[],
        failed: <String>['Xtream', 'Xtream'],
      );
      expect(r.total, 2);
      expect(r.summary, contains('Xtream'));
    });

    test('aucun échec → allOk', () {
      const ReloadBatchResult r = ReloadBatchResult(
        succeeded: <String>['A', 'B'],
        failed: <String>[],
      );
      expect(r.allOk, isTrue);
      expect(r.total, 2);
    });
  });
}
