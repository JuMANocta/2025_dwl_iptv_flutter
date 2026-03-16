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
import 'package:aetherStream/feature/replay/replay_date_picker_sheet.dart';
import 'package:aetherStream/data/services/replay_service.dart';
import 'package:aetherStream/data/services/xmltv_service.dart';
import 'package:aetherStream/data/models/xmltv_program.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:aetherStream/main.dart'; // Pour navigatorKey
import 'package:aetherStream/core/themes/colors.dart';

//############################################################################
// WIDGET "CONTENEUR" PRINCIPAL (RecherchePage)
//############################################################################

class RecherchePage extends StatefulWidget {
  /// Chemin de playlist pré-chargé par _LaunchDecider — évite un double appel à getOrDownloadPlaylist().
  final String? initialPlaylistPath;
  const RecherchePage({super.key, this.initialPlaylistPath});

  @override
  State<RecherchePage> createState() => _RecherchePageState();
}

class _RecherchePageState extends State<RecherchePage> {
  late Future<String> _playlistPathFuture;
  String? _currentAccountLabel;
  Key _rechercheM3UKey = UniqueKey(); // Force le reload propre du widget enfant
  bool _initialPathConsumed = false;

  @override
  void initState() {
    super.initState();
    _loadPlaylistPath();
  }

  void _loadPlaylistPath({bool forceDownload = false}) {
    setState(() {
      if (forceDownload) {
        _playlistPathFuture = PlaylistService.downloadCurrentM3U();
      } else if (!_initialPathConsumed && widget.initialPlaylistPath != null) {
        // Chemin déjà résolu par _LaunchDecider → pas de second appel réseau
        _initialPathConsumed = true;
        _playlistPathFuture = Future.value(widget.initialPlaylistPath);
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

  // Patterns compilés une seule fois pour toute la durée de l'app.
  // CRITIQUE : TitleMetadata.parse() est appelée pour chaque entrée M3U.
  // Recréer un RegExp() à chaque appel = recompilation → ~200 000 compilations pour 10 000 entrées.
  static final _reSeason       = RegExp(r's\s*(\d{1,2})\s*e\s*(\d{1,2})', caseSensitive: false);
  static final _reYear         = RegExp(r'\b(19|20)\d{2}\b');
  static final _reQ4K          = RegExp(r'\b(4k|uhd|2160p)\b');
  static final _reQFhd         = RegExp(r'\b(fhd|1080p)\b');
  static final _reQHd          = RegExp(r'\b(hd|720p)\b');
  static final _reQSd          = RegExp(r'\b(sd|480p)\b');
  static final _reLangMulti    = RegExp(r'\bmulti\b');
  static final _reLangVostfr   = RegExp(r'\bvostfr\b');
  static final _reLangVf       = RegExp(r'\b(vf|vff|truefrench|french)\b');
  static final _rePrefix       = RegExp(r'^(\|[A-Z0-9\s]+\||\w{2,}\s*[:-])\s*', caseSensitive: false);
  static final _reQualityTags  = RegExp(r'\b(4K|UHD|2160p|1080p|720p|480p|FHD|HD|SD|HEVC|H265|H\.265|X265|AAC|DTS|HDR|DV|HLG)\b', caseSensitive: false);
  static final _reLangTags     = RegExp(r'\b(MULTI|VOSTFR|VOST|VF|VO|VFF|VIP|RAW|TRUEFRENCH|FRENCH)\b', caseSensitive: false);
  static final _reFrEn         = RegExp(r'[\(\[]\s*(FR|EN)\s*[\)\]]', caseSensitive: false);
  static final _reYearClean    = RegExp(r'\(?(19|20)\d{2}\)?');
  static final _rePunct        = RegExp(r'[\(\)\[\]\.\-_/]');
  static final _reSeasonClean  = RegExp(r'S\s*\d{1,2}\s*E\s*\d{1,2}', caseSensitive: false);
  static final _reSpaces       = RegExp(r'\s+');
  static final _reSeasonFb     = RegExp(r'S\s*\d{1,2}', caseSensitive: false);
  static final _reLabelPrefix  = RegExp(r'^(\|[A-Z0-9\s]+\||\w{2,}\s*[:-])', caseSensitive: false);
  static final _reAllTags      = RegExp(r'\b(4K|UHD|2160p|1080p|720p|480p|FHD|HD|SD|HEVC|H265|X265|HDR|DV|HLG|MULTI|VOSTFR|VOST|VF|VO|VFF|VIP|RAW|TRUEFRENCH|FRENCH)\b', caseSensitive: false);
  static final _reTrimStart    = RegExp(r'^[ \t\-_.\(\)\[\]]+');
  static final _reTrimEnd      = RegExp(r'[ \t\-_.\(\)\[\]]+$');

  factory TitleMetadata.parse(String rawTitle) {
    final lower = rawTitle.toLowerCase();

    // Saison / Épisode
    final seasonMatch = _reSeason.firstMatch(rawTitle);
    final seasonNumber  = seasonMatch != null ? int.tryParse(seasonMatch.group(1) ?? '') : null;
    final episodeNumber = seasonMatch != null ? int.tryParse(seasonMatch.group(2) ?? '') : null;

    // Année
    final year = _reYear.firstMatch(rawTitle)?.group(0);

    // Qualité — ordre du plus précis au plus générique
    String? quality;
    if (_reQ4K.hasMatch(lower))       { quality = '4K'; }
    else if (_reQFhd.hasMatch(lower)) { quality = 'FHD'; }
    else if (_reQHd.hasMatch(lower))  { quality = 'HD'; }
    else if (_reQSd.hasMatch(lower))  { quality = 'SD'; }

    // Langues
    final langs = <String>[];
    if (_reLangMulti.hasMatch(lower))  langs.add('MULTI');
    if (_reLangVostfr.hasMatch(lower)) langs.add('VOSTFR');
    if (_reLangVf.hasMatch(lower))     langs.add('VF');

    // Nettoyage du titre
    String base = rawTitle;
    base = base.replaceAll(_rePrefix, '');
    if (seasonMatch != null && seasonMatch.start <= base.length) {
      base = base.substring(0, seasonMatch.start).trim();
    }
    base = base.replaceAll(_reQualityTags, '');
    base = base.replaceAll(_reLangTags, '');
    base = base.replaceAll(_reFrEn, ' ');
    base = base.replaceAll(_reYearClean, '');
    base = base.replaceAll(_rePunct, ' ');
    base = base.replaceAll(_reSeasonClean, ' ');
    base = base.replaceAll(_reSpaces, ' ').trim();
    if (base.length < 2) {
      base = rawTitle.split(_reSeasonFb).first;
    }
    if (base.isEmpty) base = rawTitle.trim();

    // Version label (ce qui reste après nettoyage pour distinguer les variantes)
    // Note : RegExp.escape(base) est dynamique → ne peut pas être mis en static final
    String? versionLabel;
    if (base.isNotEmpty) {
      String label = rawTitle;
      label = label.replaceAll(RegExp(RegExp.escape(base), caseSensitive: false), '');
      label = label.replaceAll(_reLabelPrefix, '');
      label = label.replaceAll(_reYearClean, '');
      label = label.replaceAll(_reAllTags, '');
      label = label.replaceAll(_reFrEn, ' ');
      label = label.replaceAll(_reTrimStart, '');
      label = label.replaceAll(_reTrimEnd, '');
      label = label.trim().replaceAll(_reSpaces, ' ');
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
  final int? streamId;       // stream_id extrait de l'URL (utile pour EPG/replay)
  final String? tvgId;       // tvg-id depuis #EXTINF (pour matching EPG/XMLTV)
  final int? catchupDays;    // Nombre de jours de replay (null = non supporté)
  final String? catchupSource; // Template URL catchup (ex: "?utc={utc}&lutc={lutc}" Flussonic)
  final String? groupTitle;  // group-title depuis #EXTINF (ex: "MANGAS", "ANIMATION | FAMILIALE | ENFANTS")
  const M3uEntry({
    required this.url,
    required this.type,
    required this.title,
    this.logoUrl,
    this.streamId,
    this.tvgId,
    this.catchupDays,
    this.catchupSource,
    this.groupTitle,
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
  double _loadingProgress = 0.0;
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
      if (mounted) setState(() { _isProcessing = false; _errorMessage = 'Fichier introuvable'; });
      return;
    }
    try {
      final bytes = await file.readAsBytes();
      String content;
      try {
        content = utf8.decode(bytes);
        debugPrint('✅ M3U: encodage UTF-8 détecté');
      } catch (_) {
        content = latin1.decode(bytes);
        debugPrint('⚠️ M3U: fallback Latin-1 (fichier non-UTF-8)');
      }

      final regExpSerie       = RegExp(r"S\s*(\d{1,2})\s*E\s*(\d{1,2})", caseSensitive: false);
      final regExpLogo        = RegExp(r'tvg-logo="([^"]*)"');
      final regExpTvgId       = RegExp(r'tvg-id="([^"]*)"');
      final regExpGroupTitle  = RegExp(r'group-title="([^"]*)"');
      final regExpCatchup     = RegExp(r'catchup="([^"]*)"', caseSensitive: false);
      final regExpCatchupDays = RegExp(r'catchup-days="(\d+)"', caseSensitive: false);
      final regExpCatchupSrc  = RegExp(r'catchup-source="([^"]*)"', caseSensitive: false);

      String? pendingMetadata;
      // Compte le total d'entrées pour la barre de progression (le fichier est déjà en mémoire)
      final lines = const LineSplitter().convert(content);
      final totalEntries = lines.where((l) => l.trimLeft().startsWith('#EXTINF')).length;
      int parsedEntries = 0;

      // Yield basé sur le temps écoulé : on redonne la main à Flutter dès qu'on a
      // consommé ~8ms (demi-frame à 60fps) — s'adapte automatiquement à la vitesse du device.
      final sw = Stopwatch()..start();

      for (final line in lines) {
        if (sw.elapsedMilliseconds > 8) {
          await Future.delayed(Duration.zero);
          sw.reset();
          if (mounted) setState(() {
            _loadingProgress = totalEntries > 0 ? parsedEntries / totalEntries : 0.0;
          });
        }

        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        if (trimmed.startsWith('#EXTINF')) {
          pendingMetadata = trimmed;
          parsedEntries++;
        } else if (trimmed.startsWith('http')) {
          String url = trimmed;
          String? title;
          String? logoUrl;
          String? tvgId;
          String? groupTitle;
          int?    catchupDays;
          String? catchupSource;

          if (pendingMetadata != null) {
            final commaIndex = pendingMetadata!.lastIndexOf(',');
            if (commaIndex != -1) {
              title      = pendingMetadata!.substring(commaIndex + 1).trim();
              logoUrl    = regExpLogo.firstMatch(pendingMetadata!)?.group(1);
              tvgId      = regExpTvgId.firstMatch(pendingMetadata!)?.group(1)?.trim();
              groupTitle = regExpGroupTitle.firstMatch(pendingMetadata!)?.group(1)?.trim();
              final catchupValue = regExpCatchup.firstMatch(pendingMetadata!)?.group(1)?.toLowerCase() ?? '';
              final hasCatchup = catchupValue.isNotEmpty
                  && catchupValue != 'false'
                  && catchupValue != 'no'
                  && catchupValue != '0';
              if (hasCatchup) {
                final daysStr = regExpCatchupDays.firstMatch(pendingMetadata!)?.group(1);
                catchupDays   = int.tryParse(daysStr ?? '') ?? 7;
                catchupSource = regExpCatchupSrc.firstMatch(pendingMetadata!)?.group(1);
              }
            }
            pendingMetadata = null;
          } else if (trimmed.contains('#Name:')) {
            final parts = trimmed.split('#Name:');
            url   = parts[0].trim();
            title = parts.length > 1 ? parts[1].trim() : null;
          }

          if (title != null && title.isNotEmpty) {
            _addEntry(
              rawTitle: title,
              url: url,
              regExpSerie: regExpSerie,
              logoUrl: logoUrl,
              tvgId: tvgId,
              groupTitle: groupTitle,
              catchupDays: catchupDays,
              catchupSource: catchupSource,
            );
          }
        }
      }

      if (mounted) {
        // Yield avant le groupage — _filterAndGroupResults() est aussi CPU-intensif
        setState(() => _loadingProgress = 1.0);
        await Future.delayed(Duration.zero);
        _filterAndGroupResults();
        setState(() => _isProcessing = false);
      }
    } catch (e) {
      debugPrint('❌ Erreur parsing M3U: $e');
      if (mounted) setState(() { _isProcessing = false; _errorMessage = e.toString(); });
    }
  }

  void _addEntry({
    required String rawTitle,
    required String url,
    required RegExp regExpSerie,
    String? logoUrl,
    String? tvgId,
    String? groupTitle,
    int? catchupDays,
    String? catchupSource,
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
      groupTitle: groupTitle,
      catchupDays: catchupDays,
      catchupSource: catchupSource,
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

  /// Retourne un label d'affichage depuis le group-title M3U.
  /// Priorité : mappings sémantiques connus → fallback nettoyage automatique.
  /// Null uniquement si le group-title est vide ou non informatif.
  static String? _contentCategoryLabel(String? groupTitle) {
    if (groupTitle == null || groupTitle.isEmpty) return null;
    final g = groupTitle.toUpperCase();

    // ── Mappings sémantiques précis (labels FR courts et propres) ─────────────
    if (g.contains('MANGA') || g.contains('ANIMÉ') || g.contains('ANIME')) return 'Manga';
    if (g.contains('ANIMAT') || g.contains('CARTOON')) return 'Animation';
    if (g.contains('DOCU')) return 'Documentaire';
    if (g.contains('BIOPIC')) return 'Biopic';
    if (g.contains('ENFANT') || g.contains('KIDS') || g.contains('JEUNESSE') ||
        g.contains('FAMILIALE') || g.contains('FAMILLE')) return 'Jeunesse';
    if (g.contains('CORÉEN') || g.contains('KOREAN') || g.contains('KOREA')) return 'Coréen';
    if (g.contains('TURC') || g.contains('TURQU') || g.contains('TÜRK')) return 'Turc';
    if (g.contains('MAGHRÉB') || g.contains('MAGHRÈB') || g.contains('MAGHREB')) return 'Maghrébin';
    if (g.contains('RAMADAN')) return 'Ramadan';
    if (g.contains('ARAB') || g.contains('العربية') || g.contains('عربية')) return 'Arabe';
    if (g.contains('INDIA') || g.contains('INDE') || g.contains('भारतीय')) return 'Indien';
    if (g.contains('DISNEY')) return 'Disney+';
    if (g.contains('PARAMOUNT')) return 'Paramount+';
    if (g.contains('BRUTX')) return 'BrutX';
    if (g.startsWith('3D')) return '3D';
    if (g.contains('IMAX')) return 'IMAX';
    if (g.contains('4K HDR') || (g.contains('4K') && g.contains('HDR'))) return '4K HDR';
    if (g.contains('SUPER-HÉR') || g.contains('SUPER-HER')) return 'Super-Héros';
    if (g.contains('SCIENCE FICTION') || g.contains('SC FICTION') || g.contains('SCI-FI')) return 'Sci-Fi';
    if (g.contains('FANTASTIQUE') || g.contains('FANTASY')) return 'Fantastique';
    if (g.contains('HORREUR') || g.contains('HORROR') || g.contains('ÉPOUVANTE')) return 'Horreur';
    if (g.contains('THRILLER')) return 'Thriller';
    if (g.contains('ACTION')) return 'Action';
    if (g.contains('AVENTURE') || g.contains('ADVENTURE')) return 'Aventure';
    if (g.contains('COMÉDIE') || g.contains('COMEDIE') || g.contains('COMEDY')) return 'Comédie';
    if (g.contains('DRAME') || g.contains('DRAMA')) return 'Drame';
    if (g.contains('ROMANCE')) return 'Romance';
    if (g.contains('WESTERN')) return 'Western';
    if (g.contains('POLICIER')) return 'Policier';
    if (g.contains('MAFIA') || g.contains('GANG')) return 'Mafia';
    if (g.contains('ESPIONNAGE') || g.contains('ESPIONN')) return 'Espionnage';
    if (g.contains('JURIDIQUE')) return 'Juridique';
    if (g.contains('PRISON')) return 'Prison';
    if (g.contains('MEDIEVAL') || g.contains('MÉDIÉVAL') || g.contains('MOYEN AGE')) return 'Médiéval';
    if (g.contains('MUSICAL')) return 'Musical';
    if (g.contains('BRAQUAGE') || g.contains('ARNAQUE')) return 'Braquage';
    if (g.contains('TUEUR EN SERIE') || g.contains('TUEUR EN SÉRIE')) return 'Tueur en série';
    if (g.contains('SURVIVAL') || g.contains('SURVIE')) return 'Survie';
    if (g.contains('CATASTROPHE')) return 'Catastrophe';
    if (g.contains('VENGEANCE')) return 'Vengeance';
    if (g.contains('MARITIME')) return 'Maritime';
    if (g.contains('SPECTACLE') || g.contains('CONCERT')) return 'Spectacle';
    if (g.contains('TÉLÉFILM') || g.contains('TELEFILM')) return 'Téléfilm';
    if (g.contains('VOITURE') || g.contains('CARS')) return 'Voitures';
    if (g.contains('LÉGENDAIRE') || g.contains('LEGENDAIRE') || g.contains('CULTE')) return 'Cultes';
    if (g.contains('CLASSIQUE') || g.contains('CLASSIC') || g.contains("70'S") || g.contains("80'S")) return 'Classiques';
    if (g.contains('OSCAR')) return 'Oscar';
    if (g.contains('BOX OFFICE')) return 'Box Office';
    if (g.contains('RECEM') || g.contains('RÉCEMM')) return 'New';
    if (g.contains('SÉLECTION') || g.contains('SELECTION')) return 'Sélection';
    if (g.contains('COUP DE COEUR')) return 'Coup de cœur';
    if (g.contains('FIN D\'AN') || g.contains('FIN D\'ANN')) return 'Fêtes';
    if (g.contains('MÉDECINE') || g.contains('MEDECINE')) return 'Médecine';
    if (g.contains('COMÉDIE MUSICAL') || g.contains('COMEDIE MUSICAL')) return 'Comédie musicale';
    if (g.contains('RÉALITÉ') || g.contains('REALITE')) return 'Téléréalité';
    if (g.contains('CRIME')) return 'Crime';
    if (g.contains('ARTS MARTIAUX')) return 'Arts martiaux';
    if (g.contains('DANSE') || g.contains('DANCE')) return 'Danse';
    if (g.contains('WORKOUT') || g.contains('SPORT')) return 'Sport';
    if (g.contains('GUERRE') || g.contains('WAR')) return 'Guerre';
    if (g.contains('HISTOIRE') || g.contains('HISTORIQUE')) return 'Histoire';
    if (g.contains('RAKUTEN')) return 'Rakuten TV';
    // ── Origines géographiques ────────────────────────────────────────────────
    if (g.contains('ALLEMAND') || g.contains('DEUTSCH')) return 'Allemagne';
    if (g.contains('ANGLAIS') || g.contains(' UK') || g.contains('(UK)')) return 'UK';
    if (g.contains('ESPAGNOL') || g.contains('ESPAÑA') || g.contains('SPAIN')) return 'Espagne';
    if (g.contains('ITALIEN')) return 'Italie';
    if (g.contains('RUSSE') || g.contains('РОССИЯ')) return 'Russie';
    if (g.contains('BRÉSIL') || g.contains('BRESIL') || g.contains('BRASILEIRO')) return 'Brésil';
    if (g.contains('BELG')) return 'Belgique';
    if (g.contains('POLONAIS') || g.contains('POLONEZ')) return 'Pologne';
    if (g.contains('PORTUGAIS') || g.contains('PORTUGUÊS')) return 'Portugal';
    if (g.contains('SUISSE') || g.contains('SWITZERLAND')) return 'Suisse';
    if (g.contains('SCANDINAV') || g.contains('DANEMARK') || g.contains('NORWAY') || g.contains('SWEDEN')) return 'Scandinavie';
    if (g.contains('TCHÈQU') || g.contains('TCHEQU') || g.contains('ČESKO')) return 'Tchéquie';
    if (g.contains('CROAT') || g.contains('HRVAT')) return 'Croatie';
    if (g.contains('GREC') || g.contains('ΕΛΛΗΝΙΚ')) return 'Grèce';
    if (g.contains('ALBANI') || g.contains('SHQIPTAR')) return 'Albanie';
    if (g.contains('ARMÉNI') || g.contains('ARMENI') || g.contains('ՀԱՅԵՐԵՆ')) return 'Arménie';
    if (g.contains('ROUMAIN') || g.contains('ROMANIAN')) return 'Roumanie';
    if (g.contains('BOSNIAK') || g.contains('BOSNIAQUE') || g.contains('BOSNA')) return 'Bosnie';
    if (g.contains('CANADA') || g.contains(' CA ') || g.contains('( CA )')) return 'Canada';
    if (g.contains('USA') || g.contains('ETATS-UNIS') || g.contains('ÉTATS-UNIS')) return 'USA';
    if (g.contains('PAYS-BAS') || g.contains('NETHERLANDS')) return 'Pays-Bas';

    // ── Fallback : nettoyage automatique du group-title brut ──────────────────
    // 1. Retire les listes de plateformes entre parenthèses : "( NETFLIX| PRIME | HBO...)"
    // 2. Prend le premier segment avant '|'
    // 3. Conserve la casse d'origine, trim, tronque à 20 chars max
    String clean = groupTitle
        .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
        .split('|').first
        .trim();
    if (clean.length > 20) clean = '${clean.substring(0, 18)}…';
    return clean.isNotEmpty ? clean : null;
  }

  /// Clé de regroupement partagée films ET séries.
  /// Format : "Titre" ou "Titre||Catégorie" quand le group-title est sémantiquement reconnu.
  /// Permet de séparer les homonymes (ex: "One Piece||Manga" vs "One Piece" live-action).
  static String _contentGroupKey(M3uEntry e) {
    final category = _contentCategoryLabel(e.groupTitle);
    return category != null ? '${e.displayName}||$category' : e.displayName;
  }

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
        if (matches(e)) newGroupedFilms.putIfAbsent(_contentGroupKey(e), () => []).add(e);
      }
    }
    if (_showSeries) {
      for (var e in _seriesList) {
        if (matches(e)) {
          final key = _contentGroupKey(e);
          newGroupedSeries.putIfAbsent(key, () => {});
          final s = e.saison ?? '00';
          newGroupedSeries[key]!.putIfAbsent(s, () => []).add(e);
        }
      }
    }
    if (_showTv) {
      for (var e in _tvList) {
        if (matches(e) && !_isHiddenTvVariant(e.title.rawTitle))
          newGroupedTv.putIfAbsent(_tvGroupKey(e.displayName), () => []).add(e);
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
      // Ordre M3U naturel — le provider place déjà les ajouts récents en tête de fichier
      _flatList = [..._groupedFilms.keys, ..._groupedSeries.keys, ..._groupedTv.keys];
    });
  }

  //############################################################################
  // LOADING SCREEN
  //############################################################################

  // Label qui s'allume (blanc) quand sa catégorie commence à être chargée
  Widget _LoadingLabel(String label, bool active) {
    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 400),
      style: TextStyle(
        color: active ? Colors.white70 : Colors.white24,
        fontSize: 13,
        fontWeight: active ? FontWeight.w600 : FontWeight.normal,
      ),
      child: Text(label),
    );
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: _loadingProgress,
                  minHeight: 3,
                  backgroundColor: Colors.white12,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _LoadingLabel('Films', _filmsList.isNotEmpty),
                  const SizedBox(width: 16),
                  _LoadingLabel('Séries', _seriesList.isNotEmpty),
                  const SizedBox(width: 16),
                  _LoadingLabel('Chaînes', _tvList.isNotEmpty),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  //############################################################################
  // UI PRINCIPALE
  //############################################################################

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (_isProcessing) return _buildLoadingScreen();
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

  Widget _buildFilmCard(String filmKey, List<M3uEntry> versions) {
    // Extraction du nom d'affichage et du badge catégorie depuis la clé composite "Titre||Catégorie"
    final keyParts = filmKey.split('||');
    final displayTitle = keyParts[0];
    final categoryLabel = keyParts.length > 1 ? keyParts[1] : null;

    // Détection de l'Homonyme (même titre, années différentes)
    final uniqueYears = versions.map((v) => v.title.year).where((y) => y != null).toSet();
    final isHomonymConflict = versions.length > 1 && uniqueYears.length > 1;

    // Chips qualité/langue (si pas de conflit d'homonymes)
    final allQualityChips = versions.map((v) => _qualityChip(v.title));
    final allLanguageChips = versions.expand((v) => _languageChips(v.title));
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
                    Row(
                      children: [
                        Expanded(child: Text(displayTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        if (categoryLabel != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.withAlpha(40),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.blue.withAlpha(80)),
                            ),
                            child: Text(categoryLabel, style: const TextStyle(fontSize: 11, color: Colors.blue)),
                          ),
                        ],
                      ],
                    ),
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

  Widget _buildSerieCard(String seriesKey, Map<String, List<M3uEntry>> saisons) {
    // Extraction du nom d'affichage et de la catégorie depuis la clé composite "Titre||Catégorie"
    final keyParts = seriesKey.split('||');
    final displayTitle = keyParts[0];
    final categoryLabel = keyParts.length > 1 ? keyParts[1] : null;

    final totalEpisodes = saisons.values.fold<int>(0, (prev, epList) => prev + epList.length);
    final allVersions = saisons.values.expand((list) => list).toList();

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: _buildCardImage(allVersions, Icons.tv, Colors.purple),
          title: Row(
            children: [
              Expanded(child: Text(displayTitle, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
              if (categoryLabel != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.purple.withAlpha(40),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.purple.withAlpha(80)),
                  ),
                  child: Text(categoryLabel, style: const TextStyle(fontSize: 11, color: Colors.purple)),
                ),
              ],
            ],
          ),
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

    if (!mounted) return;

    if (entry.type == M3uContentType.tv) {
      // TV : on passe toutes les versions — la sélection de qualité se fait
      // directement dans la fiche via les boutons qualité.
      await _showTvActionSheet(versions);
    } else {
      // Films / Séries : sélecteur de version séparé conservé
      M3uEntry selectedEntry = entry;
      if (versions.length > 1) {
        final choice = await _showVersionSelector(versions);
        if (choice == null) return;
        selectedEntry = choice;
      }
      if (!mounted) return;
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
        groupTitle: entry.groupTitle,
      );
    } else if (entry.type == M3uContentType.movie) {
      tmdbFuture = TmdbService.instance.getFullDetails(
        entry.displayName,
        isTv: false,
        explicitYear: entry.title.year,
        groupTitle: entry.groupTitle,
      );
    } else if (entry.type == M3uContentType.series) {
      tmdbFuture = TmdbService.instance.getFullDetails(
        entry.displayName,
        isTv: true,
        explicitYear: entry.title.year,
        groupTitle: entry.groupTitle,
      );
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
                // ── HEADER : épisodes de série vs films/TV ──────────────────────────────
                if (entry.title.isSeriesEpisode)
                  // Pour les épisodes : FutureBuilder gère toute la section header.
                  // Still TMDB en priorité sur le logo M3U, titre épisode en principal.
                  FutureBuilder<dynamic>(
                    future: tmdbFuture,
                    builder: (context, snap) {
                      final isLoading = snap.connectionState != ConnectionState.done;
                      final data = snap.data as Map<String, dynamic>?;

                      // Image : still_path TMDB (paysage) > logo M3U (portrait) > rien
                      final String? stillPath = data?['still_path'] as String?;
                      final String? imageUrl = stillPath != null
                          ? TmdbService.getPosterUrl(stillPath, size: 'w780')
                          : (entry.logoUrl?.isNotEmpty == true ? entry.logoUrl : null);

                      // Titre épisode : TMDB > nom parsé M3U > displayName
                      String episodeName = data?['name'] as String? ?? '';
                      if (episodeName.isEmpty || episodeName == entry.displayName) {
                        episodeName = _getEpisodeName(entry);
                      }

                      final double? voteAvg = (data?['vote_average'] as num?)?.toDouble();
                      final String? airDate = data?['air_date'] as String?;
                      final String? overview = data?['overview'] as String?;
                      final s = (entry.title.seasonNumber ?? 0).toString().padLeft(2, '0');
                      final e = (entry.title.episodeNumber ?? 0).toString().padLeft(2, '0');
                      final dimColor = Theme.of(context).colorScheme.onSurface.withAlpha(128);

                      return Column(
                        children: [
                          // Image (still TMDB ou logo M3U en fallback)
                          if (imageUrl != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  imageUrl,
                                  height: stillPath != null ? 160 : 140,
                                  width: double.infinity,
                                  fit: stillPath != null ? BoxFit.cover : BoxFit.contain,
                                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          // Fil d'Ariane : "Nom Série · S01 E04"
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Text(
                              '${entry.displayName}  ·  S$s E$e',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: dimColor),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Titre de l'épisode (principal)
                          if (isLoading)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8.0),
                              child: SizedBox(height: 4, width: 100, child: LinearProgressIndicator()),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0),
                              child: Text(episodeName, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                            ),
                          // Note ★ + Date de diffusion
                          if (!isLoading && (voteAvg != null && voteAvg > 0 || airDate != null))
                            Padding(
                              padding: const EdgeInsets.only(top: 6.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (voteAvg != null && voteAvg > 0) ...[
                                    const Icon(Icons.star_rounded, size: 15, color: Colors.amber),
                                    const SizedBox(width: 3),
                                    Text(voteAvg.toStringAsFixed(1), style: Theme.of(context).textTheme.bodySmall),
                                    if (airDate != null) const SizedBox(width: 12),
                                  ],
                                  if (airDate != null)
                                    Text(airDate, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: dimColor)),
                                ],
                              ),
                            ),
                          // Synopsis
                          if (!isLoading && overview != null && overview.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                              child: Text(
                                overview,
                                style: Theme.of(context).textTheme.bodySmall,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          const SizedBox(height: 8),
                        ],
                      );
                    },
                  )
                else ...[
                  // Films / séries (non-épisode) : logo M3U statique + titre
                  if (entry.logoUrl != null && entry.logoUrl!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          entry.logoUrl!,
                          height: 150,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(entry.displayName, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: 8),
                ],
                // Chips qualité / langue (S01E02 est maintenant dans le fil d'Ariane)
                Wrap(
                  spacing: 8,
                  children: [
                    _qualityChip(entry.title),
                    ..._languageChips(entry.title),
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
                    Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerPage(
                      path: entry.url,
                      title: entry.displayName,
                      sourceType: VideoSourceType.network,
                      badgeType: entry.type == M3uContentType.series ? PlayerBadgeType.series : PlayerBadgeType.movie,
                    )));
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
                          catchupSource: entry.catchupSource,
                        );
                        if (timeshiftUrl != null && mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PlayerPage(
                                path: timeshiftUrl,
                                title: replayProgram.title,
                                sourceType: VideoSourceType.networkReplay,
                                badgeType: PlayerBadgeType.replay,
                                replayStart: replayProgram.start,
                                replayDuration: replayProgram.end.difference(replayProgram.start),
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

  Future<void> _showTvActionSheet(List<M3uEntry> versions) async {
    // Préfère une version avec tvgId pour l'EPG ; sinon la première
    final entry = versions.firstWhere(
      (v) => v.tvgId != null,
      orElse: () => versions.first,
    );
    // Pour le replay, préfère FHD > HD > SD (4K exclu — pas d'archive replay).
    final entryForReplay = versions.firstWhere(
      (v) => v.streamId != null && v.title.quality == 'FHD',
      orElse: () => versions.firstWhere(
        (v) => v.streamId != null && v.title.quality == 'HD',
        orElse: () => versions.firstWhere(
          (v) => v.streamId != null && v.title.quality == 'SD',
          orElse: () => versions.firstWhere((v) => v.streamId != null, orElse: () => entry),
        ),
      ),
    );
    // Liste des flux dispo pour le replay (streamId requis), triés par qualité.
    // FHD/4K peuvent être sur un serveur distinct — le retry à 5s dans PlayerPage
    // laisse au serveur le temps de générer le segment HLS.
    // 4K exclu : ces flux n'ont pas d'archive replay côté serveur.
    const _replayQualities = {'FHD', 'HD', 'SD'};
    const _qualityOrder = {'FHD': 0, 'HD': 1, 'SD': 2};
    final replayEntries = versions
        .where((v) => v.streamId != null && _replayQualities.contains(v.title.quality))
        .toList()
      ..sort((a, b) => (_qualityOrder[a.title.quality] ?? 99)
          .compareTo(_qualityOrder[b.title.quality] ?? 99));
    final replayStreams = _labeledVersions(replayEntries)
        .map((e) => ReplayStreamOption(
              label: e.$2,
              streamId: e.$1.streamId!,
              streamUrl: e.$1.url,
              catchupSource: e.$1.catchupSource,
              catchupDays: e.$1.catchupDays,
            ))
        .toList();

    void playVersion(M3uEntry v) {
      Navigator.pop(context);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerPage(
            path: v.url,
            title: v.displayName,
            sourceType: VideoSourceType.network,
            badgeType: PlayerBadgeType.live,
          ),
        ),
      );
    }

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.85,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ---- Nom de la chaîne ----
                Text(entry.displayName,
                    style: Theme.of(context).textTheme.headlineSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 12),

                // ---- Bloc EPG + boutons qualité (si tvgId disponible) ----
                if (entry.tvgId != null)
                  _EpgNowNextBlock(
                    tvgId: entry.tvgId!,
                    versions: versions,
                    onPlayVersion: playVersion,
                  ),

                // ---- Fallback sans EPG : boutons qualité directs ----
                if (entry.tvgId == null)
                  _QualityButtonsRow(
                    versions: versions,
                    onPlay: playVersion,
                  ),

                const SizedBox(height: 4),

                // ---- Replay (picker manuel) ----
                if (entryForReplay.streamId != null)
                  ListTile(
                    leading: const Icon(Icons.replay_circle_filled),
                    title: Text(
                        "Replay${entryForReplay.catchupDays != null ? ' (${entryForReplay.catchupDays}j)' : ''}"),
                    onTap: () async {
                      Navigator.pop(context);
                      final replayProgram =
                          await showModalBottomSheet<ReplayProgram>(
                        context: context,
                        showDragHandle: true,
                        isScrollControlled: true,
                        builder: (_) => ReplayDatePickerSheet(
                            tvgId: entry.tvgId,
                            catchupDays: entryForReplay.catchupDays,
                            streams: replayStreams),
                      );
                      if (replayProgram != null) {
                        // Utilise le stream sélectionné dans le picker, sinon fallback sur entryForReplay
                        final timeshiftUrl =
                            await ReplayService().buildTimeshiftUrl(
                          streamId: replayProgram.selectedStreamId ?? entryForReplay.streamId!,
                          start: replayProgram.start,
                          end: replayProgram.end,
                          streamUrl: replayProgram.selectedStreamUrl ?? entryForReplay.url,
                          catchupSource: replayProgram.selectedCatchupSource ?? entryForReplay.catchupSource,
                        );
                        if (timeshiftUrl != null && mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PlayerPage(
                                path: timeshiftUrl,
                                title: replayProgram.title,
                                sourceType: VideoSourceType.networkReplay,
                                badgeType: PlayerBadgeType.replay,
                                replayStart: replayProgram.start,
                                replayDuration: replayProgram.end.difference(replayProgram.start),
                              ),
                            ),
                          );
                        } else if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text("Replay indisponible pour ce flux")),
                          );
                        }
                      }
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        );
      },
    );
  }

  //############################################################################
  // HELPERS (Groupement & Parsing)

  /// Clé de regroupement pour les chaînes TV.
  ///
  /// Plus agressive que [TitleMetadata.baseTitle] : retire les suffixes
  /// qualité/version propres aux providers IPTV qui ne font pas partie du
  /// vrai nom de la chaîne ("Résolution Exclu", "Exclu", "Backup"...).
  /// Appliquée uniquement à la clé de groupement, pas à l'affichage.
  ///
  /// ⚠️ On ne retire PAS les chiffres seuls (ex: "France 2", "M6+1", "BFM 24")
  /// pour ne pas confondre des chaînes distinctes.
  static String _tvGroupKey(String name) {
    var key = name;

    // 1. Suffixes providers courants en fin de nom (case-insensitive)
    //    "Résolution Exclu", "Résolution 4K", "Exclu", "Exclusif",
    //    "Backup", "Bkp", "Bak", "Back"
    key = key.replaceAll(
      RegExp(
        r'\s+(R[eé]solution\b.*|Exclu[a-z]*|Backup|Bkp|Bak|Back)\s*$',
        caseSensitive: false,
      ),
      '',
    );

    // 2. Tags qualité restants que baseTitle aurait dû enlever
    //    (sécurité : certains titres TV n'ont pas d'année/saison donc le
    //     path de nettoyage peut être différent)
    key = key.replaceAll(
      RegExp(r'\s+(4K|UHD|FHD|HD|SD|1080p|720p|480p)\s*$', caseSensitive: false),
      '',
    );

    return key.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Retourne true si l'entrée TV doit être masquée :
  /// - Variantes "Résolution Exclu" (fonctionnent qu'occasionnellement)
  /// - Entrées décoratives / séparateurs du provider (▀▄, ▼, ------)
  static bool _isHiddenTvVariant(String name) {
    // Séparateurs décoratifs insérés par certains providers
    if (name.contains('▀') || name.contains('▄') ||
        name.contains('▼') || name.contains('------')) {
      return true;
    }
    // Variantes Résolution / Exclu
    return RegExp(r'\bR[eé]solutions?\b|\bExclu[a-z]*\b', caseSensitive: false)
        .hasMatch(name);
  }

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

// ============================================================================
// Boutons de sélection de qualité (flux TV)
// ============================================================================

/// Trie les versions par qualité décroissante et génère un label lisible.
List<(M3uEntry, String)> _labeledVersions(List<M3uEntry> versions) {
  const order = {'4K': 0, 'UHD': 0, 'FHD': 1, 'HD': 2, 'SD': 3};
  final sorted = List<M3uEntry>.from(versions)
    ..sort((a, b) => (order[a.title.quality] ?? 99)
        .compareTo(order[b.title.quality] ?? 99));

  return sorted.indexed.map((e) {
    final i = e.$1;
    final v = e.$2;
    String label = v.title.quality ??
        (v.title.languages.isNotEmpty ? v.title.languages.first : null) ??
        v.title.versionLabel ??
        'Flux ${i + 1}';
    return (v, label);
  }).toList();
}

class _QualityButtonsRow extends StatelessWidget {
  final List<M3uEntry> versions;
  final void Function(M3uEntry) onPlay;

  const _QualityButtonsRow({required this.versions, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final labeled = _labeledVersions(versions);
    // Une seule version → un bouton "Regarder" pleine largeur
    if (labeled.length == 1) {
      return SizedBox(
        width: double.infinity,
        child: _playButton(labeled.first.$1, labeled.first.$2, full: true),
      );
    }
    // Plusieurs versions → rangée de boutons
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: labeled
          .map((e) => _playButton(e.$1, e.$2))
          .toList(),
    );
  }

  Widget _playButton(M3uEntry v, String label, {bool full = false}) {
    return SizedBox(
      height: 36,
      width: full ? double.infinity : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: kAetherGradient,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onPlay(v),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: full ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.play_arrow_rounded, color: kWhite, size: 16),
                  const SizedBox(width: 4),
                  Text(label,
                      style: const TextStyle(
                          color: kWhite,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Bloc EPG "En ce moment / Ensuite" (données XMLTV)
// ============================================================================

class _EpgNowNextBlock extends StatefulWidget {
  final String tvgId;
  final List<M3uEntry> versions;
  final void Function(M3uEntry)? onPlayVersion;

  const _EpgNowNextBlock({
    required this.tvgId,
    this.versions = const [],
    this.onPlayVersion,
  });

  @override
  State<_EpgNowNextBlock> createState() => _EpgNowNextBlockState();
}

class _EpgNowNextBlockState extends State<_EpgNowNextBlock> {
  XmltvProgram? _current;
  XmltvProgram? _next;
  String? _channelIconUrl; // icône de la chaîne (fallback si pas d'icône programme)
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Timeout de sécurité : si le XMLTV prend trop longtemps,
    // on passe directement au fallback (boutons qualité) sans bloquer l'UI.
    await Future.any([
      _doLoad(),
      Future.delayed(const Duration(seconds: 12)),
    ]);
    // Si _doLoad() n'a pas fini à temps, on force la fin du loading.
    if (mounted && _loading) {
      setState(() => _loading = false);
    }
  }

  Future<void> _doLoad() async {
    final current = await XmltvService.getCurrentProgram(widget.tvgId);
    final next = await XmltvService.getNextProgram(widget.tvgId);
    final channelIcon = await XmltvService.getChannelIconUrl(widget.tvgId);
    if (mounted) setState(() {
      _current = current;
      _next = next;
      _channelIconUrl = channelIcon;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (_current == null && _next == null) {
      // XMLTV ne couvre pas cette chaîne → fallback boutons qualité pour lancer le direct
      if (widget.versions.isEmpty || widget.onPlayVersion == null) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _QualityButtonsRow(
          versions: widget.versions,
          onPlay: widget.onPlayVersion!,
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: kContainerDark.withOpacity(0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kAetherPrimaryPurple.withOpacity(0.3)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Column(
          children: [
            if (_current != null)
              _EpgProgramRow(
                program: _current!,
                isNow: true,
                versions: widget.versions,
                onPlayVersion: widget.onPlayVersion,
                channelIconUrl: _channelIconUrl,
              ),
            if (_current != null && _next != null)
              const Divider(height: 1, indent: 12, endIndent: 12),
            if (_next != null)
              _EpgProgramRow(
                program: _next!,
                isNow: false,
                channelIconUrl: _channelIconUrl,
              ),
          ],
        ),
      ),
    );
  }
}

class _EpgProgramRow extends StatelessWidget {
  final XmltvProgram program;
  final bool isNow;
  final List<M3uEntry> versions;
  final void Function(M3uEntry)? onPlayVersion;
  final String? channelIconUrl; // icône chaîne (fallback si pas d'icône programme)

  const _EpgProgramRow({
    required this.program,
    required this.isNow,
    this.versions = const [],
    this.onPlayVersion,
    this.channelIconUrl,
  });

  @override
  Widget build(BuildContext context) {
    final showQualityButtons = isNow && versions.isNotEmpty && onPlayVersion != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- Infos programme ----
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (program.iconUrl != null || channelIconUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    program.iconUrl ?? channelIconUrl!,
                    width: 54,
                    height: 38,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) {
                      // Si icône programme échoue et icône chaîne dispo → tente le fallback
                      if (program.iconUrl != null && channelIconUrl != null) {
                        return Image.network(
                          channelIconUrl!,
                          width: 54,
                          height: 38,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox(width: 54, height: 38),
                        );
                      }
                      return const SizedBox(width: 54, height: 38);
                    },
                  ),
                )
              else
                const SizedBox(width: 54, height: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isNow
                                ? kAetherVibrantMagenta.withOpacity(0.9)
                                : kAetherPrimaryPurple.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isNow ? '● EN COURS' : 'ENSUITE',
                            style: const TextStyle(
                              color: kWhite,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(program.timeRange,
                            style: const TextStyle(fontSize: 11, color: kMediumGrey)),
                        const SizedBox(width: 4),
                        Text('(${program.durationLabel})',
                            style: const TextStyle(fontSize: 10, color: kMediumGrey)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      program.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    if (program.category != null)
                      Text(program.category!,
                          style: const TextStyle(fontSize: 11, color: kMediumGrey),
                          maxLines: 1),
                  ],
                ),
              ),
            ],
          ),

          // ---- Boutons qualité (EN COURS uniquement) ----
          if (showQualityButtons) ...[
            const SizedBox(height: 10),
            _QualityButtonsRow(versions: versions, onPlay: onPlayVersion!),
          ],
        ],
      ),
    );
  }
}
