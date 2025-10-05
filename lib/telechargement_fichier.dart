import 'dart:io';
import 'dart:math' as math;
import 'dart:async';
import 'package:dio/io.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'secure_storage_service.dart';

/// 📂 Dossier de téléchargement "Videos" temporaire
Future<String> _getTempDirectory() async {
  final dir = await getTemporaryDirectory();
  final tmp = Directory("${dir.path}/dl_tmp");
  if (!await tmp.exists()) {
    await tmp.create(recursive: true);
  }
  return tmp.path;
}

/// 🔧 Nettoie le nom du fichier
String sanitizeFilename(String filename) {
  return filename.replaceAll(RegExp(r'[\\/*?:"<>|]'), "_");
}

/// 🔧 Taille lisible
String formatFileSize(int bytes) {
  if (bytes <= 0) return "0 B";
  const suffixes = ["B", "KB", "MB", "GB", "TB"];
  int i = (bytes == 0) ? 0 : (math.log(bytes) / math.log(1024)).floor();
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
    validateStatus: (status) => status != null && status < 500,
  ));
  (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
    final client = HttpClient();
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
    return client;
  };
  return dio;
}

/// Essaie d'obtenir la taille du fichier sans le télécharger.
/// 1) HEAD -> Content-Length
/// 2) GET avec Range: bytes=0-0 -> Content-Range ou Content-Length
Future<int?> probeContentLength(Dio dio, String url) async {
  // Tentative 1 : HEAD
  try {
    final head = await dio.head(url, options: Options(followRedirects: true));
    final cl = head.headers.value('content-length');
    if (cl != null) {
      final n = int.tryParse(cl);
      if (n != null && n > 0) return n;
    }
  } catch (_) {
    // ignore, on tentera Range
  }

  // Tentative 2 : GET avec Range: bytes=0-0
  final token = CancelToken();
  try {
    final resp = await dio.get<ResponseBody>(
      url,
      options: Options(
        method: 'GET',
        headers: {'Range': 'bytes=0-0'},
        responseType: ResponseType.stream,      // ne bufferise pas tout
        followRedirects: true,
        validateStatus: (s) => s != null && s < 500,
      ),
      cancelToken: token,
    );

    // On a les headers : on peut annuler pour éviter de lire le flux
    token.cancel('probe done');

    // Ex: "bytes 0-0/123456"
    final cr = resp.headers.value('content-range');
    if (cr != null && cr.contains('/')) {
      final totalStr = cr.split('/').last.trim();
      final total = int.tryParse(totalStr);
      if (total != null && total > 0) return total;
    }

    // Certains serveurs renvoient aussi un Content-Length exploitable ici
    final cl = resp.headers.value('content-length');
    if (cl != null) {
      final n = int.tryParse(cl);
      if (n != null && n > 0) return n;
    }
  } catch (_) {
    // inconnu
  }

  return null; // taille inconnue
}

/// 🚀 Vérifie la taille et les permissions avant téléchargement
Future<void> verifierEtTelecharger(String url, BuildContext context) async {
  final dio = await buildDio(url);
  try {
    final contentLength = await probeContentLength(dio, url) ?? 0;
    final sizeFormatted = contentLength > 0 ? formatFileSize(contentLength) : "taille inconnue";

    if (!context.mounted) return; // Sécurité
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
      if (!context.mounted) return; // Sécurité
      await telechargerFichierVideo(url, context, totalSize: contentLength > 0 ? contentLength : null);
    } else {
      if (!context.mounted) return; // Sécurité
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("❌ Téléchargement annulé")),
      );
    }
  } catch (e) {
    if (!context.mounted) return; // Sécurité
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("❌ Erreur de vérification : $e")),
    );
  }
}

/// 📥 Téléchargement vidéo
Future<void> telechargerFichierVideo(String url, BuildContext context,
    {int? totalSize}) async {
  Dio dio = await buildDio(url);

  final rawFileName = Uri.parse(url).pathSegments.last;
  final fileName = sanitizeFilename(rawFileName);
  final savePath = "${await _getTempDirectory()}/$fileName";

  bool isDownloadComplete = false;
  bool isCancelled = false;
  bool started = false;
  List<Map<String, dynamic>> logs = [];
  final scrollController = ScrollController();
  final cancelToken = CancelToken();

  logs.add(
      {'message': "🚀 Lancement du téléchargement : $fileName", 'type': 'log'});
  if (totalSize != null) {
    logs.add({
      'message': "📦 Taille du fichier : ${formatFileSize(totalSize)}",
      'type': 'log'
    });
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
                scrollController
                    .jumpTo(scrollController.position.maxScrollExtent);
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
                  if (isCancelled) return;
                  final int totalBytes = totalSize ?? total;
                  if (totalBytes > 0) {
                    final progress = received / totalBytes;
                    addLog(
                      "📥 ${formatFileSize(received)} / ${formatFileSize(totalBytes)}",
                      "stats",
                      progress: progress,
                    );
                  } else {
                    // totalBytes == 0 ou -1 => taille inconnue
                    addLog("📥 ${formatFileSize(received)} / ?", "log");
                  }
                },
              );

              if (isCancelled) return;

              if (response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300) {
                // ✅ CAS DE SUCCÈS : Le téléchargement est terminé et le code HTTP est 200.
                isDownloadComplete = true;
                addLog("🪄 HTTP code : 200", "log");
                addLog("✅ Fichier téléchargé avec succès : $fileName", "log");

                // Tentative de copie vers la galerie (MediaStore)
                try {
                  final ms = MediaStore();
                  await ms.saveFile(
                    tempFilePath: savePath,
                    dirType: DirType.video,
                    dirName: DirName.movies,
                    relativePath: "IPtvFlux",
                  );
                  addLog("🎬 Copié dans la galerie (Movies/IPtvFlux)", "log");
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

                // Affichage du message de succès
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("✅ Fichier enregistré : $fileName")),
                  );
                }
              } else {
                // ❌ CAS D'ERREUR HTTP : Le téléchargement s'est terminé mais avec un code d'erreur (ex: 403, 404).
                // On lance une exception pour que le bloc 'catch' général la traite.
                throw Exception("Échec avec le code HTTP ${response.statusCode}");
              }
              // --- Fin de la logique refactorisée ---

            } catch (e) {
              // --- Début de la gestion d'erreur centralisée ---

              // On gère TOUTES les erreurs ici (annulation, erreur réseau, erreur HTTP, etc.).
              final file = File(savePath);
              if (await file.exists()) {
                try {
                  await file.delete();
                  addLog("🗑️ Fichier partiel supprimé.", "log");

                  // ✅ NOUVEAU : On notifie l'utilisateur que le fichier incomplet a été supprimé.
                  // Ligne correcte
                  if (context.mounted && !(e is DioException && e.type == DioExceptionType.cancel)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("❌ Échec, le fichier partiel a été supprimé.")),
                    );
                  }

                } catch (deleteError) {
                  addLog("⚠️ Impossible de supprimer le fichier partiel : $deleteError", "error");
                }
              }

              // Ensuite, on identifie et on affiche le type d'erreur dans les logs du terminal.
              if (e is DioException && e.type == DioExceptionType.cancel) {
                addLog("⏹️ Téléchargement annulé par l’utilisateur", "error");
              } else if (e is DioException) {
                addLog("⚠️ Erreur réseau : ${e.message}", "error");
              } else {
                addLog("❌ Erreur : $e", "error");
              }
            }
          }

          // ✅ on lance le download une seule fois
          if (!started) {
            started = true;
            Future.microtask(startDownload);
          }

          return AlertDialog(
            backgroundColor: Colors.black,
            title: Text(
              isDownloadComplete
                  ? "✅ Téléchargement terminé"
                  : "🎬 Téléchargement",
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
