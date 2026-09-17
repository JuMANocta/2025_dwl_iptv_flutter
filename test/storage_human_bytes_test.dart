import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:aetherStream/data/services/storage_janitor.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:aetherStream/l10n/l10n_ext.dart';

/// §acctDeleteTruth — Le dialogue de suppression de compte annonce ce qui part
/// (§audit0903 n° 12). Le chiffre doit rester LISIBLE : le formateur d'origine
/// était en mégaoctets fixes, et un cache de 300 Ko s'affichait « 0.0 Mo » —
/// soit « il n'y a rien à perdre », ce qui est faux.
///
/// R8 (2026-09-16) — `humanBytes` délègue désormais à `formatFileSize`, le seul
/// formateur de tailles de l'app. ⚠️ Ces tests tiennent la CONTINUITÉ : la
/// règle de précision d'origine survit à la délégation. Seul le séparateur
/// décimal change, et c'était le défaut (« 12.3 Mo » sur un écran français).
void main() {
  setUpAll(() => L10n.bind(lookupAppLocalizations(const Locale('fr'))));
  tearDownAll(L10n.resetForTest);

  test('au-dessus du mégaoctet : une décimale, virgule en français', () {
    expect(StorageJanitor.humanBytes(217 * 1024 * 1024), '217,0 Mo');
    expect(StorageJanitor.humanBytes((1.5 * 1024 * 1024).round()), '1,5 Mo');
  });

  test('sous le mégaoctet : des kilooctets, jamais « 0,0 Mo »', () {
    expect(StorageJanitor.humanBytes(300 * 1024), '300 Ko');
    expect(StorageJanitor.humanBytes(4096), '4 Ko');
  });

  test('sous le kilooctet : des octets, « 0 octet » au singulier', () {
    expect(StorageJanitor.humanBytes(512), '512 octets');
    expect(StorageJanitor.humanBytes(0), '0 octet');
  });

  test("R8 — le bilan de balayage passe par le même formateur", () {
    const r = StorageSweepResult(fileCount: 3, bytes: 300 * 1024);
    expect(r.label, '300 Ko');
    const big = StorageSweepResult(fileCount: 1, bytes: 12 * 1024 * 1024);
    expect(big.label, '12,0 Mo');
  });
}
