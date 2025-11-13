import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'main.dart'; // Import pour le navigatorKey
import 'models/download_task.dart';
import 'services/download_manager_service.dart';
import 'utils/network.dart';

// --- Utils (inchangés) ---
Future<String> _getTempDirectory() async {
  final dir = await getTemporaryDirectory();
  final tmp = Directory("${dir.path}/dl_tmp");
  if (!await tmp.exists()) await tmp.create(recursive: true);
  return tmp.path;
}

String sanitizeFilename(String filename) => filename.replaceAll(RegExp(r'[\\/*?:"<>|]'), "_");
String _ext(String name) {
  final i = name.lastIndexOf('.');
  return (i >= 0 && i < name.length - 1) ? name.substring(i + 1).toLowerCase() : '';
}
String formatFileSize(int bytes) {
  if (bytes <= 0) return "0 B";
  const suffixes = ["B", "KB", "MB", "GB", "TB"];
  final i = (math.log(bytes) / math.log(1024)).floor();
  return "${(bytes / (1 << (10 * i))).toStringAsFixed(2)} ${suffixes[i]}";
}
String formatDuration(int totalSeconds) {
  if (totalSeconds < 0) return "--:--";
  final duration = Duration(seconds: totalSeconds);
  final hours = duration.inHours.toString().padLeft(2, '0');
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return (duration.inHours > 0) ? "$hours:$minutes:$seconds" : "$minutes:$seconds";
}

Future<void> verifierEtTelecharger({required String url, required String nom, required BuildContext context}) async {
  if (!context.mounted) return;
  final downloadManager = DownloadManagerService();

  final existingTask = downloadManager.tasksNotifier.value.firstWhere(
          (t) => t.url == url, orElse: () => DownloadTask.empty());

  if (existingTask.id.isNotEmpty) {
    if (existingTask.status == DownloadStatus.completed) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Ce fichier est déjà téléchargé."), backgroundColor: Colors.green));
      return;
    }
    if (existingTask.status == DownloadStatus.downloading) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⏳ Ce fichier est déjà en cours de téléchargement."), backgroundColor: Colors.blue));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("🚀 Relance du téléchargement..."), backgroundColor: Colors.orange));
    await downloadManager.removeTask(existingTask.id);
    await _telechargerFichierVideo(url: url, nom: nom, context: context, totalSize: existingTask.totalSize);
    return;
  }

  try {
    final dio = await NetworkUtils.buildIptvDio(url);
    final contentLength = await probeContentLength(dio, url);
    final sizeFormatted = contentLength != null && contentLength > 0 ? formatFileSize(contentLength) : "taille inconnue";

    if (!context.mounted) return;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("⚠️ Confirmation"),
        content: Text(contentLength != null && contentLength > 0 ? "Le fichier fait $sizeFormatted.\nVoulez-vous lancer le téléchargement ?" : "Taille inconnue.\nVoulez-vous lancer le téléchargement ?"),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Annuler", style: TextStyle(color: Colors.red))),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text("Télécharger")),
        ],
      ),
    );

    if (confirm == true) {
      if (!context.mounted) return;
      await _telechargerFichierVideo(url: url, nom: nom, context: context, totalSize: contentLength);
    }
  } catch (e) {
    if (!context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Erreur de vérification : $e")));
  }
}

Future<int?> probeContentLength(Dio dio, String url) async {
  // On utilise directement la "feinte" de la requête GET partielle,
  // car elle est plus fiable pour obtenir le 'content-length'.
  final completer = Completer<int?>();
  final cancelToken = CancelToken();

  try {
    // On lance une requête GET qui télécharge en streaming.
    dio.get(
      url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream, // TRÈS IMPORTANT: on ne télécharge pas tout le corps
        followRedirects: true,
      ),
    ).then((response) {
      // Dès qu'on reçoit la réponse (les en-têtes sont arrivés)...
      final cl = response.headers.value('content-length');
      if (!completer.isCompleted) {
        completer.complete(cl != null ? int.tryParse(cl) : null);
      }
    }).catchError((error, stackTrace) {
      if (!completer.isCompleted) {
        completer.complete(null); // La requête a échoué avant d'avoir les en-têtes
      }
    }).whenComplete(() {
      // Dans tous les cas, on ANNULE immédiatement la requête pour ne pas télécharger le fichier.
      cancelToken.cancel();
    });

  } catch (e) {
    // Si une DioException de type 'cancel' arrive ici, c'est normal et attendu, on l'ignore.
    if (kDebugMode && e is! DioException && e.toString().contains('Request newFuture')) {
      debugPrint("⚠️ Erreur inattendue dans probeContentLength avec GET: $e");
    }
    if (!completer.isCompleted) {
      completer.complete(null);
    }
  }

  // On retourne le résultat obtenu (ou null si tout a échoué).
  return completer.future;
}

/// --- FONCTION DE TÉLÉCHARGEMENT (REVUE POUR DÉLÉGUER) ---
Future<void> _telechargerFichierVideo({required String url, required String nom, required BuildContext context, int? totalSize}) async {
  final downloadManager = DownloadManagerService();

  // 1. CRÉATION DE LA TÂCHE
  final String extension = _ext(url);
  String fileName = sanitizeFilename(nom);
  if (_ext(fileName).isEmpty) fileName = '$fileName.${extension.isNotEmpty ? extension : 'mp4'}';

  final savePath = "${await _getTempDirectory()}/$fileName";
  final taskId = 'task_${DateTime.now().millisecondsSinceEpoch}';

  final newTask = DownloadTask(
    id: taskId,
    url: url,
    displayName: nom,
    finalPath: savePath,
    totalSize: totalSize ?? 0,
    status: DownloadStatus.queued,
    createdAt: DateTime.now(),
  );

  // 2. AJOUT AU MANAGER ET DÉMARRAGE EN ARRIÈRE-PLAN
  await downloadManager.addTask(newTask);
  downloadManager.startDownloadTask(newTask); // Pas de 'await', le service s'en charge.

  // 3. AFFICHAGE DU DIALOGUE "MONITEUR" (NON BLOQUANT)
  final rootContext = navigatorKey.currentContext;
  if (rootContext == null || !rootContext.mounted) return;

  showDialog(
    context: rootContext,
    barrierDismissible: true, // Peut être fermé sans interrompre le téléchargement
    builder: (context) => TerminalDownloadDialog(taskId: taskId),
  );
}

class TerminalDownloadDialog extends StatefulWidget {
  final String taskId;
  const TerminalDownloadDialog({super.key, required this.taskId});
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

  @override
  void initState() {
    super.initState();
    _downloadManager.tasksNotifier.addListener(_onTaskUpdated);
    final initialTask = _downloadManager.tasksNotifier.value.firstWhere((t) => t.id == widget.taskId, orElse: () => DownloadTask.empty());
    if (initialTask.id.isNotEmpty) _updateLogs(initialTask);
  }

  void _onTaskUpdated() {
    if (!mounted) return;
    try {
      final task = _downloadManager.tasksNotifier.value.firstWhere((t) => t.id == widget.taskId);
      _updateLogs(task);
    } catch (e) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    }
  }

  void _updateLogs(DownloadTask task) {
    if (_lastTaskState == task) return;

    if (_logs.isEmpty) {
      _logs.add({'message': "🚀 Lancement du téléchargement :\n🎞️ ${task.displayName}", 'type': 'log'});
      if (task.totalSize > 0) _logs.add({'message': "📦 Taille du fichier : ${formatFileSize(task.totalSize)}", 'type': 'log'});
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

      final speedInfo = (_speed > 0) ? "${formatFileSize(_speed.toInt())}/s" : "";
      final etaInfo = (_eta > 0) ? " \n⏳ ETA: ${formatDuration(_eta)}" : "";
      final formatted = "[$bar] ${(task.progress * 100).toStringAsFixed(1)}% | $speedInfo$etaInfo";

      if (_logs.isNotEmpty && _logs.last["type"] == "stats") {
        _logs[_logs.length - 1] = {"message": formatted, "type": "stats"};
      } else {
        _logs.add({"message": formatted, "type": "stats"});
      }
    } else if (task.status == DownloadStatus.completed && _lastTaskState?.status != DownloadStatus.completed) {
      _logs.add({'message': "\n🟢 SUCCESS: Download complete!", 'type': 'success'});
      setState(() {
        _isDownloadComplete = true;
      });
    } else if (task.status == DownloadStatus.failed && _lastTaskState?.status != DownloadStatus.failed) {
      _logs.add({'message': "\n☣️ FATAL: An error occurred", 'type': 'error'});
      setState(() {
        _hasFatalError = true;
      });
    } else if (task.status == DownloadStatus.canceled && _lastTaskState?.status != DownloadStatus.canceled) {
      _logs.add({'message': "\nℹ️ ABORT: Download cancelled by user", 'type': 'error'});
    }

    if (!_isDownloadComplete && !_hasFatalError) {
      setState(() => _lastTaskState = task);
    }
  }

  @override
  void dispose() {
    _downloadManager.tasksNotifier.removeListener(_onTaskUpdated);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              '//:FLUX_DOWNLOAD_INTERFACE',
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
                  if (_isDownloadComplete || _hasFatalError) {
                    Navigator.of(context).pop();
                  } else {
                    _downloadManager.cancelTask(widget.taskId);
                    Navigator.of(context).pop();
                  }
                },
                child: Text(
                  (_isDownloadComplete || _hasFatalError) ? "[ CLOSE ]" : "[ ABORT ]",
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
  void dispose() { _controller.dispose(); super.dispose(); }
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
