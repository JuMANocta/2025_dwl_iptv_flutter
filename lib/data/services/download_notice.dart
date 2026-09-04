import '../models/download_task.dart';

/// §dlNotif — Décisions PURES pour la notification de téléchargement. Rien
/// ici ne touche à une plateforme : c'est ce qui les rend testables sous
/// `flutter test`. Le canal natif (`transfer_notif`) ne fait qu'exécuter ce
/// que ces fonctions décident.

const _activeStatuses = {
  DownloadStatus.downloading,
  DownloadStatus.queued,
  DownloadStatus.paused,
  DownloadStatus.finalizing,
};

/// Ce que la notification « en cours » doit afficher, ou `null` s'il n'y a
/// rien à annoncer (aucun transfert actif, TV, ou permission refusée).
typedef DownloadNotice = ({
  String title,
  String text,
  /// `null` = barre indéterminée (file d'attente, finalisation — un
  /// pourcentage y mentirait, ces étapes n'avancent pas linéairement).
  double? progress,
  int activeCount,
  /// Non-null seulement quand UNE tâche est active : « Annuler » sur
  /// l'agrégat de plusieurs transferts n'aurait pas de cible univoque.
  String? cancelTaskId,
});

/// `true` si au moins une tâche est dans un état actif — sert à décider s'il
/// vaut la peine de demander la permission de notification, SANS présumer du
/// résultat de `downloadNotice` (qui a besoin de cette même permission en
/// entrée : évite la dépendance circulaire).
bool hasActiveDownloads(List<DownloadTask> tasks) =>
    tasks.any((t) => _activeStatuses.contains(t.status));

/// ⚠️ **TV exclue** : personne ne met une box en arrière-plan, et la
/// notification n'y a pas de tiroir utile (même règle que §nowPlaying,
/// §pipPhone). ⚠️ **Permission refusée = `null`, jamais une erreur** : le
/// téléchargement continue sans notification, silencieusement.
DownloadNotice? downloadNotice(
  List<DownloadTask> tasks, {
  required bool isTv,
  required bool granted,
}) {
  if (isTv || !granted) return null;

  final active = tasks.where((t) => _activeStatuses.contains(t.status)).toList();
  if (active.isEmpty) return null;

  if (active.length == 1) {
    final t = active.first;
    final ({String text, double? progress}) info = switch (t.status) {
      DownloadStatus.downloading => (
          text: '${(t.progress.clamp(0.0, 1.0) * 100).round()} %',
          progress: t.progress.clamp(0.0, 1.0),
        ),
      DownloadStatus.queued => (text: 'En attente…', progress: null),
      DownloadStatus.finalizing => (text: 'Finalisation…', progress: null),
      DownloadStatus.paused => (
          text: 'En pause',
          progress: t.progress.clamp(0.0, 1.0),
        ),
      _ => (text: '', progress: null),
    };
    return (
      title: t.displayName,
      text: info.text,
      progress: info.progress,
      activeCount: 1,
      cancelTaskId: t.id,
    );
  }

  final double avg = active
          .map((t) => t.progress.clamp(0.0, 1.0))
          .fold<double>(0, (a, b) => a + b) /
      active.length;
  return (
    title: '${active.length} téléchargements',
    text: '${(avg * 100).round()} % en moyenne',
    progress: avg,
    activeCount: active.length,
    cancelTaskId: null,
  );
}

/// Une tâche qui vient de basculer, ENTRE [previous] et [current], vers un
/// statut final — pour la notification ponctuelle de fin de transfert.
typedef DownloadFinishNotice = ({DownloadTask task, bool success});

const _finishedStatuses = {DownloadStatus.completed, DownloadStatus.failed};

/// ⚠️ Une annulation (`canceled`) n'apparaît JAMAIS ici : l'utilisateur vient
/// de le faire lui-même, une notification pour le lui confirmer serait du
/// bruit.
///
/// ⚠️ Ne signale QUE les tâches présentes dans [previous] dans un état actif :
/// une tâche déjà `completed`/`failed` au tour précédent (ou absente de
/// [previous], donc arrivée déjà terminée — reconciliation au boot) n'est PAS
/// re-signalée. Sans cette garde, chaque frappe de progression d'une AUTRE
/// tâche redéclencherait la notification finale de celle déjà annoncée.
List<DownloadFinishNotice> finishedTransitions(
  List<DownloadTask> previous,
  List<DownloadTask> current,
) {
  final byId = {for (final t in previous) t.id: t};
  final out = <DownloadFinishNotice>[];
  for (final t in current) {
    if (!_finishedStatuses.contains(t.status)) continue;
    final prev = byId[t.id];
    if (prev == null) continue;
    if (_finishedStatuses.contains(prev.status)) continue;
    out.add((task: t, success: t.status == DownloadStatus.completed));
  }
  return out;
}
