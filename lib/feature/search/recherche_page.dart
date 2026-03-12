import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:aetherStream/feature/player/player_page.dart';
import 'package:aetherStream/feature/downloads/logic/download_initiator.dart';
import 'package:aetherStream/feature/accounts/accounts_page.dart';
import 'package:aetherStream/feature/downloads/downloads_page.dart';
import 'package:aetherStream/feature/search/details_page.dart';
import 'package:aetherStream/data/services/stream_account_service.dart';
import 'package:aetherStream/data/services/playlist_service.dart';
import 'package:aetherStream/data/services/tmdb_service.dart';
import 'package:aetherStream/data/models/media_model.dart';
import 'package:aetherStream/feature/replay/replay_widget.dart';
import 'package:aetherStream/data/services/replay_service.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:aetherStream/main.dart'; // Pour navigatorKey
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

enum M3uContentType { movie, series, tv }

/// Métadonnées complètes extraites d'un titre M3U (qualité, année, langues, etc.).
class TitleMetadata {
  final String rawTitle;
  final String baseTitle;
  final String? year;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? quality;
  final List<String> languages;
  final String? versionLabel;

  bool get isSeriesEpisode => seasonNumber != null && episodeNumber != null;

  const TitleMetadata({
    required this.rawTitle,
    required this.baseTitle,
    this.year,
    this.seasonNumber,
    this.episodeNumber,
    this.quality,
    this.languages = const [],
    this.versionLabel,
  });

  factory TitleMetadata.parse(String rawTitle) {
    final lower = rawTitle.toLowerCase();

    // Saison / Épisode
    int? seasonNumber;
    int? episodeNumber;
      final seasonMatch = RegExp(r's\s*(\d{1,2})\s*e\s*(\d{1,2})', caseSensitive: false).firstMatch(rawTitle);
    if (seasonMatch != null) {
      seasonNumber = int.tryParse(seasonMatch.group(1) ?? '');
      episodeNumber = int.tryParse(seasonMatch.group(2) ?? '');
    }

    // Année
    final yearMatch = RegExp(r'\b(19|20)\d{2}\b').firstMatch(rawTitle);
    final year = yearMatch?.group(0);

    // Qualité
    String? quality;
    if (lower.contains('4k') || lower.contains('2160p')) {quality = '4K';}
    else if (lower.contains('1080p') || lower.contains('fhd')) { quality = 'FHD';}
    else if (lower.contains('720p') || lower.contains('hd')) {quality = 'HD';}
    else if (lower.contains('sd')) {quality = 'SD';}

    // Langues
    final langs = <String>[];
    if (lower.contains('multi')) langs.add('MULTI');
    if (lower.contains('vostfr')) langs.add('VOSTFR');
    if (lower.contains('vf') || lower.contains('french') || lower.contains('vff')) langs.add('VF');

    // Nettoyage du titre
    String base = rawTitle;
    base = base.replaceAll(RegExp(r'^(\|[A-Z0-9\s]+\||\w{2,}\s*[:-])\s*', caseSensitive: false), '');
    if (seasonMatch != null && seasonMatch.start <= base.length) {
      base = base.substring(0, seasonMatch.start).trim();
    }
    const qualityTags = r'\b(4K|UHD|2160p|1080p|720p|480p|FHD|HD|SD|HEVC|H265|H\.265|X265|AAC|DTS)\b';
    base = base.replaceAll(RegExp(qualityTags, caseSensitive: false), '');
    const langTags = r'\b(MULTI|VOSTFR|VOST|VF|VO|VFF|FR|EN|VIP|RAW)\b';
    base = base.replaceAll(RegExp(langTags, caseSensitive: false), '');
    base = base.replaceAll(RegExp(r'\(?(19|20)\d{2}\)?'), '');
    base = base.replaceAll(RegExp(r'[\(\)\[\]\.\-_]'), ' ');
    // Supprime toute marque Sxx Exx restante (avec ou sans espaces)
    base = base.replaceAll(RegExp(r"S\s*\d{1,2}\s*E\s*\d{1,2}", caseSensitive: false), ' ');
    base = base.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (base.length < 2) {
      // Fallback : on découpe sur le motif saison même s'il est écrit avec espaces
      base = rawTitle.split(RegExp(r"S\\s*\\d{1,2}", caseSensitive: false)).first;
    }
    if (base.isEmpty) {
      base = rawTitle.trim();
    }

    // Version label (ce qui reste après nettoyage pour distinguer les variantes)
    String? versionLabel;
    if (base.isNotEmpty) {
      String label = rawTitle;
      label = label.replaceAll(RegExp(RegExp.escape(base), caseSensitive: false), '');
      label = label.replaceAll(RegExp(r'(\|[A-Z0-9\s]+\||\w{2,}\s*[:-])', caseSensitive: false), '');
      label = label.replaceAll(RegExp(r'\(?(19|20)\d{2}\)?'), '');
      const tagsToRemove = r'\b(4K|UHD|2160p|1080p|720p|480p|FHD|HD|SD|HEVC|H265|X265|MULTI|VOSTFR|VOST|VF|VO|VFF|FR|EN|TRUEFRENCH)\b';
      label = label.replaceAll(RegExp(tagsToRemove, caseSensitive: false), '');
      label = label.replaceAll(RegExp(r'^[ \t\-_.\(\)\[\]]+'), '');
      label = label.replaceAll(RegExp(r'[ \t\-_.\(\)\[\]]+$'), '');
      label = label.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (label.isNotEmpty) versionLabel = label;
    }

    return TitleMetadata(
      rawTitle: rawTitle,
      baseTitle: base,
      year: year,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      quality: quality,
      languages: langs,
      versionLabel: versionLabel,
    );
  }
}

class M3uEntry {
  final String url;
  final M3uContentType type;
  final TitleMetadata title;
  final String? logoUrl;
  final int? streamId;    // stream_id extrait de l'URL (utile pour EPG/replay)
  final String? tvgId;    // tvg-id depuis #EXTINF (pour matching EPG/XMLTV)
  final int? catchupDays; // Nombre de jours de replay (null = non supporté)

  const M3uEntry({
    required this.url,
    required this.type,
    required this.title,
    this.logoUrl,
    this.streamId,
    this.tvgId,
    this.catchupDays,
  });

  /// Vrai si le stream supporte le catchup/replay selon les métadonnées M3U.
  bool get supportsCatchup => catchupDays != null && catchupDays! > 0;

  // Accesseurs de compat
  String get rawTitle => title.rawTitle;
  String get displayName => title.baseTitle;
  bool get isSerie => type == M3uContentType.series;
  String? get saison => title.seasonNumber?.toString().padLeft(2, '0');
  String? get episode => title.episodeNumber?.toString().padLeft(2, '0');
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
  bool _showTv = true;
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
      String? pendingMetadata;
      final regExpSerie = RegExp(r"S\s*(\d{1,2})\s*E\s*(\d{1,2})", caseSensitive: false);
      final regExpLogo = RegExp(r'tvg-logo="([^"]*)"');
      final regExpTvgId = RegExp(r'tvg-id="([^"]*)"');
      final regExpCatchup = RegExp(r'catchup="([^"]*)"', caseSensitive: false);
      final regExpCatchupDays = RegExp(r'catchup-days="(\d+)"', caseSensitive: false);

      await file.openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((line) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) return;

        if (trimmed.startsWith("#EXTINF")) {
          pendingMetadata = trimmed;
        } else if (trimmed.startsWith("http")) {
          String url = trimmed;
          String? title;
          String? logoUrl;
          String? tvgId;
          int? catchupDays;

          // --- LOGIQUE POUR FORMAT A (#EXTINF suivi par URL) ---
          if (pendingMetadata != null) {
            final commaIndex = pendingMetadata!.lastIndexOf(',');
            if (commaIndex != -1) {
              title = pendingMetadata!.substring(commaIndex + 1).trim();
              logoUrl = regExpLogo.firstMatch(pendingMetadata!)?.group(1);
              tvgId = regExpTvgId.firstMatch(pendingMetadata!)?.group(1)?.trim();

              // catchup="default/append/flussonic/xtream" = replay supporté
              // catchup="" / catchup="false" / catchup="no" = non supporté
              final catchupValue = regExpCatchup.firstMatch(pendingMetadata!)?.group(1)?.toLowerCase() ?? '';
              final hasCatchup = catchupValue.isNotEmpty
                  && catchupValue != 'false'
                  && catchupValue != 'no'
                  && catchupValue != '0';
              if (hasCatchup) {
                final daysStr = regExpCatchupDays.firstMatch(pendingMetadata!)?.group(1);
                // Si catchup-days absent mais catchup présent : on assume 7j par défaut
                catchupDays = int.tryParse(daysStr ?? '') ?? 7;
              }
            }
            pendingMetadata = null; // Consomme les métadonnées
          }
          // --- LOGIQUE POUR FORMAT B (URL contient #Name:) ---
          // Sert de fallback si #EXTINF est absent
          else if (trimmed.contains("#Name:")) {
            final parts = trimmed.split("#Name:");
            url = parts[0].trim();
            if (parts.length > 1) {
              title = parts[1].trim();
            }
          }

          if (title != null && title.isNotEmpty) {
            _addEntry(
              rawTitle: title,
              url: url,
              regExpSerie: regExpSerie,
              logoUrl: logoUrl,
              tvgId: tvgId,
              catchupDays: catchupDays,
            );
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

  void _addEntry({
    required String rawTitle,
    required String url,
    required RegExp regExpSerie,
    String? logoUrl,
    String? tvgId,
    int? catchupDays,
  }) {
    final lowerUrl = url.toLowerCase();
    final metadata = TitleMetadata.parse(rawTitle);

    // Classification simple : film/series par URL, sinon TV (avec fallback série si motif SxxExx).
    M3uContentType type;
    if (lowerUrl.contains('/movie/')) {
      type = M3uContentType.movie;
    } else if (lowerUrl.contains('/series/')) {
      type = M3uContentType.series;
    } else if (metadata.isSeriesEpisode || regExpSerie.firstMatch(rawTitle) != null) {
      type = M3uContentType.series;
    } else {
      type = M3uContentType.tv;
    }

    // Extraction du stream_id (plus robuste : live/user/pass/<id>.<ext>, ou dernier segment numérique)
    final streamId = _extractStreamId(url);

    final entry = M3uEntry(
      url: url,
      type: type,
      title: metadata,
      logoUrl: logoUrl,
      streamId: streamId,
      tvgId: tvgId,
      catchupDays: catchupDays,
    );

    if (type == M3uContentType.series) {
      _seriesList.add(entry);
    } else if (type == M3uContentType.movie) {
      _filmsList.add(entry);
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

    if (_showFilms) {
      for (var e in _filmsList) {
        if (matches(e)) newGroupedFilms.putIfAbsent(e.displayName, () => []).add(e);
      }
    }
    if (_showSeries) {
      for (var e in _seriesList) {
        if (matches(e)) {
          newGroupedSeries.putIfAbsent(e.displayName, () => {});
          final s = e.saison ?? '00';
          newGroupedSeries[e.displayName]!.putIfAbsent(s, () => []).add(e);
        }
      }
    }
    if (_showTv) {
      for (var e in _tvList) {
        if (matches(e)) newGroupedTv.putIfAbsent(e.displayName, () => []).add(e);
      }
    }

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
      _flatList = [..._groupedFilms.keys, ..._groupedSeries.keys, ..._groupedTv.keys];
    });
  }

  //############################################################################
  // UI PRINCIPALE
  //############################################################################

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (_isProcessing) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null) return Center(child: Text("Erreur critique: $_errorMessage", style: const TextStyle(color: Colors.red)));

    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        SliverAppBar(
          // 🎯 LÉGÈRE OMBRE / ÉLÉVATION au scroll pour un effet plus doux
          elevation: innerBoxIsScrolled ? 4.0 : 0.0,
          title: Container(
            // 🎯 Amélioration visuelle de la barre de recherche
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(200),
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
            preferredSize: const Size.fromHeight(kToolbarHeight + 12),
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

          if (_groupedTv.containsKey(item)) return _buildTvCard(item, _groupedTv[item]!);
          if (_groupedSeries.containsKey(item)) return _buildSerieCard(item, _groupedSeries[item]!);
          if (_groupedFilms.containsKey(item)) return _buildFilmCard(item, _groupedFilms[item]!);
          return const SizedBox.shrink();
        },
      ),
    );
  }

  //############################################################################
  // CARTES & ITEMS
  //############################################################################

  Widget _buildImagePlaceholder({required IconData icon, required Color color}) {
    return Container(
      width: 45,
      height: 65,
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color),
    );
  }

  Widget _buildCardImage(List<M3uEntry> versions, IconData fallbackIcon, Color fallbackColor) {
    final logoUrl = versions.isNotEmpty ? versions.first.logoUrl : null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8.0),
      child: logoUrl != null && logoUrl.isNotEmpty
          ? Image.network(
        logoUrl,
        width: 45,
        height: 65,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildImagePlaceholder(icon: fallbackIcon, color: fallbackColor),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildImagePlaceholder(icon: fallbackIcon, color: fallbackColor);
        },
      )
          : _buildImagePlaceholder(icon: fallbackIcon, color: fallbackColor),
    );
  }

  Widget _buildFilmCard(String displayName, List<M3uEntry> versions) {
    // 1. Détection de l'Homonyme
    final uniqueYears = versions.map((v) => v.title.year).where((y) => y != null).toSet();
    final isHomonymConflict = versions.length > 1 && uniqueYears.length > 1;

    // 2. Construction des Chips Uniques (utilisée si ce n'est PAS un conflit d'homonymes)
    final allQualityChips = versions.map((v) => _qualityChip(v.title));
    final allLanguageChips = versions.expand((v) => _languageChips(v.title));
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
              _buildCardImage(versions, Icons.movie, Colors.blue),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    if (isHomonymConflict)
                      Text('Versions disponibles: ${uniqueYears.join(', ')}', style: TextStyle(color: Colors.white70, fontSize: 12))
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
    final allVersions = saisons.values.expand((list) => list).toList();

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: _buildCardImage(allVersions, Icons.tv, Colors.purple),
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

  Widget _buildTvCard(String displayName, List<M3uEntry> versions) {
    final bool hasReplay = versions.isNotEmpty && versions.first.supportsCatchup;

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
              _buildCardImage(versions, Icons.live_tv, Colors.green),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (versions.length > 1)
                          Text('${versions.length} flux', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        if (versions.length > 1 && hasReplay)
                          const Text(" • ", style: TextStyle(color: Colors.white70, fontSize: 12)),
                        if (hasReplay)
                          Icon(Icons.replay_circle_filled, color: Colors.blueAccent, size: 14),
                      ],
                    ),
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

  //############################################################################
  // NAVIGATION & ACTIONS
  //############################################################################

  Future<void> _onEntrySelected(List<M3uEntry> versions) async {
    if (versions.isEmpty || !mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();

    final entry = versions.first;
    M3uEntry selectedEntry = versions.first;

    if (versions.length > 1) {
      final choice = await _showVersionSelector(versions);
      if (choice == null) return;
      selectedEntry = choice;
    }

    if (!mounted) return;

    if (selectedEntry.type == M3uContentType.tv) {
      await _showTvActionSheet(selectedEntry);
    } else {
      _showActionSheet(selectedEntry);
    }
  }

  Future<M3uEntry?> _showVersionSelector(List<M3uEntry> versions) {
    return showModalBottomSheet<M3uEntry>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
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
                  final year = v.title.year;
                  final extraInfo = v.title.versionLabel ?? "Standard / Inconnue";
                  final qualityChip = _qualityChip(v.title);
                  final langChips = _languageChips(v.title);
                  final allChips = <Widget>[];

                  if (year != null) {
                    allChips.add(Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(border: Border.all(color: Colors.white60), borderRadius: BorderRadius.circular(4)),
                      child: Text(year, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                    ));
                  }
                  if (qualityChip is! SizedBox) allChips.add(qualityChip);
                  allChips.addAll(langChips);

                  Widget titleWidget;
                  Widget? subtitleWidget;

                  if (allChips.isNotEmpty) {
                    titleWidget = Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: allChips);
                    if (extraInfo.isNotEmpty && extraInfo != "Standard / Inconnue") {
                      subtitleWidget = Text(extraInfo, style: const TextStyle(fontSize: 12, color: Colors.grey));
                    }
                  } else {
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
    final bool hasEpisode = entry.title.isSeriesEpisode;

    Future<dynamic>? tmdbFuture;
    if (hasEpisode && entry.title.seasonNumber != null && entry.title.episodeNumber != null) {
      tmdbFuture = TmdbService.instance.getEpisodeDetails(
        entry.displayName,
        entry.title.seasonNumber!,
        entry.title.episodeNumber!,
        yearFilter: entry.title.year,
      );
    } else if (entry.type == M3uContentType.movie) {
      tmdbFuture = TmdbService.instance.getFullDetails(entry.displayName, isTv: false);
    } else if (entry.type == M3uContentType.series) {
      tmdbFuture = TmdbService.instance.getFullDetails(entry.displayName, isTv: true);
    }

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // AFFICHE (si disponible)
                if (entry.logoUrl != null && entry.logoUrl!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        entry.logoUrl!,
                        height: 150,
                        errorBuilder: (ctx, err, stack) => const SizedBox.shrink(),
                      ),
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(entry.displayName, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                ),
                const SizedBox(height: 8),
                if (entry.title.isSeriesEpisode)
                  FutureBuilder<dynamic>(
                    future: tmdbFuture,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: SizedBox(
                            height: 4,
                            width: 80,
                            child: LinearProgressIndicator(),
                          ),
                        );
                      }
                      final data = snap.data;
                      if (data == null) return const SizedBox.shrink();

                      String? title;
                      String? overview;
                      String? airDate;

                      if (data is Map<String, dynamic>) {
                        title = data['name'] as String?;
                        overview = data['overview'] as String?;
                        airDate = data['air_date'] as String?;
                      } else if (data is Media) {
                        title = data.title;
                        overview = data.overview;
                      }

                      // Évite de répéter le titre de la série : on n'affiche le titre d'épisode que s'il diffère.
                      final parsedEpisodeName = _getEpisodeName(entry);
                      if (title == null || title.isEmpty) {
                        title = parsedEpisodeName;
                      } else if (title == entry.displayName) {
                        title = parsedEpisodeName;
                      }

                      final hasTitle = title.isNotEmpty;
                      final hasOverview = overview != null && overview.isNotEmpty;

                      if (!hasTitle && !hasOverview) return const SizedBox.shrink();

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (hasTitle) ...[
                              Text(
                                title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 6),
                            ],
                            if (airDate != null && airDate.isNotEmpty) ...[
                              Text(
                                "Diffusé le: $airDate",
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                              ),
                              const SizedBox(height: 6),
                            ],
                            if (hasOverview) ...[
                              const SizedBox(height: 8),
                              Text(
                                overview,
                                style: Theme.of(context).textTheme.bodySmall,
                                maxLines: 5,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                if (entry.title.isSeriesEpisode) const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _qualityChip(entry.title),
                    ..._languageChips(entry.title),
                    if (entry.title.isSeriesEpisode)
                      _episodeMetaChip(entry.title),
                  ],
                ),
                const SizedBox(height: 24),
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
                ListTile(
                  leading: const Icon(Icons.play_arrow),
                  title: Text(l10n.actionSheetPlay),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerPage(path: entry.url, title: entry.displayName, sourceType: VideoSourceType.networkWithCache)));
                  },
                ),
                if (entry.type == M3uContentType.tv && entry.streamId != null)
                  ListTile(
                    leading: const Icon(Icons.replay),
                    title: Text("Replay${entry.catchupDays != null ? ' (${entry.catchupDays}j)' : ''}"),
                    onTap: () async {
                      Navigator.pop(context);
                      final replayProgram = await showModalBottomSheet<ReplayProgram>(
                        context: context,
                        showDragHandle: true,
                        isScrollControlled: true,
                        builder: (_) => ReplaySheet(streamId: entry.streamId!, streamUrl: entry.url),
                      );
                      if (replayProgram != null) {
                        final timeshiftUrl = await ReplayService().buildTimeshiftUrl(
                          streamId: entry.streamId!,
                          start: replayProgram.start,
                          end: replayProgram.end,
                          streamUrl: entry.url,
                        );
                        if (timeshiftUrl != null && mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PlayerPage(
                                path: timeshiftUrl,
                                title: replayProgram.title,
                                sourceType: VideoSourceType.network,
                              ),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.download),
                  title: Text(l10n.actionSheetDownload),
                  onTap: () {
                    Navigator.pop(context);
                    final downloadName = _buildDownloadName(entry);
                    final releaseYear = entry.type == M3uContentType.movie ? entry.title.year : null;
                    verifierEtTelecharger(
                      url: entry.url,
                      nom: downloadName,
                      releaseYear: releaseYear,
                      context: navigatorKey.currentContext!,
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showTvActionSheet(M3uEntry entry) async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.displayName, style: Theme.of(context).textTheme.headlineSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _qualityChip(entry.title),
                    ..._languageChips(entry.title),
                  ],
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.play_arrow),
                  title: Text(AppLocalizations.of(context)!.actionSheetPlay),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PlayerPage(
                          path: entry.url,
                          title: entry.displayName,
                          sourceType: VideoSourceType.network,
                        ),
                      ),
                    );
                  },
                ),
                if (entry.streamId != null)
                  ListTile(
                    leading: const Icon(Icons.replay_circle_filled),
                    title: Text("Replay${entry.catchupDays != null ? ' (${entry.catchupDays}j)' : ''}"),
                    onTap: () async {
                      Navigator.pop(context);
                      final replayProgram = await showModalBottomSheet<ReplayProgram>(
                        context: context,
                        showDragHandle: true,
                        isScrollControlled: true,
                        builder: (_) => ReplaySheet(streamId: entry.streamId!, streamUrl: entry.url),
                      );
                      if (replayProgram != null) {
                        final timeshiftUrl = await ReplayService().buildTimeshiftUrl(
                          streamId: entry.streamId!,
                          start: replayProgram.start,
                          end: replayProgram.end,
                          streamUrl: entry.url,
                        );
                        if (timeshiftUrl != null && mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PlayerPage(
                                path: timeshiftUrl,
                                title: replayProgram.title,
                                sourceType: VideoSourceType.network,
                              ),
                            ),
                          );
                        } else if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Replay indisponible pour ce flux")),
                          );
                        }
                      }
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  //############################################################################
  // HELPERS (Regex & Parsing)
  //############################################################################

  /// Tente d'extraire un stream_id depuis l'URL Xtream (live/user/pass/<id>.<ext> ou query ?stream=).
  int? _extractStreamId(String url) {
    try {
      final uri = Uri.parse(url);
      // 1) Query param stream
      final qpId = int.tryParse(uri.queryParameters['stream'] ?? '');
      if (qpId != null) return qpId;

      // 2) Segment live/username/password/<id>.<ext>
      for (final segment in uri.pathSegments.reversed) {
        // retire extension éventuelle
        final base = segment.split('.').first;
        final id = int.tryParse(base);
        if (id != null) return id;
      }
    } catch (_) {}
    // 3) Regex de secours sur la chaîne brute
    final m = RegExp(r'/live/[^/]+/[^/]+/(\d+)', caseSensitive: false).firstMatch(url);
    if (m != null) return int.tryParse(m.group(1) ?? '');
    return null;
  }

  String _getEpisodeName(M3uEntry entry) {
    final regex = RegExp(r"S\s*\d{1,2}\s*E\s*\d{1,2}", caseSensitive: false);
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

  Widget _qualityChip(TitleMetadata meta) {
    switch (meta.quality) {
      case '4K':
        return _tag('4K', Colors.red);
      case 'FHD':
        return _tag('FHD', Colors.amber);
      case 'HD':
        return _tag('HD', Colors.blue);
      case 'SD':
        return _tag('SD', Colors.teal);
      default:
        return const SizedBox.shrink();
    }
  }

  List<Widget> _languageChips(TitleMetadata meta) {
    final chips = <Widget>[];
    final seen = <String>{};
    for (final lang in meta.languages) {
      if (!seen.add(lang)) continue;
      if (lang == 'MULTI') chips.add(_tag('MULTI', Colors.purple));
      if (lang == 'VOSTFR') chips.add(_tag('VOSTFR', Colors.orange));
      if (lang == 'VF') chips.add(_tag('VF', Colors.blue));
    }
    return chips;
  }

  Widget _episodeMetaChip(TitleMetadata meta) {
    final season = meta.seasonNumber?.toString().padLeft(2, '0') ?? '--';
    final episode = meta.episodeNumber?.toString().padLeft(2, '0') ?? '--';
    return _tag('S$season E$episode', Colors.cyan);
  }

  /// Construit un nom de fichier riche (titre + SxxEyy éventuel + label de version).
  String _buildDownloadName(M3uEntry entry) {
    final parts = <String>[];
    parts.add(entry.displayName);

    if (entry.type == M3uContentType.series && entry.title.isSeriesEpisode) {
      final s = entry.saison ?? '00';
      final e = entry.episode ?? '00';
      parts.add('S$s E$e');
    }

    if (entry.title.versionLabel != null && entry.title.versionLabel!.isNotEmpty) {
      parts.add(entry.title.versionLabel!);
    }

    return parts.join(' ').trim();
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
    const Color selectedBg = kAetherPrimaryPurple;
    const Color selectedLabel = kTextDarkPrimary;
    const Color unselectedBg = kContainerDark;
    const Color unselectedBorder = kAetherSecondaryCyan;
    const Color unselectedLabel = kTextDarkSecondary;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          FilterChip(
            label: Text(l10n.searchFilterFilms),
            selected: _showFilms,
            onSelected: (s) => setState(() { _showFilms = s; _filterAndGroupResults(); }),
            selectedColor: selectedBg,
            backgroundColor: unselectedBg,
            labelStyle: _showFilms ? TextStyle(color: selectedLabel, fontWeight: FontWeight.bold) : TextStyle(color: unselectedLabel),
            side: _showFilms ? BorderSide.none : BorderSide(color: unselectedBorder.withAlpha(100)),
          ),
          const SizedBox(width: 8),
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
