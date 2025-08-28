import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'ffmpeg_loader.dart';

Future<String> _getDownloadDirectory() async {
  final directory = await getExternalStorageDirectory();
  if (directory == null) {
    throw Exception("📁 Impossible d'accéder au répertoire de téléchargement.");
  }
  final downloadDir = Directory("${directory.path}/Videos");
  if (!await downloadDir.exists()) {
    await downloadDir.create(recursive: true);
  }
  return downloadDir.path;
}

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
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
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

Future<void> telechargerFichierVideo(String url, BuildContext context) async {
  final fileName = Uri.parse(url).pathSegments.last;
  final savePath = "${await _getDownloadDirectory()}/$fileName";
  final ffmpegPath = await FFmpegLoader.prepareFFmpeg(context);

  bool isDownloadComplete = false;
  bool isCancelled = false;
  List<Map<String, dynamic>> logs = [];
  final scrollController = ScrollController();
  final logStream = StreamController<void>();

  print("🛰️ Lancement de FFmpeg pour : $url");
  print("📂 Destination : $savePath");
  print("🔧 Binaire FFmpeg utilisé : $ffmpegPath");

  final command = ['-user_agent', 'Mozilla/5.0', '-i', url, '-c', 'copy', '-bsf:a', 'aac_adtstoasc', savePath];

  final process = await Process.start(ffmpegPath, command);

  process.stdout.transform(utf8.decoder).listen((data) {
    logs.add({'message': data.trim(), 'type': 'log'});
    logStream.add(null);
  });

  process.stderr.transform(utf8.decoder).listen((data) {
    logs.add({'message': data.trim(), 'type': 'error'});
    logStream.add(null);
  });

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
                scrollController.jumpTo(scrollController.position.maxScrollExtent);
              }
            });
          });

          return AlertDialog(
            backgroundColor: Colors.black,
            title: Text(
              isDownloadComplete ? "✅ Téléchargement terminé" : "🎬 Téléchargement via FFmpeg...",
              style: const TextStyle(color: Colors.greenAccent, fontFamily: 'Courier New'),
            ),
            content: Stack(
              children: [
                SizedBox(
                  width: double.maxFinite,
                  height: 300,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
                              BoxShadow(color: Colors.greenAccent.withOpacity(0.3), blurRadius: 5)
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
                    process.kill();
                    Navigator.of(context).pop();
                  },
                  child: const Text("❌ Annuler", style: TextStyle(color: Colors.redAccent)),
                ),
              if (isDownloadComplete)
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text("✅ Terminer", style: TextStyle(color: Colors.greenAccent)),
                ),
            ],
          );
        },
      );
    },
  ));

  final exitCode = await process.exitCode;

  isDownloadComplete = exitCode == 0;
  logStream.add(null);

  if (isDownloadComplete) {
    print("✅ Fichier téléchargé : $savePath");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("✅ Fichier enregistré : $fileName")),
    );
  } else {
    logs.add({'message': "❌ FFmpeg a échoué avec le code $exitCode", 'type': 'error'});
    logStream.add(null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("❌ Échec du téléchargement (code exitCode)")),
    );
  }

  await Future.delayed(const Duration(seconds: 1));
  logStream.close();
}