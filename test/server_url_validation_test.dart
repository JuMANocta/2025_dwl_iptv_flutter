import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/feature/accounts/edit_account_sheet.dart';

/// Revue 2026-09-11, D4B-02 — Les deux validateurs du formulaire de compte
/// faisaient `Uri.tryParse(v)!.isAbsolute` : `tryParse` rend `null` sur une
/// URL non analysable (port non numérique, crochet IPv6 non fermé), et le `!`
/// levait en plein `validate()` — aucun message sous le champ, « Enregistrer »
/// ne faisait plus rien.
void main() {
  group('isValidServerUrl (D4B-02)', () {
    test('le cas du signalement : un O à la place d\'un 0 dans le port', () {
      // Le point de départ du défaut : `tryParse` rend null ici.
      expect(Uri.tryParse('http://monserveur.tv:808O'), isNull);
      expect(isValidServerUrl('http://monserveur.tv:808O'), isFalse);
      expect(isValidServerUrl('http://h:80a'), isFalse);
    });

    test('crochet IPv6 non fermé → refusé, sans lever', () {
      expect(isValidServerUrl('http://[fe80::1'), isFalse);
    });

    test('adresses valides', () {
      expect(isValidServerUrl('http://h:8080/get.php'), isTrue);
      expect(isValidServerUrl('  https://iptv.example.com  '), isTrue);
      expect(
          isValidServerUrl(
              'http://host.tv:8080/get.php?username=u&password=p&type=m3u_plus'),
          isTrue);
    });

    test('vide, nul, relative ou sans hôte → refusée', () {
      expect(isValidServerUrl(null), isFalse);
      expect(isValidServerUrl(''), isFalse);
      expect(isValidServerUrl('   '), isFalse);
      expect(isValidServerUrl('monserveur.tv:8080'), isFalse);
      expect(isValidServerUrl('http://'), isFalse);
    });
  });
}
