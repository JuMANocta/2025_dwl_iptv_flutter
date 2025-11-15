import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'models/download_task.dart';
import 'screens/accounts_screen.dart';
import 'screens/downloads_page.dart';
import 'services/iptv_account_service.dart';
import 'services/playlist_service.dart';
import 'telechargement_fichier.dart';
import 'screens/player_page.dart';
import 'services/download_manager_service.dart';

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
            icon: const Icon(Icons.download),
            tooltip: 'Voir les téléchargements',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DownloadsPage()),
              );
            },
          ),
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
    _searchController.addListener(() {
      if (_searchQuery != _searchController.text) {
        setState(() {
          _searchQuery = _searchController.text;
          _filterAndGroupResults();
        });
      }
    });
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
      if (!await file.exists()) {
        throw Exception("Fichier de playlist non trouvé : ${widget.filePath}");
      }

      final fileSize = await file.length();

      if (fileSize < 10) {
        throw Exception("Le fichier est vide ou corrompu.");
      }

      final lines = await file.readAsLines(encoding: utf8);

      List<M3uEntry> parsed = [];
      final fileContent = lines.join('\n');

      // --- LOGIQUE DE SÉLECTION DU PARSER ---
      if (fileContent.contains("#EXTINF")) {
        // Parser standard (pour les listes m3u classiques)
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.startsWith("#EXTINF")) {
            final title = line.contains(',') ? line.split(',').last.trim() : '';
            if (title.isEmpty) continue;

            String? url;
            for (int j = i + 1; j < lines.length; j++) {
              final nextLine = lines[j].trim();
              if (nextLine.startsWith('http')) {
                url = nextLine;
                i = j;
                break;
              }
              if (nextLine.startsWith('#EXTINF')) break;
            }

            if (url != null) {
              parsed.add(M3uEntry(nom: title, url: url));
            }
          }
        }
      } else {
        // Parser spécial pour le format "URL #Name: Titre"
        for (final line in lines) {
          if (line.contains("#Name:")) {
            final parts = line.split("#Name:");
            final url = parts[0].trim();
            final title = parts.length > 1 ? parts[1].trim() : '';

            if (url.startsWith('http') && title.isNotEmpty) {
              parsed.add(M3uEntry(nom: title, url: url));
            }
          }
        }
      }
      // --- FIN DE LA LOGIQUE DE SÉLECTION ---


      // Le reste du code est le même, mais on adapte la logique pour les séries
      // car ce format simple ne contient probablement pas d'infos SxxExx
      for (int i=0; i < parsed.length; i++) {
        final entry = parsed[i];
        final isSerie = RegExp(r"S\d{2} E\d{2}", caseSensitive: false).hasMatch(entry.nom);
        if (isSerie) {
          final match = RegExp(r"S(\d{2}) E(\d{2})", caseSensitive: false).firstMatch(entry.nom);
          parsed[i] = M3uEntry(
            nom: entry.nom,
            url: entry.url,
            isSerie: true,
            saison: match?.group(1),
            episode: match?.group(2),
          );
        }
      }

      if (parsed.isEmpty && lines.isNotEmpty) {
        throw Exception("Format de playlist non reconnu (aucune entrée valide trouvée).");
      }

      setState(() {
        _allEntries = parsed;
        _isLoading = false;
        _filterAndGroupResults();
      });

    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _allEntries = [];
        _filterAndGroupResults();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("❌ Erreur de chargement de la playlist: $e", style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.red.shade800,
          duration: const Duration(seconds: 10),
        ),
      );
    }
  }

  String _getBaseName(M3uEntry entry) {
    String name = entry.nom;

    // On enlève d'abord le SxxExx pour les séries pour ne pas interférer
    name = name
        .split(RegExp(r"S\d{2} E\d{2}", caseSensitive: false))
        .first;

    // Cette Regex supprime :
    // 1. Tout contenu entre crochets [...]
    // 2. Tout contenu entre parenthèses (...) s'il contient un des mots-clés.
    // 3. Les mots-clés eux-mêmes s'ils sont seuls.
    const String tags = r'4K|UHD|FHD|HD|SD|2160p|1080p|720p|480p|HEVC|H265|X265|HDR10\+?|HDR|MULTI|VOSTFR|VF|VO|VFF|TRUEFRENCH|TRUEHD|DTS|ATMOS|FR|EN|ES';

    name = name.replaceAll(RegExp(
      // Explication de la nouvelle partie :
      // \([^\(\)]*?($tags)[^\(\)]*?\)
      //   \(        => parenthèse ouvrante
      //   [^\(\)]*? => n'importe quel caractère SAUF une parenthèse (0 ou plusieurs fois, non gourmand)
      //   ($tags)   => un de nos tags
      //   [^\(\)]*? => à nouveau, n'importe quel caractère SAUF une parenthèse
      //   \)        => parenthèse fermante
        r'\s*(\[.*?\]|\([^\(\)]*?(' + tags + r')[^\(\)]*?\)|' r'\b(' + tags + r')\b)',
        caseSensitive: false), '');

    // On nettoie les espaces et caractères de séparation résiduels.
    name = name.trim().replaceAll(RegExp(r'[-_.]'), ' ').replaceAll(
        RegExp(r'\s+'), ' ');

    // Si après nettoyage, le nom est vide, on retourne le nom original pour éviter un crash.
    return name.isEmpty ? entry.nom.replaceAll('|', ' ').trim() : name;
  }

  /// Retourne le nom de l'épisode SANS le numéro SxxExx.
  String _getEpisodeName(M3uEntry entry) {
    // Sépare le titre en deux parties au niveau de "SxxExx"
    final parts = entry.nom.split(
        RegExp(r"S\d{2}\s*E\d{2}", caseSensitive: false));
    if (parts.length > 1) {
      // La deuxième partie contient le nom de l'épisode (s'il existe)
      final episodeTitle = parts[1].trim();
      if (episodeTitle.isNotEmpty) {
        return episodeTitle;
      }
    }
    // S'il n'y a pas de titre d'épisode, on retourne le nom de la série
    return _getBaseName(entry);
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
      // 1. Filtre par le nom (recherche textuelle)
      if (query.isNotEmpty && !entry.nom.toLowerCase().contains(query)) {
        return false;
      }

      // --- LOGIQUE DE FILTRAGE SIMPLIFIÉE ET FIABLE ---
      final url = entry.url.toLowerCase();

      // Un film est montré si le filtre film est actif ET que l'URL est une URL de film.
      if (_showFilms && url.contains('/movie/')) {
        return true;
      }

      // Une série est montrée si le filtre série est actif ET que l'URL est une URL de série.
      if (_showSeries && url.contains('/series/')) {
        return true;
      }

      // Un direct TV est montré si le filtre TV est actif ET que ce n'est ni un film, ni une série.
      final bool isTvUrl = !url.contains('/movie/') && !url.contains('/series/');
      if (_showTv && isTvUrl) {
        return true;
      }

      // Si aucune des conditions n'est remplie, on cache l'élément.
      return false;

    }).toList();

    final Map<String, Map<String, List<M3uEntry>>> tempGroupedSeries = {};
    for (var entry in filtered.where((e) => e.isSerie)) {
      final baseName = _getBaseName(entry);
      final seasonLabel = entry.saison != null
          ? "Saison ${entry.saison}"
          : "Autre";

      tempGroupedSeries.putIfAbsent(baseName, () => {});
      tempGroupedSeries[baseName]!.putIfAbsent(seasonLabel, () => []).add(
          entry);
    }

    tempGroupedSeries.forEach((_, seasons) {
      seasons.forEach((_, episodes) {
        episodes.sort((a, b) => a.nom.compareTo(b.nom));
      });
    });

    final Map<String, List<M3uEntry>> tempGroupedFilms = {};
    for (var entry in filtered.where((e) => !e.isSerie)) {
      final baseName = _getBaseName(entry);
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
    if (lower.contains("4k") || lower.contains("2160p")) return _chip("4K", Colors.yellow.shade800);
    if (lower.contains("fhd") || lower.contains("1080p")) return _chip("FHD", Colors.orange.shade800);
    if (lower.contains("hd") || lower.contains("720p")) return _chip("HD", Colors.blue.shade800);
    if (lower.contains("sd") || lower.contains("480p")) return _chip("SD", Colors.green.shade800);
    return const SizedBox.shrink();
  }

  List<Widget> _getLanguageChips(String title) {
    final lower = title.toLowerCase();
    final chips = <Widget>[];
    if (lower.contains("multi")) chips.add(_chip("MULTI", Colors.lightBlue));
    if (lower.contains("vostfr")) chips.add(_chip("VOSTFR", Colors.teal));
    if (lower.contains("vf")) chips.add(_chip("VF", Colors.cyan.shade800));
    return chips;
  }

  Widget _chip(String label, Color color) {
    return Chip(
      label: Text(label),
      labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
      backgroundColor: color,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
    );
  }

  void _onEntrySelected(M3uEntry entry) async {    final url = entry.url.toLowerCase();
  // On identifie si c'est une chaîne de TV en direct
  final bool isTvChannel = !url.contains('/movie/') && !url.contains('/series/');

  // Si c'est une chaîne TV, on lance le lecteur directement, sans choix.
  if (isTvChannel) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerPage(
          path: entry.url,
          title: entry.nom,
          sourceType: VideoSourceType.network,
        ),
      ),
    );
    return; // On arrête l'exécution ici
  }

  // Pour les films et séries, on affiche une boîte de dialogue avec des choix.
  final choix = await showDialog<String>(
    context: context,
    builder: (BuildContext ctx) {
      return AlertDialog(
        title: Text(
            _getBaseName(entry),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600)
        ),
        content: const Text(
          "Quelle action souhaitez-vous effectuer ?",
          textAlign: TextAlign.center,
        ),
        actions: <Widget>[
          TextButton(
            child: const Text("Annuler", style: TextStyle(color: Colors.red)),
            onPressed: () {
              Navigator.of(ctx).pop('cancel');
            },
          ),
          FilledButton(
            child: const Text("Lire"),
            onPressed: () {
              Navigator.of(ctx).pop('play');
            },
          ),
          TextButton(
            child: const Text("Télécharger", style: TextStyle(color: Colors.green)),
            onPressed: () {
              Navigator.of(ctx).pop('download');
            },
          ),
        ],
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      );
    },
  );

  if (!context.mounted) return;
  // --- ON GÈRE LE CHOIX DE L'UTILISATEUR ---
  if (choix == 'download') {
    // Option 1: L'utilisateur veut juste télécharger.
    // On appelle la fonction existante qui gère tout (confirmation de taille, ajout à la liste, etc.)
    verifierEtTelecharger(
      url: entry.url,
      nom: entry.nom,
      context: context,
    );
  } else if (choix == 'play') {
    // Option 2: L'utilisateur veut lire ET lancer le téléchargement en arrière-plan.

    // Étape 2.1: On lance le lecteur vidéo immédiatement.
    // Le lecteur lira toujours le flux réseau (`sourceType: VideoSourceType.network`).
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerPage(
          path: entry.url,
          title: entry.nom,
          sourceType: VideoSourceType.network,
        ),
      ),
    );

    // Étape 2.2: En parallèle, on lance le téléchargement en arrière-plan.
    // On ne veut PAS afficher le dialogue de confirmation de taille ici.
    // On appelle directement le DownloadManagerService.
    final downloadManager = DownloadManagerService();

    // On vérifie si la tâche n'existe pas déjà pour éviter les doublons.
    final tasks = downloadManager.tasksNotifier.value;
    if (tasks.any((t) => t.url == entry.url)) {
      debugPrint("ℹ️ Le téléchargement pour ce fichier a déjà été initié. Pas d'action supplémentaire.");
      return;
    }

    // Création et démarrage de la tâche sans dialogue de confirmation.
    final String extension = _ext(entry.url);
    String fileName = sanitizeFilename(entry.nom);
    if (_ext(fileName).isEmpty) fileName = '$fileName.${extension.isNotEmpty ? extension : 'mp4'}';

    final savePath = "${await _getTempDirectory()}/$fileName";
    final taskId = 'task_${DateTime.now().millisecondsSinceEpoch}';

    final newTask = DownloadTask(
      id: taskId,
      url: entry.url,
      displayName: entry.nom,
      finalPath: savePath,
      status: DownloadStatus.queued,
      createdAt: DateTime.now(),
    );

    // On ajoute la tâche au manager qui s'occupera de la démarrer.
    // L'UI dans `downloads_page.dart` se mettra à jour automatiquement.
    await downloadManager.addTask(newTask);
    downloadManager.startDownloadTask(newTask); // Pas de 'await', c'est asynchrone.
  }
    // Si choix == 'cancel' ou si le dialogue est fermé, on ne fait rien.
  }

  // J'ai ajouté ces petites fonctions utilitaires qui sont dans telechargement_fichier.dart
  // pour que le code ci-dessus fonctionne sans erreur.
  Future<String> _getTempDirectory() async {
    final dir = await getTemporaryDirectory();
    final tmp = Directory("${dir.path}/dl_tmp");
    if (!await tmp.exists()) await tmp.create(recursive: true);
    return tmp.path;
  }
  String sanitizeFilename(String filename) => filename.replaceAll(RegExp(r'[\\/*?:"<>|]'), "_");
  String _ext(String name) {
    final i = name.lastIndexOf('.');
    return (i >= 0 && i < name.length - 1) ? name.substring(i + 1).toLowerCase() : '';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Analyse de la playlist..."),
          ],
        ),
      );
    }

    return NestedScrollView(
      headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
        // La partie "en-tête" contient les filtres et le champ de recherche.
        // Elle défilera avec le contenu si nécessaire.
        return <Widget>[
          SliverToBoxAdapter(
            child: Column(
              children: [
                // --- FILTRES (CHIPS) ---
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('🎬 Films'),
                        selected: _showFilms,
                        onSelected: (val) =>
                            setState(() {
                              _showFilms = val;
                              _filterAndGroupResults();
                            }),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('📺 Séries'),
                        selected: _showSeries,
                        onSelected: (val) =>
                            setState(() {
                              _showSeries = val;
                              _filterAndGroupResults();
                            }),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('📡 TV'),
                        selected: _showTv,
                        onSelected: (val) =>
                            setState(() {
                              _showTv = val;
                              _filterAndGroupResults();
                            }),
                      ),
                    ],
                  ),
                ),
                // --- CHAMP DE RECHERCHE ---
                Padding(
                  padding: const EdgeInsets.fromLTRB(8.0, 0, 8.0, 8.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Rechercher...',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          // L'état se mettra à jour via le listener
                        },
                      )
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ];
      },
      // Le "corps" contient la liste des résultats qui défile.
      body: (_groupedFilms.isEmpty && _groupedSeries.isEmpty &&
          _searchQuery.isNotEmpty)
          ? const Center(child: Text('🔎 Aucun résultat trouvé'))
          : ListView(
        padding: EdgeInsets.zero, // Important avec NestedScrollView
        children: [
          // --- LISTE DES SÉRIES ---
          ..._groupedSeries.entries.map((seriesEntry) {
            return ExpansionTile(
              leading: const Text("📺", style: TextStyle(fontSize: 24)),
              title: Text(seriesEntry.key,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
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
                  children: seasonEntry.value
                      .map((ep) =>
                      ListTile(
                        title: Padding(
                          padding: const EdgeInsets.only(left: 32.0),
                          child: Text(_getEpisodeName(ep)),
                        ),
                        trailing: _getEpisodeChip(ep),
                        onTap: () => _onEntrySelected(ep),
                      ))
                      .toList(),
                );
              }).toList(),
            );
          }),
          // --- LISTE DES FILMS ET TV ---
          ..._groupedFilms.entries.map((entry) {
            if (entry.value.length == 1) {
              final film = entry.value.first;
              return ListTile(
                leading: const Padding(
                  padding: EdgeInsets.only(left: 8.0),
                  child: Text("🎬", style: TextStyle(fontSize: 24)),
                ),
                title: Text(entry.key),
                trailing: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    _getQualityChip(film.nom),
                    ..._getLanguageChips(film.nom)
                  ],
                ),
                onTap: () => _onEntrySelected(film),
              );
            }
            return ExpansionTile(
              leading: const Text("🎬", style: TextStyle(fontSize: 24)),
              title: Text(entry.key,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              children: entry.value
                  .map((film) =>
                  ListTile(
                    title: Text(entry.key),
                    trailing: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        _getQualityChip(film.nom),
                        ..._getLanguageChips(film.nom)
                      ],
                    ),
                    onTap: () => _onEntrySelected(film),
                  ))
                  .toList(),
            );
          }),
        ],
      ),
    );
  }
}
