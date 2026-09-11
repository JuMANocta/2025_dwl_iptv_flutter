// §cookieScope — revue 2026-09-11, D1B-10 — Les cookies du stockage LEGACY
// (ère mono-compte) partaient avec les requêtes de TOUT compte sans cookies,
// donc vers un autre fournisseur. decisions.md annonçait `cookiesFor` « pure
// et testée » : aucun test n'existait.

import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/core/utils/network.dart';
import 'package:aetherStream/data/models/stream_account.dart';

StreamAccount _account({String? cookies}) => StreamAccount(
      id: 'acc_b',
      label: 'Fournisseur B',
      mode: StreamAuthMode.separate,
      baseUrl: 'http://b.example:8080',
      username: 'u',
      password: 'p',
      cookies: cookies,
    );

void main() {
  const Map<String, dynamic> legacy = <String, dynamic>{
    'cookies': 'PHPSESSID=panelA',
  };

  test('un compte avec cookies envoie les siens', () {
    expect(NetworkUtils.cookiesFor(_account(cookies: ' sid=b '), legacy), 'sid=b');
  });

  test('⚠️ un compte SANS cookies n envoie RIEN — jamais ceux du legacy', () {
    expect(NetworkUtils.cookiesFor(_account(), legacy), '');
    expect(NetworkUtils.cookiesFor(_account(cookies: '   '), legacy), '');
  });

  test('sans compte du tout (avant migration) : le legacy reste lu', () {
    expect(NetworkUtils.cookiesFor(null, legacy), 'PHPSESSID=panelA');
    expect(NetworkUtils.cookiesFor(null, const <String, dynamic>{}), '');
  });
}
