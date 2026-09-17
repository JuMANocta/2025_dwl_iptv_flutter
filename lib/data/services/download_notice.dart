import '../models/download_task.dart';
import '../../core/utils/formatters.dart';
import '../../l10n/l10n_ext.dart';

/// §dlNotif — Décisions PURES pour la notification de téléchargement. Rien
/// ici ne touche à une plateforme : c'est ce qui les rend testables sous
/// `flutter test`. Le canal natif (`transfer_notif`) ne fait qu'exécuter ce
/// que ces fonctions décident.

// Revue 2026-09-11, D3A-15 — `paused` n'est jamais affecté : retiré des
// statuts actifs, et sa ligne « En pause » (texte en dur, jamais affichable).
const _activeStatuses = {
  DownloadStatus.downloading,
  DownloadStatus.queued,
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
/// §pipPhone).
///
/// ⚠️ §notifAudit P3 — **La permission de notification n'entre PAS ici.**
/// Elle gouvernait le résultat : refusée, cette fonction rendait `null`, le
/// pont appelait `stopOngoing` et le SERVICE de premier plan s'arrêtait. Or
/// c'est lui qui garde le processus — donc le transfert — en vie ; sans lui,
/// Android tue l'app au premier besoin de mémoire. Refuser la notification
/// doit coûter la notification, pas le téléchargement. Android 13+ laisse
/// tourner un service de premier plan dont la notification n'est pas
/// affichée : le contenu calculé ici part au vide, et c'est tout.
DownloadNotice? downloadNotice(
  List<DownloadTask> tasks, {
  required bool isTv,
}) {
  if (isTv) return null;

  final active = tasks.where((t) => _activeStatuses.contains(t.status)).toList();
  if (active.isEmpty) return null;

  if (active.length == 1) {
    final t = active.first;
    final ({String text, double? progress}) info = switch (t.status) {
      DownloadStatus.downloading => (
          text: _downloadedOf(t),
          progress: t.progress.clamp(0.0, 1.0),
        ),
      DownloadStatus.queued => (text: L10n.current.dlQueued, progress: null),
      DownloadStatus.finalizing => (text: L10n.current.dlFinalizing, progress: null),
      _ => (text: '', progress: null),
    };
    return (
      title: t.displayName,
      text: info.text,
      progress: info.progress,
      activeCount: 1,
      // D3A-07 — Pas d'« Annuler » pendant la finalisation : le transfert est
      // fini, l'interrompre ne ferait que laisser un fichier à moitié copié.
      cancelTaskId: t.status == DownloadStatus.finalizing ? null : t.id,
    );
  }

  final double avg = active
          .map((t) => t.progress.clamp(0.0, 1.0))
          .fold<double>(0, (a, b) => a + b) /
      active.length;
  return (
    title: L10n.current.dlActiveCount(active.length),
    // Revue 2026-09-11, D3A-11 — était écrit en dur, en français.
    text: L10n.current.dlNoticeAverage((avg * 100).round()),
    progress: avg,
    activeCount: active.length,
    cancelTaskId: null,
  );
}

/// §notifAudit P7 — « 1,2 Go sur 3,4 Go » plutôt que « 42 % ».
///
/// Le pourcentage seul ne dit ni ce qui reste, ni si le transfert vaut la
/// peine d'être laissé sur des données mobiles ; la taille, oui. La barre de
/// progression, elle, porte déjà le pourcentage.
///
/// ⛔ Pas de débit ni d'ETA instantanés (§clientText) : ils sautent d'une
/// seconde à l'autre et ne disent rien de vrai. Taille inconnue (le serveur
/// n'a pas donné de `content-length`) → on retombe sur le pourcentage, seule
/// chose qu'on sache alors.
String _downloadedOf(DownloadTask t) {
  final double p = t.progress.clamp(0.0, 1.0);
  if (t.totalSize <= 0) return '${(p * 100).round()} %';
  return L10n.current.dlNoticeSizeOf(
    formatFileSize((p * t.totalSize).round()),
    formatFileSize(t.totalSize),
  );
}

/// Une tâche qui vient de basculer, ENTRE [previous] et [current], vers un
/// statut final — pour la notification ponctuelle de fin de transfert.
typedef DownloadFinishNotice = ({DownloadTask task, bool success});

const _finishedStatuses = {DownloadStatus.completed, DownloadStatus.failed};

/// §notifAudit P6 — Ce que la notification de FIN annonce, et si elle propose
/// de relancer.
typedef DownloadFinishCard = ({
  String title,
  String text,
  /// Non-null sur un ÉCHEC seulement : la tâche que le bouton « Relancer »
  /// doit reprendre. Un succès n'a rien à relancer — et §dlErgo interdit de
  /// proposer de refaire plusieurs Go sur un fichier déjà là.
  String? restartTaskId,
});

/// §notifAudit P6 — **Le défaut payé** : un échec n'annonçait que
/// « Téléchargement échoué », sans dire POURQUOI ni offrir de reprendre.
/// L'utilisateur devait rouvrir l'app, retrouver l'onglet et la tuile.
///
/// La raison est déjà écrite sur la tâche par `_failOrRequeue`, passée par
/// `describeError` (§userError) : elle est donc lisible et traduite. Aucun
/// code d'erreur brut n'atteint l'écran.
DownloadFinishCard downloadFinishCard(DownloadFinishNotice f) {
  if (f.success) {
    return (
      title: f.task.displayName,
      text: L10n.current.dlNotifFinished,
      restartTaskId: null,
    );
  }
  final String why = (f.task.errorMessage ?? '').trim();
  return (
    title: f.task.displayName,
    text: why.isEmpty ? L10n.current.dlNotifFailed : why,
    restartTaskId: f.task.id,
  );
}

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
