// lib/telechargement_fichier.dart
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart'; // NOUVEAU : Import pour les polices
import 'package:media_store_plus/media_store_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'secure_storage_service.dart';
import 'services/iptv_account_service.dart';

// ... (Tout le code des fonctions utilitaires comme formatFileSize, buildDio, etc. reste inchangé) ...
// [Le code des fonctions utilitaires est omis ici pour la lisibilité, mais il est inclus dans le bloc final]
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

String? _extFromContentType(String? ct) {
  if (ct == null) return null;
  final mime = ct.toLowerCase().split(';').first.trim();
  switch (mime) {
    case 'video/mp4':
      return 'mp4';
    case 'video/webm':
      return 'webm';
    case 'video/quicktime':
      return 'mov';
    case 'video/x-msvideo':
      return 'avi';
    case 'video/x-matroska':
    case 'application/x-matroska':
      return 'mkv';
    default:
      return null;
  }
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

/// --- Effet scanline --------------------------------------------------------
// ... (code de ScanLine inchangé) ...
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
            child: Container(
              height: 2,
              color: Colors.greenAccent.withAlpha(75),
            ),
          );
        },
      ),
    );
  }
}
// NOUVEAU : Widget pour le curseur clignotant
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
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: const Text(
        "_",
        style: TextStyle(
          color: Color(0xFF33FF33),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// --- Réseau / DIO ----------------------------------------------------------
// ... (code de buildDio, probeContentLength, probeContentType inchangé) ...
Future<Dio> buildDio(String url) async {
  // Cookies depuis le compte courant, fallback legacy si besoin
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
        'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
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
    final head = await dio.head(url, options: Options(followRedirects: true));
    final cl = head.headers.value('content-length');
    if (cl != null) {
      final n = int.tryParse(cl);
      if (n != null && n > 0) return n;
    }
  } catch (_) {}

  final token = CancelToken();
  try {
    final resp = await dio.get<ResponseBody>(
      url,
      options: Options(
        method: 'GET',
        headers: {'Range': 'bytes=0-0'},
        responseType: ResponseType.stream,
        followRedirects: true,
        validateStatus: (s) => s != null && s < 500,
      ),
      cancelToken: token,
    );
    token.cancel('probe done');

    final cr = resp.headers.value('content-range'); // e.g. "bytes 0-0/123456"
    if (cr != null && cr.contains('/')) {
      final totalStr = cr.split('/').last.trim();
      final total = int.tryParse(totalStr);
      if (total != null && total > 0) return total;
    }
    final cl = resp.headers.value('content-length');
    if (cl != null) {
      final n = int.tryParse(cl);
      if (n != null && n > 0) return n;
    }
  } catch (_) {}

  return null;
}

Future<String?> probeContentType(Dio dio, String url) async {
  try {
    final head = await dio.head(url, options: Options(followRedirects: true));
    final ct = head.headers.value('content-type');
    if (ct != null && ct.isNotEmpty) return ct;
  } catch (_) {}

  final token = CancelToken();
  try {
    final resp = await dio.get<ResponseBody>(
      url,
      options: Options(
        method: 'GET',
        headers: {'Range': 'bytes=0-0'},
        responseType: ResponseType.stream,
        followRedirects: true,
        validateStatus: (s) => s != null && s < 500,
      ),
      cancelToken: token,
    );
    token.cancel('probe done');
    final ct = resp.headers.value('content-type');
    if (ct != null && ct.isNotEmpty) return ct;
  } catch (_) {}

  return null;
}
/// --- Vérification / Confirmation -------------------------------------------
// ... (code de verifierEtTelecharger inchangé) ...
Future<void> verifierEtTelecharger(String url, BuildContext context) async {
  final dio = await buildDio(url);

  try {
    final contentLength = await probeContentLength(dio, url) ?? 0;
    final sizeFormatted = contentLength > 0 ? formatFileSize(contentLength) : "taille inconnue";

    if (!context.mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("⚠️ Confirmation"),
        content: Text(
          contentLength > 0
              ? "Le fichier fait $sizeFormatted.\nVoulez-vous lancer le téléchargement ?"
              : "Taille inconnue.\nVoulez-vous lancer le téléchargement ?",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("❌ Annuler")),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text("✅ Télécharger")),
        ],
      ),
    );

    if (confirm == true) {
      if (!context.mounted) return;
      await telechargerFichierVideo(url, context, totalSize: contentLength > 0 ? contentLength : null);
    } else {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("❌ Téléchargement annulé")));
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Erreur de vérification : $e")));
  }
}
/// --- Téléchargement + copie MediaStore -------------------------------------

Future<void> telechargerFichierVideo(String url, BuildContext context, {int? totalSize}) async {
  final Dio dio = await buildDio(url);

  // Nom de fichier (nettoyé) + extension (URL ou probe Content-Type)
  final urlName = sanitizeFilename(Uri.parse(url).pathSegments.isNotEmpty
      ? Uri.parse(url).pathSegments.last
      : "video");
  String fileName = urlName.isEmpty ? "video" : urlName;

  if (_ext(fileName).isEmpty) {
    final ct = await probeContentType(dio, url);
    final guessed = _extFromContentType(ct) ?? 'mp4';
    fileName = "$fileName.$guessed";
  }

  final savePath = "${await _getTempDirectory()}/$fileName";

  bool isDownloadComplete = false;
  bool isCancelled = false;
  bool started = false;

  final logs = <Map<String, dynamic>>[];
  final scrollController = ScrollController();
  final cancelToken = CancelToken();

  logs.add({'message': "🚀 Lancement du téléchargement : $fileName", 'type': 'log'});
  if (totalSize != null) {
    logs.add({'message': "📦 Taille du fichier : ${formatFileSize(totalSize)}", 'type': 'log'});
  }

  // MODIFIÉ : On utilise Dialog au lieu de AlertDialog pour plus de contrôle
  await showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withOpacity(0.75), // Fond noir semi-transparent
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {

          void addLog(String msg, String type, {double? progress, double? speed, int? eta}) {
            if (isCancelled) return;

            if (type == "stats" && progress != null) {
              const barLength = 20;
              final filled = (progress * barLength).clamp(0, barLength).toInt();
              // MODIFIÉ : Barre de progression avec des caractères plus "tech"
              final bar = "█" * filled + "▒" * (barLength - filled);
              final speedInfo = (speed != null && speed > 0) ? "${formatFileSize(speed.toInt())}/s" : "";
              final etaInfo = (eta != null && eta > 0 && progress < 1.0) ? " | ETA: ${formatDuration(eta)}" : "";
              final formatted = "[$bar] ${(progress * 100).toStringAsFixed(1)}% | $msg | $speedInfo$etaInfo";

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
            final Stopwatch stopwatch = Stopwatch()..start();
            double downloadSpeed = 0.0;
            int remainingSeconds = 0;

            // ... (Toute la logique de startDownload, parallelDownload reste identique) ...
            // ----- FONCTION UTILITAIRE POUR LE TÉLÉCHARGEMENT PARALLÈLE -----
            Future<void> parallelDownload() async {
              if (totalSize == null) return;

              const int concurrentDownloads = 4;
              final chunkPaths = List<String>.generate(
                  concurrentDownloads, (i) => '$savePath.part$i');
              final chunkSize = (totalSize! / concurrentDownloads).ceil();

              final progressMap = <int, int>{
                for (var i = 0; i < concurrentDownloads; i++) i: 0
              };

              final downloadTasks = <Future<void>>[];

              for (int i = 0; i < concurrentDownloads; i++) {
                final start = i * chunkSize;
                final end = (i == concurrentDownloads - 1)
                    ? totalSize! - 1
                    : start + chunkSize - 1;

                if (start >= totalSize!) continue;

                downloadTasks.add(
                  dio.download(
                    url,
                    chunkPaths[i],
                    cancelToken: cancelToken,
                    options: Options(headers: {'Range': 'bytes=$start-$end'}),
                    onReceiveProgress: (received, total) {
                      if (isCancelled) return;
                      progressMap[i] = received;
                      final totalReceived =
                      progressMap.values.reduce((a, b) => a + b);
                      final progress = totalReceived / totalSize!;

                      // Calcul de la vitesse et du temps restant
                      final elapsedSeconds = stopwatch.elapsed.inSeconds;
                      if (elapsedSeconds > 0) {
                        downloadSpeed = totalReceived / elapsedSeconds;
                        final remainingBytes = totalSize! - totalReceived;
                        remainingSeconds = (remainingBytes / downloadSpeed).round();
                      }

                      addLog(
                          "DL_STATS",
                          "stats",
                          progress: progress,
                          speed: downloadSpeed,
                          eta: remainingSeconds);
                    },
                  ),
                );
              }

              await Future.wait(downloadTasks);

              if (cancelToken.isCancelled) {
                throw DioException.requestCancelled(
                  requestOptions: RequestOptions(path: url),
                  reason: 'Cancelled by user',
                );
              }

              addLog("SYSTEM: Assembling chunks...", "log");
              final finalFile = File(savePath).openSync(mode: FileMode.writeOnlyAppend);
              for (final path in chunkPaths) {
                final chunkFile = File(path);
                if (await chunkFile.exists()) {
                  await finalFile.writeFrom(await chunkFile.readAsBytes());
                  await chunkFile.delete();
                }
              }
              await finalFile.close();
            }
            // ----- FIN DE LA FONCTION UTILITAIRE -----


            // ----- CORPS PRINCIPAL DE STARTDOWNLOAD -----
            try {
              if (totalSize != null && totalSize! > 10 * 1024 * 1024) {
                addLog("SYSTEM: Parallel mode activated (4 streams)", "log");
                await parallelDownload();
              } else {
                if (totalSize == null) {
                  addLog("SYSTEM: Unknown size, fallback to single stream", "log");
                }
                else {
                  addLog("SYSTEM: Single stream mode", "log");
                }

                await dio.download(
                  url,
                  savePath,
                  cancelToken: cancelToken,
                  onReceiveProgress: (received, total) {
                    if (isCancelled) return;
                    final int totalBytes = totalSize ?? total;
                    if (totalBytes > 0) {
                      final progress = received / totalBytes;

                      // Calcul de la vitesse et du temps restant
                      final elapsedSeconds = stopwatch.elapsed.inSeconds;
                      if (elapsedSeconds > 0) {
                        downloadSpeed = received / elapsedSeconds;
                        final remainingBytes = totalBytes - received;
                        remainingSeconds = (remainingBytes / downloadSpeed).round();
                      }

                      addLog("DL_STATS", "stats",
                          progress: progress,
                          speed: downloadSpeed,
                          eta: remainingSeconds);
                    } else {
                      addLog("DL_INFO: ${formatFileSize(received)} / ?", "log");
                    }
                  },
                );
              }

              if (cancelToken.isCancelled) return;

              isDownloadComplete = true;
              addLog("SUCCESS: Download complete -> $fileName", "log");

              try {
                addLog("MEDIA_STORE: Copying to gallery...", "log");
                final ms = MediaStore();
                await ms.saveFile(
                  tempFilePath: savePath,
                  dirType: DirType.video,
                  dirName: DirName.movies,
                  relativePath: "IPtvFlux",
                );
                addLog("SUCCESS: File saved in Movies/IPtvFlux", "log");
              } catch (e) {
                addLog("ERROR: Gallery copy failed: $e", "error");
              }

              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text("✅ Fichier enregistré : $fileName")));
              }

            } catch (e) {
              if (e is! DioException || e.type != DioExceptionType.cancel) {
                addLog("FATAL: ${e is DioException ? e.message : e.toString()}", "error");
              }

              try {
                for (int i = 0; i < 4; i++) {
                  final partFile = File('$savePath.part$i');
                  if (await partFile.exists()) await partFile.delete();
                }
                final singleFile = File(savePath);
                if (await singleFile.exists()) await singleFile.delete();

                addLog("CLEANUP: Temporary files deleted.", "log");

                if (context.mounted && (e is! DioException || e.type != DioExceptionType.cancel)) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text("❌ Échec, les fichiers partiels ont été supprimés.")));
                }

              } catch (deleteError) {
                addLog("ERROR: Cleanup failed: $deleteError", "error");
              }

              if (e is DioException && e.type == DioExceptionType.cancel) {
                addLog("ABORT: Download cancelled by user.", "error");
              }

            } finally {
              if (isDownloadComplete) {
                final f = File(savePath);
                if (await f.exists()) {
                  await f.delete();
                  addLog("CLEANUP: Final temp file deleted.", "log");
                }
              }
            }
          }

          if (!started) {
            startDownload();
            started = true;
          }

          // MODIFIÉ : Remplacement de AlertDialog par une composition de Widgets personnalisée
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.9),
                border: Border.all(color: Colors.green.withOpacity(0.5)),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.2),
                    blurRadius: 10,
                    spreadRadius: 2,
                  )
                ],
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
                            controller: scrollController,
                            itemCount: logs.length,
                            itemBuilder: (context, index) {
                              final log = logs[index];
                              final Color color;
                              switch(log['type']) {
                                case 'stats': color = const Color(0xFF33FF33); break; // Vert vif
                                case 'error': color = const Color(0xFFFF5555); break; // Rouge
                                default: color = const Color(0xFFADFF2F); break; // Vert-jaune
                              }
                              return Text(
                                log['message'],
                                style: GoogleFonts.sourceCodePro(
                                  color: color,
                                  fontSize: 11,
                                ),
                              );
                            },
                          ),
                          const ScanLine(),
                        ],
                      ),
                    ),
                  ),
                  // NOUVEAU : Curseur clignotant
                  if (!isDownloadComplete)
                    const Row(
                      children: [
                        Text(">", style: TextStyle(color: Color(0xFF33FF33))),
                        BlinkingCursor(),
                      ],
                    ),
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
