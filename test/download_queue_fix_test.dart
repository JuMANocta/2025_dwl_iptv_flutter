import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aetherStream/core/settings/perf_config.dart';
import 'package:aetherStream/core/settings/performance_settings_service.dart';
import 'package:aetherStream/data/models/download_task.dart';
import 'package:aetherStream/data/services/download_manager_service.dart';
import 'package:aetherStream/feature/downloads/logic/download_scheduler.dart';

/// §dlQueueFix — Ce que la FILE fait d'une erreur, d'un jeton oublié et d'une
/// relance. Ces règles-là ne sont pas pures : elles vivent dans
/// l'enchaînement `onError` → `Completer` → `catch` → `_failOrRequeue`. Le
/// seul moyen honnête de les tenir est donc de rejouer un vrai transfert avec
/// un faux Dio — aucun réseau, aucun fichier utile.
class _FailingAdapter implements HttpClientAdapter {
  _FailingAdapter(this.error);

  /// L'erreur émise par le FLUX (en-têtes déjà reçus) : c'est le cas du
  /// défaut — une coupure en plein transfert, pas un refus initial.
  final Object error;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls++;
    return ResponseBody(
      Stream<Uint8List>.error(error),
      200,
      headers: {
        Headers.contentLengthHeader: ['1000'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const device = MethodChannel('aetherstream/device');
  const transfer = MethodChannel('aetherstream/transfer_notif');

  final m = DownloadManagerService();

  DownloadTask sample({
    String id = 't1',
    DownloadStatus status = DownloadStatus.queued,
  }) =>
      DownloadTask(
        id: id,
        url: 'http://panel.test/movie/u/p/$id.mkv',
        displayName: 'Film $id',
        // Dossier inexistant : le transfert ne doit de toute façon jamais
        // écrire un octet, l'erreur arrive au premier chunk.
        finalPath: '/movies/$id.mkv',
        tempPath: '${Directory.systemTemp.path}/aether_test_$id.part',
        totalSize: 1000,
        status: status,
        createdAt: DateTime(2026, 9, 16),
      );

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(device, (call) async {
        if (call.method == 'network') {
          // Wi-Fi non facturé : rien ne doit retenir la file.
          return {'transport': 'wifi', 'metered': false};
        }
        return null;
      })
      ..setMockMethodCallHandler(transfer, (call) async => null);
    SharedPreferences.setMockInitialValues({
      'aether_perf_v1': jsonEncode({'dwo': false}),
    });
    m.resetQueueForTest();
    m.tasksNotifier.value = [];
    PerformanceSettingsService.config.value = PerfConfig.defaults;
  });

  tearDown(() {
    DownloadManagerService.dioFactoryForTest = null;
    m.resetQueueForTest();
    m.tasksNotifier.value = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(device, null)
      ..setMockMethodCallHandler(transfer, null);
  });

  Future<void> settle([int turns = 40]) async {
    for (int i = 0; i < turns; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Dio dioThatFailsMidStream(Object error) {
    final d = Dio();
    d.httpClientAdapter = _FailingAdapter(error);
    return d;
  }

  test('🔴 §dlQueueFix — une coupure réseau ne consomme QU\'UN crédit',
      () async {
    // Le défaut : `onError` appelait `_failOrRequeue` PUIS complétait en
    // erreur ; l'exception ressortait du `Completer` et le `catch` extérieur
    // rappelait `_failOrRequeue`. Une seule coupure brûlait donc DEUX des
    // trois remises en file, et le second appel pouvait écraser par `failed`
    // le `queued` que le premier venait d'écrire.
    await m.init();
    final t = sample();
    await m.addTask(t);
    final DioException coupure = DioException(
      requestOptions: RequestOptions(path: t.url),
      type: DioExceptionType.connectionError,
      message: 'Connection reset by peer',
    );
    DownloadManagerService.dioFactoryForTest =
        (_) async => dioThatFailsMidStream(coupure);

    await m.startDownloadTask(t);
    await settle();

    expect(m.networkRequeuesForTest(t.id), 1,
        reason: 'une erreur = un crédit ; deux gestionnaires en consommaient '
            'deux et la tâche mourait au bout de deux coupures.');
    expect(m.tasksNotifier.value.single.status, DownloadStatus.queued,
        reason: 'une coupure réseau remet en file, elle ne condamne pas un '
            'transfert déjà à 90 % (§dlNetRetry).');
  });

  test('🔴 §dlQueueFix — la remise en file impose un DÉLAI avant de repartir',
      () async {
    await m.init();
    final t = sample(id: 't2');
    await m.addTask(t);
    DownloadManagerService.dioFactoryForTest = (_) async =>
        dioThatFailsMidStream(DioException(
          requestOptions: RequestOptions(path: t.url),
          type: DioExceptionType.connectionError,
        ));

    final DateTime avant = DateTime.now();
    await m.startDownloadTask(t);
    await settle();

    final DateTime? notBefore = m.notBeforeForTest(t.id);
    expect(notBefore, isNotNull,
        reason: 'sans délai, le pump du whenComplete relançait la tâche dans '
            'la milliseconde : les trois crédits partaient en moins d\'une '
            'seconde sur un hôte qui répond en erreur.');
    expect(notBefore!.difference(avant).inSeconds,
        greaterThanOrEqualTo(kRequeueBackoff.first.inSeconds - 1));
    // Et la file la SAUTE tant que le délai court.
    expect(
      pickStartable(
        tasks: m.tasksNotifier.value,
        inFlightIds: const {},
        maxParallel: 2,
        notBefore: {t.id: notBefore},
        now: avant,
      ),
      isEmpty,
    );
  });

  test('🔴 §dlQueueFix — un jeton orphelin ne condamne plus la tâche',
      () async {
    // Un jeton d'annulation resté derrière un chemin d'erreur rendait la
    // tâche INDÉMARRABLE pour le reste de la session : `startDownloadTask`
    // rendait la main en silence, et `pump()` n'y pouvait rien.
    await m.init();
    final t = sample(id: 't3');
    await m.addTask(t);
    m.plantCancelTokenForTest(t.id);
    expect(m.hasCancelTokenForTest(t.id), isTrue);
    DownloadManagerService.dioFactoryForTest = (_) async =>
        dioThatFailsMidStream(DioException(
          requestOptions: RequestOptions(path: t.url),
          type: DioExceptionType.badResponse,
          response: Response(
              requestOptions: RequestOptions(path: t.url), statusCode: 404),
        ));

    await m.startDownloadTask(t);
    await settle();

    // Le transfert est BIEN parti (il a échoué sur un 404, ce qui prouve
    // qu'il a atteint le réseau au lieu de sortir en silence).
    expect(m.tasksNotifier.value.single.status, DownloadStatus.failed,
        reason: 'le jeton orphelin faisait sortir startDownloadTask sans '
            'rien tenter : la tâche restait queued à vie.');
  });

  test(
      '🔴 §notifAudit P2 — une relance ne publie jamais « annulé » : le '
      'service de premier plan ne doit pas s\'arrêter', () async {
    await m.init();
    final t = sample(id: 't4', status: DownloadStatus.downloading);
    await m.addTask(t);
    final List<DownloadStatus> vus = [];
    void record() {
      for (final x in m.tasksNotifier.value) {
        if (x.id == t.id) vus.add(x.status);
      }
    }

    m.tasksNotifier.addListener(record);
    await m.cancelTask(t.id, restarting: true);
    m.tasksNotifier.removeListener(record);

    expect(vus, isNot(contains(DownloadStatus.canceled)),
        reason: 'publier `canceled` le temps d\'une relance vide la liste des '
            'tâches ACTIVES : downloadNotice rend null, le pont arrête le '
            'service — et Android refuse ensuite de le redémarrer depuis '
            'l\'arrière-plan. Le reste du transfert se faisait sans rien '
            'pour le garder en vie.');
    expect(m.tasksNotifier.value.single.status, DownloadStatus.queued);
  });

  test('une annulation VRAIE, elle, publie bien « annulé »', () async {
    await m.init();
    final t = sample(id: 't5', status: DownloadStatus.downloading);
    await m.addTask(t);
    await m.cancelTask(t.id);
    expect(m.tasksNotifier.value.single.status, DownloadStatus.canceled);
  });
}
