import 'dart:io';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'secure_storage_service.dart';

class ConnectivityBanner extends StatefulWidget {
  final Widget child;
  const ConnectivityBanner({required this.child, Key? key}) : super(key: key);

  @override
  _ConnectivityBannerState createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner> {
  late StreamSubscription<List<ConnectivityResult>> _subscription;
  bool _hasInternet = true;

  @override
  void initState() {
    super.initState();
    Connectivity().checkConnectivity().then(_updateConnectionStatus);
    _subscription = Connectivity().onConnectivityChanged.listen(_updateConnectionStatus);
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
    setState(() {
      _hasInternet = !results.contains(ConnectivityResult.none);
      debugPrint("📶 État internet : $_hasInternet");
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (!_hasInternet)
        Container(color: Colors.red, padding: const EdgeInsets.all(8.0), child: const Text("Pas de connexion Internet", style: TextStyle(color: Colors.white))),
      Expanded(child: widget.child),
    ],
  );
}

class Recherche extends StatefulWidget {
  const Recherche({super.key});

  @override
  _RechercheState createState() => _RechercheState();
}

class _RechercheState extends State<Recherche> {
  final SecureStorageService _storageService = SecureStorageService();
  String _filePath = "";
  bool _fileExists = false;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _initializeFile();
  }

  Future<void> _initializeFile() async {
    Directory appDocDir = await getApplicationDocumentsDirectory();
    String filePath = "${appDocDir.path}/iptv_links.txt";
    bool exists = await File(filePath).exists();
    setState(() {
      _filePath = filePath;
      _fileExists = exists;
    });
    debugPrint("📂 Fichier existant : $_fileExists, chemin : $_filePath");
  }

  Future<String> _getDownloadUrl() async {
    var creds = await _storageService.getCredentials();
    return "${creds['baseUrl']}?username=${creds['login']}&password=${creds['password']}&type=m3u&output=ts";
  }

  Future<void> _downloadFile() async {
    String url = await _getDownloadUrl();
    setState(() => _isDownloading = true);
    try {
      await Dio().download(url, _filePath);
      debugPrint("✅ Fichier téléchargé : $_filePath");
    } catch (e) {
      debugPrint("❌ Erreur téléchargement : $e");
    } finally {
      setState(() => _isDownloading = false);
      _initializeFile();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConnectivityBanner(
      child: Scaffold(
        appBar: AppBar(title: const Text("Recherche IPTV")),
        body: Center(
          child: _isDownloading
              ? const CircularProgressIndicator()
              : ElevatedButton(
            onPressed: _downloadFile,
            child: const Text("Télécharger le fichier IPTV"),
          ),
        ),
      ),
    );
  }
}