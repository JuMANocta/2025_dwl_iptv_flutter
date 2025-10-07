// lib/telechargement_fichier.dart
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/material.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'secure_storage_service.dart';
import 'services/iptv_account_service.dart';

/// --- Utils fichiers --------------------------------------------------------

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

/// --- Effet scanline --------------------------------------------------------

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
              color: Colors.greenAccent.withValues(alpha: 0.3), // tu souhaites withValues
            ),
          );
        },
      ),
    );
  }
}

/// --- Réseau / DIO ----------------------------------------------------------

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

  // Tu gardes l'acceptation des certifs (serveur sans cert)
  (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
    final client = HttpClient();
    client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    return client;
  };

  return dio;
}

/// HEAD → Range probe: taille du contenu
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

/// Probe Content-Type pour déduire l'extension si absente
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

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          void addLog(String msg, String type, {double? progress}) {
            if (isCancelled) return;

            if (type == "stats" && progress != null) {
              const barLength = 20;
              final filled = (progress * barLength).clamp(0, barLength).toInt();
              final bar = "▰" * filled + "▱" * (barLength - filled);
              final formatted = "$bar ${(progress * 100).toStringAsFixed(1)}%  $msg";

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
            try {
              final resp = await dio.download(
                url,
                savePath,
                cancelToken: cancelToken,
                onReceiveProgress: (received, total) {
                  if (isCancelled) return;
                  final int totalBytes = totalSize ?? total;
                  if (totalBytes > 0) {
                    final progress = received / totalBytes;
                    addLog("📥 ${formatFileSize(received)} / ${formatFileSize(totalBytes)}", "stats",
                        progress: progress);
                  } else {
                    addLog("📥 ${formatFileSize(received)} / ?", "log");
                  }
                },
              );

              if (isCancelled) return;

              if (resp.statusCode != null && resp.statusCode! >= 200 && resp.statusCode! < 300) {
                isDownloadComplete = true;
                addLog("🪄 HTTP code : ${resp.statusCode}", "log");
                addLog("✅ Fichier téléchargé avec succès : $fileName", "log");

                try {
                  final ms = MediaStore();
                  await ms.saveFile(
                    tempFilePath: savePath,
                    dirType: DirType.video,
                    dirName: DirName.movies,
                    relativePath: "IPtvFlux",
                  );
                  addLog("🎬 Copié dans la galerie (Movies/IPtvFlux)", "log");

                  // Nettoyage si le temp existe encore
                  try {
                    final f = File(savePath);
                    if (await f.exists()) {
                      await f.delete();
                      addLog("🧹 Fichier temporaire supprimé", "log");
                    }
                  } catch (e) {
                    addLog("⚠️ Nettoyage temp impossible : $e", "error");
                  }
                } catch (e) {
                  addLog("⚠️ Erreur copie galerie : $e", "error");
                }

                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text("✅ Fichier enregistré : $fileName")));
                }
              } else {
                throw Exception("Échec avec le code HTTP ${resp.statusCode}");
              }
            } catch (e) {
              final file = File(savePath);
              if (await file.exists()) {
                try {
                  await file.delete();
                  addLog("🗑️ Fichier partiel supprimé.", "log");
                  if (context.mounted && !(e is DioException && e.type == DioExceptionType.cancel)) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text("❌ Échec, le fichier partiel a été supprimé.")));
                  }
                } catch (deleteError) {
                  addLog("⚠️ Impossible de supprimer le fichier partiel : $deleteError", "error");
                }
              }

              if (e is DioException && e.type == DioExceptionType.cancel) {
                addLog("⏹️ Téléchargement annulé par l’utilisateur", "error");
              } else if (e is DioException) {
                addLog("⚠️ Erreur réseau : ${e.message}", "error");
              } else {
                addLog("❌ Erreur : $e", "error");
              }
            }
          }

          if (!started) {
            started = true;
            Future.microtask(startDownload);
          }

          return AlertDialog(
            backgroundColor: Colors.black,
            title: Text(
              isDownloadComplete ? "✅ Téléchargement terminé" : "🎬 Téléchargement",
              style: const TextStyle(color: Colors.greenAccent, fontFamily: 'Courier New'),
            ),
            content: Stack(
              children: [
                SizedBox(
                  width: double.maxFinite,
                  height: 300,
                  child: Column(
                    children: [
                      if (!isDownloadComplete) const CircularProgressIndicator(color: Colors.greenAccent),
                      const SizedBox(height: 16),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(color: Colors.greenAccent.withValues(alpha: 0.3), blurRadius: 5),
                            ],
                          ),
                          child: ListView.builder(
                            controller: scrollController,
                            itemCount: logs.length,
                            itemBuilder: (context, index) {
                              final log = logs[index];
                              final message = log['message'] as String;
                              final type = log['type'] as String;
                              Color color;
                              if (type == 'error') {
                                color = Colors.redAccent;
                              } else if (type == 'stats') {
                                color = Colors.lightGreenAccent;
                              } else {
                                color = Colors.greenAccent;
                              }
                              return Text(
                                message,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: color,
                                  fontFamily: 'Courier New',
                                  letterSpacing: 1.2,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const ScanLine(),
              ],
            ),
            actions: [
              if (!isDownloadComplete)
                TextButton(
                  onPressed: () {
                    isCancelled = true;
                    cancelToken.cancel();
                    Navigator.of(context).pop();
                  },
                  child: const Text("❌ Annuler", style: TextStyle(color: Colors.redAccent)),
                ),
              if (isDownloadComplete)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("✅ Terminer", style: TextStyle(color: Colors.greenAccent)),
                ),
            ],
          );
        },
      );
    },
  );
}
