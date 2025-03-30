import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';

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
  List<FilmEntry> _filteredFlatList = [];
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

        final isSerie = RegExp(r"S\d{2} E\d{2}", caseSensitive: false).hasMatch(title);
        String? saison;
        String? episode;

        if (isSerie) {
          final match = RegExp(r"S(\d{2}) E(\d{2})", caseSensitive: false).firstMatch(title);
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

  void _filterResults(String query) {
    final isAllowed = (FilmEntry entry) {
      if (entry.url.contains('/series/')) return _showSeries;
      if (entry.url.contains('/movie/')) return _showFilms;
      return _showTv;
    };
    query = query.toLowerCase();
    final filtered = _entries
        .where((entry) => entry.nom.toLowerCase().contains(query) && isAllowed(entry))
        .toList();

    final Map<String, List<FilmEntry>> grouped = {};
    for (var entry in filtered) {
      if (entry.isSerie) {
        final baseName = entry.nom.split(RegExp(r"S\d{2} E\d{2}")).first.trim();
        final saisonLabel = entry.saison != null ? "📺 Saison ${entry.saison}" : "📺 Autre";
        final groupKey = "$baseName - $saisonLabel";
        grouped.putIfAbsent(groupKey, () => []).add(entry);
      }
    }

    setState(() {
      _filteredFlatList = filtered.where((e) => !e.isSerie).toList();
      _groupedSeries = grouped;
      _searchQuery = query;
    });
  }

  void _onEntrySelected(FilmEntry entry) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("📥 URL détectée : ${entry.url} 🌐")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
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
        Expanded(
          child: (_filteredFlatList.isEmpty && _groupedSeries.isEmpty)
              ? const Center(child: Text('🔎 Aucun résultat trouvé'))
              : ListView(
            children: [
              ..._groupedSeries.entries.map((entry) => ExpansionTile(
                title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                children: entry.value
                    .map((ep) => ListTile(
                  title: Text("🎞️ Épisode ${ep.episode} - ${ep.nom}"),
                  subtitle: Text(ep.url, style: const TextStyle(fontSize: 12)),
                  onTap: () => _onEntrySelected(ep),
                  trailing: const Icon(Icons.download),
                ))
                    .toList(),
              )),
              ..._filteredFlatList.map((entry) => ListTile(
                title: Text("🎬 ${entry.nom}"),
                subtitle: Text(entry.url, style: const TextStyle(fontSize: 12)),
                onTap: () => _onEntrySelected(entry),
                trailing: const Icon(Icons.download),
              )),
            ],
          ),
        ),
      ],
    );
  }
}