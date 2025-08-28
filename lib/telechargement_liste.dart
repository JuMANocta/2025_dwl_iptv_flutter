import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
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
        headers: {
          'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
          'Accept': '*/*',
          'Connection': 'keep-alive',
        },
        validateStatus: (status) => status != null && status < 500,
      ));

      (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) => true;
        return client;
      };

      final url = await _getDownloadUrl();

      // supprimer l'ancien fichier si déjà présent
      if (await File(_filePath).exists()) {
        debugPrint("📄 Fichier existant détecté, suppression...");
        await File(_filePath).delete();
      }

      // ⚡ utilisation de get() pour pouvoir lire les headers (cookies)
      final response = await dio.get(url,
          options: Options(
            responseType: ResponseType.bytes,
            followRedirects: false,
          ));

      // sauvegarder les cookies si présents
      final cookies = response.headers['set-cookie'];
      if (cookies != null && cookies.isNotEmpty) {
        final cookieString = cookies.join("; ");
        await _storageService.saveCredentials({"cookies": cookieString});
        debugPrint("🍪 Cookies sauvegardés : $cookieString");
      }

      // écrire le fichier en local
      final file = File(_filePath);
      await file.writeAsBytes(response.data);

      debugPrint("✅ Téléchargement terminé");
      debugPrint("📥 Fichier enregistré à : $_filePath");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Playlist téléchargée 🎉')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("❌ Erreur téléchargement : $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Erreur lors du téléchargement : $e')),
        );
      }
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('📥 Téléchargement IPTV')),
      body: Center(
        child: _isDownloading
            ? const CircularProgressIndicator()
            : ElevatedButton.icon(
          onPressed: _downloadFile,
          icon: const Icon(Icons.download),
          label: const Text("⬇️ Télécharger le fichier IPTV"),
        ),
      ),
    );
  }
}
