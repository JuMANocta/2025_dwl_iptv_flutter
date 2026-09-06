import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/services/storage_janitor.dart';

/// §acctDeleteTruth — Le dialogue de suppression de compte annonce désormais
/// ce qui part (§audit0903 n° 12). Le chiffre doit rester LISIBLE : le
/// formateur d'origine était en mégaoctets fixes, et un cache de 300 Ko
/// s'affichait « 0.0 Mo » — soit « il n'y a rien à perdre », ce qui est faux.
void main() {
  test('au-dessus du mégaoctet : une décimale', () {
    expect(StorageJanitor.humanBytes(217 * 1024 * 1024), '217.0 Mo');
    expect(StorageJanitor.humanBytes((1.5 * 1024 * 1024).round()), '1.5 Mo');
  });

  test('sous le mégaoctet : des kilooctets, jamais « 0.0 Mo »', () {
    expect(StorageJanitor.humanBytes(300 * 1024), '300 Ko');
    expect(StorageJanitor.humanBytes(4096), '4 Ko');
  });

  test('sous le kilooctet : des octets', () {
    expect(StorageJanitor.humanBytes(512), '512 octets');
    expect(StorageJanitor.humanBytes(0), '0 octets');
  });
}
