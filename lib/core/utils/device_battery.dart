import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// §castBattery — Batterie du téléphone, lue au natif (`BatteryManager`).
///
/// **Pourquoi** : pendant une diffusion Cast, le téléphone porte la session —
/// et, en relais, le film entier. S'il s'éteint, tout s'arrête. Le client doit
/// être prévenu AVANT, en chiffres, pas par une phrase vague.
///
/// Jamais bloquant : `null` si le natif ne répond pas.
typedef DeviceBatteryState = ({int? percent, bool? charging});

abstract final class DeviceBattery {
  static const MethodChannel _channel = MethodChannel('aetherstream/device');

  static Future<DeviceBatteryState> read() async {
    try {
      final Map<Object?, Object?>? m =
          await _channel.invokeMethod<Map<Object?, Object?>>('battery');
      if (m == null) return (percent: null, charging: null);
      final int? p = (m['percent'] as num?)?.toInt();
      return (
        percent: (p != null && p >= 0 && p <= 100) ? p : null,
        charging: m['charging'] as bool?,
      );
    } catch (e) {
      debugPrint('⚠️ DeviceBattery.read : $e');
      return (percent: null, charging: null);
    }
  }
}
