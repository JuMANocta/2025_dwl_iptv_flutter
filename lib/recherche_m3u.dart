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
  Map<String, Map<String, List<FilmEntry>>> _groupedSeries = {};
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

  /// 🔧 Nettoie le titre pour grouper films/séries
  String cleanBaseName(String title) {
    var name = title;

    name = name.replaceAll(RegExp(r'\(.*?\)', caseSensitive: false), '');
    name = name.replaceAll(
      RegExp(
        r'FHD|UHD|4K|2160p|1080p|720p|480p|SD|HDR10\+?|HDR|MULTI|VOSTFR|VF|VO|TRUEHD|DTS|ATMOS|FR',
        caseSensitive: false,
      ),
      '',
    );
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

    // --- Séries : Série > Saison > Épisodes ---
    final Map<String, Map<String, List<FilmEntry>>> groupedSeries = {};
    for (var entry in filtered.where((e) => e.isSerie)) {
      final seriesName =
      entry.nom.split(RegExp(r"S\d{2} E\d{2}")).first.trim();
      final saisonLabel =
      entry.saison != null ? "Saison ${entry.saison}" : "Autre";

      groupedSeries.putIfAbsent(seriesName, () => {});
      groupedSeries[seriesName]!.putIfAbsent(saisonLabel, () => []);
      groupedSeries[seriesName]![saisonLabel]!.add(entry);
    }

    // --- Films regroupés ---
    final Map<String, List<FilmEntry>> groupedFilms = {};
    for (var entry in filtered.where((e) => !e.isSerie)) {
      final baseName = cleanBaseName(entry.nom);
      groupedFilms.putIfAbsent(baseName, () => []).add(entry);
    }

    // --- Trier films par qualité ---
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
      _groupedSeries = groupedSeries; // ✅ type correct
      _groupedFilms = groupedFilms;   // ✅ type correct
      _searchQuery = query;
    });
  }

  /// 🔧 Badge qualité films
  Widget getQualityChip(String title) {
    final lower = title.toLowerCase();
    if (lower.contains("4k") || lower.contains("2160p")) {
      return _chip("4K", Colors.blueAccent);
    } else if (lower.contains("fhd") || lower.contains("1080p")) {
      return _chip("FHD", Colors.green);
    } else if (lower.contains("hd") || lower.contains("720p")) {
      return _chip("HD", Colors.orange);
    } else if (lower.contains("sd") || lower.contains("480p")) {
      return _chip("SD", Colors.redAccent);
    }
    return _chip("?", Colors.grey);
  }

  /// 🔧 Badge épisode séries
  Widget getEpisodeChip(FilmEntry ep) {
    if (ep.saison != null && ep.episode != null) {
      return _chip("S${ep.saison}E${ep.episode}", Colors.purple);
    }
    return const SizedBox.shrink();
  }

  /// 🔧 Badges langue
  List<Widget> getLanguageChips(String title) {
    final lower = title.toLowerCase();
    List<Widget> chips = [];
    if (lower.contains("multi")) chips.add(_chip("MULTI", Colors.teal));
    if (lower.contains("vostfr")) chips.add(_chip("VOSTFR", Colors.deepOrange));
    if (lower.contains("vf")) chips.add(_chip("VF", Colors.indigo));
    if (lower.contains("vo")) chips.add(_chip("VO", Colors.brown));
    return chips;
  }

  /// 🔧 Fabrique un Chip
  Widget _chip(String label, Color color) {
    return Chip(
      label: Text(label),
      backgroundColor: color,
      labelStyle: const TextStyle(color: Colors.white),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
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
            children: [
              FilterChip(
                label: const Text('🎬 Films'),
                selected: _showFilms,
                onSelected: (val) {
                  setState(() {
                    _showFilms = val;
                    _filterResults(_searchQuery);
                  });
                },
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('📺 Séries'),
                selected: _showSeries,
                onSelected: (val) {
                  setState(() {
                    _showSeries = val;
                    _filterResults(_searchQuery);
                  });
                },
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('📡 TV'),
                selected: _showTv,
                onSelected: (val) {
                  setState(() {
                    _showTv = val;
                    _filterResults(_searchQuery);
                  });
                },
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

        // --- Résultats ---
        Expanded(
          child: (_groupedFilms.isEmpty && _groupedSeries.isEmpty)
              ? const Center(child: Text('🔎 Aucun résultat trouvé'))
              : ListView(
            children: [
              // Séries
              ..._groupedSeries.entries.map((seriesEntry) => ExpansionTile(
                title: Text("📺 ${seriesEntry.key}",
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                children: seriesEntry.value.entries.map((seasonEntry) =>
                    ExpansionTile(
                      title: Text(seasonEntry.key),
                      children: seasonEntry.value.map((ep) => ListTile(
                        title: Text(ep.nom),
                        subtitle: Text(ep.url, style: const TextStyle(fontSize: 12)),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            getEpisodeChip(ep),
                            ...getLanguageChips(ep.nom),
                          ],
                        ),
                        onTap: () => _onEntrySelected(ep),
                      )).toList(),
                    )).toList(),
              )),

              // Films
              ..._groupedFilms.entries.map((entry) => ExpansionTile(
                title: Text("🎬 ${entry.key}",
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                children: entry.value.map((film) => ListTile(
                  title: Text(film.nom),
                  subtitle: Text(film.url,
                      style: const TextStyle(fontSize: 12)),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      getQualityChip(film.nom),
                      ...getLanguageChips(film.nom),
                    ],
                  ),
                  onTap: () => _onEntrySelected(film),
                )).toList(),
              )),
            ],
          ),
        ),
      ],
    );
  }
}
