import 'brightness_service.dart';

class WindowsBrightness implements PlatformBrightness {
  @override
  Future<double> get current async => 0.5;

  @override
  Future<void> set(double value) async {
    // No-op sur Windows pour l'instant.
  }

  @override
  Future<void> reset() async {
    // No-op sur Windows pour l'instant.
  }
}
