import 'package:flutter/foundation.dart';

/// §notifAudit P5 (second volet) — « Appuyer pour ouvrir » une notification de
/// téléchargement doit montrer le téléchargement, pas l'accueil.
///
/// **Le défaut.** `AetherDownloadService` posait bien l'extra
/// `aether_open_route` sur l'`Intent` de la notification, mais personne ne le
/// lisait : l'app s'ouvrait là où elle en était, l'accueil au démarrage.
///
/// **Le chemin.** `MainActivity` relaie la route (à la demande de Dart au
/// démarrage à froid, `takeOpenRoute` ; aussitôt si l'app vit, `openRoute`) →
/// `TransferNotificationBridge` → [DownloadsOpenRequest.request] → l'écran
/// principal bascule sur l'onglet Téléchargements ([takeTabRequest]) et la
/// page met la tâche en vue ([takeFocusTask]).
///
/// ⛔ **On ne coupe jamais un film** pour une notification : lecteur ouvert,
/// la demande est ignorée ([shouldOpenDownloads]) — l'app revient simplement
/// au premier plan, comme avant.
abstract final class DownloadsOpenRequest {
  /// Incrémenté à chaque demande : l'écran principal l'écoute.
  static final ValueNotifier<int> requests = ValueNotifier<int>(0);

  /// Dernière demande déjà appliquée par l'écran principal.
  static int _handled = 0;

  /// La tâche à mettre en vue, consommée UNE fois par la page.
  static final ValueNotifier<String?> focusTask = ValueNotifier<String?>(null);

  /// Une notification demande l'onglet Téléchargements (et, si elle en
  /// désigne une, la tâche [taskId]).
  static void request({String? taskId}) {
    if (taskId != null && taskId.isNotEmpty) focusTask.value = taskId;
    requests.value++;
  }

  /// `true` UNE fois par demande en attente — plusieurs demandes arrivées avant
  /// que l'écran principal existe (démarrage à froid) n'en font qu'une.
  static bool takeTabRequest() {
    if (_handled == requests.value) return false;
    _handled = requests.value;
    return true;
  }

  /// La tâche demandée, une seule fois.
  static String? takeFocusTask() {
    final String? id = focusTask.value;
    if (id != null) focusTask.value = null;
    return id;
  }

  @visibleForTesting
  static void resetForTest() {
    requests.value = 0;
    _handled = 0;
    focusTask.value = null;
  }
}

/// Route demandée par une notification, telle que `MainActivity` la relaie
/// (`{route: 'downloads', taskId: …}`). `null` = rien à faire : pas de
/// route, route inconnue (version du natif plus récente), forme inattendue.
///
/// Fonction pure : c'est elle qu'on teste.
({String? taskId})? downloadsRouteFrom(Object? args) {
  if (args is! Map) return null;
  if (args['route'] != 'downloads') return null;
  final Object? id = args['taskId'];
  return (taskId: id is String && id.isNotEmpty ? id : null);
}

/// ⛔ Une notification ne coupe jamais un film : lecteur ouvert, on ne
/// navigue pas.
bool shouldOpenDownloads({required bool playerOpen}) => !playerOpen;

/// L'index, dans la liste de la page, de la tâche [taskId] parmi [visibleIds]
/// (la liste filtrée), en comptant la section « Sur l'appareil » posée en
/// tête quand elle existe. `-1` si la tâche n'y est pas.
int downloadsListIndexOf(
  List<String> visibleIds,
  String taskId, {
  required bool hasDeviceSection,
}) {
  final int i = visibleIds.indexOf(taskId);
  if (i < 0) return -1;
  return i + (hasDeviceSection ? 1 : 0);
}
