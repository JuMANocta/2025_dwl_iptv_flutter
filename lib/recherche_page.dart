import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'screens/settings/accounts_screen.dart';
import 'services/iptv_account_service.dart';
import 'services/playlist_service.dart';
import 'telechargement_fichier.dart';

//############################################################################
// WIDGET "CONTENEUR" PRINCIPAL (RecherchePage)
//############################################################################

class RecherchePage extends StatefulWidget {
  const RecherchePage({super.key});

  @override
  State<RecherchePage> createState() => _RecherchePageState();
}

class _RecherchePageState extends State<RecherchePage> {
  late Future<String> _playlistPathFuture;
  String? _currentAccountLabel;

  @override
  void initState() {
    super.initState();
    _loadPlaylistPath();
  }

  void _loadPlaylistPath() {
    setState(() {
      _playlistPathFuture = PlaylistService.getOrDownloadPlaylist();
      IptvAccountService.getCurrentAccount().then((acc) {
        if (mounted) setState(() => _currentAccountLabel = acc?.label);
      });
    });
  }

  void _forceReload() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("🔄 Forçage du rechargement de la playlist...")),
    );
    await PlaylistService.deleteExisting();
    _loadPlaylistPath();
  }

  Future<void> _openSettings() async {
    final dynamic result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AccountsScreen()),
    );
    if (result == true) {
      _forceReload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentAccountLabel ?? "IPtvFlux"),
        actions: [
          IconButton(
            tooltip: 'Recharger la playlist',
            icon: const Icon(Icons.refresh),
            onPressed: _forceReload,
          ),
          IconButton(
            tooltip: 'Comptes et Paramètres',
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: FutureBuilder<String>(
        future: _playlistPathFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    const Text("Impossible de charger la playlist", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18), textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text(snapshot.error.toString(), textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    FilledButton.icon(onPressed: _forceReload, icon: const Icon(Icons.refresh), label: const Text("Réessayer")),
                  ],
                ),
              ),
            );
          }
          final playlistPath = snapshot.data!;
          return RechercheM3U(filePath: playlistPath);
        },
      ),
    );
  }
}

//############################################################################
// WIDGET D'UI POUR LA RECHERCHE (RechercheM3U)
//############################################################################

class M3uEntry {
  final String nom;
  final String url;
  final bool isSerie;
  final String? saison;
  final String? episode;

  M3uEntry({required this.nom, required this.url, this.isSerie = false, this.saison, this.episode});
}

class RechercheM3U extends StatefulWidget {
  final String filePath;
  const RechercheM3U({super.key, required this.filePath});

  @override
  State<RechercheM3U> createState() => _RechercheM3UState();
}

class _RechercheM3UState extends State<RechercheM3U> {
  bool _showFilms = true;
  bool _showSeries = true;
  bool _showTv = false;
  List<M3uEntry> _allEntries = [];
  Map<String, Map<String, List<M3uEntry>>> _groupedSeries = {};
  Map<String, List<M3uEntry>> _groupedFilms = {};
  String _searchQuery = "";
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadM3U();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadM3U() async {
    setState(() => _isLoading = true);
    try {
      final file = File(widget.filePath);
      if (!await file.exists()) throw Exception("Fichier de playlist non trouvé : ${widget.filePath}");
      final content = await file.readAsString(encoding: utf8);
      final lines = LineSplitter.split(content).toList();
      List<M3uEntry> parsed = [];
      for (int i = 0; i < lines.length - 1; i++) {
        final line = lines[i].trim();
        if (line.startsWith("#EXTINF")) {
          final title = line.split(',').last.trim();
          final url = lines[i + 1].trim();
          if (url.isEmpty || !url.startsWith('http')) continue;
          final isSerie = RegExp(r"S\d{2} E\d{2}", caseSensitive: false).hasMatch(title);
          String? saison, episode;
          if (isSerie) {
            final match = RegExp(r"S(\d{2}) E(\d{2})", caseSensitive: false).firstMatch(title);
            if (match != null) {
              saison = match.group(1);
              episode = match.group(2);
            }
          }
          parsed.add(M3uEntry(nom: title, url: url, isSerie: isSerie, saison: saison, episode: episode));
        }
      }
      setState(() {
        _allEntries = parsed;
        _isLoading = false;
        _filterAndGroupResults();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Erreur parsing M3U: $e")));
      setState(() => _isLoading = false);
    }
  }

  String _getBaseName(String title) {
    String name = title.split(RegExp(r"S\d{2} E\d{2}", caseSensitive: false)).first;
    name = name.replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '');
    name = name.replaceAll(RegExp(r'\b(FHD|UHD|4K|2160p|1080p|720p|480p|SD|HDR10\+?|HDR|MULTI|VOSTFR|VF|VO|VFF|TRUEFRENCH|TRUEHD|DTS|ATMOS|FR|ENG)\b', caseSensitive: false), '');
    return name.trim().replaceAll(RegExp(r'[-_.|]'), ' ').replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Retourne le nom de l'épisode SANS le numéro SxxExx.
  String _getEpisodeName(M3uEntry entry) {
    // Sépare le titre en deux parties au niveau de "SxxExx"
    final parts = entry.nom.split(RegExp(r"S\d{2}\s*E\d{2}", caseSensitive: false));
    if (parts.length > 1) {
      // La deuxième partie contient le nom de l'épisode (s'il existe)
      final episodeTitle = parts[1].trim();
      if (episodeTitle.isNotEmpty) {
        return episodeTitle;
      }
    }
    // S'il n'y a pas de titre d'épisode, on retourne le nom de la série
    return _getBaseName(entry.nom);
  }

  /// Crée un tag (Chip) pour le numéro de l'épisode.
  Widget _getEpisodeChip(M3uEntry ep) {
    if (ep.saison != null && ep.episode != null) {
      return _chip("S${ep.saison}E${ep.episode}", Colors.purple);
    }
    return const SizedBox.shrink();
  }


  void _filterAndGroupResults() {
    final query = _searchQuery.toLowerCase();
    final filtered = _allEntries.where((entry) {
      final url = entry.url.toLowerCase();
      bool isAllowed = (_showFilms && url.contains('/movie/')) || (_showSeries && url.contains('/series/')) || (_showTv && !url.contains('/movie/') && !url.contains('/series/'));
      return entry.nom.toLowerCase().contains(query) && isAllowed;
    }).toList();

    final Map<String, Map<String, List<M3uEntry>>> tempGroupedSeries = {};
    for (var entry in filtered.where((e) => e.isSerie)) {
      final baseName = _getBaseName(entry.nom);
      final seasonLabel = entry.saison != null ? "Saison ${entry.saison}" : "Autre";

      tempGroupedSeries.putIfAbsent(baseName, () => {});
      tempGroupedSeries[baseName]!.putIfAbsent(seasonLabel, () => []).add(entry);
    }

    tempGroupedSeries.forEach((_, seasons) {
      seasons.forEach((_, episodes) {
        episodes.sort((a, b) => a.nom.compareTo(b.nom));
      });
    });

    final Map<String, List<M3uEntry>> tempGroupedFilms = {};
    for (var entry in filtered.where((e) => !e.isSerie && e.url.contains('/movie/'))) {
      final baseName = _getBaseName(entry.nom);
      tempGroupedFilms.putIfAbsent(baseName, () => []).add(entry);
    }

    int qualityRank(String title) {
      final lower = title.toLowerCase();
      if (lower.contains("4k") || lower.contains("2160p")) return 1;
      if (lower.contains("fhd") || lower.contains("1080p")) return 2;
      if (lower.contains("hd") || lower.contains("720p")) return 3;
      if (lower.contains("sd") || lower.contains("480p")) return 4;
      return 99;
    }
    tempGroupedFilms.updateAll((key, films) {
      films.sort((a, b) => qualityRank(a.nom).compareTo(qualityRank(b.nom)));
      return films;
    });

    setState(() {
      _groupedSeries = tempGroupedSeries;
      _groupedFilms = tempGroupedFilms;
    });
  }

  Widget _getQualityChip(String title) {
    final lower = title.toLowerCase();
    if (lower.contains("4k") || lower.contains("2160p")) return _chip("4K", Colors.blueAccent);
    if (lower.contains("fhd") || lower.contains("1080p")) return _chip("FHD", Colors.green);
    if (lower.contains("hd") || lower.contains("720p")) return _chip("HD", Colors.orange);
    if (lower.contains("sd") || lower.contains("480p")) return _chip("SD", Colors.redAccent);
    return const SizedBox.shrink();
  }

  List<Widget> _getLanguageChips(String title) {
    final lower = title.toLowerCase();
    List<Widget> chips = [];
    if (lower.contains("multi")) chips.add(_chip("MULTI", Colors.teal));
    else if (lower.contains("vostfr")) chips.add(_chip("VOSTFR", Colors.deepOrange));
    else if (lower.contains("vf") || lower.contains("truefrench") || lower.contains("vff")) chips.add(_chip("VF", Colors.indigo));
    else if (lower.contains("vo")) chips.add(_chip("VO", Colors.brown));
    else if (lower.contains("fr")) chips.add(_chip("VF", Colors.indigo));
    return chips;
  }

  Widget _chip(String label, Color color) {
    return Chip(label: Text(label, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: color, visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap);
  }

  void _onEntrySelected(M3uEntry entry) => verifierEtTelecharger(url: entry.url, nom: entry.nom, context: context);

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(height: 16), Text("Analyse de la playlist...")]));
    return Column(children: [
      SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(8.0), child: Row(children: [
        FilterChip(label: const Text('🎬 Films'), selected: _showFilms, onSelected: (val) => setState(() { _showFilms = val; _filterAndGroupResults(); })),
        const SizedBox(width: 8),
        FilterChip(label: const Text('📺 Séries'), selected: _showSeries, onSelected: (val) => setState(() { _showSeries = val; _filterAndGroupResults(); })),
        const SizedBox(width: 8),
        FilterChip(label: const Text('📡 TV'), selected: _showTv, onSelected: (val) => setState(() { _showTv = val; _filterAndGroupResults(); })),
      ])),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 8.0), child: TextField(controller: _searchController, decoration: InputDecoration(labelText: 'Rechercher...', prefixIcon: const Icon(Icons.search), border: const OutlineInputBorder(), suffixIcon: _searchQuery.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); FocusScope.of(context).unfocus(); setState((){ _searchQuery = ""; _filterAndGroupResults(); }); }) : null), onChanged: (q) => setState(() { _searchQuery = q; _filterAndGroupResults(); }))),
      Expanded(child: (_groupedFilms.isEmpty && _groupedSeries.isEmpty && _searchQuery.isNotEmpty) ? const Center(child: Text('🔎 Aucun résultat trouvé')) : ListView(
        children: [
          ..._groupedSeries.entries.map((seriesEntry) {
            return ExpansionTile(
              leading: const Text("📺", style: TextStyle(fontSize: 24)),
              title: Text(seriesEntry.key, style: const TextStyle(fontWeight: FontWeight.bold)),
              children: seriesEntry.value.entries.map((seasonEntry) {
                final representativeEpisodeName = seasonEntry.value.first.nom;
                return ExpansionTile(
                  title: Padding(
                    padding: const EdgeInsets.only(left: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(seasonEntry.key),
                        Wrap(
                          spacing: 4,
                          children: [
                            ..._getLanguageChips(representativeEpisodeName),
                            _getQualityChip(representativeEpisodeName),
                          ],
                        )
                      ],
                    ),
                  ),
                  children: seasonEntry.value.map((ep) => ListTile(
                    title: Padding(
                      padding: const EdgeInsets.only(left: 32.0),
                      child: Text(_getEpisodeName(ep)), // Titre nettoyé
                    ),
                    // Le trailing affiche maintenant le tag de l'épisode
                    trailing: _getEpisodeChip(ep),
                    onTap: () => _onEntrySelected(ep),
                  )).toList(),
                );
              }).toList(),
            );
          }),
          ..._groupedFilms.entries.map((entry) {
            if (entry.value.length == 1) {
              final film = entry.value.first;
              return ListTile(leading: const Padding(padding: EdgeInsets.only(left: 8.0), child: Text("🎬", style: TextStyle(fontSize: 24))), title: Text(entry.key), trailing: Wrap(spacing: 4, runSpacing: 4, children: [_getQualityChip(film.nom), ..._getLanguageChips(film.nom)]), onTap: () => _onEntrySelected(film));
            }
            return ExpansionTile(leading: const Text("🎬", style: TextStyle(fontSize: 24)), title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold)), children: entry.value.map((film) => ListTile(title: Text(film.nom.split(entry.key).last.trim()), trailing: Wrap(spacing: 4, runSpacing: 4, children: [_getQualityChip(film.nom), ..._getLanguageChips(film.nom)]), onTap: () => _onEntrySelected(film))).toList());
          }),
        ],
      )),
    ]);
  }
}
