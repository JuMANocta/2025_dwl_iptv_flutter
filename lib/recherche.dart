import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'telechargement_liste.dart';
import 'recherche_m3u.dart';

class Recherche extends StatefulWidget {
  const Recherche({super.key});

  @override
  _RechercheState createState() => _RechercheState();
}

class _RechercheState extends State<Recherche> {
  String _filePath = "";
  bool _fileExists = false;

  @override
  void initState() {
    super.initState();
    _initializeFile();
  }

  Future<void> _initializeFile() async {
    Directory appDocDir = await getApplicationDocumentsDirectory();
    String filePath = "${appDocDir.path}/iptv_links.m3u";
    bool exists = await File(filePath).exists();
    setState(() {
      _filePath = filePath;
      _fileExists = exists;
    });
  }

  void _goToTelechargement() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const TelechargementPage()),
    );
    if (result == true) {
      _initializeFile(); // re-check après retour
    }
  }

  Future<void> _supprimerEtTelecharger() async {
    final file = File(_filePath);
    if (await file.exists()) {
      await file.delete();
      debugPrint("🗑️ Fichier supprimé");
    }
    setState(() {
      _fileExists = false;
    });
    _goToTelechargement();
  }

  void _onDownloadSelected(FilmEntry entry) {
    // Pour l'instant, on affiche juste un toast avec l'URL
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("📥 Téléchargement prévu pour : ${entry.url}")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Recherche IPTV")),
      body: _fileExists
          ? Column(
        children: [
          Expanded(
            child: RechercheM3U(
              filePath: _filePath,
              onDownloadSelected: _onDownloadSelected,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton.icon(
              onPressed: _supprimerEtTelecharger,
              icon: const Icon(Icons.refresh),
              label: const Text("🔄 Mettre à jour la liste IPTV"),
            ),
          ),
        ],
      )
          : Center(
        child: ElevatedButton(
          onPressed: _goToTelechargement,
          child: const Text("📥 Télécharger d'abord le fichier IPTV"),
        ),
      ),
    );
  }
}