// §tourFix — revue 2026-09-11, D1A-16 — `buildM3uUrl` (mode séparé)
// interpolait identifiant et mot de passe BRUTS dans la query : « ab&cd#1 »
// partait en `password=ab`, et le repli get.php échouait à tous les coups.

import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/data/models/stream_account.dart';

StreamAccount _separate(String user, String pass) => StreamAccount(
      id: 'acc_1',
      label: 'Test',
      mode: StreamAuthMode.separate,
      baseUrl: 'http://panel.example:8080/',
      username: user,
      password: pass,
    );

void main() {
  test('⚠️ mot de passe à caractères réservés : restitué à l identique', () {
    final String url = _separate('jean dupont', 'a&b#c+d').buildM3uUrl()!;
    final Map<String, String> qp = Uri.parse(url).queryParameters;
    expect(qp['password'], 'a&b#c+d');
    expect(qp['username'], 'jean dupont');
    expect(qp['type'], 'm3u_plus');
    expect(qp['output'], 'ts');
  });

  test('identifiants alphanumériques : URL strictement inchangée', () {
    expect(
      _separate('jean', 's3cr3t').buildM3uUrl(),
      'http://panel.example:8080/get.php?username=jean&password=s3cr3t'
      '&type=m3u_plus&output=ts',
    );
  });
}
