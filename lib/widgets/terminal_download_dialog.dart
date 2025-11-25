import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/models/download_task.dart';
import '../data/services/download_manager_service.dart';
import '../core/utils/formatters.dart';
import '../l10n/app_localizations.dart';

class TerminalDownloadDialog extends StatefulWidget {
  final String taskId;
  final bool isResume;

  const TerminalDownloadDialog({
    super.key,
    required this.taskId,
    this.isResume = false,
  });

  @override
  State<TerminalDownloadDialog> createState() => _TerminalDownloadDialogState();
}

class _TerminalDownloadDialogState extends State<TerminalDownloadDialog> {
  final DownloadManagerService _downloadManager = DownloadManagerService();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _logs = [];
  DownloadTask? _lastTaskState;
  Stopwatch? _stopwatch;
  int _lastReceivedBytes = 0;
  double _speed = 0;
  int _eta = 0;
  bool _isDownloadComplete = false;
  bool _hasFatalError = false;
  bool _isAborting = false;

  @override
  void initState() {
    super.initState();
    _downloadManager.tasksNotifier.addListener(_onTaskUpdated);
    // On trouve la tâche initiale pour pré-remplir les logs ET l'état de la progression.
    final initialTask = _downloadManager.tasksNotifier.value.firstWhere(
          (t) => t.id == widget.taskId,
      orElse: () => DownloadTask.empty(),
    );

    if (initialTask.id.isNotEmpty) {
      // C'est la ligne la plus importante : on initialise _lastReceivedBytes
      // avec la quantité de données DÉJÀ téléchargées.
      if (initialTask.totalSize > 0) {
        _lastReceivedBytes = (initialTask.progress * initialTask.totalSize).toInt();
      }
      _updateLogs(initialTask);
    }
  }

  void _onTaskUpdated() {
    if(!mounted) return;
      setState(() {});
  }

  void _updateLogs(DownloadTask task, [AppLocalizations? l10n]) {
    if (_lastTaskState == task) return;

    if (l10n != null && _logs.isEmpty) {
      if (widget.isResume) {
        _logs.add({
          'message': l10n.terminalResumeMessage(task.displayName),
          'type': 'log'
        });
      } else {
        _logs.add({
          'message': l10n.terminalStartMessage(task.displayName),
          'type': 'log'
        });
      }

      if (task.totalSize > 0) {
        _logs.add({
          'message': l10n.terminalFileSizeMessage(formatFileSize(task.totalSize)),
          'type': 'log'
        });
      }
    }

    if (task.status == DownloadStatus.downloading) {
      _stopwatch ??= Stopwatch()..start();
      const barLength = 20;
      final filled = (task.progress * barLength).clamp(0, barLength).toInt();
      final bar = "█" * filled + "▒" * (barLength - filled);

      if (_stopwatch!.elapsedMilliseconds > 500) { // On calcule toutes les 500ms par exemple
        final currentReceived = (task.progress * task.totalSize).toInt();
        final receivedSinceLast = currentReceived - _lastReceivedBytes;
        final elapsedSeconds = _stopwatch!.elapsedMilliseconds / 1000.0;

        if (elapsedSeconds > 0 && receivedSinceLast > 0) {
          _speed = receivedSinceLast / elapsedSeconds; // Met à jour la variable de classe
          final remainingBytes = task.totalSize - currentReceived;
          if (_speed > 0) {
            _eta = (remainingBytes / _speed).round(); // Met à jour la variable de classe
          }
        }

        // On met à jour les valeurs pour le prochain calcul
        _lastReceivedBytes = currentReceived;
        _stopwatch!.reset(); // On réinitialise APRES avoir fait le calcul
      }

      final speedInfo = (_speed > 0) ? "\n 🚀 Speed:${formatFileSize(_speed.toInt())}/s" : "";
      final etaInfo = (_eta > 0) ? "\n⏳ ETA: ${formatDuration(_eta)}" : "";
      final formatted = "[$bar] ${(task.progress * 100).toStringAsFixed(1)}% | $speedInfo$etaInfo";

      if (_logs.isNotEmpty && _logs.last["type"] == "stats") {
        _logs[_logs.length - 1] = {"message": formatted, "type": "stats"};
      } else {
        _logs.add({"message": formatted, "type": "stats"});
      }
    } else if (l10n != null && task.status == DownloadStatus.finalizing && _lastTaskState?.status != DownloadStatus.finalizing) {
      _logs.add({
        'message': l10n.terminalFinalizingMessage, 'type': 'log'});
    } else if (l10n != null && task.status == DownloadStatus.completed && _lastTaskState?.status != DownloadStatus.completed) {
      _logs.add({'message': l10n.terminalSuccessMessage, 'type': 'log'});
      setState(() {
        _isDownloadComplete = true;
      });
    } else if (l10n != null && task.status == DownloadStatus.failed && _lastTaskState?.status != DownloadStatus.failed) {
      _logs.add({'message': l10n.terminalFatalErrorMessage, 'type': 'error'});
      setState(() {
        _hasFatalError = true;
      });
    } else if (l10n != null && task.status == DownloadStatus.canceled && _lastTaskState?.status != DownloadStatus.canceled) {
      _logs.add({'message': l10n.terminalCancelMessage, 'type': 'log'});
    }
    if(mounted) setState(() => _lastTaskState = task);
  }

  @override
  void dispose() {
    _downloadManager.tasksNotifier.removeListener(_onTaskUpdated);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // On essaie de trouver la tâche actuelle.
    final currentTask = _downloadManager.tasksNotifier.value.firstWhere(
          (t) => t.id == widget.taskId,
      // Si elle n'est pas trouvée (supprimée ?), on utilise le dernier état connu.
      orElse: () => _lastTaskState ?? DownloadTask.empty(),
    );

    // On capture le Navigator AVANT toute logique asynchrone.
    final navigator = Navigator.of(context);

    // On ne met à jour les logs que si une tâche valide existe.
    if (currentTask.id.isEmpty) {
      // scheduleMicrotask évite une erreur de build en exécutant le pop() juste après.
      Future.microtask(() {
        if (mounted && navigator.canPop()) {
          navigator.pop();
        }
      });
      // On retourne un widget vide en attendant la fermeture
      return const SizedBox.shrink();
    }

    // Si on a demandé l'annulation et que la tâche est confirmée comme annulée
    if (_isAborting && currentTask.status == DownloadStatus.canceled) {
      Future.microtask(() {
        if (mounted && navigator.canPop()) {
          navigator.pop();
        }
      });
      return const SizedBox.shrink();
    }

    // L'appel clé : on met à jour les logs avec un l10n valide
    _updateLogs(currentTask, l10n);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha((255 * 0.9).round()),
          border: Border.all(color: Colors.green.withAlpha(50)),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [BoxShadow(color: Colors.green.withAlpha(20), blurRadius: 10, spreadRadius: 2)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.terminalTitle,
              style: GoogleFonts.vt323(color: Colors.green, fontSize: 22),
            ),
            const Divider(color: Colors.green),
            Flexible(
              child: SizedBox(
                width: double.maxFinite,
                height: 300,
                child: Stack(
                  children: [
                    ListView.builder(
                      controller: _scrollController,
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[index];
                        final Color color;
                        switch (log['type']) {
                          case 'stats': color = const Color(0xFF33FF33); break;
                          case 'error': color = const Color(0xFFFF5555); break;
                          case 'success': color = Colors.lightGreenAccent; break;
                          default: color = const Color(0xFFADFF2F); break;
                        }
                        return Text(log['message'], style: GoogleFonts.sourceCodePro(color: color, fontSize: 12));
                      },
                    ),
                    const ScanLine(),
                  ],
                ),
              ),
            ),
            if (!_isDownloadComplete && !_hasFatalError && _lastTaskState?.status == DownloadStatus.downloading)
              const Row(children: [Text(">", style: TextStyle(color: Color(0xFF33FF33))), BlinkingCursor()]),
            const Divider(color: Colors.green),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  if (_isDownloadComplete || _hasFatalError || _isAborting) {
                    Navigator.of(context).pop();
                  } else {
                    setState(() {
                      _isAborting = true; // On passe en mode "annulation"
                    });
                    // On demande l'annulation mais on ne ferme PAS le dialogue
                    _downloadManager.cancelTask(widget.taskId);
                  }
                },
                child: Text(
                  _isDownloadComplete || _hasFatalError
                      ? l10n.terminalCloseButton
                      : _isAborting
                      ? l10n.terminalAbortingButton // Texte pendant l'attente de la confirmation
                      : l10n.terminalAbortButton,
                  style: GoogleFonts.vt323(color: Colors.white, fontSize: 18),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}

class ScanLine extends StatefulWidget {
  const ScanLine({super.key});
  @override
  State<ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<ScanLine> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Align(
          alignment: Alignment(0, _controller.value * 2 - 1),
          child: Container(height: 2, color: Colors.greenAccent.withAlpha(75)),
        ),
      ),
    );
  }
}

class BlinkingCursor extends StatefulWidget {
  const BlinkingCursor({super.key});
  @override
  State<BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<BlinkingCursor> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..repeat(reverse: true);
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => FadeTransition(opacity: _controller, child: const Text("_", style: TextStyle(color: Color(0xFF33FF33), fontWeight: FontWeight.bold)));
}
