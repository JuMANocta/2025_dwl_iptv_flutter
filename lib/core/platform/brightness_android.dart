import 'package:screen_brightness/screen_brightness.dart';
import 'brightness_service.dart';

class AndroidBrightness implements PlatformBrightness {
  @override
  Future<double> get current async {
    try {
      return await ScreenBrightness().current;
    } catch (_) {
      return 0.5;
    }
  }

  @override
  Future<void> set(double value) async {
    try {
      await ScreenBrightness().setScreenBrightness(value);
    } catch (_) {}
  }

  @override
  Future<void> reset() async {
    try {
      await ScreenBrightness().resetScreenBrightness();
    } catch (_) {}
  }
}
