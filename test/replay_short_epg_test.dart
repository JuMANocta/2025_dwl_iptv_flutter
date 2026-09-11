// §iptvUaCompat — revue 2026-09-11, D1B-06 / D5A-03 / D1B-24 — Le guide
// Replay (`get_short_epg`) était le SEUL appel au panel fait par un
// `package:http` nu : sans l'UA `IPTVSmartersPro`, un panel qui filtre l'UA
// répond 500 et la feuille se présente VIDE, sans un mot. Ce serveur local
// rejoue exactement ce panel-là.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/core/utils/host_gate.dart';
import 'package:aetherStream/data/services/replay_service.dart';

void main() {
  late HttpServer server;
  final List<String?> userAgents = <String?>[];

  setUp(() async {
    // `buildDio` lit le compte courant et le stockage legacy (cookies).
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    HostGate.resetForTest();
    userAgents.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest req) async {
      final String? ua = req.headers.value('user-agent');
      userAgents.add(ua);
      if (ua != 'IPTVSmartersPro') {
        // Le « 500 muet » des panels face à un UA inconnu (§iptvUaCompat).
        req.response.statusCode = 500;
        await req.response.close();
        return;
      }
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(<String, dynamic>{
        'epg_listings': <Map<String, dynamic>>[
          <String, dynamic>{
            'title': base64Encode(utf8.encode('Journal de 20 h')),
            'description': base64Encode(utf8.encode('Les titres')),
            'start_timestamp': 1757620800,
            'stop_timestamp': 1757622600,
            'has_archive': 1,
          },
        ],
      }));
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('⚠️ get_short_epg part avec le profil IPTV — le panel répond', () async {
    final programs = await ReplayService().fetchShortEpg(
      42,
      streamUrl: 'http://127.0.0.1:${server.port}/live/jean/s3cr3t/42.ts',
    );
    expect(userAgents, isNotEmpty);
    expect(userAgents.last, 'IPTVSmartersPro');
    expect(programs, hasLength(1));
    expect(programs.single.title, 'Journal de 20 h');
    expect(programs.single.hasArchive, isTrue);
  });

  group('ReplayCredentials.fromStreamUrl — la règle UNIQUE (D1B-24)', () {
    test('préfixe en majuscules reconnu (l ancienne copie le ratait)', () {
      final c = ReplayCredentials.fromStreamUrl(
          'http://h:8080/LIVE/jean/s3cr3t/1.ts')!;
      expect((c.server, c.username, c.password),
          ('http://h:8080', 'jean', 's3cr3t'));
    });

    test('⚠️ URL de CDN : aucun faux identifiant, repli sur le compte', () {
      expect(
          ReplayCredentials.fromStreamUrl('http://cdn.example.com/a.b/c/d.m3u8'),
          isNull);
    });

    test('query username/password : lue', () {
      final c = ReplayCredentials.fromStreamUrl(
          'http://h/get.php?username=jean&password=s3cr3t')!;
      expect((c.server, c.username, c.password), ('http://h', 'jean', 's3cr3t'));
    });
  });
}
