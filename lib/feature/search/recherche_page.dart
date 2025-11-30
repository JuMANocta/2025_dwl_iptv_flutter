import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../player/player_page.dart';
import '../downloads/logic/download_initiator.dart';
import '../accounts/accounts_page.dart';
import '../downloads/downloads_page.dart';
import '../../data/services/stream_account_service.dart';
import '../../data/services/playlist_service.dart';
import '../../l10n/app_localizations.dart';
import '../../main.dart'; // Pour navigatorKey
import 'details_page.dart';
import 'package:aetherStream/core/themes/colors.dart';

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
  Key _rechercheM3UKey = UniqueKey(); // Force le reload propre du widget enfant

  @override
  void initState() {
    super.initState();
    _loadPlaylistPath();
  }

  void _loadPlaylistPath({bool forceDownload = false}) {
    setState(() {
      if (forceDownload) {
        _playlistPathFuture = PlaylistService.downloadCurrentM3U();
      } else {
        _playlistPathFuture = PlaylistService.getOrDownloadPlaylist();
      }

      _playlistPathFuture.then((_) {
        StreamAccountService.getCurrentAccount().then((acc) {
          if (mounted) setState(() => _currentAccountLabel = acc?.label);
        });
      }).catchError((_) {
        if (mounted) setState(() => _currentAccountLabel = "Erreur de connexion");
      });
    });
  }

  void _forceReload() {
    debugPrint("🔄 Forçage du rechargement de la playlist...");
    setState(() {
      _rechercheM3UKey = UniqueKey();
    });
    _loadPlaylistPath(forceDownload: true);
  }

  Future<void> _openSettings() async {
    final dynamic result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AccountsPage()),
    );

    if (result == true) {
      setState(() {
        _rechercheM3UKey = UniqueKey();
        _loadPlaylistPath(forceDownload: false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentAccountLabel ?? l10n.searchPageDefaultTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: l10n.searchPageDownloadsTooltip,
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadsPage())),
          ),
          IconButton(
            tooltip: l10n.searchPageReloadTooltip,
            icon: const Icon(Icons.refresh),
            onPressed: _forceReload,
          ),
          IconButton(
            tooltip: l10n.searchPageAccountsTooltip,
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
                    const Icon(Icons.broken_image_outlined, color: Colors.orange, size: 48),
                    const SizedBox(height: 16),
                    Text(l10n.searchPageLoadingError, style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                        onPressed: _forceReload,
                        icon: const Icon(Icons.refresh),
                        label: Text(l10n.searchPageRetryButton)
                    ),
                  ],
                ),
              ),
            );
          }
          return RechercheM3U(key: _rechercheM3UKey, filePath: snapshot.data!);
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
  // --- UI State ---
  bool _showFilms = true;
  bool _showSeries = true;
  bool _showTv = false;
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  // --- Data ---
  final List<M3uEntry> _filmsList = [];
  final List<M3uEntry> _seriesList = [];
  final List<M3uEntry> _tvList = [];

  Map<String, Map<String, List<M3uEntry>>> _groupedSeries = {};
  Map<String, List<M3uEntry>> _groupedFilms = {};
  Map<String, List<M3uEntry>> _groupedTv = {};

  List<dynamic> _flatList = [];
  bool _isProcessing = true;
  String? _errorMessage;

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

    _processFileStream();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

//############################################################################
  // ⚡ LOGIQUE DE TRAITEMENT PAR FLUX (STREAM) - DUAL FORMAT
  //############################################################################

  Future<void> _processFileStream() async {
    final file = File(widget.filePath);
    if (!await file.exists()) {
      if (mounted) setState(() { _isProcessing = false; _errorMessage = "Fichier introuvable"; });
      return;
    }

    try {
      String? pendingTitle; // Titre en attente (Pour le format EXTINF classique)
      final regExpSerie = RegExp(r"S(\d{2})\s*E(\d{2})", caseSensitive: false);

      await file.openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((line) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) return;

        // --- CAS 1 : Ligne de métadonnées (Format A) ---
        if (trimmed.startsWith("#EXTINF")) {
          // Ex: #EXTINF:-1,Titre du film (FR)
          final commaIndex = trimmed.lastIndexOf(',');
          if (commaIndex != -1) {
            pendingTitle = trimmed.substring(commaIndex + 1).trim();
          }
        }
        // --- CAS 2 : Ligne d'URL (Format A ou B) ---
        else if (trimmed.startsWith("http")) {
          String url = trimmed;
          String currentTitle = "";

          // DÉTECTION FORMAT B (URL #Name: Titre)
          if (trimmed.contains("#Name:")) {
            final parts = trimmed.split("#Name:");
            url = parts[0].trim(); // L'URL est avant
            if (parts.length > 1) {
              currentTitle = parts[1].trim(); // Le titre est après
            }
          }
          // UTILISATION FORMAT A (Titre stocké précédement)
          else if (pendingTitle != null && pendingTitle!.isNotEmpty) {
            currentTitle = pendingTitle!;
            pendingTitle = null; // On consomme le titre en attente
          }

          // Si on a bien un titre et une URL, on ajoute
          if (currentTitle.isNotEmpty) {
            _addEntry(currentTitle, url, regExpSerie);
          }
        }
      });

      if (mounted) {
        _filterAndGroupResults();
        setState(() => _isProcessing = false);
      }

    } catch (e) {
      debugPrint("❌ Erreur Stream M3U: $e");
      if (mounted) setState(() { _isProcessing = false; _errorMessage = e.toString(); });
    }
  }

  void _addEntry(String rawTitle, String url, RegExp regExpSerie) {
    final lowerUrl = url.toLowerCase();
    final displayName = _getDisplayName(rawTitle);

    final matchSerie = regExpSerie.firstMatch(rawTitle);
    final isSerie = matchSerie != null;

    final entry = M3uEntry(
      rawTitle: rawTitle,
      url: url,
      isSerie: isSerie,
      saison: matchSerie?.group(1),
      episode: matchSerie?.group(2),
      displayName: displayName,
    );

    if (isSerie) {
      _seriesList.add(entry);
    } else if (lowerUrl.contains('/movie/')) {
      _filmsList.add(entry);
    } else if (lowerUrl.contains('/series/')) {
      // Cas rare où le tag URL dit series mais pas de SxxExx dans le titre
      _seriesList.add(entry);
    } else {
      _tvList.add(entry);
    }
  }

  //############################################################################
  // FILTRAGE ET REGROUPEMENT
  //############################################################################

  void _filterAndGroupResults() {
    final query = _searchQuery.toLowerCase();

    final newGroupedSeries = <String, Map<String, List<M3uEntry>>>{};
    final newGroupedFilms = <String, List<M3uEntry>>{};
    final newGroupedTv = <String, List<M3uEntry>>{};

    bool matches(M3uEntry e) {
      if (query.isEmpty) return true;
      return e.rawTitle.toLowerCase().contains(query) ||
          e.displayName.toLowerCase().contains(query);
    }

    // 1. Filtrage Films
    if (_showFilms) {
      for (var e in _filmsList) {
        if (matches(e)) {
          newGroupedFilms.putIfAbsent(e.displayName, () => []).add(e);
        }
      }
    }

    // 2. Filtrage Séries
    if (_showSeries) {
      for (var e in _seriesList) {
        if (matches(e)) {
          newGroupedSeries.putIfAbsent(e.displayName, () => {});
          final s = e.saison ?? '00';
          newGroupedSeries[e.displayName]!.putIfAbsent(s, () => []).add(e);
        }
      }
    }

    // 3. Filtrage TV
    if (_showTv) {
      for (var e in _tvList) {
        if (matches(e)) {
          newGroupedTv.putIfAbsent(e.displayName, () => []).add(e);
        }
      }
    }

    // Tris internes
    for (var list in newGroupedFilms.values) {
      list.sort((a, b) => a.rawTitle.compareTo(b.rawTitle));
    }
    for (var list in newGroupedTv.values) {
      list.sort((a, b) => a.rawTitle.compareTo(b.rawTitle));
    }
    for (var seasons in newGroupedSeries.values) {
      for (var episodes in seasons.values) {
        episodes.sort((a, b) => a.rawTitle.compareTo(b.rawTitle));
      }
    }

    setState(() {
      _groupedSeries = newGroupedSeries;
      _groupedFilms = newGroupedFilms;
      _groupedTv = newGroupedTv;

      _flatList = [
        ..._groupedFilms.keys,
        ..._groupedSeries.keys,
        ..._groupedTv.keys,
      ];
    });
  }

  //############################################################################
  // UI PRINCIPALE
  //############################################################################

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // Si le traitement initial est en cours (Tier 1)
    if (_isProcessing) {
      return const Center(child: CircularProgressIndicator());
    }

    // Si une erreur critique s'est produite lors du Stream (Tier 2)
    if (_errorMessage != null) {
      return Center(child: Text("Erreur critique: $_errorMessage", style: const TextStyle(color: Colors.red)));
    }

    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        SliverAppBar(
          // 🎯 LÉGÈRE OMBRE / ÉLÉVATION au scroll pour un effet plus doux
          elevation: innerBoxIsScrolled ? 4.0 : 0.0,
          title: Container(
            // 🎯 Amélioration visuelle de la barre de recherche
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant.withAlpha(200),
              borderRadius: BorderRadius.circular(25.0),
            ),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              decoration: InputDecoration(
                hintText: l10n.searchFieldHint,
                hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.6)),
                prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.onSurfaceVariant),
                suffixIcon: _searchQuery.isNotEmpty ? IconButton(
                    icon: Icon(Icons.clear, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    onPressed: () => _searchController.clear()
                ) : null,
                border: InputBorder.none, // Retirer la bordure par défaut
                contentPadding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 10.0),
              ),
            ),
          ),
          pinned: true,
          floating: true,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(kToolbarHeight),
            // 🎯 Utilisation du helper refactorisé
            child: _buildFilterChips(l10n),
          ),
        ),
      ],
      // 🎯 BODY (Liste ou État Vide Amélioré)
      body: _flatList.isEmpty
          ? Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
              _searchQuery.isNotEmpty ? l10n.searchNoResults : l10n.searchNoContent,
              style: TextStyle(color: Colors.grey, fontSize: 16, fontStyle: FontStyle.italic)
          ),
        ],
      ))
          : ScrollablePositionedList.builder(
        itemCount: _flatList.length,
        itemBuilder: (context, index) {
          final item = _flatList[index];
          if (item is! String) return const SizedBox.shrink();

          if (_groupedSeries.containsKey(item)) {
            return _buildSerieCard(item, _groupedSeries[item]!);
          }
          if (_groupedFilms.containsKey(item)) {
            return _buildFilmCard(item, _groupedFilms[item]!);
          }
          if (_groupedTv.containsKey(item)) {
            return _buildFilmCard(item, _groupedTv[item]!);
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  //############################################################################
  // CARTES & ITEMS
  //############################################################################
  Widget _buildFilmCard(String displayName, List<M3uEntry> versions) {
    // 1. Détection de l'Homonyme
    final uniqueYears = versions.map((v) => _getYear(v.rawTitle)).where((y) => y != null).toSet();
    final isHomonymConflict = versions.length > 1 && uniqueYears.length > 1;

    // 2. Construction des Chips Uniques (utilisée si ce n'est PAS un conflit d'homonymes)
    final allQualityChips = versions.map((v) => _getQualityChip(v.rawTitle));
    final allLanguageChips = versions.expand((v) => _getLanguageChips(v.rawTitle));
    // Utilise Set pour n'avoir qu'un seul [FHD]
    final uniqueChips = <Widget>{...allQualityChips, ...allLanguageChips}.toList().where((w) => w is! SizedBox).toList();

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _onEntrySelected(versions),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              // Placeholder icône
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: Colors.blue.withAlpha(25), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.movie, color: Colors.blue),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),

                    const SizedBox(height: 4),

                    // 🎯 CAS 1: CONFLIT D'HOMONYMES (Affiche la liste des années/versions)
                    if (isHomonymConflict)
                      Text(
                          'Versions disponibles: ${uniqueYears.join(', ')}',
                          style: TextStyle(color: Colors.white70, fontSize: 12)
                      )
                    // CAS 2: VERSION MULTIPLE OU UNIQUE (Affiche les tags uniques)
                    else if (uniqueChips.isNotEmpty)
                      Wrap(spacing: 4, runSpacing: 4, children: uniqueChips),

                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSerieCard(String serieName, Map<String, List<M3uEntry>> saisons) {
    final totalEpisodes = saisons.values.fold<int>(0, (prev, epList) => prev + epList.length);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: Colors.purple.withAlpha(25), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.tv, color: Colors.purple),
          ),
          title: Text(serieName, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text("${saisons.keys.length} Saisons • $totalEpisodes Épisodes", style: const TextStyle(fontSize: 12)),
          children: saisons.entries.map((entry) {
            return ExpansionTile(
              title: Text("Saison ${entry.key}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              leading: const Icon(Icons.folder_open, size: 20),
              children: entry.value.map((ep) => ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 32, right: 16),
                title: Text(_getEpisodeName(ep)),
                leading: _getEpisodeChip(ep),
                trailing: const Icon(Icons.play_arrow_rounded),
                onTap: () => _onEntrySelected([ep]),
              )).toList(),
            );
          }).toList(),
        ),
      ),
    );
  }

  //############################################################################
  // NAVIGATION & ACTIONS
  //############################################################################

  Future<void> _onEntrySelected(List<M3uEntry> versions) async {
    if (versions.isEmpty || !mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();

    final entry = versions.first;
    // Détection basique pour savoir si c'est une chaîne TV en direct
    final bool isTvChannel = !entry.url.contains('/movie/') && !entry.url.contains('/series/');

    M3uEntry selectedEntry = versions.first;

    if (versions.length > 1) {
      final choice = await _showVersionSelector(versions);
      if (choice == null) return;
      selectedEntry = choice;
    }

    if (!mounted) return;

    if (isTvChannel) {
      Navigator.push(context, MaterialPageRoute(
          builder: (_) => PlayerPage(
            path: selectedEntry.url,
            title: selectedEntry.displayName,
            sourceType: VideoSourceType.network,
          )
      ));
    } else {
      _showActionSheet(selectedEntry);
    }
  }

  Future<M3uEntry?> _showVersionSelector(List<M3uEntry> versions) {
    return showModalBottomSheet<M3uEntry>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text("Choisir une version", style: Theme.of(context).textTheme.titleLarge),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: versions.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                itemBuilder: (ctx, i) {
                  final v = versions[i];

                  // 1. Extraction des données
                  final year = _getYear(v.rawTitle);       // 📅 Année
                  final extraInfo = _getVersionLabel(v);   // Texte restant (ex: Director's Cut)
                  final qualityChip = _getQualityChip(v.rawTitle);
                  final langChips = _getLanguageChips(v.rawTitle);

                  // 2. Construction de la liste des Badges
                  final allChips = <Widget>[];

                  // 🚨 L'ANNÉE EN PREMIER (Badge Blanc/Gris)
                  if (year != null) {
                    allChips.add(Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          border: Border.all(color: Colors.white60),
                          borderRadius: BorderRadius.circular(4)
                      ),
                      child: Text(year, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                    ));
                  }

                  // Ensuite Qualité et Langues
                  if (qualityChip is! SizedBox) allChips.add(qualityChip);
                  allChips.addAll(langChips);

                  // 3. Logique d'affichage Titre/Sous-titre
                  Widget titleWidget;
                  Widget? subtitleWidget;

                  if (allChips.isNotEmpty) {
                    // Les badges deviennent le titre principal
                    titleWidget = Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: allChips);

                    // Si on a du texte spécifique en plus, il passe en sous-titre
                    if (extraInfo.isNotEmpty && extraInfo != "Standard / Inconnue") {
                      subtitleWidget = Text(extraInfo, style: const TextStyle(fontSize: 12, color: Colors.grey));
                    }
                  } else {
                    // Fallback texte brut
                    titleWidget = Text(extraInfo, style: const TextStyle(fontWeight: FontWeight.bold));
                  }

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                    title: titleWidget,
                    subtitle: subtitleWidget,
                    trailing: const Icon(Icons.check_circle_outline, color: Colors.white24, size: 20),
                    onTap: () => Navigator.pop(ctx, v),
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }

  Future<void> _showActionSheet(M3uEntry entry) async {
    final l10n = AppLocalizations.of(context)!;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(entry.displayName, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [_getQualityChip(entry.rawTitle), ..._getLanguageChips(entry.rawTitle)]),
              const SizedBox(height: 24),

              // 1. ACTION PRINCIPALE : DETAILS (Netflix Style)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => DetailsPage(entry: entry)));
                    },
                    icon: const Icon(Icons.info_outline),
                    label: const Text("Fiche Détaillée & Infos"),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 2. ACTIONS SECONDAIRES
              ListTile(
                leading: const Icon(Icons.play_arrow),
                title: Text(l10n.actionSheetPlay),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerPage(path: entry.url, title: entry.displayName, sourceType: VideoSourceType.networkWithCache)));
                },
              ),
              ListTile(
                leading: const Icon(Icons.download),
                title: Text(l10n.actionSheetDownload),
                onTap: () {
                  Navigator.pop(context);
                  verifierEtTelecharger(url: entry.url, nom: entry.displayName, context: navigatorKey.currentContext!);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  //############################################################################
  // HELPERS (Regex & Parsing)
  //############################################################################

  String _getDisplayName(String originalName) {
    String name = originalName;

    // 1. Nettoyage Prefixes bizarres (IPTV)
    // Ex: "|FR| FILM", "FR : FILM"
    name = name.replaceAll(RegExp(r'^(\|[A-Z0-9\s]+\||\w{2,}\s*[:-])\s*', caseSensitive: false), '');

    // 2. Gestion Séries : On coupe tout ce qui est après S01 E01
    final matchSerie = RegExp(r"S\d{2}\s*E\d{2}", caseSensitive: false).firstMatch(name);
    if (matchSerie != null) {
      name = name.substring(0, matchSerie.start).trim();
    }

    // 3. Suppression des tags de QUALITÉ
    const qualityTags = r'\b(4K|UHD|2160p|1080p|720p|480p|FHD|HD|SD|HEVC|H265|H\.265|X265|AAC|DTS)\b';
    name = name.replaceAll(RegExp(qualityTags, caseSensitive: false), '');

    // 4. Suppression des tags de LANGUE
    const langTags = r'\b(MULTI|VOSTFR|VOST|VF|VO|VFF|FR|EN|VIP|RAW)\b';
    name = name.replaceAll(RegExp(langTags, caseSensitive: false), '');

    // 5. 🎯 Suppression de l'ANNÉE (ex: 2021, (2019))
    // On cherche 4 chiffres commençant par 19 ou 20, potentiellement entre parenthèses
    name = name.replaceAll(RegExp(r'\(?(19|20)\d{2}\)?'), '');

    // 6. Nettoyage final des ponctuations résiduelles
    // On remplace parenthèses, crochets, points, tirets par des espaces
    name = name.replaceAll(RegExp(r'[\(\)\[\]\.\-_]'), ' ');

    // 7. Trim et réduction des espaces multiples
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Sécurité: Si on a tout effacé, on renvoie une version minimaliste de l'original
    if (name.length < 2) {
      return originalName.split(RegExp(r"S\d{2}", caseSensitive: false)).first;
    }

    return name;
  }

  String _getEpisodeName(M3uEntry entry) {
    final regex = RegExp(r"S\d{2}\s*E\d{2}", caseSensitive: false);
    final match = regex.firstMatch(entry.rawTitle);
    if (match != null && match.end < entry.rawTitle.length) {
      String rest = entry.rawTitle.substring(match.end).trim();
      rest = rest.replaceAll(RegExp(r'\.(mkv|mp4|avi)$', caseSensitive: false), '');
      if (rest.isNotEmpty && rest.length > 2) return rest.replaceAll(RegExp(r'^[-_.]'), '').trim();
    }
    return entry.displayName;
  }

  Chip _getEpisodeChip(M3uEntry ep) {
    return Chip(
      label: Text("S${ep.saison} E${ep.episode}"),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      backgroundColor: Colors.grey.withAlpha(25),
    );
  }

  Widget _getQualityChip(String title) {
    final t = title.toLowerCase();
    if (t.contains('4k') || t.contains('2160p')) return _tag('4K', Colors.red);
    if (t.contains('1080p') || t.contains('fhd')) return _tag('FHD', Colors.amber);
    if (t.contains('720p') || t.contains('hd')) return _tag('HD', Colors.blue);
    if (t.contains('sd')) return _tag('SD', Colors.teal);
    return const SizedBox.shrink();
  }

  List<Widget> _getLanguageChips(String title) {
    final t = title.toLowerCase();
    final chips = <Widget>[];
    if (t.contains('multi')) chips.add(_tag('MULTI', Colors.purple));
    if (t.contains('vostfr')) chips.add(_tag('VOSTFR', Colors.orange));
    if (t.contains('vf') || t.contains('french') || t.contains('vff')) chips.add(_tag('VF', Colors.blue));
    return chips;
  }

  /// Nettoie le titre pour n'afficher que la qualité/langue dans le sélecteur
  String _getVersionLabel(M3uEntry entry) {
    String label = entry.rawTitle;

    // 1. Retire le Titre du film
    label = label.replaceAll(RegExp(RegExp.escape(entry.displayName), caseSensitive: false), '');

    // 2. Retire les Préfixes IPTV
    label = label.replaceAll(RegExp(r'(\|[A-Z0-9\s]+\||\w{2,}\s*[:-])', caseSensitive: false), '');

    // 3. Retire l'Année
    label = label.replaceAll(RegExp(r'\(?(19|20)\d{2}\)?'), '');

    // 4. 🎯 NOUVEAU : Retire les mots-clés de QUALITÉ et LANGUE (car ils seront en Chips)
    const tagsToRemove = r'\b(4K|UHD|2160p|1080p|720p|480p|FHD|HD|SD|HEVC|H265|X265|MULTI|VOSTFR|VOST|VF|VO|VFF|FR|EN|TRUEFRENCH)\b';
    label = label.replaceAll(RegExp(tagsToRemove, caseSensitive: false), '');

    // 5. Nettoyage final (ponctuation résiduelle)
    label = label.replaceAll(RegExp(r'^[ \t\-_.\(\)\[\]]+'), '');
    label = label.replaceAll(RegExp(r'[ \t\-_.\(\)\[\]]+$'), '');
    label = label.trim().replaceAll(RegExp(r'\s+'), ' ');

    return label;
  }

  String? _getYear(String rawTitle) {
    // Cherche 4 chiffres commençant par 19 ou 20, avec ou sans parenthèses
    final match = RegExp(r'\(?(19|20)\d{2}\)?').firstMatch(rawTitle);
    if (match != null) {
      // On retourne juste l'année propre (sans parenthèses)
      final match = RegExp(r'\b(19|20)\d{2}\b').firstMatch(rawTitle);
      return match?.group(0);
    }
    return null;
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
          color: color.withAlpha(25),
          border: Border.all(color: color.withAlpha(25)),
          borderRadius: BorderRadius.circular(4)
      ),
      child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _buildFilterChips(AppLocalizations l10n) {
    // Définition des couleurs spécifiques au thème AetherStream
    const Color selectedBg = kAetherPrimaryPurple; // Fond Violet
    const Color selectedLabel = kTextDarkPrimary;   // Texte Blanc
    const Color unselectedBg = kContainerDark;      // Fond Conteneur (Gris très foncé)
    const Color unselectedBorder = kAetherSecondaryCyan; // Bordure Cyan (pour l'accentuation subtile)
    const Color unselectedLabel = kTextDarkSecondary; // Texte Gris clair

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Film Chip
          FilterChip(
            label: Text(l10n.searchFilterFilms),
            selected: _showFilms,
            onSelected: (s) => setState(() { _showFilms = s; _filterAndGroupResults(); }),

            // 🎯 STYLING AETHERSTREAM
            selectedColor: selectedBg,
            backgroundColor: unselectedBg,
            labelStyle: _showFilms ? TextStyle(color: selectedLabel, fontWeight: FontWeight.bold) : TextStyle(color: unselectedLabel),
            side: _showFilms ? BorderSide.none : BorderSide(color: unselectedBorder.withAlpha(100)), // Bordure Cyan subtile
            // FIN STYLING AETHERSTREAM
          ),
          const SizedBox(width: 8),

          // Series Chip
          FilterChip(
            label: Text(l10n.searchFilterSeries),
            selected: _showSeries,
            onSelected: (s) => setState(() { _showSeries = s; _filterAndGroupResults(); }),

            selectedColor: selectedBg,
            backgroundColor: unselectedBg,
            labelStyle: _showSeries ? TextStyle(color: selectedLabel, fontWeight: FontWeight.bold) : TextStyle(color: unselectedLabel),
            side: _showSeries ? BorderSide.none : BorderSide(color: unselectedBorder.withAlpha(100)),
          ),
          const SizedBox(width: 8),

          // TV Chip
          FilterChip(
            label: Text(l10n.searchFilterTv),
            selected: _showTv,
            onSelected: (s) => setState(() { _showTv = s; _filterAndGroupResults(); }),

            selectedColor: selectedBg,
            backgroundColor: unselectedBg,
            labelStyle: _showTv ? TextStyle(color: selectedLabel, fontWeight: FontWeight.bold) : TextStyle(color: unselectedLabel),
            side: _showTv ? BorderSide.none : BorderSide(color: unselectedBorder.withAlpha(100)),
          ),
        ],
      ),
    );
  }
}
