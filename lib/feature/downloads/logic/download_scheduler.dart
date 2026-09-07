/// §dlQueue (2026-09-06, lot 6) — File d'attente des téléchargements, PAR HÔTE.
///
/// **Pourquoi par hôte et pas un simple sémaphore.** Le roadmap disait « 2 ou 3
/// téléchargements simultanés ». Mais §hostGate a mesuré la vraie contrainte :
/// les panels IPTV comptent les connexions **par abonnement** (« Connexions
/// 1 / 1 »), et le lecteur en réserve une. Deux transferts en parallèle sur le
/// même abonnement se répondent par `403 Too many connections` — que le
/// gardien de téléchargement (§dlWatchdog) ne distingue pas d'une panne. Un
/// transfert à la fois par hôte, donc ; le parallélisme n'a de sens qu'entre
/// abonnements différents, sous un plafond global réglable.
///
/// Cette fonction est PURE : elle décide, le service exécute.
library;

import 'package:aetherStream/data/models/download_task.dart';

/// L'hôte d'une tâche (serveur du fournisseur, port compris) — la clé de la
/// limite. Chaîne vide si l'URL n'est pas lisible (jamais bloquée pour rien).
String downloadHostOf(DownloadTask task) {
  final Uri? u = Uri.tryParse(task.url);
  if (u == null || u.host.isEmpty) return '';
  return u.hasPort ? '${u.host}:${u.port}' : u.host;
}

/// Les tâches en attente qui peuvent PARTIR maintenant, dans l'ordre de leur
/// création.
///
/// [tasks] — toutes les tâches connues ; seules celles en `queued` sont
/// candidates. [inFlightIds] — les transferts réellement en vol (c'est eux,
/// pas le statut persisté, qui occupent les places). [maxParallel] — plafond
/// global ; [perHost] — plafond par hôte (1 : voir l'en-tête).
List<DownloadTask> pickStartable({
  required Iterable<DownloadTask> tasks,
  required Set<String> inFlightIds,
  required int maxParallel,
  int perHost = 1,
  String Function(DownloadTask) hostOf = downloadHostOf,
}) {
  if (maxParallel <= 0 || perHost <= 0) return const [];
  final Map<String, int> perHostRunning = {};
  int running = 0;
  final List<DownloadTask> queued = [];
  for (final DownloadTask t in tasks) {
    if (inFlightIds.contains(t.id)) {
      running++;
      final String h = hostOf(t);
      if (h.isNotEmpty) perHostRunning[h] = (perHostRunning[h] ?? 0) + 1;
      continue;
    }
    if (t.status == DownloadStatus.queued) queued.add(t);
  }
  if (running >= maxParallel || queued.isEmpty) return const [];
  queued.sort((a, b) => a.createdAt.compareTo(b.createdAt));

  final List<DownloadTask> picks = [];
  for (final DownloadTask t in queued) {
    if (running >= maxParallel) break;
    final String h = hostOf(t);
    if (h.isNotEmpty && (perHostRunning[h] ?? 0) >= perHost) continue;
    picks.add(t);
    running++;
    if (h.isNotEmpty) perHostRunning[h] = (perHostRunning[h] ?? 0) + 1;
  }
  return picks;
}
