import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'main.dart';
import 'screens/accounts_screen.dart';
import 'screens/downloads_page.dart';
import 'services/stream_account_service.dart';
import 'services/playlist_service.dart';
import 'telechargement_fichier.dart';
import 'screens/player_page.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

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
      StreamAccountService.getCurrentAccount().then((acc) {
        if (mounted) setState(() => _currentAccountLabel = acc?.label);
      });
    });
  }

  void _forceReload() async {
    debugPrint("🔄 Forçage du rechargement de la playlist...");
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
        title: Text(_currentAccountLabel ?? "AetherStream"),
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
  final String rawTitle;
  final String url;
  final bool isSerie;
  final String? saison;
  final String? episode;
  final String displayName;

  M3uEntry({
    required this.rawTitle,
    required this.url,
    this.isSerie = false,
    this.saison,
    this.episode,
    required this.displayName,
  });
}

class RechercheM3U extends StatefulWidget {
  final String filePath;
  const RechercheM3U({super.key, required this.filePath});

  @override
  State<RechercheM3U> createState() => _RechercheM3UState();
}

class _RechercheM3UState extends State<RechercheM3U> {
  // --- Variables d'état de l'UI ---
  bool _showFilms = true;
  bool _showSeries = true;
  bool _showTv = false;
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  // --- Données ---
  List<M3uEntry> _filmsList = [];
  List<M3uEntry> _seriesList = [];
  List<M3uEntry> _tvList = [];
  Map<String, Map<String, List<M3uEntry>>> _groupedSeries = {};
  Map<String, List<M3uEntry>> _groupedFilms = {};
  Map<String, List<M3uEntry>> _groupedTv = {};

  // --- Liste pour l'affichage virtualisé ---
  List<dynamic> _flatList = [];

  // --- Contrôle du chargement asynchrone ---
  late Future<bool> _initFuture;

  @override
  void initState() {
    super.initState();
    // 1. On lie le listener au champ de recherche
    _searchController.addListener(() {
      // Pour éviter les rebuilds inutiles si le texte n'a pas changé
      if (_searchQuery != _searchController.text) {
        // Un setState est nécessaire ici pour réagir à l'action de l'utilisateur
        setState(() {
          _searchQuery = _searchController.text;
          _filterAndGroupResults();
        });
      }
    });

    // 2. On lance l'opération de chargement et de traitement des données
    _initFuture = _loadAndProcessM3U();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  //############################################################################
  // LOGIQUE DE CHARGEMENT ET TRAITEMENT (Le cœur de la performance)
  //############################################################################

  /// Charge, parse et pré-calcule TOUTES les données lourdes UNE SEULE FOIS.
  /// Ne met PAS à jour l'état (pas de setState), mais retourne un Future.
  Future<bool> _loadAndProcessM3U() async {
    try {
      final file = File(widget.filePath);
      if (!await file.exists() || await file.length() < 10) {
        throw Exception("Le fichier de playlist est invalide, vide ou non trouvé.");
      }

      final lines = await file.readAsLines(encoding: utf8);
      final List<M3uEntry> parsedEntries = [];
      final fileContent = lines.join('\n');

      // --- Logique de Parsing ---
      if (fileContent.contains("#EXTINF")) {
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.startsWith("#EXTINF")) {
            final title = line.contains(',') ? line.split(',').last.trim() : '';
            if (title.isEmpty) continue;
            String? url;
            for (int j = i + 1; j < lines.length; j++) {
              final nextLine = lines[j].trim();
              if (nextLine.startsWith('http')) { url = nextLine; i = j; break; }
              if (nextLine.startsWith('#EXTINF')) break;
            }
            if (url != null) parsedEntries.add(M3uEntry(rawTitle: title, url: url, displayName: ''));
          }
        }
      } else {
        for (final line in lines) {
          if (line.contains("#Name:")) {
            final parts = line.split("#Name:");
            final url = parts[0].trim();
            final title = parts.length > 1 ? parts[1].trim() : '';
            if (url.startsWith('http') && title.isNotEmpty) parsedEntries.add(M3uEntry(rawTitle: title, url: url, displayName: ''));
          }
        }
      }

      if (parsedEntries.isEmpty) {
        throw Exception("Aucune entrée valide trouvée. Le format de la playlist pourrait ne pas être reconnu.");
      }

      // --- Pré-calcul intensif (la clé de la performance) ---
      _filmsList = [];
      _seriesList = [];
      _tvList = [];

      for (final entry in parsedEntries) {
        final displayName = _getDisplayName(entry.rawTitle);
        final url = entry.url.toLowerCase();
        final isSerie = RegExp(r"S\d{2} E\d{2}", caseSensitive: false).hasMatch(entry.rawTitle);

        if (isSerie) {
          final match = RegExp(r"S(\d{2}) E(\d{2})", caseSensitive: false).firstMatch(entry.rawTitle);
          _seriesList.add(M3uEntry(rawTitle: entry.rawTitle, url: entry.url, isSerie: true, saison: match?.group(1), episode: match?.group(2), displayName: displayName));
        } else if (url.contains('/movie/')) {
          _filmsList.add(M3uEntry(rawTitle: entry.rawTitle, url: entry.url, isSerie: false, displayName: displayName));
        } else if (url.contains('/series/')) {
          _seriesList.add(M3uEntry(rawTitle: entry.rawTitle, url: entry.url, isSerie: true, displayName: displayName));
        } else {
          _tvList.add(M3uEntry(rawTitle: entry.rawTitle, url: entry.url, isSerie: false, displayName: displayName));
        }
      }

      // Lance le premier filtrage/groupement pour que l'UI initiale ait des données.
      _filterAndGroupResults();

      return true; // Signale au FutureBuilder que tout est prêt.

    } catch (e) {
      debugPrint("Erreur critique dans _loadAndProcessM3U: $e");
      rethrow; // Propage l'erreur au FutureBuilder pour qu'il l'affiche.
    }
  }

  //############################################################################
  // LOGIQUE DE FILTRAGE (Rendue ultra-rapide par le pré-calcul)
  //############################################################################

  /// Filtre et regroupe les listes en fonction des actions de l'utilisateur.
  void _filterAndGroupResults() {
    final query = _searchQuery.toLowerCase();

    List<M3uEntry> activeEntries = [];
    // On respecte les filtres de l'utilisateur
    if (_showFilms) activeEntries.addAll(_filmsList);
    if (_showSeries) activeEntries.addAll(_seriesList);
    if (_showTv) activeEntries.addAll(_tvList);

    final filtered = activeEntries.where((entry) {
      if (query.isEmpty) return true;
      return entry.rawTitle.toLowerCase().contains(query) || entry.displayName.toLowerCase().contains(query);
    }).toList();

    // --- TROIS GROUPES DISTINCTS ---
    final newGroupedSeries = <String, Map<String, List<M3uEntry>>>{};
    final newGroupedFilms = <String, List<M3uEntry>>{};
    // On crée une map pour regrouper les chaînes TV par leur nom
    final newGroupedTv = <String, List<M3uEntry>>{};

    for (final entry in filtered) {
      final displayName = entry.displayName;
      final url = entry.url.toLowerCase();

      // On utilise la même condition que partout ailleurs
      final isTvChannel = !url.contains('/movie/') && !url.contains('/series/');

      if (entry.isSerie) {
        // Catégorie SÉRIES
        newGroupedSeries.putIfAbsent(displayName, () => {});
        final saison = entry.saison ?? '00';
        newGroupedSeries[displayName]!.putIfAbsent(saison, () => []);
        newGroupedSeries[displayName]![saison]!.add(entry);
      } else if (isTvChannel) {
        // Catégorie TV
        newGroupedTv.putIfAbsent(displayName, () => []);
        newGroupedTv[displayName]!.add(entry);
      } else {
        // Catégorie FILMS
        newGroupedFilms.putIfAbsent(displayName, () => []);
        newGroupedFilms[displayName]!.add(entry);
      }
    }

    // --- TRIS INTERNES (utiles et conservés) ---
    // Trier les épisodes dans chaque saison
    newGroupedSeries.forEach((_, saisons) {
      saisons.forEach((_, episodes) => episodes.sort((a, b) => a.rawTitle.compareTo(b.rawTitle)));
    });
    // Trier les versions d'un même film (par qualité, etc.)
    newGroupedFilms.forEach((_, versions) {
      versions.sort((a, b) => a.rawTitle.compareTo(b.rawTitle));
    });
    // Trier les versions d'une même chaîne TV (par qualité, etc.)
    newGroupedTv.forEach((_, versions) {
      versions.sort((a, b) => a.rawTitle.compareTo(b.rawTitle));
    });

    setState(() {
      _groupedSeries = newGroupedSeries;
      _groupedFilms = newGroupedFilms;
      _groupedTv = newGroupedTv;

      // Construction de la liste finale, SANS tri global pour respecter l'ordre de la playlist
      _flatList = [
        ..._groupedFilms.keys,
        ..._groupedSeries.keys,
        ..._groupedTv.keys,
      ];
    });
  }

  //############################################################################
  // CONSTRUCTION DE L'INTERFACE (Pilotée par FutureBuilder)
  //############################################################################

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _initFuture,
      builder: (context, snapshot) {
        // CAS 1: L'opération est en cours
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // CAS 2: L'opération a échoué
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text("Erreur de traitement de la playlist:\n${snapshot.error}", textAlign: TextAlign.center, style: TextStyle(color: Colors.red.shade400)),
            ),
          );
        }

        // CAS 3: L'opération a réussi, on peut construire l'UI complète
        return NestedScrollView(
          headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
            return <Widget>[
              SliverAppBar(
                title: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Rechercher...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () => _searchController.clear()) : null,
                  ),
                ),
                pinned: true,
                floating: true,
                forceElevated: innerBoxIsScrolled,
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(kToolbarHeight),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterChip(label: const Text('Films'), selected: _showFilms, onSelected: (s) => setState(() { _showFilms = s; _filterAndGroupResults(); })),
                        const SizedBox(width: 8),
                        FilterChip(label: const Text('Séries'), selected: _showSeries, onSelected: (s) => setState(() { _showSeries = s; _filterAndGroupResults(); })),
                        const SizedBox(width: 8),
                        FilterChip(label: const Text('TV'), selected: _showTv, onSelected: (s) => setState(() { _showTv = s; _filterAndGroupResults(); })),
                      ],
                    ),
                  ),
                ),
              ),
            ];
          },
          body: _flatList.isEmpty
              ? Center(child: Text(_searchQuery.isNotEmpty ? "Aucun résultat trouvé." : "Aucun contenu à afficher."))
              : ScrollablePositionedList.builder(
            itemCount: _flatList.length,
              itemBuilder: (context, index) {
                final item = _flatList[index];

                if (item is String) {
                  if (_groupedSeries.containsKey(item)) {
                    final saisons = _groupedSeries[item]!;
                    return _buildSerieCard(item, saisons);
                  }
                  // Si la clé est dans les films OU dans les TV, on utilise la même carte
                  if (_groupedFilms.containsKey(item)) {
                    final versions = _groupedFilms[item]!;
                    return _buildFilmCard(item, versions);
                  }
                  if (_groupedTv.containsKey(item)) { // AJOUT DE CETTE CONDITION
                    final versions = _groupedTv[item]!;
                    return _buildFilmCard(item, versions); // On réutilise _buildFilmCard
                  }
                }
            // CAS 2: C'est une M3uEntry, donc une chaîne TV seule
            if (item is M3uEntry) {
              // On la traite comme un film avec une seule version
              return _buildFilmCard(item.displayName, [item]);
            }

            return const SizedBox.shrink();
          },
          ),
        );
      },
    );
  }

  //############################################################################
  // WIDGETS DE CARTES (Films et Séries)
  //############################################################################

  Widget _buildFilmCard(String displayName, List<M3uEntry> versions) {
    // On fusionne tous les tags de toutes les versions pour les afficher.
    final allQualityChips = versions.map((v) => _getQualityChip(v.rawTitle));
    final allLanguageChips = versions.expand((v) => _getLanguageChips(v.rawTitle));

    // On utilise un Set pour enlever les doublons (ex: si 2 versions sont "VF").
    final uniqueChips = <Widget>{...allQualityChips, ...allLanguageChips}.toList();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        title: Text(displayName, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Wrap(
          spacing: 4.0,
          runSpacing: 4.0,
          children: uniqueChips, // On affiche les tags uniques
        ),
        onTap: () => _onEntrySelected(versions), // <-- Appel modifié !
      ),
    );
  }

  Widget _buildSerieCard(String serieName, Map<String, List<M3uEntry>> saisons) {
    final totalEpisodes = saisons.values.fold<int>(0, (prev, epList) => prev + epList.length);
    final firstEpisode = saisons.values.first.first;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ExpansionTile(
        title: Text(serieName),
        subtitle: Wrap(spacing: 4.0, runSpacing: 4.0, children: [
          Chip(label: Text('${saisons.keys.length} Saison(s) / $totalEpisodes Ép.')),
          _getQualityChip(firstEpisode.rawTitle),
          ..._getLanguageChips(firstEpisode.rawTitle),
        ]),
        children: saisons.entries.map((saisonEntry) {
          final saisonNum = saisonEntry.key;
          final episodes = saisonEntry.value;
          return ExpansionTile(
            title: Text("Saison $saisonNum", style: const TextStyle(fontWeight: FontWeight.bold)),
            children: episodes.map((ep) {
              return ListTile(
                title: Text(_getEpisodeName(ep)),
                leading: _getEpisodeChip(ep),
                onTap: () => _onEntrySelected([ep]),
              );
            }).toList(),
          );
        }).toList(),
      ),
    );
  }

  //############################################################################
  // MÉTHODES UTILITAIRES
  //############################################################################
  Future<void> _onEntrySelected(List<M3uEntry> versions) async {
    if (versions.isEmpty || !mounted) return;

    final entry = versions.first;
    final url = entry.url.toLowerCase();
    final bool isTvChannel = !url.contains('/movie/') && !url.contains('/series/');

    // --- LOGIQUE CORRIGÉE ---
    M3uEntry? selectedEntry;

    if (versions.length == 1) {
      // S'il n'y a qu'une version, c'est elle qu'on a choisie.
      selectedEntry = versions.first;
    } else {
      // S'il y a plusieurs versions, on ouvre la feuille de CHOIX DE VERSION.
      selectedEntry = await showModalBottomSheet<M3uEntry>(
        context: context,
        builder: (context) {
          // C'est un widget très similaire à _showActionSheet
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Le titre de la feuille d'action
                Text(
                  "Choisir une version pour :",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  entry.displayName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Divider(height: 32),
                // La liste des versions disponibles
                Flexible( // Important pour que la liste ne dépasse pas
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: versions.length,
                    itemBuilder: (ctx, index) {
                      final version = versions[index];
                      final qualityChip = _getQualityChip(version.rawTitle);
                      final languageChips = _getLanguageChips(version.rawTitle);
                      final allChips = [qualityChip, ...languageChips];

                      Widget titleWidget = Wrap(spacing: 6.0, runSpacing: 4.0, children: allChips);

                      // Si aucun tag n'est trouvé, on affiche un texte par défaut
                      if (allChips.every((w) => w is SizedBox)) {
                        final fallbackLabel = version.rawTitle.replaceAll(version.displayName, "").trim();
                        titleWidget = Text(fallbackLabel.isNotEmpty ? fallbackLabel : "Version ${index + 1}");
                      }

                      return ListTile(
                        title: titleWidget,
                        // Quand on clique, on "retourne" la version choisie
                        onTap: () => Navigator.of(context).pop(version),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    // Si aucune version n'a été sélectionnée (l'utilisateur a annulé), on ne fait rien.
    if (selectedEntry == null || !mounted) return;

    if (isTvChannel) {
      Navigator.push(context, MaterialPageRoute(
          builder: (_) => PlayerPage(
            path: selectedEntry!.url,
            title: selectedEntry.displayName,
            sourceType: VideoSourceType.networkWithCache,
          )
      ));
    } else {
      // CAS FILMS/SÉRIES : On affiche la feuille d'actions "Lire/Télécharger"
      _showActionSheet(selectedEntry);
    }
  }

  Future<void> _showActionSheet(M3uEntry entry) async {
    await showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                entry.displayName,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8.0,
                alignment: WrapAlignment.center,
                children: [_getQualityChip(entry.rawTitle), ..._getLanguageChips(entry.rawTitle)],
              ),
              const Divider(height: 32),

              // --- OPTION 1 : LIRE (maintenant avec cache implicite) ---
              ListTile(
                leading: const Icon(Icons.play_circle_outline, size: 32),
                title: const Text("Lire"),
                subtitle: const Text("Lance la lecture (mise en cache automatique)."),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(
                      builder: (_) => PlayerPage(
                        path: entry.url,
                        title: entry.displayName,
                        // ON FORCE LE MODE CACHE SYSTÉMATIQUEMENT !
                        sourceType: VideoSourceType.networkWithCache,
                      )
                  ));
                },
              ),

              // --- OPTION 2 : TÉLÉCHARGER (sans lire) ---
              ListTile(
                leading: const Icon(Icons.download_for_offline_outlined, size: 32),
                title: const Text("Télécharger en arrière-plan"),
                subtitle: const Text("Pour regarder plus tard sans connexion."),
                onTap: () {
                  Navigator.pop(context);
                  final rootContext = navigatorKey.currentContext;
                  if (rootContext == null || !rootContext.mounted) {
                    debugPrint("Erreur critique : Impossible d'obtenir le contexte global.");
                    return;
                  }
                  // La fonction de téléchargement classique reste la même
                  verifierEtTelecharger(
                      url: entry.url,
                      nom: entry.displayName,
                      context: rootContext,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  String _getDisplayName(String originalName) {
    String name = originalName;
    name = name.replaceFirst(RegExp(r'^\|[A-Z]{2,}\|\s*'), '');
    name = name.split(RegExp(r"S\d{2} E\d{2}", caseSensitive: false)).first;
    const String tags = r'4K|UHD|FHD|HD|SD|2160p|1080p|720p|480p|HEVC|H265|X265|HDR10\+?|HDR|MULTI|VOSTFR|VF|VO|VFF|TRUEFRENCH|TRUEHD|DTS|ATMOS|FR|EN|ES';
    name = name.replaceAll(RegExp(r'\s*(\[.*?\]|\([^\(\)]*?(' + tags + r')[^\(\)]*?\)|' r'\b(' + tags + r')\b)', caseSensitive: false), '');
    name = name.trim().replaceAll(RegExp(r'[-_.]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

    if (name.isEmpty) {
      name = originalName.split(RegExp(r"S\d{2} E\d{2}", caseSensitive: false)).first.replaceAll(RegExp(r'[\[\]\(\)|_.-]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    return name.isNotEmpty ? name : "Titre indisponible";
  }

  String _getEpisodeName(M3uEntry entry) {
    final parts = entry.rawTitle.split(RegExp(r"S\d{2}\s*E\d{2}", caseSensitive: false));
    if (parts.length > 1) {
      final episodeTitle = parts[1].trim();
      if (episodeTitle.isNotEmpty) return episodeTitle;
    }
    return _getDisplayName(entry.rawTitle);
  }

  Widget _getEpisodeChip(M3uEntry ep) {
    if (ep.saison != null && ep.episode != null) {
      return _chip("S${ep.saison}E${ep.episode}", Colors.purple);
    }
    return const SizedBox.shrink();
  }

  Widget _chip(String label, Color color) {
    return Chip(
      label: Text(label),
      backgroundColor: color.withOpacity(0.2),
      shape: StadiumBorder(side: BorderSide(color: color.withOpacity(0.5))),
      padding: EdgeInsets.zero,
      labelStyle: TextStyle(fontSize: 11, color: color),
    );
  }

  Widget _getQualityChip(String title) {
    final lowerTitle = title.toLowerCase();
    if (RegExp(r'4k|2160p|uhd').hasMatch(lowerTitle)) return _chip('4K', Colors.red);
    if (RegExp(r'1080p|fhd').hasMatch(lowerTitle)) return _chip('FHD', Colors.orange);
    if (RegExp(r'720p|hd(?!mi)').hasMatch(lowerTitle)) return _chip('HD', Colors.blue); // hd(?!mi) pour éviter de matcher "hdmi"
    if (RegExp(r'sd|480p|576p').hasMatch(lowerTitle)) return _chip('SD', Colors.green);
    return const SizedBox.shrink();
  }

  List<Widget> _getLanguageChips(String title) {
    final chips = <Widget>[];
    final lowerTitle = title.toLowerCase();

    // Utilisation de RegExp plus permissives avec les délimiteurs de mots (\b)
    // pour éviter les faux positifs (ex: "gaufre" ne matchera plus "vf").
    if (RegExp(r'\b(vff|truefrench|multi)\b').hasMatch(lowerTitle)) {
      chips.add(_chip('VF', Colors.cyan));
      // Si c'est multi, on peut aussi supposer VO
      if (lowerTitle.contains('multi')) {
        chips.add(_chip('VO', Colors.teal));
      }
    } else if (RegExp(r'\bvostfr\b').hasMatch(lowerTitle)) {
      chips.add(_chip('VOSTFR', Colors.purple));
    } else if (RegExp(r'\bvf\b').hasMatch(lowerTitle)) {
      chips.add(_chip('VF', Colors.cyan));
    }

    // Vérifier la VO séparément pour les cas comme "Titre VO" ou "Titre MULTI"
    if (RegExp(r'\bvo\b').hasMatch(lowerTitle) && !lowerTitle.contains('vostfr')) {
      // On s'assure de ne pas ajouter un deuxième chip VO si on a déjà mis "VOSTFR" ou "MULTI"
      if (!chips.any((w) => w is Chip && (w.label as Text).data == 'VO')) {
        chips.add(_chip('VO', Colors.teal));
      }
    }
    return chips;
  }
}
