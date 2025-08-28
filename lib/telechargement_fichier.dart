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

/// 🔄 Rafraîchit les cookies à partir du m3u
Future<void> refreshCookies() async {
  final storage = SecureStorageService();
  final creds = await storage.getCredentials();
  String? completeUrl = creds["completeUrl"];
  String? baseUrl = creds["baseUrl"];
  String? login = creds["login"];
  String? password = creds["password"];

  final url = completeUrl?.isNotEmpty == true
      ? completeUrl!
      : "$baseUrl?username=$login&password=$password&type=m3u&output=ts";

  final dio = Dio();
  (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
    final client = HttpClient();
    client.badCertificateCallback = (cert, host, port) => true;
    return client;
  };

  try {
    final response = await dio.get(url,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
        ));

    final cookies = response.headers['set-cookie'];
    if (cookies != null && cookies.isNotEmpty) {
      final cookieString = cookies.join("; ");
      await storage.saveCredentials({"cookies": cookieString});
      debugPrint("🍪 Cookies rafraîchis : $cookieString");
    } else {
      debugPrint("⚠️ Aucun cookie trouvé lors du refresh");
    }
  } catch (e) {
    debugPrint("❌ Erreur refreshCookies : $e");
  }
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

/// 📥 Téléchargement vidéo avec auto-refresh cookies
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

  int maxRetries = 3;
  int attempt = 0;

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
          void addLog(String msg, String type) {
            if (type == "stats" && logs.isNotEmpty && logs.last["type"] == "stats") {
              // ⚡️ on remplace la dernière ligne si c'est déjà une progression
              logs[logs.length - 1] = {"message": msg, "type": type};
            } else {
              // sinon on ajoute une nouvelle ligne (erreur, info, etc.)
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
            while (attempt < maxRetries &&
                !isDownloadComplete &&
                !isCancelled) {
              try {
                attempt++;
                final file = File(savePath);
                int downloadedLength = 0;
                if (await file.exists()) {
                  downloadedLength = await file.length();
                  addLog("⏩ Reprise à ${formatFileSize(downloadedLength)}", "log");
                }

                final response = await dio.download(
                  url,
                  savePath,
                  cancelToken: cancelToken,
                  options: Options(
                    headers: {
                      if (downloadedLength > 0) "Range": "bytes=$downloadedLength-",
                    },
                  ),
                  onReceiveProgress: (received, total) {
                    final totalBytes = totalSize ?? total;
                    if (totalBytes > 0) {
                      final downloaded = received + downloadedLength;
                      final progress =
                      (downloaded / totalBytes * 100).toStringAsFixed(1);
                      addLog("📥 ${formatFileSize(downloaded)} / ${formatFileSize(totalBytes)} ($progress%)", "stats");
                    }
                  },
                );

                addLog("⚠️ HTTP code : ${response.statusCode}", "log");

                if (response.statusCode == 200 || response.statusCode == 206) {
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
                  final statusCode = e.response?.statusCode;
                  addLog("⚠️ Erreur HTTP $statusCode : ${e.message}", "error");
                  print("❌ DioException: ${e.message}");

                  if (statusCode == 461 || statusCode == 403) {
                    addLog("🔄 Cookies expirés → rafraîchissement...", "log");
                    await refreshCookies();
                    dio = await buildDio(url); // recharger avec nouveaux cookies
                    continue; // retry immédiat
                  }
                } else {
                  addLog("❌ Erreur : $e", "error");
                }

                if (attempt >= maxRetries) {
                  addLog("❌ Abandon après $maxRetries tentatives", "error");
                }
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
