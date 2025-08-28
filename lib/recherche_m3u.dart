import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'telechargement_fichier.dart';

class FilmEntry {
  final String nom;
  final String url;
  final bool isSerie;
  final String? saison;
  final String? episode;

  FilmEntry({
    required this.nom,
    required this.url,
    this.isSerie = false,
    this.saison,
    this.episode,
  });
}

class RechercheM3U extends StatefulWidget {
  final String filePath;
  final void Function(FilmEntry entry) onDownloadSelected;

  const RechercheM3U({
    super.key,
    required this.filePath,
    required this.onDownloadSelected,
  });

  @override
  State<RechercheM3U> createState() => _RechercheM3UState();
}

class _RechercheM3UState extends State<RechercheM3U> {
  bool _showFilms = true;
  bool _showSeries = true;
  bool _showTv = false;
  List<FilmEntry> _entries = [];
  Map<String, List<FilmEntry>> _groupedSeries = {};
  Map<String, List<FilmEntry>> _groupedFilms = {};
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _loadM3U();
  }

  Future<void> _loadM3U() async {
    final file = File(widget.filePath);
    if (!await file.exists()) return;
    final content = await file.readAsString(encoding: utf8);
    final lines = LineSplitter.split(content).toList();

    List<FilmEntry> parsed = [];

    for (int i = 0; i < lines.length - 1; i++) {
      final line = lines[i].trim();
      if (line.startsWith("#EXTINF")) {
        final title = line.split(',').last.trim();
        final url = lines[i + 1].trim();

        final isSerie =
        RegExp(r"S\d{2} E\d{2}", caseSensitive: false).hasMatch(title);
        String? saison;
        String? episode;

        if (isSerie) {
          final match = RegExp(r"S(\d{2}) E(\d{2})", caseSensitive: false)
              .firstMatch(title);
          if (match != null) {
            saison = match.group(1);
            episode = match.group(2);
          }
        }

        parsed.add(FilmEntry(
          nom: title,
          url: url,
          isSerie: isSerie,
          saison: saison,
          episode: episode,
        ));
      }
    }

    setState(() {
      _entries = parsed;
      _filterResults(_searchQuery);
    });
  }

  /// 🔧 Nettoie le titre d’un film pour créer un nom de groupe (sans qualité)
  String cleanBaseName(String title) {
    var name = title;

    // Supprimer tout ce qui est entre parenthèses
    name = name.replaceAll(RegExp(r'\(.*?\)', caseSensitive: false), '');

    // Supprimer les tags qualité + audio fréquemment utilisés
    name = name.replaceAll(
      RegExp(
          r'FHD|UHD|4K|2160p|1080p|720p|480p|SD|HDR10\+?|HDR|MULTI|VOSTFR|VF|VO|TRUEHD|DTS|ATMOS|FR',
          caseSensitive: false),
      '',
    );

    // Nettoyer les espaces multiples
    return name.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  void _filterResults(String query) {
    final isAllowed = (FilmEntry entry) {
      if (entry.url.contains('/series/')) return _showSeries;
      if (entry.url.contains('/movie/')) return _showFilms;
      return _showTv;
    };
    query = query.toLowerCase();
    final filtered = _entries
        .where((entry) =>
    entry.nom.toLowerCase().contains(query) && isAllowed(entry))
        .toList();

    // --- Grouper les séries par saisons ---
    final Map<String, List<FilmEntry>> groupedSeries = {};
    for (var entry in filtered) {
      if (entry.isSerie) {
        final baseName =
        entry.nom.split(RegExp(r"S\d{2} E\d{2}")).first.trim();
        final saisonLabel =
        entry.saison != null ? "📺 Saison ${entry.saison}" : "📺 Autre";
        final groupKey = "$baseName - $saisonLabel";
        groupedSeries.putIfAbsent(groupKey, () => []).add(entry);
      }
    }

    // --- Grouper les films par baseName nettoyé ---
    final Map<String, List<FilmEntry>> groupedFilms = {};
    for (var entry in filtered.where((e) => !e.isSerie)) {
      final baseName = cleanBaseName(entry.nom);
      groupedFilms.putIfAbsent(baseName, () => []).add(entry);
    }

    // --- Trier les films par qualité ---
    int qualityRank(String title) {
      final lower = title.toLowerCase();
      if (lower.contains("4k") || lower.contains("2160p")) return 1;
      if (lower.contains("fhd") || lower.contains("1080p")) return 2;
      if (lower.contains("hd") || lower.contains("720p")) return 3;
      if (lower.contains("sd") || lower.contains("480p")) return 4;
      return 99;
    }

    groupedFilms.updateAll((key, films) {
      films.sort((a, b) => qualityRank(a.nom).compareTo(qualityRank(b.nom)));
      return films;
    });

    setState(() {
      _groupedSeries = groupedSeries;
      _groupedFilms = groupedFilms;
      _searchQuery = query;
    });
  }

  /// 🔧 Crée un Chip de qualité
  Widget getQualityChip(String title) {
    final lower = title.toLowerCase();
    if (lower.contains("4k") || lower.contains("2160p")) {
      return const Chip(
          label: Text("4K"),
          backgroundColor: Colors.blueAccent,
          labelStyle: TextStyle(color: Colors.white));
    } else if (lower.contains("fhd") || lower.contains("1080p")) {
      return const Chip(
          label: Text("FHD"),
          backgroundColor: Colors.green,
          labelStyle: TextStyle(color: Colors.white));
    } else if (lower.contains("hd") || lower.contains("720p")) {
      return const Chip(
          label: Text("HD"),
          backgroundColor: Colors.orange,
          labelStyle: TextStyle(color: Colors.white));
    } else if (lower.contains("sd") || lower.contains("480p")) {
      return const Chip(
          label: Text("SD"),
          backgroundColor: Colors.redAccent,
          labelStyle: TextStyle(color: Colors.white));
    }
    return const Chip(
        label: Text("?"),
        backgroundColor: Colors.grey,
        labelStyle: TextStyle(color: Colors.white));
  }

  void _onEntrySelected(FilmEntry entry) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("📥 URL détectée : ${entry.url} 🌐")),
    );
    telechargerFichierVideo(entry.url, context);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // --- Filtres ---
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('🎬 Films'),
                selected: _showFilms,
                onSelected: (val) => setState(() {
                  _showFilms = val;
                  _filterResults(_searchQuery);
                }),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('📺 Séries'),
                selected: _showSeries,
                onSelected: (val) => setState(() {
                  _showSeries = val;
                  _filterResults(_searchQuery);
                }),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('📡 TV'),
                selected: _showTv,
                onSelected: (val) => setState(() {
                  _showTv = val;
                  _filterResults(_searchQuery);
                }),
              ),
            ],
          ),
        ),

        // --- Barre de recherche ---
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Rechercher un film ou une série',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: _filterResults,
          ),
        ),
        const SizedBox(height: 8),

        // --- Résultats ---
        Expanded(
          child: (_groupedFilms.isEmpty && _groupedSeries.isEmpty)
              ? const Center(child: Text('🔎 Aucun résultat trouvé'))
              : ListView(
            children: [
              // Séries regroupées
              ..._groupedSeries.entries.map((entry) => ExpansionTile(
                title: Text(entry.key,
                    style:
                    const TextStyle(fontWeight: FontWeight.bold)),
                children: entry.value
                    .map((ep) => ListTile(
                  title: Text(
                      "🎞️ Épisode ${ep.episode} - ${ep.nom}"),
                  subtitle: Text(ep.url,
                      style:
                      const TextStyle(fontSize: 12)),
                  onTap: () => _onEntrySelected(ep),
                  trailing: const Icon(Icons.download),
                ))
                    .toList(),
              )),

              // Films regroupés
              ..._groupedFilms.entries.map((entry) => ExpansionTile(
                title: Text("🎬 ${entry.key}",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold)),
                children: entry.value
                    .map((film) => ListTile(
                  title: Text(film.nom),
                  subtitle: Text(film.url,
                      style:
                      const TextStyle(fontSize: 12)),
                  onTap: () => _onEntrySelected(film),
                  trailing: getQualityChip(film.nom),
                ))
                    .toList(),
              )),
            ],
          ),
        ),
      ],
    );
  }
}
