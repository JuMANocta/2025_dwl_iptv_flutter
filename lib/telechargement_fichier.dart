import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart'; // Import nécessaire pour debugPrint
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'models/download_task.dart';
import 'services/download_manager_service.dart';
import 'secure_storage_service.dart';
import 'services/iptv_account_service.dart';

// --- Utils fichiers --------------------------------------------------------
Future<String> _getTempDirectory() async {
  final dir = await getTemporaryDirectory();
  final tmp = Directory("${dir.path}/dl_tmp");
  if (!await tmp.exists()) {
    await tmp.create(recursive: true);
  }
  return tmp.path;
}

String sanitizeFilename(String filename) {
  return filename.replaceAll(RegExp(r'[\\/*?:"<>|]'), "_");
}

String _ext(String name) {
  final i = name.lastIndexOf('.');
  return (i >= 0 && i < name.length - 1) ? name.substring(i + 1).toLowerCase() : '';
}

String formatFileSize(int bytes) {
  if (bytes <= 0) return "0 B";
  const suffixes = ["B", "KB", "MB", "GB", "TB"];
  final i = (math.log(bytes) / math.log(1024)).floor();
  final size = bytes / (1 << (10 * i));
  return "${size.toStringAsFixed(2)} ${suffixes[i]}";
}

String formatDuration(int totalSeconds) {
  if (totalSeconds < 0) return "--:--";
  final duration = Duration(seconds: totalSeconds);
  final hours = duration.inHours.toString().padLeft(2, '0');
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');

  if (duration.inHours > 0) {
    return "$hours:$minutes:$seconds";
  } else {
    return "$minutes:$seconds";
  }
}

/// --- Widgets UI (ScanLine, BlinkingCursor) --------------------------------
class ScanLine extends StatefulWidget {
  const ScanLine({super.key});
  @override
  State<ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<ScanLine> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _animation = Tween<double>(begin: 0, end: 1).animate(_controller);
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
        animation: _animation,
        builder: (context, child) {
          return Align(
            alignment: Alignment(0, _animation.value * 2 - 1),
            child: Container(height: 2, color: Colors.greenAccent.withAlpha(75)),
          );
        },
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
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: const Text("_", style: TextStyle(color: Color(0xFF33FF33), fontWeight: FontWeight.bold)),
    );
  }
}

/// --- Réseau / DIO ----------------------------------------------------------
Future<Dio> buildDio(String url) async {
  final acc = await IptvAccountService.getCurrentAccount();
  final legacy = await SecureStorageService().getCredentials();
  final cookies = (acc?.cookies?.trim().isNotEmpty == true)
      ? acc!.cookies!.trim()
      : (legacy["cookies"] ?? "").toString().trim();

  final uri = Uri.parse(url);
  final referer = "${uri.origin}/";
  final origin = uri.origin;

  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 10),
      sendTimeout: const Duration(minutes: 2),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
        'Accept': '*/*',
        'Connection': 'keep-alive',
        'Referer': referer,
        'Origin': origin,
        if (cookies.isNotEmpty) 'Cookie': cookies,
      },
      validateStatus: (s) => s != null && s < 500,
    ),
  );

  (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
    final client = HttpClient();
    client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    return client;
  };

  return dio;
}

Future<int?> probeContentLength(Dio dio, String url) async {
  try {
    final response = await dio.get(
      url,
      options: Options(
        responseType: ResponseType.stream,
        followRedirects: true,
      ),
    );
    response.data.stream.listen((_) {}).cancel();

    final cl = response.headers.value('content-length');
    if (cl != null) {
      final n = int.tryParse(cl);
      if (n != null && n > 0) {
        if (kDebugMode) {
          print("✅ Taille du fichier trouvée : ${formatFileSize(n)}");
        }
        return n;
      }
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint("⚠️ Probe content length a échoué pour l'URL $url: $e");
    }
  }
  if (kDebugMode) {
    print("❌ Impossible de déterminer la taille du fichier.");
  }
  return null;
}

/// --- Vérification / Confirmation -------------------------------------------
Future<void> verifierEtTelecharger({required String url, required String nom, required BuildContext context}) async {
  if (!context.mounted) return;

  final downloadManager = DownloadManagerService();
  final dio = await buildDio(url);

  // ÉTAPE 1: Vérifier si une tâche pour cette URL existe déjà.
  final existingTask = downloadManager.tasksNotifier.value.firstWhere(
        (t) => t.url == url,
    orElse: () => DownloadTask.empty(), // Renvoie une tâche "vide" si non trouvée
  );

  // ÉTAPE 2: Gérer la tâche existante
  if (existingTask.id.isNotEmpty) {
    if (existingTask.status == DownloadStatus.completed) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("✅ Ce fichier est déjà téléchargé."),
        backgroundColor: Colors.green,
      ));
      return; // Ne rien faire de plus
    }

    if (existingTask.status == DownloadStatus.downloading) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("⏳ Ce fichier est déjà en cours de téléchargement."),
        backgroundColor: Colors.blue,
      ));
      return; // Ne rien faire de plus
    }

    // SI LA TÂCHE EXISTE ET A ÉCHOUÉ/A ÉTÉ ANNULÉE :
    // On affiche un dialogue de confirmation de reprise.
    final downloadedSoFar = existingTask.totalSize * existingTask.progress;
    final totalSize = existingTask.totalSize;
    final String progressInfo;
    if (totalSize > 0 && existingTask.progress > 0) {
      final percentage = (existingTask.progress * 100).toStringAsFixed(1);
      progressInfo = "$percentage% du fichier a déjà été téléchargé.";
    } else {
      progressInfo = "Une partie du fichier a déjà été téléchargée.";
    }

    final bool? confirmResume = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("⚠️ Reprendre le téléchargement ?"),
        content: Text("$progressInfo\nVoulez-vous continuer ?"),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("❌ Annuler")),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text("✅ Reprendre")),
        ],
      ),
    );

    if (confirmResume == true) {
      // Si l'utilisateur confirme, on relance la reprise
      await downloadManager.removeTask(existingTask.id); // On la retire de la liste pour la relancer proprement
      await Future.delayed(const Duration(milliseconds: 50)); // Laisse le temps à l'UI de réagir

      await telechargerFichierVideo(url: url, nom: nom, context: context, totalSize: totalSize > 0 ? totalSize : null);
    } else {
      // Si l'utilisateur annule, on ne fait rien.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("❌ Reprise annulée")));
    }
    return; // On a fini de gérer le cas de la tâche existante.
  }

  // ÉTAPE 3: Si aucune tâche n'existe, on suit le processus normal de confirmation.
  try {
    final contentLength = await probeContentLength(dio, url);
    final sizeFormatted = contentLength != null && contentLength > 0 ? formatFileSize(contentLength) : "taille inconnue";

    if (!context.mounted) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("⚠️ Confirmation"),
        content: Text(contentLength != null && contentLength > 0
            ? "Le fichier fait $sizeFormatted.\nVoulez-vous lancer le téléchargement ?"
            : "Taille inconnue.\nVoulez-vous lancer le téléchargement ?"),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("❌ Annuler")),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text("✅ Télécharger")),
        ],
      ),
    );

    if (confirm == true) {
      if (!context.mounted) return;
      await telechargerFichierVideo(url: url, nom: nom, context: context, totalSize: contentLength);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("❌ Téléchargement annulé")));
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Erreur de vérification : $e")));
  }
}

/// --- Téléchargement + copie MediaStore -------------------------------------
Future<void> telechargerFichierVideo({required String url, required String nom, required BuildContext context, int? totalSize}) async {
  final Dio dio = await buildDio(url);

  final String extension = _ext(url);
  String fileName = sanitizeFilename(nom);
  if (_ext(fileName).isEmpty && extension.isNotEmpty) {
    fileName = '$fileName.$extension';
  } else if (_ext(fileName).isEmpty) {
    fileName = '$fileName.mp4';
  }

  final taskId = 'task_${DateTime.now().millisecondsSinceEpoch}';
  final savePath = "${await _getTempDirectory()}/$fileName";
  final downloadManager = DownloadManagerService();

  final initialTask = DownloadTask(
    id: taskId,
    url: url,
    displayName: nom,
    finalPath: savePath,
    totalSize: totalSize ?? 0,
    createdAt: DateTime.now(),
  );

  await downloadManager.addTask(initialTask);

  bool isDownloadComplete = false;
  bool isCancelled = false;
  bool started = false;
  final logs = <Map<String, dynamic>>[];
  final scrollController = ScrollController();
  final cancelToken = CancelToken();
  logs.add({'message': "🚀 Lancement du téléchargement : $fileName", 'type': 'log'});
  if (totalSize != null) { logs.add({'message': "📦 Taille du fichier : ${formatFileSize(totalSize)}", 'type': 'log'}); }

  await showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withAlpha((255 * 0.75).round()), // Utilise withAlpha
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          void addLog(String msg, String type, {double? progress, double? speed, int? eta}) {
            if (isCancelled) return;
            if (type == "stats" && progress != null) {
              const barLength = 20;
              final filled = (progress * barLength).clamp(0, barLength).toInt();
              final bar = "█" * filled + "▒" * (barLength - filled);
              final speedInfo = (speed != null && speed > 0) ? "${formatFileSize(speed.toInt())}/s" : "";
              final etaInfo = (eta != null && eta > 0 && progress < 1.0) ? " | ETA: ${formatDuration(eta)}" : "";
              final formatted = "[$bar] ${(progress * 100).toStringAsFixed(1)}% | $speedInfo$etaInfo";
              if (logs.isNotEmpty && logs.last["type"] == "stats") {
                logs[logs.length - 1] = {"message": formatted, "type": "stats"};
              } else {
                logs.add({"message": formatted, "type": "stats"});
              }
            } else {
              logs.add({"message": msg, "type": type});
            }
            setState(() {});
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (scrollController.hasClients) {
                scrollController.jumpTo(scrollController.position.maxScrollExtent);
              }
            });
          }

          Future<void> startDownload() async {
            final Stopwatch stopwatch = Stopwatch()
              ..start();
            double downloadSpeed = 0.0;
            int remainingSeconds = 0;
            // ----> REMPLACEZ le bloc try...catch dans startDownload() par ceci <----

            try {
              int bytesDownloaded = 0;
              // 1. On ne travaille qu'avec le fichier temporaire .downloading
              final tempDownloadPath = "$savePath.downloading";
              final tempFile = File(tempDownloadPath);

              // 2. Si le fichier .downloading existe, on récupère sa taille pour la reprise
              if (await tempFile.exists()) {
                bytesDownloaded = await tempFile.length();
                if (bytesDownloaded > 0) {
                  addLog("SYSTEM: Resuming download from ${formatFileSize(bytesDownloaded)}", "log");
                }
              }

              // 3. On télécharge EN CONTINUANT d'écrire dans le même fichier .downloading
              await dio.download(
                url,
                tempDownloadPath,
                cancelToken: cancelToken,
                deleteOnError: false, // Crucial : on garde le fichier partiel si ça plante
                onReceiveProgress: (received, total) {
                  if (isCancelled) return;
                  downloadManager.updateTask(taskId, status: DownloadStatus.downloading);
                  final totalReceived = bytesDownloaded + received;
                  final int totalBytes = totalSize ?? (bytesDownloaded + total);
                  if (totalBytes > 0) {
                    final progress = totalReceived / totalBytes;
                    downloadManager.updateTask(taskId, progress: progress);
                    final elapsedSeconds = stopwatch.elapsed.inSeconds;
                    if (elapsedSeconds > 0) {
                      downloadSpeed = received / elapsedSeconds;
                      if (downloadSpeed > 0) {
                        final remainingBytes = totalBytes - totalReceived;
                        remainingSeconds = (remainingBytes / downloadSpeed).round();
                      }
                    }
                    addLog("DL_STATS", "stats", progress: progress, speed: downloadSpeed, eta: remainingSeconds);
                  } else {
                    addLog("DL_INFO: ${formatFileSize(totalReceived)} / ?", "log");
                  }
                },
                options: Options(
                  headers: {
                    if (bytesDownloaded > 0) 'Range': 'bytes=$bytesDownloaded-',
                  },
                  // Accepte le statut 206 "Partial Content" qui est la réponse normale pour une reprise
                  validateStatus: (s) => s != null && (s >= 200 && s < 300 || s == 206),
                ),
              );

              if (cancelToken.isCancelled) return;

              // 4. Une fois le téléchargement terminé, on renomme le fichier .downloading en fichier final
              addLog("SYSTEM: Finalizing download...", "log");
              await tempFile.rename(savePath);

              isDownloadComplete = true;
              addLog("SUCCESS: Download complete -> $fileName", "log");
              await downloadManager.updateTask(taskId, status: DownloadStatus.completed, progress: 1.0);

              try {
                addLog("MEDIA_STORE: Copying to gallery...", "log");
                final ms = MediaStore();
                // Le nom de dossier est "IPtvFlux" (depuis le main.dart)
                await ms.saveFile(
                  tempFilePath: savePath,
                  dirType: DirType.video,
                  dirName: DirName.movies,
                );
                addLog("SUCCESS: File saved in Movies/IPtvFlux", "log");
              } catch (e) {
                addLog("ERROR: Gallery copy failed: $e", "error");
              }

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("✅ Fichier enregistré : $fileName")));
              }

            } catch (e) {
              if (e is DioException && e.type == DioExceptionType.cancel) {
                addLog("ABORT: Download cancelled by user.", "error");
                await downloadManager.updateTask(taskId, status: DownloadStatus.canceled);
              } else {
                // Affiche un message d'erreur plus clair pour les autres cas
                addLog("FATAL: An error occurred: $e", "error");
                await downloadManager.updateTask(taskId, status: DownloadStatus.failed); // <-- AJOUT
                await Future.delayed(const Duration(seconds: 3));
                if (context.mounted) Navigator.of(context).pop();
              }
            } finally {
              stopwatch.stop(); // Arrêter le chronomètre
              // On ne nettoie le fichier final temporaire que si le DL est complet
              if (isDownloadComplete) {
                final f = File(savePath);
                if (await f.exists()) {
                  try {
                    await f.delete();
                    addLog("CLEANUP: Final temp file deleted.", "log");
                  } catch (_) {}
                }
              }
            }
          }

          if (!started) { startDownload(); started = true; }

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
                  Text('//:FLUX_DOWNLOAD_INTERFACE', style: GoogleFonts.vt323(color: Colors.green, fontSize: 22)),
                  const Divider(color: Colors.green),
                  Flexible(
                    child: SizedBox(
                      width: double.maxFinite,
                      height: 300,
                      child: Stack(
                        children: [
                          ListView.builder(
                            controller: scrollController,
                            itemCount: logs.length,
                            itemBuilder: (context, index) {
                              final log = logs[index];
                              final Color color;
                              switch(log['type']) {
                                case 'stats': color = const Color(0xFF33FF33); break;
                                case 'error': color = const Color(0xFFFF5555); break;
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
                  if (!isDownloadComplete && !isCancelled)
                    const Row(children: [
                      Text(">", style: TextStyle(color: Color(0xFF33FF33))),
                      BlinkingCursor()
                    ]),
                  const Divider(color: Colors.green),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        if (!isDownloadComplete) {
                          isCancelled = true;
                          cancelToken.cancel('User cancelled');
                        }
                        Navigator.of(context).pop();
                      },
                      child: Text(
                        isDownloadComplete ? "[ CLOSE ]" : "[ ABORT ]",
                        style: GoogleFonts.vt323(color: Colors.white, fontSize: 18),
                      ),
                    ),
                  )
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
