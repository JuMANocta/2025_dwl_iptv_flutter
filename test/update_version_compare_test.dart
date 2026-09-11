// D5A-14 (revue 2026-09-11, lot 9) — `isNewerVersion` décide SEULE si l'app
// propose une mise à jour. Elle vivait en privé dans `UpdateService` sans un
// seul test : inverser une comparaison aurait coupé toute mise à jour (ou
// proposé une rétrogradation) sans que rien ne rougisse.
//
// ⚠️ Le build (`+N`) est ignoré À DESSEIN : depuis le split par ABI, le
// versionCode installé vaut `codeAbi × 1000 + build` (2151 pour un arm64) et
// ne se compare plus au build du tag.

import 'package:aetherStream/data/services/update_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isNewerVersion — quand proposer la mise à jour', () {
    test('le patch se compare en NOMBRE, pas en texte (10 > 9)', () {
      expect(isNewerVersion('v1.18.10', '1.18.9'), isTrue);
      expect(isNewerVersion('v1.18.9', '1.18.10'), isFalse);
    });

    test('le mineur et le majeur l\'emportent sur le patch', () {
      expect(isNewerVersion('v1.19.0', '1.18.99'), isTrue);
      expect(isNewerVersion('v2.0.0', '1.99.99'), isTrue);
      expect(isNewerVersion('v1.17.99', '1.18.0'), isFalse);
    });

    test('la même version n\'est pas une mise à jour', () {
      expect(isNewerVersion('v1.18.18', '1.18.18'), isFalse);
    });

    test('le préfixe « v » du tag est facultatif', () {
      expect(isNewerVersion('1.18.19', '1.18.18'), isTrue);
    });

    test('le build (+N) est ignoré des deux côtés', () {
      expect(isNewerVersion('v1.18.18+999', '1.18.18+151'), isFalse);
      // Une split arm64 installée (versionCode 2151) n'est pas « plus
      // récente » que la release de même numéro…
      expect(isNewerVersion('v1.18.18', '1.18.18+2151'), isFalse);
      // …et la suivante lui est bien proposée.
      expect(isNewerVersion('v1.18.19', '1.18.18+2151'), isTrue);
    });

    test('un tag illisible ne propose RIEN (jamais de rétrogradation)', () {
      expect(isNewerVersion('nightly', '1.18.18'), isFalse);
      expect(isNewerVersion('v1.18.x', '1.18.18'), isFalse);
      expect(isNewerVersion('', '1.18.18'), isFalse);
    });
  });
}
