import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/services/tmdb_service.dart';
import '../../data/models/media_model.dart';
import '../player/player_page.dart';
import '../downloads/logic/download_initiator.dart';
import '../../data/models/m3u_entry.dart';
import '../../l10n/app_localizations.dart';
import 'actor_details_page.dart';

/// Couleur associée à un label de qualité — cohérente avec media_chips.dart.
Color _qualityColor(String? quality) {
  return switch (quality) {
    '4K'  => Colors.red,
    'FHD' => Colors.amber,
    'HD'  => Colors.blue,
    'SD'  => Colors.teal,
    _     => Colors.grey,
  };
}

class DetailsPage extends StatefulWidget {
  final M3uEntry entry;
  /// Toutes les versions disponibles (qualités différentes du même contenu).
  /// Si vide, seule [entry] est utilisée.
  final List<M3uEntry> versions;

  const DetailsPage({super.key, required this.entry, this.versions = const []});

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends State<DetailsPage> {
  Media? _tmdbData;
  Map<String, dynamic>? _episodeData; // données spécifiques à l'épisode (si série)
  bool _isLoading = true;
  late M3uEntry _selectedEntry;
  /// Versions dédupliquées par label de qualité.
  /// En multi-comptes, le même film peut exister en double avec la même qualité
  /// (ex: deux sources "4K") — on garde la première occurrence (compte prioritaire).
  late List<M3uEntry> _uniqueVersions;

  bool get _isEpisode =>
      widget.entry.title.isSeriesEpisode &&
      widget.entry.title.seasonNumber != null &&
      widget.entry.title.episodeNumber != null;

  @override
  void initState() {
    super.initState();
    _uniqueVersions = _deduplicateVersions(widget.versions);
    _selectedEntry = _uniqueVersions.isNotEmpty ? _uniqueVersions.first : widget.entry;
    _loadData();
  }

  Future<void> _loadData() async {
    final service = TmdbService.instance;

    if (_isEpisode) {
      // Chargement parallèle : données épisode + données série (pour le casting)
      final results = await Future.wait([
        service.getEpisodeDetails(
          widget.entry.displayName,
          widget.entry.title.seasonNumber!,
          widget.entry.title.episodeNumber!,
          yearFilter: widget.entry.title.year,
          groupTitle: widget.entry.groupTitle,
        ),
        service.getFullDetails(
          widget.entry.displayName,
          isTv: true,
          explicitYear: widget.entry.title.year,
          groupTitle: widget.entry.groupTitle,
        ),
      ]);
      if (mounted) {
        setState(() {
          _episodeData = results[0] as Map<String, dynamic>?;
          _tmdbData    = results[1] as Media?;
          _isLoading   = false;
        });
      }
    } else {
      final data = await service.getFullDetails(
        widget.entry.displayName,
        isTv: widget.entry.isSerie,
        explicitYear: widget.entry.title.year,
        groupTitle: widget.entry.groupTitle,
      );
      if (mounted) {
        setState(() {
          _tmdbData  = data;
          _isLoading = false;
        });
      }
    }
  }

  // 🎯 NOUVELLE MÉTHODE : Chercher l'ID de l'acteur via TMDB
  Future<void> _searchActor(String actorName) async {
    final service = TmdbService.instance;
    final personId = await service.getPersonId(actorName);

    if (!mounted) return;

    if (personId != null) {
      debugPrint("🚀 ID acteur trouvé ($personId). Navigation vers la fiche.");

      // 🎯 NAVIGATION FINALE
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ActorDetailsPage(personId: personId)));

    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("TMDB n'a pas trouvé de fiche pour $actorName.")),
      );
    }
  }

  // Fonction pour ouvrir la bande-annonce dans un navigateur/YouTube
  Future<void> _launchTrailer() async {
    if (_tmdbData?.trailerKey == null) return;
    final url = Uri.parse('https://www.youtube.com/watch?v=${_tmdbData!.trailerKey}');

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.platformDefault);
    } else {
      debugPrint("❌ ERREUR : Impossible de lancer la bande-annonce à l'URL: $url");
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasTmdbData = _tmdbData != null;
    final hasEpData   = _episodeData != null;

    // ── Données épisode (prioritaires) vs série ──────────────────────────────
    final String? episodeName  = hasEpData ? _episodeData!['name'] as String? : null;
    final String? stillPath    = hasEpData ? _episodeData!['still_path'] as String? : null;
    final String? epOverview   = hasEpData ? _episodeData!['overview'] as String? : null;
    final String? epAirDate    = hasEpData ? _episodeData!['air_date'] as String? : null;
    final double? epRating     = hasEpData ? (_episodeData!['vote_average'] as num?)?.toDouble() : null;

    // Image header : still épisode > backdrop série
    final String? headerImagePath = stillPath ?? _tmdbData?.backdropPath;
    final String? headerImageUrl  = headerImagePath != null
        ? TmdbService.getPosterUrl(headerImagePath, size: stillPath != null ? 'w780' : 'original')
        : null;

    // Synopsis : overview épisode > overview série
    final String? overview   = (epOverview?.isNotEmpty == true) ? epOverview : _tmdbData?.overview;
    final double  rating     = epRating ?? _tmdbData?.voteAverage ?? 0.0;
    final String? releaseDate = epAirDate?.split('-').first ?? _tmdbData?.releaseDate?.split('-').first;

    final castList   = _tmdbData?.cast;
    final hasTrailer = _tmdbData?.trailerKey != null;
    final runtime    = _tmdbData?.runtimeOrEpisodeLength;
    final companies  = _tmdbData?.productionCompanies;

    // Labels S/E
    final s = widget.entry.title.seasonNumber != null
        ? 'S${widget.entry.title.seasonNumber!.toString().padLeft(2, '0')}'
        : null;
    final e = widget.entry.title.episodeNumber != null
        ? 'E${widget.entry.title.episodeNumber!.toString().padLeft(2, '0')}'
        : null;

    final surface = Theme.of(context).colorScheme.surface;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    final surfaceContainerHighest = Theme.of(context).colorScheme.surfaceContainerHighest;
    final outlineVariant = Theme.of(context).colorScheme.outlineVariant;

    return Scaffold(
      backgroundColor: surface,
      body: CustomScrollView(
        slivers: [
          // 1. IMMERSIVE HEADER
          SliverAppBar(
            expandedHeight: 400.0,
            pinned: true,
            stretch: true,
            backgroundColor: surface,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Image : still épisode ou backdrop série
                  if (headerImageUrl != null)
                    Image.network(
                      headerImageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: surfaceContainerHighest),
                    )
                  else
                    Container(color: surfaceContainerHighest),

                  // Gradient (transparent → surface) pour transition seamless
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black45,
                          surface,
                        ],
                        stops: const [0.0, 0.6, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. CONTENU PRINCIPAL
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // BREADCRUMB série (nom série · S01 E05) — épisodes seulement
                  if (_isEpisode && s != null && e != null) ...[
                    Text(
                      '${widget.entry.displayName}  ·  $s $e',
                      style: TextStyle(fontSize: 13, color: onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                  ],

                  // TITRE (nom épisode si dispo, sinon nom série)
                  Text(
                    (_isEpisode && episodeName != null && episodeName.isNotEmpty)
                        ? episodeName
                        : widget.entry.displayName,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: onSurface,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // LIGNE DE MÉTADONNÉES (Année • Durée • Note)
                  Row(
                    children: [
                      if (releaseDate != null) _buildMetaTag(releaseDate, onSurfaceVariant),
                      if (runtime != null && !_isEpisode) ...[
                        const SizedBox(width: 8),
                        Text('•', style: TextStyle(color: onSurfaceVariant)),
                        const SizedBox(width: 8),
                        _buildMetaTag(runtime, onSurfaceVariant),
                      ],
                      const Spacer(),
                      if (rating > 0) ...[
                        const Icon(Icons.star, color: Colors.amber, size: 20),
                        const SizedBox(width: 4),
                        Text(
                          rating.toStringAsFixed(1),
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amber),
                        ),
                      ]
                    ],
                  ),

                  const SizedBox(height: 24),

                  // SÉLECTEUR DE QUALITÉ (affiché seulement si plusieurs versions)
                  if (_uniqueVersions.length > 1) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: _uniqueVersions.asMap().entries.map((e) {
                        final v        = e.value;
                        final label    = _qualityLabel(v, e.key);
                        final color    = _qualityColor(v.title.quality);
                        final selected = _selectedEntry == v;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedEntry = v),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: selected ? color.withAlpha(55) : color.withAlpha(25),
                              border: Border.all(
                                color: selected ? color.withAlpha(200) : color.withAlpha(60),
                                width: selected ? 1.5 : 1,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                                color: color,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // BOUTONS D'ACTION (Jouer / Télécharger)
                  Row(
                    children: [
                      // Bouton JOUER
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => PlayerPage(
                              path: _selectedEntry.url,
                              title: _selectedEntry.displayName,
                              sourceType: VideoSourceType.network,
                              badgeType: _selectedEntry.type == M3uContentType.series ? PlayerBadgeType.series : PlayerBadgeType.movie,
                            ),
                          )),
                          icon: const Icon(Icons.play_arrow),
                          label: Text(l10n.actionSheetPlay.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),

                      const SizedBox(width: 12),

                      // Bouton TÉLÉCHARGER
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          onPressed: () => verifierEtTelecharger(
                              url: _selectedEntry.url, nom: _selectedEntry.displayName, context: context),
                          icon: const Icon(Icons.download),
                          label: Text(l10n.download.toUpperCase()),
                        ),
                      ),
                    ],
                  ),

                  // BOUTON BANDE-ANNONCE
                  if (hasTrailer)
                    Padding(
                      padding: const EdgeInsets.only(top: 12.0),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                            foregroundColor: Colors.red,
                          ),
                          onPressed: _launchTrailer,
                          icon: const Icon(Icons.videocam),
                          label: const Text("Bande-Annonce"),
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),

                  // SYNOPSIS
                  if (hasTmdbData || hasEpData) ...[
                    Text("Synopsis", style: Theme.of(context).textTheme.titleMedium?.copyWith(color: onSurfaceVariant)),
                    const SizedBox(height: 8),
                    Text(
                      overview ?? "Données classifiées.",
                      style: TextStyle(color: onSurfaceVariant, height: 1.5, fontSize: 15),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // 🎯 CASTING PRINCIPAL (ActionChips cliquables)
                  if (hasTmdbData && castList != null && castList.isNotEmpty) ...[
                    Text("Casting principal", style: Theme.of(context).textTheme.titleSmall?.copyWith(color: onSurfaceVariant)),
                    Divider(color: outlineVariant),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: castList.map((actor) {
                        return ActionChip(
                          avatar: const Icon(Icons.person, size: 18, color: Colors.amber),
                          label: Text(actor),
                          onPressed: () => _searchActor(actor),
                          backgroundColor: surfaceContainerHighest,
                          labelStyle: TextStyle(color: onSurface, fontSize: 13, fontWeight: FontWeight.w500),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // GENRES (Chips modernes)
                  if (hasTmdbData && _tmdbData!.genres.isNotEmpty) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _tmdbData!.genres.map((g) => Chip(
                        label: Text(g),
                        backgroundColor: surfaceContainerHighest,
                        labelStyle: TextStyle(color: onSurfaceVariant, fontSize: 12),
                        side: BorderSide.none,
                        padding: EdgeInsets.zero,
                      )).toList(),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // PLATEFORMES DE STREAMING
                  Builder(builder: (context) {
                    final platforms = _parsePlatforms(widget.entry.groupTitle);
                    if (platforms.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Disponible sur", style: Theme.of(context).textTheme.titleSmall?.copyWith(color: onSurfaceVariant)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: platforms.map((p) {
                            final color = _platformColor(p);
                            return Chip(
                              label: Text(p),
                              backgroundColor: color.withAlpha(40),
                              labelStyle: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
                              side: BorderSide(color: color.withAlpha(100)),
                              padding: EdgeInsets.zero,
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 24),
                      ],
                    );
                  }),

                  // PRODUCTION & COMPAGNIES
                  if (companies != null && companies.isNotEmpty) ...[
                    Divider(color: outlineVariant),
                    const SizedBox(height: 8),
                    Text(
                      "Production: $companies",
                      style: TextStyle(color: onSurfaceVariant, fontSize: 12),
                    ),
                    const SizedBox(height: 40),
                  ],

                  // LOADING STATE
                  if (_isLoading)
                    const Center(child: Padding(
                      padding: EdgeInsets.all(20.0),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Déduplique les versions par label de qualité.
  /// Garde la première occurrence → compte prioritaire en tête de liste.
  static List<M3uEntry> _deduplicateVersions(List<M3uEntry> versions) {
    final seen = <String>{};
    final result = <M3uEntry>[];
    for (int i = 0; i < versions.length; i++) {
      final label = _buildQualityLabel(versions[i], i);
      if (seen.add(label)) result.add(versions[i]);
    }
    return result;
  }

  /// Construit le label affiché sur le chip de qualité (instance + statique).
  String _qualityLabel(M3uEntry v, int index) => _buildQualityLabel(v, index);

  static String _buildQualityLabel(M3uEntry v, int index) {
    final q  = v.title.quality;
    final vl = v.title.versionLabel;
    if (q != null && vl != null) return '$q · $vl';
    if (q != null) return q;
    if (vl != null) return vl;
    return 'V${index + 1}';
  }

  /// Extrait la liste des plateformes depuis le group-title M3U.
  /// Ex: "ACTION ( NETFLIX| PRIME | HBO | APPLE TV+ )" → ["Netflix", "Prime Video", "HBO", "Apple TV+"]
  static List<String> _parsePlatforms(String? groupTitle) {
    if (groupTitle == null || groupTitle.isEmpty) return [];
    final match = RegExp(r'\(([^)]+)\)').firstMatch(groupTitle);
    if (match == null) return [];
    return match.group(1)!
        .split('|')
        .map((s) => _normalizePlatform(s.trim()))
        .where((s) => s.isNotEmpty)
        .toSet() // dédoublonne
        .toList();
  }

  static String _normalizePlatform(String raw) {
    final r = raw.toUpperCase();
    if (r.contains('NETFLIX')) return 'Netflix';
    if (r.contains('PRIME')) return 'Prime Video';
    if (r.contains('HBO')) return 'HBO Max';
    if (r.contains('APPLE')) return 'Apple TV+';
    if (r.contains('STARZPLAY') || r.contains('STARZ')) return 'Starz';
    if (r.contains('PARAMOUNT')) return 'Paramount+';
    if (r.contains('DISNEY')) return 'Disney+';
    if (r.contains('PEACOCK')) return 'Peacock';
    if (r.contains('CANAL')) return 'Canal+';
    if (r.contains('DAZN')) return 'DAZN';
    if (r.contains('HULU')) return 'Hulu';
    if (r.contains('RAKUTEN')) return 'Rakuten TV';
    return ''; // entrée non reconnue → filtrée
  }

  static Color _platformColor(String platform) {
    switch (platform) {
      case 'Netflix':      return const Color(0xFFE50914);
      case 'Prime Video':  return const Color(0xFF00A8E1);
      case 'HBO Max':      return const Color(0xFF5B2D8E);
      case 'Apple TV+':    return const Color(0xFF555555);
      case 'Starz':        return const Color(0xFF00B4D8);
      case 'Paramount+':   return const Color(0xFF0064FF);
      case 'Disney+':      return const Color(0xFF0063E5);
      case 'Canal+':       return const Color(0xFF000000);
      case 'Peacock':      return const Color(0xFF000000);
      default:             return Colors.grey.shade700;
    }
  }

  // Petit widget utilitaire pour les tags de métadonnées
  Widget _buildMetaTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline.withAlpha(80)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}
