import 'dart:io';
import 'dart:math' as Math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

/// 📂 Récupère ou crée le dossier de téléchargement "Videos"
Future<String> _getDownloadDirectory() async {
  final dir = await getExternalStorageDirectory();
  final downloadDir = Directory("${dir!.path}/Videos");
  if (!await downloadDir.exists()) {
    await downloadDir.create(recursive: true);
  }
  return downloadDir.path;
}

/// 🔧 Nettoie le nom du fichier pour éviter les caractères interdits
String sanitizeFilename(String filename) {
  return filename.replaceAll(RegExp(r'[\\/*?:"<>|]'), "_");
}

/// 🔧 Formatage taille lisible (B, KB, MB, GB...)
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
              color: Colors.greenAccent.withOpacity(0.3),
            ),
          );
        },
      ),
    );
  }
}

/// 🚀 Vérifie la taille avant téléchargement et demande confirmation
Future<void> verifierEtTelecharger(String url, BuildContext context) async {
  final dio = Dio();

  try {
    final response = await dio.head(
      url,
      options: Options(
        headers: {
          "User-Agent": "Mozilla/5.0",
          "Referer": "https://tonsite.com/",
        },
      ),
    );

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

/// 📥 Téléchargement avec reprise + progression détaillée
Future<void> telechargerFichierVideo(String url, BuildContext context,
    {int? totalSize}) async {
  final dio = Dio();

  final rawFileName = Uri.parse(url).pathSegments.last;
  final fileName = sanitizeFilename(rawFileName);
  final savePath = "${await _getDownloadDirectory()}/$fileName";

  bool isDownloadComplete = false;
  bool isCancelled = false;
  List<Map<String, dynamic>> logs = [];
  final scrollController = ScrollController();
  final logStream = StreamController<void>.broadcast();
  final cancelToken = CancelToken();

  int maxRetries = 3;
  int attempt = 0;

  logs.add(
      {'message': "🚀 Lancement du téléchargement : $fileName", 'type': 'log'});
  if (totalSize != null) {
    logs.add({
      'message': "📦 Taille du fichier : ${formatFileSize(totalSize)}",
      'type': 'log'
    });
  }
  logStream.add(null);

  unawaited(showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          logStream.stream.listen((_) {
            if (!context.mounted) return;
            setState(() {});
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (scrollController.hasClients) {
                scrollController
                    .jumpTo(scrollController.position.maxScrollExtent);
              }
            });
          });

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
                        const CircularProgressIndicator(
                            color: Colors.greenAccent),
                      const SizedBox(height: 16),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.greenAccent.withOpacity(0.3),
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
  ));

  while (attempt < maxRetries && !isDownloadComplete && !isCancelled) {
    try {
      attempt++;

      final file = File(savePath);
      int downloadedLength = 0;
      if (await file.exists()) {
        downloadedLength = await file.length();
        logs.add({
          'message': "⏩ Reprise à ${formatFileSize(downloadedLength)}",
          'type': 'log'
        });
        logStream.add(null);
      }

      final response = await dio.download(
        url,
        savePath,
        cancelToken: cancelToken,
        options: Options(
          headers: {
            "User-Agent": "Mozilla/5.0",
            "Referer": "https://tonsite.com/",
            if (downloadedLength > 0) "Range": "bytes=$downloadedLength-",
          },
        ),
        onReceiveProgress: (received, total) {
          final totalBytes = totalSize ?? total;
          if (totalBytes > 0) {
            final downloaded = received + downloadedLength;
            final progress =
            (downloaded / totalBytes * 100).toStringAsFixed(1);
            logs.add({
              'message':
              "📥 ${formatFileSize(downloaded)} / ${formatFileSize(totalBytes)} ($progress%)",
              'type': 'stats'
            });
            logStream.add(null);
          }
        },
      );

      if (response.statusCode == 200 || response.statusCode == 206) {
        isDownloadComplete = true;
        logs.add({'message': "✅ Fichier téléchargé : $savePath", 'type': 'log'});
        logStream.add(null);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("✅ Fichier enregistré : $fileName")),
          );
        }
      } else {
        throw Exception("Code HTTP ${response.statusCode}");
      }
    } catch (e) {
      logs.add({'message': "⚠️ Erreur : $e", 'type': 'error'});
      logStream.add(null);
      if (attempt >= maxRetries) {
        logs.add({
          'message': "❌ Abandon après $maxRetries tentatives",
          'type': 'error'
        });
        logStream.add(null);
      }
    }
  }

  await Future.delayed(const Duration(seconds: 1));
  logStream.close();
}
