import 'package:flutter/material.dart';
import 'widgets/download_task_tile.dart';
import 'package:aetherStream/data/models/download_task.dart';
import 'package:aetherStream/data/services/download_manager_service.dart';
import 'package:aetherStream/l10n/app_localizations.dart';


class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  final DownloadManagerService _downloadManager = DownloadManagerService();

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
          if (tasks.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.download_done, size: 80, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    l10n.noDownloads,
                    style: const TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              return DownloadTaskTile(task: task);
            },
          );
        },
      ),
    );
  }
}
