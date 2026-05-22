import 'package:flutter/material.dart';
import 'widgets/download_task_tile.dart';
import 'package:aetherStream/data/models/download_task.dart';
import 'package:aetherStream/data/services/download_manager_service.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:aetherStream/widgets/empty_state.dart';


class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  final DownloadManagerService _downloadManager = DownloadManagerService();

  /// §12-c — Pull-to-refresh : recharge les tâches depuis disque + réconcilie
  /// les statuts (utile si une tâche s'est figée en `downloading` après crash).
  Future<void> _refresh() => _downloadManager.init();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.downloadManagerTitle),
      ),
      body: ValueListenableBuilder<List<DownloadTask>>(
        valueListenable: _downloadManager.tasksNotifier,
        builder: (context, tasks, child) {
          // §12-a — Empty state unifié.
          if (tasks.isEmpty) {
            // Le RefreshIndicator a besoin d'un Scrollable pour fonctionner,
            // donc on emballe l'empty state dans une ListView qui prend toute
            // la hauteur disponible.
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.7,
                    child: EmptyState(
                      icon: Icons.download_done,
                      title: l10n.noDownloads,
                      subtitle:
                          'Lance un téléchargement depuis la fiche d\'un film ou d\'une série — il apparaîtra ici avec sa progression.',
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final task = tasks[index];
                return DownloadTaskTile(task: task);
              },
            ),
          );
        },
      ),
    );
  }
}
