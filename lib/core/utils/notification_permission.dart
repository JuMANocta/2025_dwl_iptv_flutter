import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// §nowPlaying — Permission `POST_NOTIFICATIONS` (Android 13+), demandée UNE
/// fois par vie de processus, au moment où une notification va réellement
/// servir — jamais au démarrage.
///
/// **Ne bloque jamais** : un refus rend simplement `false`, et l'appelant
/// continue sans notification. Sur Android ≤ 12 `permission_handler` répond
/// « accordée » d'office. Partagée par la notification de lecture et, plus
/// tard, par celle des téléchargements (§dlNotif).
///
/// ⚠️ Mémorisé en statique : redemander à chaque lecture serait du
/// harcèlement, et Android cesse de toute façon d'afficher la boîte après
/// deux refus.
bool? _granted;

Future<bool> ensureNotificationPermission() async {
  final bool? known = _granted;
  if (known != null) return known;
  try {
    final PermissionStatus status = await Permission.notification.status;
    if (status.isGranted) return _granted = true;
    if (status.isPermanentlyDenied) return _granted = false;
    final PermissionStatus asked = await Permission.notification.request();
    _granted = asked.isGranted;
    debugPrint(_granted!
        ? '🔔 Notifications autorisées'
        : '🔕 Notifications refusées — lecture sans notification');
    return _granted!;
  } catch (e) {
    // Un plugin absent (test, plateforme inattendue) ne doit jamais empêcher
    // la lecture : on note et on continue.
    debugPrint('⚠️ Permission de notification indisponible : $e');
    return _granted = false;
  }
}

/// Tests uniquement : oublie la réponse mémorisée.
@visibleForTesting
void resetNotificationPermissionForTest() => _granted = null;
