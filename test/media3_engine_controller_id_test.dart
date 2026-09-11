import 'package:aetherStream/feature/player/media3_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// §exitCost / revue 2026-09-11, D2B-01 — chaque moteur a SON identifiant
/// natif.
///
/// Le défaut : tous les lecteurs étaient construits avec `id: 7000`, alors que
/// le natif indexe tout par cet identifiant et que la libération est différée
/// de 450 ms (patch 14). Zapping rapide A → Retour → B : le report de A
/// arrêtait puis libérait le lecteur de B (ou le démontage du canal de A
/// emportait celui de B). La défense native (patch 15) est vérifiée sur
/// appareil ; ce test tient la moitié Dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const pluginChannel = MethodChannel('native_video_player');

  setUp(() {
    messenger.setMockMethodCallHandler(pluginChannel, (call) async => null);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(pluginChannel, null);
  });

  Media3Engine build() {
    final engine = Media3Engine();
    // Le canal d'événements du contrôleur s'ouvre APRÈS un aller-retour de
    // canal : le simuler ici, juste après la construction, arrive à temps.
    messenger.setMockStreamHandler(
      EventChannel('native_video_player_controller_${engine.controllerId}'),
      MockStreamHandler.inline(onListen: (arguments, events) {}),
    );
    return engine;
  }

  test('deux moteurs successifs : identifiants natifs distincts', () async {
    final a = build();
    final b = build();
    expect(a.controllerId, isNot(b.controllerId));

    // A se ferme, C s'ouvre aussitôt (le zapping) : C ne reprend PAS
    // l'identifiant de A, dont la libération native est encore en attente.
    a.dispose();
    final c = build();
    expect(c.controllerId, isNot(a.controllerId));
    expect(c.controllerId, isNot(b.controllerId));

    b.dispose();
    c.dispose();
    await Future<void>.delayed(Duration.zero);
  });
}
