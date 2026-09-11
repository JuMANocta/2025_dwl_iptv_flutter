// §webConsole — revue 2026-09-11, D1B-02 / D1B-12 / D1B-13 — La console web
// RESTE en release (décision utilisateur), mais VERROUILLÉE. Ce test la démarre
// pour de vrai, sur la boucle locale, et vérifie ce qu'elle expose.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/core/themes/app_theme_config.dart';
import 'package:aetherStream/core/utils/lan_address.dart';
import 'package:aetherStream/data/services/web_console_service.dart';

void main() {
  final WebConsoleService svc = WebConsoleService.instance;

  setUp(() async {
    WebConsoleService.localAddress = () async => '127.0.0.1';
    await svc.start(theme: AppThemeConfig.defaults);
  });

  tearDown(() async {
    await svc.stop();
    WebConsoleService.localAddress = () => lanIpv4(allowNonPrivate: true);
    WebConsoleService.maxBodyBytes = 20 * 1024 * 1024;
  });

  Future<HttpClientResponse> send(String method, String pathAndQuery,
      {String? body}) async {
    final HttpClient client = HttpClient();
    final HttpClientRequest req = await client.openUrl(
        method, Uri.parse('http://127.0.0.1:${svc.port}$pathAndQuery'));
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(body);
    }
    return req.close();
  }

  Future<String> textOf(HttpClientResponse r) => r.transform(utf8.decoder).join();

  test('jeton de 16 caractères, serveur lié à l adresse choisie', () {
    expect(svc.token, hasLength(16));
    expect(svc.boundAddress?.address, '127.0.0.1');
    expect(svc.running.value, isTrue);
    expect(svc.consoleUrl, contains('t=${svc.token}'));
  });

  test('sans jeton, ou avec un faux : 403', () async {
    final HttpClientResponse r1 = await send('GET', '/');
    expect(r1.statusCode, 403);
    await r1.drain<void>();
    final HttpClientResponse r2 = await send('GET', '/?t=AAAAAAAAAAAAAAAA');
    expect(r2.statusCode, 403);
    await r2.drain<void>();
  });

  test('⚠️ page servie : ni CORS *, ni police Google, Referer coupé', () async {
    final HttpClientResponse r = await send('GET', '/?t=${svc.token}');
    expect(r.statusCode, 200);
    expect(r.headers.value('access-control-allow-origin'), isNull);
    expect(r.headers.value('referrer-policy'), 'no-referrer');
    final String html = await textOf(r);
    expect(html, isNot(contains('fonts.googleapis.com')));
    expect(html, isNot(contains('fonts.gstatic.com')));
    expect(html, contains('<meta name="referrer" content="no-referrer">'));
  });

  test('un geste authentifié (page ouverte) repousse l arrêt automatique', () async {
    final DateTime before = svc.autoStopAt!;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final HttpClientResponse r = await send('GET', '/?t=${svc.token}');
    expect(r.statusCode, 200);
    await r.drain<void>();
    expect(svc.autoStopAt!.isAfter(before), isTrue);
  });

  // Relecture de la revue — la vue Journal relit `/logs.txt` toutes les 2 s,
  // l'état des listes `/fleet.json` toutes les 5 s : si ces lectures
  // AUTOMATIQUES repoussaient l'arrêt, un onglet oublié garderait la console
  // ouverte sans fin (pire que les 30 min fixes d'avant la revue).
  test('⚠️ le suivi automatique du journal ne repousse PAS l arrêt', () async {
    final DateTime before = svc.autoStopAt!;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final HttpClientResponse r = await send('GET', '/logs.txt?t=${svc.token}');
    expect(r.statusCode, 200);
    await r.drain<void>();
    expect(svc.autoStopAt, before);
  });

  test('erreur d API : la phrase lisible, jamais un toString brut', () async {
    final HttpClientResponse r =
        await send('POST', '/api/theme/save?t=${svc.token}', body: '{}');
    expect(r.statusCode, 400);
    final Map<String, dynamic> j =
        jsonDecode(await textOf(r)) as Map<String, dynamic>;
    expect(j['ok'], isFalse);
    expect(j['error'], 'Preset manquant.');
  });

  test('⚠️ corps au-delà du plafond : 413, rien chargé', () async {
    WebConsoleService.maxBodyBytes = 64;
    final HttpClientResponse r = await send('POST', '/api/remote?t=${svc.token}',
        body: jsonEncode(<String, String>{'key': 'x' * 200}));
    expect(r.statusCode, 413);
    await r.drain<void>();
  });

  test('stop() : bandeau éteint, plus rien n écoute', () async {
    final int port = svc.port!;
    await svc.stop();
    expect(svc.running.value, isFalse);
    expect(svc.token, isNull);
    await expectLater(
      HttpClient()
          .getUrl(Uri.parse('http://127.0.0.1:$port/'))
          .then((HttpClientRequest q) => q.close()),
      throwsA(isA<SocketException>()),
    );
  });
}
