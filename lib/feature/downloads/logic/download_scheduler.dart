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

/// §dlQueueFix — Combien de temps une tâche remise en file attend AVANT de
/// repartir, selon le nombre de remises déjà accordées (1 = la première).
///
/// **Le défaut payé** : `_failOrRequeue` repassait la tâche en `queued`, et le
/// `pump()` du `whenComplete` la faisait repartir dans la milliseconde. Un
/// hôte qui répond en erreur brûlait donc les trois crédits de
/// `kMaxNetworkRequeues` en moins d'une seconde, et l'utilisateur voyait un
/// échec immédiat là où une coupure de 15 s aurait été encaissée.
///
/// ⚠️ Le délai croît : une coupure brève repart vite, une panne durable ne
/// martèle pas la source.
const List<Duration> kRequeueBackoff = <Duration>[
  Duration(seconds: 5),
  Duration(seconds: 15),
  Duration(seconds: 45),
];

/// Le délai à respecter après la [requeues]-ième remise en file (1-based).
/// Au-delà du dernier palier, c'est le dernier palier qui s'applique.
Duration requeueBackoffFor(int requeues) {
  if (requeues <= 0) return Duration.zero;
  final int i = requeues - 1;
  return i < kRequeueBackoff.length
      ? kRequeueBackoff[i]
      : kRequeueBackoff.last;
}

/// §dlQueueFix — Le réglage « transferts en même temps » a-t-il un sens ?
///
/// Non avec un seul abonnement : la file n'autorise **qu'un** transfert par
/// hôte (§dlQueue, §hostGate), donc le curseur ne changerait rien — un réglage
/// qui ne fait rien ment à qui le tourne. Il n'apparaît qu'à partir de deux
/// abonnements, où il dit combien d'abonnements peuvent travailler ensemble.
bool showParallelDownloadsSetting(int accountCount) => accountCount >= 2;

/// Les tâches en attente qui peuvent PARTIR maintenant, dans l'ordre de leur
/// création.
///
/// [tasks] — toutes les tâches connues ; seules celles en `queued` sont
/// candidates. [inFlightIds] — les transferts réellement en vol (c'est eux,
/// pas le statut persisté, qui occupent les places). [maxParallel] — plafond
/// global ; [perHost] — plafond par hôte (1 : voir l'en-tête).
///
/// [notBefore] — §dlQueueFix : l'instant avant lequel une tâche remise en file
/// ne doit PAS repartir (cf. [requeueBackoffFor]). Une tâche encore au chaud
/// est simplement sautée : elle ne consomme aucune place et ne bloque pas les
/// suivantes. [now] n'est lu que pour ça (les tests le fixent).
List<DownloadTask> pickStartable({
  required Iterable<DownloadTask> tasks,
  required Set<String> inFlightIds,
  required int maxParallel,
  int perHost = 1,
  String Function(DownloadTask) hostOf = downloadHostOf,
  Map<String, DateTime> notBefore = const {},
  DateTime? now,
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

  final DateTime at = now ?? DateTime.now();
  final List<DownloadTask> picks = [];
  for (final DownloadTask t in queued) {
    if (running >= maxParallel) break;
    // §dlQueueFix — Encore au chaud après une remise en file : on la saute
    // sans lui compter de place, le sondage reviendra.
    final DateTime? wait = notBefore[t.id];
    if (wait != null && wait.isAfter(at)) continue;
    final String h = hostOf(t);
    if (h.isNotEmpty && (perHostRunning[h] ?? 0) >= perHost) continue;
    picks.add(t);
    running++;
    if (h.isNotEmpty) perHostRunning[h] = (perHostRunning[h] ?? 0) + 1;
  }
  return picks;
}
