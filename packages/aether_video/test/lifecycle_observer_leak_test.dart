import 'package:better_native_video_player/better_native_video_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// §engineVendor patch 17 (AetherStream, revue 2026-09-11, D2B-05) — le
/// contrôleur retire, à sa destruction, l'observateur de cycle de vie qu'il a
/// inscrit à sa construction. Amont, il ne le retirait jamais : chaque lecteur
/// ouvert laissait un contrôleur mort retenu par `WidgetsBinding`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methodChannel = MethodChannel('native_video_player');

  setUp(() {
    messenger.setMockMethodCallHandler(methodChannel, (call) async => null);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('dispose() retire l’observateur inscrit par le constructeur', () async {
    // L'observateur n'est inscrit que sur Android.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockStreamHandler(
      const EventChannel('native_video_player_controller_92'),
      MockStreamHandler.inline(onListen: (arguments, events) {}),
    );
    final controller = NativeVideoPlayerController(id: 92);

    final WidgetsBindingObserver? observer = controller.debugLifecycleObserver;
    expect(observer, isNotNull);
    // Preuve qu'il est bien inscrit : on le retire… puis on le remet.
    expect(WidgetsBinding.instance.removeObserver(observer!), isTrue);
    WidgetsBinding.instance.addObserver(observer);

    await controller.dispose();

    expect(controller.debugLifecycleObserver, isNull);
    // Déjà retiré par `dispose()` : plus rien à retirer.
    expect(WidgetsBinding.instance.removeObserver(observer), isFalse);
  });

  test('hors Android : aucun observateur, dispose() sans effet de bord',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    messenger.setMockStreamHandler(
      const EventChannel('native_video_player_controller_93'),
      MockStreamHandler.inline(onListen: (arguments, events) {}),
    );
    final controller = NativeVideoPlayerController(id: 93);
    expect(controller.debugLifecycleObserver, isNull);
    await controller.dispose();
    expect(controller.debugLifecycleObserver, isNull);
  });
}
