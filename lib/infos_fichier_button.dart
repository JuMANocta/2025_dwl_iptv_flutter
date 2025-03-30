import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

class InfosFichierButton extends StatelessWidget {
  final String filePath;

  const InfosFichierButton({super.key, required this.filePath});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.info_outline),
      label: const Text("Infos fichier"),
      onPressed: () async {
        final file = File(filePath);
        if (await file.exists()) {
          final content = await file.readAsString(encoding: utf8);
          final lines = LineSplitter.split(content).toList();
          final extinfLines = lines.where((line) => line.trim().startsWith("#EXTINF")).toList();
          final urls = lines.where((line) => line.startsWith("http")).toList();
          int tvCount = 0;
          int serieCount = 0;
          int filmCount = 0;

          for (int i = 0; i < extinfLines.length && i < urls.length; i++) {
            final url = urls[i];
            if (url.contains("/series/")) {
              serieCount++;
            } else if (url.contains("/movie/")) {
              filmCount++;
            } else {
              tvCount++;
            }
          }

          final fileSize = await file.length();
          final fileSizeKB = (fileSize / 1024).toStringAsFixed(2);

          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text("🔎 Info fichier M3U"),
              content: SingleChildScrollView(
                child: Text(
                  "Taille : $fileSizeKB KB\n"
                      "Nombre de lignes : ${lines.length}\n"
                      "🎬 Films : $filmCount\n"
                      "📺 Séries : $serieCount\n"
                      "📡 TV : $tvCount",
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Fermer"),
                ),
              ],
            ),
          );
        }
      },
    );
  }
}