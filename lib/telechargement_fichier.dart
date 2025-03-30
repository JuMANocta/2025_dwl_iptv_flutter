import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

Future<String> _getDownloadDirectory() async {
  final directory = await getExternalStorageDirectory();
  final downloadDir = Directory("${directory!.path}/Videos");
  if (!await downloadDir.exists()) {
    await downloadDir.create(recursive: true);
  }
  return downloadDir.path;
}

Future<void> telechargerFichierVideo(String url, BuildContext context) async {
  final fileName = Uri.parse(url).pathSegments.last;
  final savePath = "${await _getDownloadDirectory()}/$fileName";
  final dio = Dio();
  double progress = 0;
  bool isDownloadComplete = false;
  bool isCancelled = false;
  late CancelToken cancelToken;

  cancelToken = CancelToken();

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(isDownloadComplete
                ? "✅ Téléchargement terminé"
                : "⬇️ Téléchargement en cours..."),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isDownloadComplete)
                  LinearProgressIndicator(value: progress),
                SizedBox(height: 16),
                Text(isDownloadComplete
                    ? "🎉 Le fichier a été téléchargé avec succès."
                    : "📊 ${(progress * 100).toStringAsFixed(0)}%"),
              ],
            ),
            actions: [
              if (!isDownloadComplete)
                TextButton(
                  onPressed: () {
                    isCancelled = true;
                    cancelToken.cancel("Téléchargement annulé par l'utilisateur");
                    Navigator.of(context).pop();
                  },
                  child: Text("❌ Annuler"),
                ),
              if (isDownloadComplete)
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text("✅ Terminer"),
                ),
            ],
          );
        },
      );
    },
  );

  if (isCancelled) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("❌ Téléchargement annulé.")),
    );
    return;
  }

  try {
    final response = await dio.download(
      url,
      savePath,
      cancelToken: cancelToken,
      onReceiveProgress: (received, total) {
        if (total != -1) {
          progress = received / total;
          (context as Element).markNeedsBuild();
        }
      },
    );

    if (response.statusCode == 200) {
      isDownloadComplete = true;
      (context as Element).markNeedsBuild();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("✅ Fichier téléchargé dans Vidéos: $fileName")),
      );
    } else {
      throw Exception("❗ Échec du téléchargement. Statut: ${response.statusCode}");
    }
  } catch (e) {
    if (!isCancelled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Erreur: $e")),
      );
    }
  }
}