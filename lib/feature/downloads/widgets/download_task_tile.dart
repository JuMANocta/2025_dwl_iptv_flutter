import 'dart:async';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:aetherStream/core/utils/formatters.dart';
import 'package:aetherStream/main.dart';
import 'package:aetherStream/data/models/download_task.dart';
import 'package:aetherStream/data/services/download_manager_service.dart';
import 'package:aetherStream/data/services/watch_progress_service.dart';
import 'package:aetherStream/widgets/info_row.dart';
import 'package:aetherStream/widgets/terminal_download_dialog.dart';
import 'package:aetherStream/widgets/tv/focusable_card.dart';
import 'package:aetherStream/feature/player/player_page.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:aetherStream/core/platform/storage_service.dart';

class DownloadTaskTile extends StatelessWidget {
  final DownloadTask task;

  const DownloadTaskTile({super.key, required this.task});

  Future<void> _handleTap(BuildContext context) async {
    final downloadManager = DownloadManagerService();
    switch (task.status) {
      case DownloadStatus.downloading:
      // ACTION : Annuler (logique correcte)
        await downloadManager.cancelTask(task.id);
        break;

      case DownloadStatus.completed:
      // ACTION : Lire (logique correcte)
        _openFile(context);
        break;

      case DownloadStatus.failed:
      case DownloadStatus.canceled:
        debugPrint("🔄 Reprise du téléchargement pour la tâche : ${task.displayName}");

        // On ne supprime PAS la tâche.
        // On demande simplement au manager de relancer CETTE tâche existante.
        // Lancement intentionnel en arrière-plan — les erreurs sont gérées dans startDownloadTask.
        unawaited(downloadManager.startDownloadTask(task));

        // On affiche le moniteur pour que l'utilisateur voie la reprise.
        final rootContext = navigatorKey.currentContext;
        if (rootContext != null && rootContext.mounted) {
          showDialog(
              context: rootContext,
              builder: (_) => TerminalDownloadDialog(
                taskId: task.id,
                isResume: true,
              ) // On utilise l'ID de la tâche existante + l'état
          );
        }
        break;

      default:
      // Pour les autres statuts (queued, paused), on ne fait rien pour l'instant
        break;
    }
  }

  Future<void> _deleteTask(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final downloadManager = DownloadManagerService();
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        // 1. Un titre avec une icône d'avertissement claire
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            const SizedBox(width: 12),
            Text(l10n.deleteDialogTitle),
          ],
        ),

        // 2. Un contenu structuré qui donne confiance
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // On met en évidence le nom du fichier concerné
            Text(
              task.displayName,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            // On ajoute la taille pour être sûr de ce qu'on supprime
            InfoRow(
                icon: Icons.straighten,
                label: l10n.deleteDialogSizeLabel,
                value: formatFileSize(task.totalSize)
            ),
            const Divider(height: 24),
            // Un message d'avertissement plus explicite
            Text(l10n.deleteDialogWarning),
          ],
        ),

        // 3. Des boutons d'action sans ambiguïté
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton.icon(
            // On donne au bouton un style "destructif"
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white, // Pour que le texte et l'icône soient blancs
            ),
            icon: const Icon(Icons.delete_forever),
            label: Text(l10n.deleteDialogConfirmButton),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await downloadManager.removeTask(task.id);

      // Suppression du fichier final via le service multi-plateforme
      await StorageService.deleteVideo(task.finalPath);

      // Suppression du fichier temporaire s'il existe encore
      try {
        final tempFile = File(task.tempPath);
        if (await tempFile.exists()) await tempFile.delete();
      } catch (e) {
        debugPrint("⚠️ Suppression fichier temporaire échouée : $e");
      }
    }
  }

  Future<void> _openFile(BuildContext context) async {
    // §forgetResume — On joue le fichier LOCAL mais on garde l'URL réseau
    // comme clé de progression. Effet : la lecture du fichier téléchargé
    // continue à alimenter la pile "Reprendre" de la home (qui regarde par
    // `entry.url`), et la reprise depuis la home reste cohérente même si le
    // film a été regardé partiellement en local.
    final progress = WatchProgressService.getProgress(task.url);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerPage(
          path: task.finalPath,
          title: task.displayName,
          sourceType: VideoSourceType.file,
          progressKey: task.url,
          startPosition: progress?.position,
        ),
      ),
    );
  }

  // --- WIDGETS D'UI ---
  Widget _getLeadingIcon(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (task.status) {
      case DownloadStatus.downloading:
        return SizedBox(
          width: 24,
          height: 24,
          child: Stack(
            // On s'assure que les deux indicateurs sont parfaitement centrés l'un sur l'autre
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: null, // Mode indéterminé (rotation continue)
                strokeWidth: 2, // Un peu plus fin pour être discret
                color: cs.surfaceContainerHighest,
              ),
              CircularProgressIndicator(
                value: task.progress, // Mode déterministe (remplissage)
                strokeWidth: 3, // Un peu plus épais pour être au premier plan
                color: Colors.greenAccent,
                backgroundColor: Colors.transparent, // Fond transparent pour voir celui du dessous
              ),
            ],
          ),
        );
      case DownloadStatus.completed:
        return const Icon(Icons.check_circle, color: Colors.green);
      case DownloadStatus.failed:
        return const Icon(Icons.error, color: Colors.red);
      case DownloadStatus.canceled:
        return const Icon(Icons.cancel, color: Colors.amber);
      case DownloadStatus.paused:
        return const Icon(Icons.pause_circle, color: Colors.blueGrey);
      case DownloadStatus.queued:
        return Icon(Icons.hourglass_top, color: cs.onSurfaceVariant);
      case DownloadStatus.finalizing:
        return const Icon(Icons.check_circle, color: Colors.green);
    }
  }

  Widget _buildSubtitle(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(task.createdAt);
    switch (task.status) {
      case DownloadStatus.downloading:
        String remainingText = '';
        if (task.totalSize > 0 && task.progress > 0) {
          final remainingBytes = task.totalSize * (1 - task.progress);
          remainingText = l10n.taskStatusRemaining(formatFileSize(remainingBytes.toInt()));
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              "${l10n.taskStatusDownloading}$remainingText",
              style: const TextStyle(fontSize: 12)
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: task.progress, backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest, color: Colors.greenAccent),
        ]);
      case DownloadStatus.completed:
        return Text(
            l10n.taskStatusCompleted(formatFileSize(task.totalSize), formattedDate),
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)
        );
      case DownloadStatus.failed:
        final String errorText = task.errorMessage ?? l10n.taskStatusUnknownError;
        String progressInfo = '';
        if (task.totalSize > 0 && task.progress > 0) {
          final percentage = (task.progress * 100).toStringAsFixed(1);
          final downloadedSize = formatFileSize((task.totalSize * task.progress).toInt());
          final totalSize = formatFileSize(task.totalSize);
          progressInfo = ' ($percentage% - $downloadedSize / $totalSize)';
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.taskStatusFailed(progressInfo),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.bold, // On met en évidence l'échec
              ),
            ),
            Text(
              errorText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.error.withValues(alpha: 0.9),
              ),
            ),
          ],
        );
      case DownloadStatus.canceled:
        String progressInfo = '';
        if (task.totalSize > 0 && task.progress > 0) {
          final percentage = (task.progress * 100).toStringAsFixed(1);
          final downloadedSize = formatFileSize((task.totalSize * task.progress).toInt());
          final totalSize = formatFileSize(task.totalSize);
          progressInfo = '($percentage% - $downloadedSize / $totalSize)';
        }
        return Text(
            l10n.taskStatusCanceled(progressInfo),
            style: const TextStyle(fontSize: 12, color: Colors.amber)
        );
      case DownloadStatus.finalizing:
        return Text(
          "${l10n.terminalFinalizingMessage.trim()}...",
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant));
      default:
        return Text(
          l10n.taskStatusPending(formattedDate),
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Construire le titre avec l'année si disponible
    String titleText = task.displayName;
    if (task.releaseYear != null && task.releaseYear!.isNotEmpty) {
      titleText = '$titleText (${task.releaseYear})';
    }

    final l10n = AppLocalizations.of(context)!;
    // §3c-3 — Wrap focus TV (decorateOnly = on garde le ListTile et son tap
    // mobile/souris ; sur TV, la touche OK télécommande déclenche aussi le
    // _handleTap).
    return FocusableCard(
      decorateOnly: true,
      onTap: () => _handleTap(context),
      borderRadius: BorderRadius.circular(8),
      child: ListTile(
        leading: _getLeadingIcon(context),
        title: Text(titleText, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: _buildSubtitle(context),
        trailing: IconButton(
          icon: const Icon(Icons.delete_forever_outlined),
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          tooltip: l10n.deleteTooltip,
          onPressed: () => _deleteTask(context),
        ),
        onTap: () => _handleTap(context),
        isThreeLine: task.status == DownloadStatus.downloading,
      ),
    );
  }
}
