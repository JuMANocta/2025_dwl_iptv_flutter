import 'dart:io';

import 'package:aetherStream/data/services/cast_service.dart';
import 'package:aetherStream/data/services/watch_progress_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// §castSend / revue 2026-09-11, D2A-06 — changer d'appareil puis échouer à
/// s'y connecter ne laisse plus l'ANCIENNE diffusion publiée.
///
/// Le défaut : `CastService.start` vers la télé 2 fermait la session de la
/// télé 1, puis la connexion échouait ; `state` gardait la télé 1, que plus
/// aucun abonnement ne pouvait remettre à nul — panneau et notification figés,
/// Pause et ±30 s sans effet. Et la progression de la télé 1 depuis la
/// dernière sauvegarde (10 s au plus) était perdue.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CastService.resetForTest();
  });

  tearDown(CastService.resetForTest);

  test('connexion impossible vers un autre appareil : état retiré, '
      'progression de l’ancienne diffusion sauvée', () async {
    // Un port certainement fermé : connexion refusée, sans réseau réel.
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final int deadPort = probe.port;
    await probe.close();

    const String resumeKey = 'http://panel.test/movie/u/p/1.mkv';
    const tv1 = CastDevice(
      id: 'tv1',
      name: 'tv1',
      host: '127.0.0.1',
      port: 8009,
      friendlyName: 'Salon',
    );
    final tv2 = CastDevice(
      id: 'tv2',
      name: 'tv2',
      host: '127.0.0.1',
      port: deadPort,
      friendlyName: 'Chambre',
    );

    // Diffusion en cours sur la télé 1, à 40 min d'un film de 2 h.
    CastService.state.value = const CastState(
      device: tv1,
      url: 'http://192.168.1.2:8080/local/media.mkv',
      title: 'Heat',
      live: false,
      progressKey: resumeKey,
      status: CastSessionStatus(
        playerState: 'PLAYING',
        position: Duration(minutes: 40),
        duration: Duration(minutes: 120),
      ),
    );

    await expectLater(
      CastService.start(
        device: tv2,
        url: 'http://panel.test/movie/u/p/2.mkv',
        contentType: 'video/x-matroska',
        live: false,
        title: 'Ronin',
      ),
      throwsA(isA<CastException>()),
    );

    // Plus rien n'est diffusé : panneau et notification disparaissent.
    expect(CastService.state.value, isNull);
    expect(CastService.isActive, isFalse);

    // La position de la télé 1 a été écrite AVANT la fermeture.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final saved = WatchProgressService.getProgress(resumeKey);
    expect(saved, isNotNull);
    expect(saved!.position, const Duration(minutes: 40));
  });

  test('aucune diffusion préalable : l’échec ne publie rien', () async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final int deadPort = probe.port;
    await probe.close();

    await expectLater(
      CastService.start(
        device: CastDevice(
          id: 'tv3',
          name: 'tv3',
          host: '127.0.0.1',
          port: deadPort,
        ),
        url: 'http://panel.test/movie/u/p/3.mkv',
        contentType: 'video/x-matroska',
        live: false,
        title: 'Collateral',
      ),
      throwsA(isA<CastException>()),
    );
    expect(CastService.state.value, isNull);
  });
}
