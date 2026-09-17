// R41 (2026-09-13) — « Vider le journal » n'effaçait que la session COURANTE :
// `diagnostic_session_previous.log` restait intact sur le disque et la console
// continuait de le servir sur le réseau local via `/logs.txt?session=previous`.
// Depuis R35 on sait que ces journaux peuvent porter le jeton de nos serveurs
// locaux : « vider » devait vraiment vider.
//
// Ce test parle à la VRAIE console (comme `web_console_auth_test.dart`) : c'est
// le seul moyen de vérifier ce que la page reçoit juste après un vidage.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/core/diagnostics/log_buffer.dart';
import 'package:aetherStream/core/themes/app_theme_config.dart';
import 'package:aetherStream/core/utils/lan_address.dart';
import 'package:aetherStream/data/services/web_console_service.dart';

late Directory _root;

void _mockPathProvider() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => switch (call.method) {
      'getApplicationSupportDirectory' => _root.path,
      'getApplicationDocumentsDirectory' => _root.path,
      _ => null,
    },
  );
}

File get _current => File('${_root.path}/diagnostic_session_current.log');
File get _previous => File('${_root.path}/diagnostic_session_previous.log');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ⚠️ Il faut les DEUX moitiés, et elles se gênent : le binding, pour simuler
  // `path_provider` (le dossier où vivent les fichiers de session), et un VRAI
  // client HTTP, pour parler à la console — qui, elle, écoute pour de bon sur
  // la boucle locale. Or `TestWidgetsFlutterBinding` installe un `HttpClient`
  // factice qui rend 400 à tout sans jamais sortir. On lui retire ce seul
  // remplacement ; `web_console_auth_test.dart` s'en tire autrement, en
  // n'installant simplement jamais le binding.
  final HttpOverrides? clientFactice = HttpOverrides.current;

  final WebConsoleService svc = WebConsoleService.instance;

  setUp(() async {
    HttpOverrides.global = null;
    _root = Directory.systemTemp.createTempSync('aether_r41_console');
    _mockPathProvider();
    DiagnosticLog.resetForTest();
    WebConsoleService.localAddress = () async => '127.0.0.1';
    await svc.start(theme: AppThemeConfig.defaults);
  });

  tearDown(() async {
    await svc.stop();
    WebConsoleService.localAddress = () => lanIpv4(allowNonPrivate: true);
    DiagnosticLog.resetForTest();
    // ⚠️ Artefact de timing Windows (errno 32), pas un état de l'application.
    try {
      if (_root.existsSync()) _root.deleteSync(recursive: true);
    } catch (_) {}
    HttpOverrides.global = clientFactice;
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

  Future<void> clearFromConsole() async {
    final HttpClientResponse r =
        await send('POST', '/api/logs/clear?t=${svc.token}', body: '{}');
    expect(r.statusCode, 200);
    await r.drain<void>();
  }

  test('🧹 Vider emporte la session PRÉCÉDENTE, pas seulement la courante',
      () async {
    // Ce que la rotation du démarrage a laissé en place.
    _current.writeAsStringSync('10:00:00.000  jeton HJKLMNPQRSTUVWXY');
    await DiagnosticLog.initPersistenceForTest();
    DiagnosticLog.add('session en cours');
    await DiagnosticLog.flushNowForTest();
    expect(_previous.existsSync(), isTrue);
    expect(_current.existsSync(), isTrue);

    await clearFromConsole();

    expect(_previous.existsSync(), isFalse,
        reason: 'le fichier que R41 laissait derrière lui');
    expect(_current.existsSync() ? _current.readAsStringSync() : '', isEmpty);
  });

  test('juste après un vidage, ?session=previous rend du VIDE, jamais une erreur',
      () async {
    _current.writeAsStringSync('10:00:00.000  secret_de_la_session_precedente');
    await DiagnosticLog.initPersistenceForTest();
    // La route sert bien quelque chose AVANT le vidage : le test a du sens.
    final HttpClientResponse avant =
        await send('GET', '/logs.txt?session=previous&t=${svc.token}');
    expect(await textOf(avant), contains('secret_de_la_session_precedente'));

    await clearFromConsole();

    final HttpClientResponse apres =
        await send('GET', '/logs.txt?session=previous&t=${svc.token}');
    // La vue Journal relance cette lecture toute seule : une erreur s'afficherait
    // en boucle. Vide, et 200.
    expect(apres.statusCode, 200);
    expect(await textOf(apres), isEmpty);

    final HttpClientResponse courant =
        await send('GET', '/logs.txt?t=${svc.token}');
    expect(courant.statusCode, 200);
    expect(await textOf(courant), isEmpty);
  });

  // F1 — La moitié visible : ce que la personne LIT quand l'effacement n'a pas
  // été complet. Un « Journal vidé » affiché à tort laisse croire qu'un secret
  // est parti alors qu'il reviendra au prochain démarrage.
  test('un fichier qui résiste : la console le DIT, sans code d erreur',
      () async {
    _current.writeAsStringSync('10:00:00.000  session précédente');
    await DiagnosticLog.initPersistenceForTest();
    // Un dossier à la place du fichier : la suppression échoue pour une raison
    // qui n'est PAS « déjà absent ».
    _previous.deleteSync();
    Directory(_previous.path).createSync();

    final HttpClientResponse r =
        await send('POST', '/api/logs/clear?t=${svc.token}', body: '{}');
    expect(r.statusCode, 200);
    final Map<String, dynamic> j =
        jsonDecode(await textOf(r)) as Map<String, dynamic>;
    expect(j['ok'], isFalse,
        reason: '« Journal vidé » alors qu un fichier survit est un mensonge');
    final String message = j['error'] as String;
    expect(message, contains('pas pu être supprimé'));
    // §clientText / §userError : le résultat, jamais la mécanique ni un `$e`.
    expect(message, isNot(contains('Exception')));
    expect(message, isNot(contains(_root.path)));
  });
}
