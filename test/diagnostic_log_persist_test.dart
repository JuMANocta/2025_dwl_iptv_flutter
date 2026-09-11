// §logPersist / §tvLogsPersist — revue 2026-09-11, D3B-12.
//
// Le journal persistant écrivait par `writeAsString`, qui TRONQUE la
// destination avant d'écrire : un kill en plein flush — le cas même pour
// lequel §logPersist existe — laissait un fichier coupé. Et la relecture
// décodait en UTF-8 STRICT : un emoji coupé en fin de fichier faisait perdre
// TOUTE la session précédente pour un seul caractère.
import 'dart:convert';
import 'dart:io';

import 'package:aetherStream/core/diagnostics/log_buffer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _root = Directory.systemTemp.createTempSync('aether_logpersist');
    _mockPathProvider();
    DiagnosticLog.resetForTest();
  });

  tearDown(() {
    DiagnosticLog.resetForTest();
    if (_root.existsSync()) _root.deleteSync(recursive: true);
  });

  test('une session précédente coupée au milieu d\'un caractère reste LISIBLE',
      () async {
    final List<int> octets =
        utf8.encode('10:00:00.000  ligne 1\n10:00:01.000  plantage 💀');
    // Coupure au milieu de l'emoji (4 octets) : exactement ce que laisse un
    // kill pendant l'écriture.
    _current.writeAsBytesSync(octets.sublist(0, octets.length - 2));

    await DiagnosticLog.initPersistenceForTest();

    final String? precedente = DiagnosticLog.previousSessionDump;
    expect(precedente, isNotNull,
        reason: 'un seul caractère coupé ne doit pas coûter toute la session');
    expect(precedente, contains('ligne 1'));
    expect(precedente, contains('plantage'));
  });

  test('un flush passe par un .tmp puis un renommage : le fichier courant est '
      'le tampon, aucun .tmp ne traîne', () async {
    await DiagnosticLog.initPersistenceForTest();
    DiagnosticLog.add('première ligne');
    DiagnosticLog.add('seconde ligne');

    await DiagnosticLog.flushNowForTest();

    expect(_current.existsSync(), isTrue);
    expect(_current.readAsStringSync(), DiagnosticLog.dump());
    expect(File('${_current.path}.tmp').existsSync(), isFalse);
  });

  test('un .tmp laissé par un kill est écarté : la session précédente vient '
      'du dernier flush COMPLET', () async {
    _current.writeAsStringSync('ancienne session complète');
    final File tmp = File('${_current.path}.tmp')
      ..writeAsStringSync('écriture interrom');

    await DiagnosticLog.initPersistenceForTest();

    expect(DiagnosticLog.previousSessionDump, 'ancienne session complète');
    expect(tmp.existsSync(), isFalse);
  });
}
