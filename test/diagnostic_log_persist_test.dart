// §logPersist / §tvLogsPersist — revue 2026-09-11, D3B-12.
//
// Le journal persistant écrivait par `writeAsString`, qui TRONQUE la
// destination avant d'écrire : un kill en plein flush — le cas même pour
// lequel §logPersist existe — laissait un fichier coupé. Et la relecture
// décodait en UTF-8 STRICT : un emoji coupé en fin de fichier faisait perdre
// TOUTE la session précédente pour un seul caractère.
import 'dart:async';
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
File get _previous => File('${_root.path}/diagnostic_session_previous.log');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _root = Directory.systemTemp.createTempSync('aether_logpersist');
    _mockPathProvider();
    DiagnosticLog.resetForTest();
  });

  tearDown(() {
    DiagnosticLog.resetForTest();
    // ⚠️ Windows refuse d'effacer un dossier dont un fichier vient d'être
    // écrit par un flush non attendu (errno 32) : c'est un artefact de timing
    // du test, pas un état de l'application, et le dossier est dans le temp
    // du système.
    try {
      if (_root.existsSync()) _root.deleteSync(recursive: true);
    } catch (_) {}
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

  // R41 (2026-09-13) — « Vider le journal » ne touchait JAMAIS
  // `diagnostic_session_previous.log` : une session entière restait sur le
  // disque, et la console continuait de la servir sur le réseau local via
  // `/logs.txt?session=previous`. Depuis R35, on sait que ces journaux peuvent
  // porter le jeton de nos serveurs locaux.
  group('R41 — un vidage emporte les DEUX sessions', () {
    test('clearAll() efface le courant, le précédent, et le .tmp qui traîne',
        () async {
      _current.writeAsStringSync('10:00:00.000  session précédente, un secret');
      await DiagnosticLog.initPersistenceForTest(); // rotation : courant → précédent
      DiagnosticLog.add('session en cours');
      await DiagnosticLog.flushNowForTest();
      File('${_current.path}.tmp').writeAsStringSync('écriture interrom');
      expect(_previous.existsSync(), isTrue);
      expect(_current.existsSync(), isTrue);

      await DiagnosticLog.clearAll();

      expect(_previous.existsSync(), isFalse,
          reason: 'c est exactement le fichier que R41 laissait sur le disque');
      expect(File('${_current.path}.tmp').existsSync(), isFalse);
      // Le fichier courant peut être recréé VIDE par le flush périodique : ce
      // qui compte est qu'il ne porte plus rien.
      expect(_current.existsSync() ? _current.readAsStringSync() : '', isEmpty);
      // Et la copie mémoire de la session précédente, que sert la console.
      expect(DiagnosticLog.previousSessionDump, isNull);
      expect(DiagnosticLog.previousSessionLineCount, 0);
      expect(DiagnosticLog.lineCount, 0);
    });

    test('⚠️ une écriture EN VOL ne ressuscite pas le fichier effacé', () async {
      await DiagnosticLog.initPersistenceForTest();
      DiagnosticLog.add('SECRET de la session en cours');

      // ⚠️ La porte est indispensable, et une première version de ce test s'en
      // passait : lancer une grosse écriture puis vider produit l'interleaving
      // BÉNIN (la purge efface le `.tmp`, le renommage échoue, rien ne renaît),
      // et le test restait vert même en retirant la garde qu'il prétendait
      // tenir. Ici l'écriture est retenue APRÈS avoir photographié le tampon
      // d'avant le vidage et AVANT de toucher au disque : les suppressions
      // passent donc en premier, et l'écriture recrée ensuite son `.tmp` puis
      // le renomme sur `current`. C'est le cas dangereux, à coup sûr.
      final Completer<void> porte = Completer<void>();
      DiagnosticLog.pauseBeforeWriteForTest = () => porte.future;
      final Future<void> enVol = DiagnosticLog.flushNowForTest();

      final Future<bool> vidage = DiagnosticLog.clearAll(); // PAS attendu ici
      await Future<void>.delayed(const Duration(milliseconds: 50));
      porte.complete(); // l'écriture reprend et veut recréer `current`
      await enVol;
      final bool propre = await vidage;

      expect(propre, isTrue);
      final String surDisque =
          _current.existsSync() ? _current.readAsStringSync() : '';
      expect(surDisque, isEmpty,
          reason: 'le renommage d une écriture en vol a recréé le fichier');
      expect(surDisque, isNot(contains('SECRET')));
    });

    test('⚠️ un vidage lancé AVANT la fin de la rotation n est pas ressuscité '
        'par elle', () async {
      // La console peut s'ouvrir très tôt après le boot : l'amorçage disque est
      // async. Une rotation qui tournerait APRÈS l'effacement renommerait le
      // fichier courant en « précédent » — elle recréerait exactement ce qu'on
      // vient de détruire.
      _current.writeAsStringSync('10:00:00.000  session précédente, un secret');
      final Future<void> amorce =
          DiagnosticLog.initPersistenceForTest(); // volontairement PAS attendue

      await DiagnosticLog.clearAll();
      await amorce;

      expect(_previous.existsSync(), isFalse);
      expect(DiagnosticLog.previousSessionDump, isNull);
    });

    test('sans persistance amorcée, un vidage ne lance PAS la rotation',
        () async {
      // En production `install()` amorce toujours la persistance ; ici on
      // verrouille le garde-fou : un `clear()` dans un test du tampon ne doit
      // ni amorcer la rotation ni écrire un fichier de journal sur le disque.
      _current.writeAsStringSync('trace laissée par une autre session');

      await DiagnosticLog.clearAll();

      expect(_previous.existsSync(), isFalse);
      expect(_current.readAsStringSync(), 'trace laissée par une autre session');
    });

    test('un fichier qui RÉSISTE est rapporté, jamais avalé', () async {
      _current.writeAsStringSync('session précédente');
      await DiagnosticLog.initPersistenceForTest();
      expect(_previous.existsSync(), isTrue);
      // Un dossier à la place du fichier : la suppression échoue pour une
      // raison qui n'est PAS « déjà absent » — ce que rencontrerait un droit
      // refusé, un verrou, un stockage en lecture seule.
      _previous.deleteSync();
      Directory(_previous.path).createSync();

      final bool propre = await DiagnosticLog.clearAll();

      expect(propre, isFalse,
          reason: 'un succès affiché à tort est le pire résultat ici');
      // La fuite RÉSEAU est refermée quand même : plus rien n'est servi.
      expect(DiagnosticLog.previousSessionDump, isNull);
      expect(DiagnosticLog.lineCount, 0);
    });

    test('deux « Vider » rapprochés : idempotent, et tous deux rendent vrai',
        () async {
      _current.writeAsStringSync('session précédente');
      await DiagnosticLog.initPersistenceForTest();

      final List<bool> verdicts = await Future.wait(<Future<bool>>[
        DiagnosticLog.clearAll(),
        DiagnosticLog.clearAll(),
      ]);

      expect(verdicts, <bool>[true, true],
          reason: '« déjà absent » est le résultat voulu, pas un échec');
      expect(_previous.existsSync(), isFalse);
    });

    test('une ligne écrite PENDANT le vidage survit', () async {
      _current.writeAsStringSync('session précédente');
      await DiagnosticLog.initPersistenceForTest();

      final Future<bool> vidage = DiagnosticLog.clearAll();
      DiagnosticLog.add('ligne écrite PENDANT le vidage');
      await vidage;

      // Le vidage efface ce qui EXISTAIT ; il ne doit pas avaler ce qui arrive
      // après lui, sinon le journal serait mort jusqu'au prochain démarrage.
      expect(DiagnosticLog.dump(), contains('ligne écrite PENDANT le vidage'));
      expect(_previous.existsSync(), isFalse);
    });
  });
}
