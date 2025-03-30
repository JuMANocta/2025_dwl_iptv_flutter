import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'secure_storage_service.dart';

class TelechargementPage extends StatefulWidget {
  const TelechargementPage({super.key});

  @override
  State<TelechargementPage> createState() => _TelechargementPageState();
}

class _TelechargementPageState extends State<TelechargementPage> {
  final SecureStorageService _storageService = SecureStorageService();
  bool _isDownloading = false;
  String _filePath = "";

  Future<String> _getDownloadUrl() async {
    var creds = await _storageService.getCredentials();
    if (creds.containsKey('completeUrl') && creds['completeUrl']!.isNotEmpty) {
      return creds['completeUrl']!;
    } else {
      return "${creds['baseUrl']}?username=${creds['login']}&password=${creds['password']}&type=m3u&output=ts";
    }
  }

  Future<void> _downloadFile() async {
    Directory appDocDir = await getApplicationDocumentsDirectory();
    _filePath = "${appDocDir.path}/iptv_links.m3u";
    setState(() => _isDownloading = true);

    try {
      final dio = Dio(BaseOptions(
        headers: {'User-Agent': 'Mozilla/5.0'},
        validateStatus: (status) => status != null && status < 500,
      ));

      final url = await _getDownloadUrl();
      await dio.download(url, _filePath);
      debugPrint("✅ Téléchargement terminé");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Téléchargement terminé 🎉')),
        );
        Navigator.pop(context, true); // retour à la page précédente avec succès
      }
    } catch (e) {
      debugPrint("❌ Erreur : $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors du téléchargement : $e')),
        );
      }
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Téléchargement IPTV')),
      body: Center(
        child: _isDownloading
            ? const CircularProgressIndicator()
            : ElevatedButton(
          onPressed: _downloadFile,
          child: const Text("Télécharger le fichier IPTV"),
        ),
      ),
    );
  }
}
