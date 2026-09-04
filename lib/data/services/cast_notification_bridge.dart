import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/utils/notification_permission.dart';
import '../../core/utils/platform_tv.dart';
import '../../feature/player/cast_policy.dart';
import 'cast_service.dart';

/// §castSend — Pont entre `CastService.state` (le SEUL état de diffusion) et
/// le canal natif `aetherstream/cast_notif`, porté par `AetherCastService.kt`
/// (service de premier plan `mediaPlayback`).
///
/// **Pourquoi un service de premier plan ici aussi** : la session Cast est un
/// socket TLS tenu depuis l'isolate Dart, avec un battement de cœur toutes les
/// 5 s. Le téléviseur continuerait de lire si Android tuait le processus —
/// mais l'utilisateur perdrait toute commande : plus de pause, plus d'arrêt,
/// et une notification qui mentirait. Même raisonnement que §dlNotif : le
/// service garde le processus (donc la session) vivant, la notification n'en
/// est que la face visible.
///
/// ⚠️ **N'introduit PAS de second état** : ce pont ne fait que LIRE
/// `CastService.state` et traduire ce qu'il voit ; les boutons de la
/// notification rappellent `CastService.toggle()` / `stop()`, exactement
/// comme le panneau du lecteur — une seule vérité.
abstract final class CastNotificationBridge {
  static const MethodChannel _channel =
      MethodChannel('aetherstream/cast_notif');

  static bool _wired = false;
  static bool _showing = false;

  /// Dernière notification envoyée : le récepteur pousse un statut à chaque
  /// changement de position, on ne repose la notification que si son TEXTE
  /// change (titre, appareil, lecture/pause).
  static String? _lastKey;

  /// Appelé une fois depuis `main.dart`.
  static void attach() {
    if (_wired) return;
    _wired = true;
    _channel.setMethodCallHandler(_onNativeCall);
    CastService.state.addListener(_onStateChanged);
  }

  static Future<void> _onStateChanged() async {
    final CastState? s = CastService.state.value;
    if (s == null) {
      await _hide();
      return;
    }
    // La permission a déjà été demandée à la première lecture (§nowPlaying) :
    // ici, on la LIT, on ne redemande que si elle n'a jamais été résolue.
    final bool granted = await ensureNotificationPermission();
    final CastNotice? notice = castNotice(
      isTv: PlatformTv.isTv,
      granted: granted,
      deviceName: s.device.displayName,
      mediaTitle: s.title,
      playing: s.playing,
    );
    if (notice == null) {
      await _hide();
      return;
    }
    // L'affiche fait partie de la clé : si elle change (nouvel épisode),
    // la notification se repose pour charger la nouvelle image.
    // §castBattery — Sous 15 % hors charge, la notification dit l'alerte
    // et passe en rouge (même vérité que le panneau du lecteur).
    final String? battery = s.batteryWarning;
    final String text = battery ?? notice.text;
    final String key = '${notice.title}|$text|${notice.playing}|${s.imageUrl}';
    if (_showing && key == _lastKey) return;
    // ⚠️ **Ce listener est asynchrone et l'état change chaque seconde.**
    // Pendant l'attente de la permission, la diffusion a pu se terminer et
    // `_hide()` passer : reprendre ici rallumerait un service de premier
    // plan pour une diffusion finie, que plus aucun événement ne viendrait
    // refermer. On revérifie donc que l'état lu est TOUJOURS le courant.
    if (!identical(CastService.state.value, s)) return;
    _lastKey = key;
    _showing = true;
    try {
      await _channel.invokeMethod('show', {
        'title': notice.title,
        'text': text,
        'playing': notice.playing,
        'image': s.imageUrl,
        'lowBattery': battery != null,
      });
    } catch (e) {
      debugPrint('⚠️ CastNotificationBridge.show : $e');
    }
  }

  static Future<void> _hide() async {
    if (!_showing) return;
    _showing = false;
    _lastKey = null;
    try {
      await _channel.invokeMethod('hide');
    } catch (e) {
      debugPrint('⚠️ CastNotificationBridge.hide : $e');
    }
  }

  static Future<void> _onNativeCall(MethodCall call) async {
    if (call.method != 'onCastAction') return;
    final args = (call.arguments as Map?) ?? const {};
    switch (args['action']) {
      case 'toggle':
        await CastService.toggle();
      case 'stop':
        await CastService.stop();
    }
  }

  /// Tests uniquement.
  @visibleForTesting
  static void resetForTest() {
    _wired = false;
    _showing = false;
    _lastKey = null;
  }
}
