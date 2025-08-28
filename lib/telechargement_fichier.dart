import 'dart:io';
import 'dart:math' as Math;
import 'dart:async';
import 'package:dio/io.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'secure_storage_service.dart';

/// 📂 Récupère ou crée le dossier de téléchargement "Videos"
Future<String> _getDownloadDirectory() async {
  final dir = await getExternalStorageDirectory();
  final downloadDir = Directory("${dir!.path}/Videos");
  if (!await downloadDir.exists()) {
    await downloadDir.create(recursive: true);
  }
  return downloadDir.path;
}

/// 🔧 Nettoie le nom du fichier
String sanitizeFilename(String filename) {
  return filename.replaceAll(RegExp(r'[\\/*?:"<>|]'), "_");
}

/// 🔧 Taille lisible
String formatFileSize(int bytes) {
  if (bytes <= 0) return "0 B";
  const suffixes = ["B", "KB", "MB", "GB", "TB"];
  int i = (bytes == 0) ? 0 : (Math.log(bytes) / Math.log(1024)).floor();
  double size = bytes / (1 << (10 * i));
  return "${size.toStringAsFixed(2)} ${suffixes[i]}";
}

/// Effet scanline vert
class ScanLine extends StatefulWidget {
  const ScanLine({super.key});
  @override
  State<ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<ScanLine>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  @override
  void initState() {
    super.initState();
    _controller =
    AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
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
              color: Colors.greenAccent.withValues(alpha: 0.3),
            ),
          );
        },
      ),
    );
  }
}

/// 🔧 Construit Dio configuré avec headers + cookies
Future<Dio> buildDio(String url) async {
  final storage = SecureStorageService();
  final creds = await storage.getCredentials();
  final cookies = creds["cookies"] ?? "";
  final referer = Uri.parse(url).origin + "/";
  final origin = Uri.parse(url).origin;

  final dio = Dio(BaseOptions(
    headers: {
      'User-Agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
      'Accept': '*/*',
      'Connection': 'keep-alive',
      'Referer': referer,
      'Origin': origin,
      if (cookies.isNotEmpty) 'Cookie': cookies,
    },
    validateStatus: (status) => status != null && status < 500,
  ));

  (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
    final client = HttpClient();
    client.badCertificateCallback = (cert, host, port) => true;
    return client;
  };
  return dio;
}

/// 🚀 Vérifie la taille avant téléchargement
Future<void> verifierEtTelecharger(String url, BuildContext context) async {
  final dio = await buildDio(url);
  try {
    final response = await dio.head(url);
    final contentLength =
        int.tryParse(response.headers.value("content-length") ?? "0") ?? 0;
    final sizeFormatted = formatFileSize(contentLength);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("⚠️ Confirmation"),
        content: Text(contentLength > 0
            ? "Le fichier fait $sizeFormatted.\nVoulez-vous lancer le téléchargement ?"
            : "Taille inconnue.\nVoulez-vous lancer le téléchargement ?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("❌ Annuler"),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("✅ Télécharger"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await telechargerFichierVideo(url, context,
          totalSize: contentLength > 0 ? contentLength : null);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ Téléchargement annulé")),
      );
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("❌ Erreur HEAD request : $e")),
    );
  }
}

/// 📥 Téléchargement vidéo (sans logique de reprise)
Future<void> telechargerFichierVideo(String url, BuildContext context,
    {int? totalSize}) async {
  Dio dio = await buildDio(url);

  final rawFileName = Uri.parse(url).pathSegments.last;
  final fileName = sanitizeFilename(rawFileName);
  final savePath = "${await _getDownloadDirectory()}/$fileName";

  bool isDownloadComplete = false;
  bool isCancelled = false;
  List<Map<String, dynamic>> logs = [];
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
            if (type == "stats" && progress != null) {
              // Construire une petite barre de progression
              const barLength = 20;
              int filled = (progress * barLength).clamp(0, barLength).toInt();
              String bar = "▰" * filled + "▱" * (barLength - filled);

              final formatted =
                  "$bar ${(progress * 100).toStringAsFixed(1)}%  $msg";

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
              final response = await dio.download(
                url,
                savePath,
                cancelToken: cancelToken,
                onReceiveProgress: (received, total) {
                  final totalBytes = totalSize ?? total;
                  if (totalBytes > 0) {
                    final progress = received / totalBytes;
                    addLog(
                      "📥 ${formatFileSize(received)} / ${formatFileSize(totalBytes)}",
                      "stats",
                      progress: progress,
                    );
                  }
                },
              );

              addLog("⚠️ HTTP code : ${response.statusCode}", "log");

              if (response.statusCode == 200) {
                isDownloadComplete = true;
                addLog("✅ Fichier téléchargé : $savePath", "log");
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("✅ Fichier enregistré : $fileName")),
                  );
                }
              } else {
                throw Exception("Code HTTP ${response.statusCode}");
              }
            } catch (e) {
              if (e is DioException) {
                addLog("⚠️ Erreur HTTP ${e.response?.statusCode} : ${e.message}", "error");
                print("❌ DioException: ${e.message}");
              } else {
                addLog("❌ Erreur : $e", "error");
              }
            }
          }

          Future.microtask(startDownload);

          return AlertDialog(
            backgroundColor: Colors.black,
            title: Text(
              isDownloadComplete
                  ? "✅ Téléchargement terminé"
                  : "🎬 Téléchargement en cours...",
              style: const TextStyle(
                  color: Colors.greenAccent, fontFamily: 'Courier New'),
            ),
            content: Stack(
              children: [
                SizedBox(
                  width: double.maxFinite,
                  height: 300,
                  child: Column(
                    children: [
                      if (!isDownloadComplete)
                        const CircularProgressIndicator(color: Colors.greenAccent),
                      const SizedBox(height: 16),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.greenAccent.withValues(alpha: 0.3),
                                  blurRadius: 5)
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
                  child: const Text("❌ Annuler",
                      style: TextStyle(color: Colors.redAccent)),
                ),
              if (isDownloadComplete)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("✅ Terminer",
                      style: TextStyle(color: Colors.greenAccent)),
                ),
            ],
          );
        },
      );
    },
  );
}
