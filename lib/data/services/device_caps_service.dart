import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/settings/perf_config.dart';
import '../../core/settings/performance_settings_service.dart';
import '../../core/utils/image_cache_config.dart';
import '../models/device_caps.dart';

/// §deviceCaps (2026-09-06) — La sonde des capacités de l'appareil.
///
/// Mesure une fois (canal natif `aetherstream/device` → `caps`), garde le
/// résultat en préférences avec sa date, et l'expose dans [caps]. Le premier
/// démarrage qui possède une mesure choisit le profil de performance
/// (§autoProfile) — une seule fois, jamais par-dessus un choix de l'utilisateur.
///
/// ⚠️ Jamais bloquante pour le démarrage : la sonde tourne APRÈS la première
/// frame. Tant qu'elle n'a pas répondu, [caps] vaut la dernière mesure
/// persistée, ou `null` — et `null` ne refuse rien (`PlayVerdict.unknown`).
abstract final class DeviceCapsService {
  static const MethodChannel _channel = MethodChannel('aetherstream/device');
  static const String _kCaps = 'device_caps_v1';
  static const String _kMeasuredAt = 'device_caps_measured_at_v1';
  static const String _kAutoProfileDone = 'device_caps_auto_profile_v1';

  static final ValueNotifier<DeviceCaps?> caps = ValueNotifier<DeviceCaps?>(null);

  /// Vrai si le profil courant a été choisi par la sonde (et jamais retouché).
  static final ValueNotifier<SuggestedProfile?> autoProfile =
      ValueNotifier<SuggestedProfile?>(null);

  /// Relit la dernière mesure persistée, puis mesure les ressources du
  /// moment ([measureResources]). Appelé par `_initServices`, APRÈS `runApp`
  /// (§bootFast) et avant l'accueil.
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kCaps);
      final at = prefs.getInt(_kMeasuredAt);
      if (raw != null) {
        caps.value = DeviceCaps.fromMap(
          jsonDecode(raw) as Map<String, dynamic>,
          measuredAt:
              at != null ? DateTime.fromMillisecondsSinceEpoch(at) : null,
        );
      }
      final auto = prefs.getString(_kAutoProfileDone);
      if (auto != null) {
        autoProfile.value = SuggestedProfile.values
            .cast<SuggestedProfile?>()
            .firstWhere((p) => p!.name == auto, orElse: () => null);
      }
    } catch (e) {
      debugPrint('⚠️ §deviceCaps init : $e');
    }
    await measureResources();
  }

  /// §imgRightSize (2026-09-25) — Mesure LÉGÈRE, à chaque démarrage : espace
  /// libre du stockage interne (`StatFs` du cache) et classe mémoire, par le
  /// canal `aetherstream/device` → `resources`.
  ///
  /// Distincte de [probe] : la sonde complète (décodeurs, écran) ne tourne
  /// qu'une fois dans la vie de l'app, alors que l'espace libre change d'un
  /// jour à l'autre. Et la classe mémoire arrive ici même si la sonde complète
  /// n'a jamais tourné (profil déjà choisi à la main → pas de sonde).
  ///
  /// Pose les quotas du cache disque des images (`AetherImageCache.configure`,
  /// avant la première image) et le budget du cache d'images décodées
  /// (`PerformanceSettingsService.setDeviceMemory`). Jamais bloquante : une
  /// réponse absente ou lente laisse les valeurs d'un appareil non mesuré.
  static Future<void> measureResources() async {
    int? freeMb;
    int? memoryClassMb = caps.value?.memory?.memoryClassMb;
    bool lowRam = caps.value?.memory?.lowRamDevice ?? false;
    try {
      final Map<Object?, Object?>? m = await _channel
          .invokeMethod<Map<Object?, Object?>>('resources')
          .timeout(const Duration(seconds: 2));
      if (m != null) {
        freeMb = (m['freeMb'] as num?)?.toInt();
        memoryClassMb = (m['memoryClassMb'] as num?)?.toInt() ?? memoryClassMb;
        if (m['lowRamDevice'] is bool) lowRam = m['lowRamDevice'] as bool;
        debugPrint('💾 §imgRightSize : stockage ${freeMb ?? '?'} / ${m['totalMb'] ?? '?'} Mo libres, classe mémoire ${memoryClassMb ?? '?'} Mo, lowRam=$lowRam');
      }
    } catch (e) {
      debugPrint('⚠️ §imgRightSize : ressources non mesurées — $e');
    }
    AetherImageCache.configure(freeMb: freeMb);
    PerformanceSettingsService.setDeviceMemory(
      memoryClassMb: memoryClassMb,
      lowRamDevice: lowRam,
    );
  }

  /// Mesure (ou re-mesure) l'appareil. Rend `null` si le natif ne répond pas.
  static Future<DeviceCaps?> probe() async {
    try {
      // Revue 2026-09-11, D2B-14 — Sonde : la mesure native tourne sur le
      // thread PRINCIPAL Android (gestionnaire de canal). Ce chrono en donne la
      // durée, aller-retour du canal compris — à relever sur appareil AVANT de
      // la déplacer sur un fil d'arrière-plan (§feedback_instrument_first).
      final Stopwatch nativeSw = Stopwatch()..start();
      final Map<Object?, Object?>? m =
          await _channel.invokeMethod<Map<Object?, Object?>>('caps');
      final int nativeMs = nativeSw.elapsedMilliseconds;
      if (m == null) return null;
      final now = DateTime.now();
      final measured = DeviceCaps.fromMap(m, measuredAt: now);
      caps.value = measured;
      // §imgRightSize — sans effet si `measureResources` a déjà posé la même.
      PerformanceSettingsService.setDeviceMemory(
        memoryClassMb: measured.memory?.memoryClassMb,
        lowRamDevice: measured.memory?.lowRamDevice ?? false,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCaps, jsonEncode(measured.toMap()));
      await prefs.setInt(_kMeasuredAt, now.millisecondsSinceEpoch);
      debugPrint('\u{1F50E} §deviceCaps : ${describe(measured)} — sonde native $nativeMs ms');
      return measured;
    } catch (e) {
      debugPrint('⚠️ §deviceCaps probe : $e');
      return null;
    }
  }

  /// Sonde au premier lancement, puis applique le profil recommandé — une
  /// seule fois. ⚠️ Un utilisateur qui a déjà choisi un profil (config
  /// différente du défaut) n'est JAMAIS écrasé.
  static Future<void> probeAndAutoProfileIfFirstRun() async {
    final measured = caps.value ?? await probe();
    if (measured == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_kAutoProfileDone) != null) return;
      final bool userAlreadyChose =
          PerformanceSettingsService.config.value != PerfConfig.defaults;
      final suggested = measured.suggestedProfile;
      if (!userAlreadyChose) {
        // Revue 2026-09-11, D4L-01 : `userAlreadyChose` compare par `==`, qui
        // ignore le confort — une sauvegarde `.aether` restaurée dans
        // l'onboarding (« Wi-Fi seulement », rangées TMDB coupées…) passait
        // donc pour « rien de choisi », et le preset BRUT l'écrasait. On
        // n'applique plus que les leviers de profil (§perfNotify).
        await PerformanceSettingsService.save(PerformanceSettingsService
            .config.value
            .withProfileOf(_configFor(suggested)));
        autoProfile.value = suggested;
        debugPrint('\u{1F3AF} §autoProfile : profil ${suggested.name} choisi par la sonde');
      }
      await prefs.setString(_kAutoProfileDone, suggested.name);
    } catch (e) {
      debugPrint('⚠️ §autoProfile : $e');
    }
  }

  static PerfConfig _configFor(SuggestedProfile p) => switch (p) {
        SuggestedProfile.confort => PerfConfig.defaults,
        SuggestedProfile.equilibre => PerfConfig.equilibre,
        SuggestedProfile.performance => PerfConfig.performance,
      };

  /// Une ligne de journal, sans rien d'identifiant.
  static String describe(DeviceCaps c) {
    final d = c.display;
    final m = c.memory;
    final best = c.best2160;
    return '${c.model} sdk${c.sdk} ${c.cores} coeurs ; '
        'RAM ${m?.totalMb ?? '?'} Mo (lowRam=${m?.lowRamDevice}) ; '
        'ecran ${d?.width ?? '?'}x${d?.height ?? '?'}@${d?.refreshHz.toStringAsFixed(0) ?? '?'} hdr=${d?.hdr} ; '
        '2160p decodable=${best != null} (${best?.name}) affichable=${c.canDisplay2160} ; '
        'profil suggere=${c.suggestedProfile.name}';
  }
}
