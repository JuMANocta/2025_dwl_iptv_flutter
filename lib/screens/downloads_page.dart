import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_file_plus/open_file_plus.dart';
import '../main.dart';
import '../models/download_task.dart';
import '../services/download_manager_service.dart';
import '../telechargement_fichier.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  final DownloadManagerService _downloadManager = DownloadManagerService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestion des Téléchargements'),
      ),
      body: ValueListenableBuilder<List<DownloadTask>>(
        valueListenable: _downloadManager.tasksNotifier,
        builder: (context, tasks, child) {
          if (tasks.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.download_done, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Aucun téléchargement',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              return _DownloadTaskTile(task: task);
            },
          );
        },
      ),
    );
  }
}

/// Widget pour une seule tâche de téléchargement
class _DownloadTaskTile extends StatelessWidget {
  final DownloadTask task;

  const _DownloadTaskTile({required this.task});

  // --- ACTIONS ---

  Future<void> _handleTap(BuildContext context) async {
    switch (task.status) {
      case DownloadStatus.completed:
        _openFile(context);
        break;
      case DownloadStatus.failed:
      case DownloadStatus.canceled:
      // Au lieu d'un menu, on relance directement au clic
        _retryDownload(context);
        break;
      default:
      // Pour les autres statuts (downloading, queued), un clic ne fait rien.
        break;
    }
  }

  Future<void> _deleteTask(BuildContext context) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirmation de suppression"),
        content: Text("Voulez-vous vraiment supprimer le fichier \"${task.displayName}\" ? Cette action est irréversible."),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Annuler")),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text("Supprimer", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      await DownloadManagerService().removeTask(task.id);
      try {
        final file = File(task.finalPath);
        final tempFile = File('${task.finalPath}.downloading');
        if (await file.exists()) await file.delete();
        if (await tempFile.exists()) await tempFile.delete();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur lors de la suppression du fichier : $e")));
        }
      }
    }
  }

  Future<void> _openFile(BuildContext context) async {
    final result = await OpenFile.open(task.finalPath);
    if (result.type != ResultType.done && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Impossible d'ouvrir le fichier : ${result.message}")));
    }
  }

  Future<void> _retryDownload(BuildContext context) async {
    Navigator.of(context).pop();

    await Future.delayed(const Duration(milliseconds: 100));

    final BuildContext? safeContext = navigatorKey.currentContext;
    if (safeContext == null || !safeContext.mounted) {
      debugPrint("Le contexte de navigation n'est plus valide, impossible de continuer.");
      return;
    }

    await verifierEtTelecharger(
      url: task.url,
      nom: task.displayName,
      context: safeContext,
    );
  }

  // --- WIDGETS D'UI ---
  Widget _getLeadingIcon() {
    switch (task.status) {
      case DownloadStatus.downloading:
        return SizedBox(width: 24, height: 24, child: CircularProgressIndicator(value: task.progress > 0 ? task.progress : null, strokeWidth: 3));
      case DownloadStatus.completed:
        return const Icon(Icons.check_circle, color: Colors.green);
      case DownloadStatus.failed:
        return const Icon(Icons.error, color: Colors.red);
      case DownloadStatus.canceled:
        return const Icon(Icons.cancel, color: Colors.amber);
      case DownloadStatus.paused:
        return const Icon(Icons.pause_circle, color: Colors.blueGrey);
      case DownloadStatus.queued:
        return const Icon(Icons.hourglass_top, color: Colors.grey);
    }
  }

  Widget _buildSubtitle() {
    final formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(task.createdAt);
    switch (task.status) {
      case DownloadStatus.downloading:
        String remainingText = '';
        if (task.totalSize > 0 && task.progress > 0) {
          final remainingBytes = task.totalSize * (1 - task.progress);
          remainingText = ' • Reste ${formatFileSize(remainingBytes.toInt())}';
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Téléchargement en cours...$remainingText", style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: task.progress, backgroundColor: Colors.grey.shade300, color: Colors.blue),
        ]);
      case DownloadStatus.completed:
        final size = formatFileSize(task.totalSize);
        return Text("Terminé • $size • $formattedDate", style: const TextStyle(fontSize: 12, color: Colors.grey));
      case DownloadStatus.failed:
        String progressInfo = '';
        if (task.totalSize > 0 && task.progress > 0) {
          final percentage = (task.progress * 100).toStringAsFixed(1);
          final downloadedSize = formatFileSize((task.totalSize * task.progress).toInt());
          final totalSize = formatFileSize(task.totalSize);
          progressInfo = '($percentage% - $downloadedSize / $totalSize)';
        }
        return Text("Échec $progressInfo • Appuyer pour relancer", style: const TextStyle(fontSize: 12, color: Colors.red));
      case DownloadStatus.canceled:
        String progressInfo = '';
        if (task.totalSize > 0 && task.progress > 0) {
          final percentage = (task.progress * 100).toStringAsFixed(1);
          final downloadedSize = formatFileSize((task.totalSize * task.progress).toInt());
          final totalSize = formatFileSize(task.totalSize);
          progressInfo = '($percentage% - $downloadedSize / $totalSize)';
        }
        return Text("Annulé $progressInfo • Appuyer pour relancer", style: const TextStyle(fontSize: 12, color: Colors.amber));
      default:
        return Text("En attente • $formattedDate", style: const TextStyle(fontSize: 12, color: Colors.grey));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _getLeadingIcon(),
      title: Text(task.displayName, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: _buildSubtitle(),
      trailing: IconButton(
        icon: const Icon(Icons.delete_forever_outlined),
        color: Colors.grey.shade600,
        tooltip: "Supprimer définitivement",
        onPressed: () => _deleteTask(context),
      ),
      onTap: () => _handleTap(context),
      isThreeLine: task.status == DownloadStatus.downloading,
    );
  }
}
