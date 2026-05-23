import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/themes/colors.dart';
import '../../core/themes/aether_theme_extension.dart';
import '../../data/services/favorites_service.dart';
import '../../data/services/tmdb_service.dart';
import '../../data/services/parsed_playlist_service.dart';
import '../../data/services/watch_progress_service.dart';
import '../../data/models/media_model.dart';
import '../player/player_page.dart';
import '../downloads/logic/download_initiator.dart';
import '../../data/models/m3u_entry.dart';
import '../../l10n/app_localizations.dart';
import 'actor_details_page.dart';

Color _qualityColor(String? quality) {
  return switch (quality) {
    '4K'  => kQuality4K,
    'FHD' => kQualityFHD,
    'HD'  => kQualityHD,
    'SD'  => kQualitySD,
    _     => Colors.grey,
  };
}

class DetailsPage extends StatefulWidget {
  final M3uEntry entry;
  final List<M3uEntry> versions;

  const DetailsPage({super.key, required this.entry, this.versions = const []});

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _EpGroup {
  final int episodeNumber;
  final List<M3uEntry> versions;
  M3uEntry get best => versions.first;
  _EpGroup(this.episodeNumber, this.versions);
}

class _DetailsPageState extends State<DetailsPage> {
  Media? _tmdbData;
  Map<String, dynamic>? _episodeData;
  bool _isLoading = true;
  late M3uEntry _selectedEntry;
  late List<M3uEntry> _uniqueVersions;

  // ── Navigation série ────────────────────────────────────────────────────────
  late M3uEntry _currentEpisode;
  bool _episodeSelected = false;
  Map<int, List<_EpGroup>> _seasonEpisodes = {};
  int? _selectedSeason;

  final ScrollController _episodeScrollController = ScrollController();

  bool get _isEpisode =>
      _episodeSelected &&
      _currentEpisode.title.isSeriesEpisode &&
      _currentEpisode.title.seasonNumber != null &&
      _currentEpisode.title.episodeNumber != null;

  /// §1i — Calcule l'épisode suivant pour la série en cours :
  /// - épisode N+1 dans la même saison si présent
  /// - sinon premier épisode de la saison suivante si présent
  /// - sinon null (fin de série).
  M3uEntry? get _nextEpisode {
    if (!_isEpisode || _seasonEpisodes.isEmpty) return null;
    final season = _currentEpisode.title.seasonNumber!;
    final epNum  = _currentEpisode.title.episodeNumber!;
    // Suivant dans la même saison
    final eps = _seasonEpisodes[season];
    if (eps != null) {
      final next = eps.where((g) => g.episodeNumber == epNum + 1).firstOrNull;
      if (next != null) return next.best;
    }
    // Premier de la saison suivante
    final seasons = _seasonEpisodes.keys.toList()..sort();
    final idx = seasons.indexOf(season);
    if (idx >= 0 && idx + 1 < seasons.length) {
      final nextSeasonEps = _seasonEpisodes[seasons[idx + 1]] ?? [];
      if (nextSeasonEps.isNotEmpty) return nextSeasonEps.first.best;
    }
    return null;
  }

  /// §1i — Sélectionne l'épisode suivant + recharge les métadonnées TMDB +
  /// rebascule sur la fiche détaillée. Utilisé par le bouton "next" du player.
  void _goToNextEpisode() {
    final next = _nextEpisode;
    if (next == null) return;
    final epNum  = next.title.episodeNumber;
    final season = next.title.seasonNumber;
    if (epNum == null || season == null) return;
    final group = _seasonEpisodes[season]
        ?.where((g) => g.episodeNumber == epNum)
        .firstOrNull;
    if (group == null) return;
    setState(() {
      _selectedSeason = season;
      _episodeSelected = true;
      _currentEpisode = group.best;
      _uniqueVersions = _deduplicateVersions(group.versions);
      _selectedEntry = _uniqueVersions.isNotEmpty
          ? _uniqueVersions.first
          : group.best;
    });
    _loadData();
  }

  @override
  void initState() {
    super.initState();
    _currentEpisode = widget.entry;
    _buildSeasonEpisodes();

    if (_seasonEpisodes.isNotEmpty) {
      final season = widget.entry.title.seasonNumber;
      final epNum  = widget.entry.title.episodeNumber;

      if (season != null && epNum != null) {
        final group = _seasonEpisodes[season]
            ?.where((g) => g.episodeNumber == epNum)
            .firstOrNull;
        if (group != null) {
          _episodeSelected = true;
          _selectedSeason  = season;
          _currentEpisode  = group.best;
          _uniqueVersions  = _deduplicateVersions(group.versions);
          _selectedEntry   = _uniqueVersions.isNotEmpty ? _uniqueVersions.first : group.best;
        } else {
          _episodeSelected = false;
          _uniqueVersions  = [];
          _selectedEntry   = widget.entry;
        }
      } else {
        _episodeSelected = false;
        _uniqueVersions  = [];
        _selectedEntry   = widget.entry;
      }
    } else {
      _uniqueVersions = _deduplicateVersions(widget.versions);
      _selectedEntry  = _uniqueVersions.isNotEmpty ? _uniqueVersions.first : widget.entry;
    }

    _loadData();
  }

  @override
  void dispose() {
    _episodeScrollController.dispose();
    super.dispose();
  }

  void _buildSeasonEpisodes() {
    if (widget.entry.type != M3uContentType.series) return;
    final seriesName = widget.entry.displayName;
    final all = ParsedPlaylistService.entriesWithPriority(widget.entry.accountId)
        .where((e) => e.type == M3uContentType.series && e.displayName == seriesName)
        .toList();

    final tmp = <int, Map<int, List<M3uEntry>>>{};
    for (final e in all) {
      final s  = e.title.seasonNumber;
      final ep = e.title.episodeNumber;
      if (s == null || ep == null) continue;
      tmp.putIfAbsent(s, () => {}).putIfAbsent(ep, () => []).add(e);
    }

    final result = <int, List<_EpGroup>>{};
    for (final entry in tmp.entries) {
      final groups = entry.value.entries
          .map((e) => _EpGroup(e.key, e.value))
          .toList()
        ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
      result[entry.key] = groups;
    }

    final sortedSeasons = result.keys.toList()..sort();
    _seasonEpisodes = {for (final s in sortedSeasons) s: result[s]!};
    _selectedSeason = null;
  }

  void _selectSeason(int season) {
    final episodes = _seasonEpisodes[season] ?? [];
    setState(() => _selectedSeason = season);
    if (episodes.isNotEmpty) _selectEpisode(episodes.first);
  }

  void _selectEpisode(_EpGroup group) {
    final versions = _deduplicateVersions(group.versions);
    setState(() {
      _currentEpisode  = group.best;
      _episodeSelected = true;
      _uniqueVersions  = versions;
      _selectedEntry   = versions.isNotEmpty ? versions.first : group.best;
      _isLoading       = true;
      _episodeData     = null;
    });
    _loadData();
    // Auto-scroll vers l'épisode sélectionné
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_episodeScrollController.hasClients) return;
      final episodes = _seasonEpisodes[_selectedSeason] ?? [];
      final idx = episodes.indexWhere((g) => g.episodeNumber == group.episodeNumber);
      if (idx < 0) return;
      final target = (idx * 58.0).clamp(
          0.0, _episodeScrollController.position.maxScrollExtent);
      _episodeScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _loadData() async {
    final service  = TmdbService.instance;
    final isSeries = widget.entry.type == M3uContentType.series;

    if (_isEpisode) {
      final results = await Future.wait([
        service.getEpisodeDetails(
          widget.entry.displayName,
          _currentEpisode.title.seasonNumber!,
          _currentEpisode.title.episodeNumber!,
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
        isSeries ? widget.entry.displayName : _currentEpisode.displayName,
        isTv: isSeries || _currentEpisode.isSerie,
        explicitYear: isSeries
            ? widget.entry.title.year
            : _currentEpisode.title.year,
        groupTitle: isSeries
            ? widget.entry.groupTitle
            : _currentEpisode.groupTitle,
      );
      if (mounted) {
        setState(() {
          _tmdbData  = data;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _searchActor(String actorName) async {
    final personId = await TmdbService.instance.getPersonId(actorName);
    if (!mounted) return;
    if (personId != null) {
      Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ActorDetailsPage(personId: personId)));
    } else {
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(content: Text("TMDB n'a pas trouvé de fiche pour $actorName.")),
      );
    }
  }

  Future<void> _launchTrailer() async {
    if (_tmdbData?.trailerKey == null) return;
    final url = Uri.parse('https://www.youtube.com/watch?v=${_tmdbData!.trailerKey}');
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.platformDefault);
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n    = AppLocalizations.of(context)!;
    final cs      = Theme.of(context).colorScheme;
    final hasTmdb = _tmdbData != null;
    final isSeries = _seasonEpisodes.isNotEmpty;

    // Image header : still épisode (si sélectionné) > backdrop série
    final String? stillPath    = _episodeData?['still_path'] as String?;
    final String? headerPath   = (_episodeSelected && stillPath != null)
        ? stillPath
        : _tmdbData?.backdropPath;
    final String? headerUrl    = headerPath != null
        ? TmdbService.getPosterUrl(headerPath,
            size: (_episodeSelected && stillPath != null) ? 'w780' : 'original')
        : null;

    final String? epName     = _episodeData?['name'] as String?;
    final String? epOverview = _episodeData?['overview'] as String?;
    final String? epAirDate  = _episodeData?['air_date'] as String?;
    final double? epRating   = (_episodeData?['vote_average'] as num?)?.toDouble();

    // Titre et métadonnées : épisode prioritaire sur série
    final double  rating      = epRating ?? _tmdbData?.voteAverage ?? 0.0;
    final String? releaseDate = epAirDate?.split('-').first
        ?? _tmdbData?.releaseDate?.split('-').first;

    // Titre affiché : nom épisode si sélectionné, sinon nom série/film
    final String seriesTitle = (_tmdbData?.title.isNotEmpty == true)
        ? _tmdbData!.title
        : widget.entry.displayName;
    final bool showEpTitle = _isEpisode && epName != null && epName.isNotEmpty;

    // Synopsis : épisode si sélectionné, sinon série/film
    final String? displayOverview = (_isEpisode && epOverview?.isNotEmpty == true)
        ? epOverview
        : _tmdbData?.overview;

    return Scaffold(
      backgroundColor: cs.surface,
      body: CustomScrollView(
        slivers: [
          // ── HEADER ────────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 360.0,
            pinned: true,
            stretch: true,
            backgroundColor: cs.surface,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (headerUrl != null)
                    Image.network(
                      headerUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Container(color: cs.surfaceContainerHighest),
                    )
                  else
                    Container(color: cs.surfaceContainerHighest),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54, cs.surface],
                        stops: const [0.0, 0.55, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── CONTENU ───────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // TITRE — breadcrumb série + nom épisode quand épisode sélectionné
                  if (showEpTitle) ...[
                    Text(
                      seriesTitle,
                      style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    showEpTitle ? epName : seriesTitle,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // MÉTADONNÉES
                  Row(
                    children: [
                      if (releaseDate != null)
                        _buildMetaTag(releaseDate, cs.onSurfaceVariant),
                      if (_tmdbData?.runtimeOrEpisodeLength != null && !isSeries) ...[
                        const SizedBox(width: 8),
                        Text('•', style: TextStyle(color: cs.onSurfaceVariant)),
                        const SizedBox(width: 8),
                        _buildMetaTag(_tmdbData!.runtimeOrEpisodeLength!, cs.onSurfaceVariant),
                      ],
                      const Spacer(),
                      if (rating > 0) ...[
                        const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                        const SizedBox(width: 3),
                        Text(
                          rating.toStringAsFixed(1),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, color: Colors.amber, fontSize: 14),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── SÉRIES : navigation immédiate ──────────────────────────
                  if (isSeries) ...[
                    _buildSeriesNavigator(cs, l10n),
                    const SizedBox(height: 24),
                  ],

                  // ── FILMS : qualités + actions ──────────────────────────────
                  if (!isSeries) ...[
                    if (_uniqueVersions.isNotEmpty) ...[
                      _buildQualityChips(cs),
                      const SizedBox(height: 12),
                    ],
                    _buildActionButtons(l10n),
                    if (_tmdbData?.trailerKey != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: SizedBox(
                            width: double.infinity, child: _buildTrailerButton()),
                      ),
                    const SizedBox(height: 24),
                  ],

                  // SYNOPSIS : épisode si sélectionné, série sinon
                  if (displayOverview?.isNotEmpty == true) ...[
                    Text('Synopsis',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    Text(
                      displayOverview!,
                      style: TextStyle(
                          color: cs.onSurfaceVariant, height: 1.55, fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // BANDE-ANNONCE — série uniquement si aucun épisode sélectionné
                  if (isSeries && !_episodeSelected && _tmdbData?.trailerKey != null) ...[
                    SizedBox(width: double.infinity, child: _buildTrailerButton()),
                    const SizedBox(height: 24),
                  ],

                  // CASTING (toujours)
                  if (hasTmdb && _tmdbData!.cast.isNotEmpty) ...[
                    Text('Casting principal',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                    Divider(color: cs.outlineVariant),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _tmdbData!.cast
                          .map((a) => _FocusableChip(
                                icon: Icons.person,
                                label: a,
                                onPressed: () => _searchActor(a),
                                accentColor: kAccentSecondary,
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // GENRES (toujours)
                  if (hasTmdb && _tmdbData!.genres.isNotEmpty) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _tmdbData!.genres
                          .map((g) => Chip(
                                label: Text(g),
                                backgroundColor: cs.surfaceContainerHighest,
                                labelStyle: TextStyle(
                                    color: cs.onSurfaceVariant, fontSize: 12),
                                side: BorderSide.none,
                                padding: EdgeInsets.zero,
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // PLATEFORMES (toujours)
                  Builder(builder: (context) {
                    final platforms = _parsePlatforms(widget.entry.groupTitle);
                    if (platforms.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Disponible sur',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(color: cs.onSurfaceVariant)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: platforms.map((p) {
                            final color = _platformColor(p);
                            return Chip(
                              label: Text(p),
                              backgroundColor: color.withAlpha(40),
                              labelStyle: TextStyle(
                                  color: color,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold),
                              side: BorderSide(color: color.withAlpha(100)),
                              padding: EdgeInsets.zero,
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 24),
                      ],
                    );
                  }),

                  // PRODUCTION (toujours)
                  if (_tmdbData?.productionCompanies?.isNotEmpty == true) ...[
                    Divider(color: cs.outlineVariant),
                    const SizedBox(height: 8),
                    Text(
                      'Production: ${_tmdbData!.productionCompanies}',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                    const SizedBox(height: 40),
                  ],

                  // LOADING
                  if (_isLoading && !isSeries)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Navigateur série ────────────────────────────────────────────────────────

  Widget _buildSeriesNavigator(ColorScheme cs, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // SAISONS
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _seasonEpisodes.keys.map((sNum) {
              final isSelected = sNum == _selectedSeason;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _FocusableChip(
                  label: 'Saison $sNum',
                  isSelected: isSelected,
                  onPressed: isSelected ? null : () => _selectSeason(sNum),
                ),
              );
            }).toList(),
          ),
        ),

        // ÉPISODES (scroll horizontal, apparaît dès qu'une saison est choisie)
        if (_selectedSeason != null &&
            _seasonEpisodes[_selectedSeason] != null) ...[
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            controller: _episodeScrollController,
            child: Row(
              children: _seasonEpisodes[_selectedSeason]!.map((group) {
                final isCurrent = _episodeSelected &&
                    group.episodeNumber ==
                        _currentEpisode.title.episodeNumber &&
                    _selectedSeason == _currentEpisode.title.seasonNumber;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _FocusableChip(
                    label: 'E${group.episodeNumber.toString().padLeft(2, '0')}',
                    isSelected: isCurrent,
                    onPressed: isCurrent ? null : () => _selectEpisode(group),
                    width: 58,
                  ),
                );
              }).toList(),
            ),
          ),
        ],

        // CARD ÉPISODE SÉLECTIONNÉ
        if (_episodeSelected) ...[
          const SizedBox(height: 16),
          _buildEpisodeCard(cs, l10n),
        ],
      ],
    );
  }

  Widget _buildEpisodeCard(ColorScheme cs, AppLocalizations l10n) {
    final epDate   = _episodeData?['air_date'] as String?;
    final epRating = (_episodeData?['vote_average'] as num?)?.toDouble();

    final sNum = _currentEpisode.title.seasonNumber;
    final eNum = _currentEpisode.title.episodeNumber;
    final label = (sNum != null && eNum != null)
        ? 'S${sNum.toString().padLeft(2, '0')}  E${eNum.toString().padLeft(2, '0')}'
        : '';

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label + titre épisode
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: cs.primary.withAlpha(80)),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                    letterSpacing: 1,
                  ),
                ),
              ),
              if (epDate != null) ...[
                const SizedBox(width: 10),
                Text(
                  epDate,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
              if (epRating != null && epRating > 0) ...[
                const Spacer(),
                const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                const SizedBox(width: 2),
                Text(
                  epRating.toStringAsFixed(1),
                  style: const TextStyle(
                      fontSize: 12, color: Colors.amber, fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),

          // Barre de chargement TMDB
          if (_isLoading) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              minHeight: 2,
              borderRadius: BorderRadius.circular(2),
              color: cs.primary.withAlpha(120),
              backgroundColor: cs.outlineVariant,
            ),
          ],

          const SizedBox(height: 14),

          // QUALITÉS
          if (_uniqueVersions.isNotEmpty) ...[
            _buildQualityChips(cs),
            const SizedBox(height: 12),
          ],

          // PLAY + DOWNLOAD
          _buildActionButtons(l10n),
        ],
      ),
    );
  }

  // ── Widgets partagés ───────────────────────────────────────────────────────

  Widget _buildQualityChips(ColorScheme cs) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: _uniqueVersions.asMap().entries.map((e) {
        final v        = e.value;
        final label    = _qualityLabel(v, e.key);
        final color    = _qualityColor(v.title.quality);
        final selected = _selectedEntry == v;
        return _FocusableChip(
          label: label,
          isSelected: selected,
          onPressed: () => setState(() => _selectedEntry = v),
          accentColor: color,
        );
      }).toList(),
    );
  }

  /// Format Duration → "1h23" ou "12:34" pour libellé court de reprise.
  String _formatResumeShort(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h${m.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _launchSelected({Duration? from}) {
    // Auto-ajout favoris au play, cohérent avec le reste de l'app (§1d)
    FavoritesService.add(FavoritesService.keyFor(_selectedEntry));
    // §1i — Si on lance un épisode et qu'il existe un suivant, on passe le
    // callback au player pour exposer le bouton "épisode suivant" (▶▶).
    final hasNext = _isEpisode && _nextEpisode != null;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerPage(
        path: _selectedEntry.url,
        title: _selectedEntry.displayName,
        sourceType: VideoSourceType.network,
        badgeType: _selectedEntry.type == M3uContentType.series
            ? PlayerBadgeType.series
            : PlayerBadgeType.movie,
        startPosition: from,
        onNextEpisode: hasNext
            ? () {
                // Retour à DetailsPage + sélection auto épisode suivant +
                // relance du player. Évite d'empiler des PlayerPage.
                Navigator.of(context).pop();
                _goToNextEpisode();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _launchSelected();
                });
              }
            : null,
      ),
    ));
  }

  Widget _buildActionButtons(AppLocalizations l10n) {
    return ListenableBuilder(
      listenable: Listenable.merge(
          [FavoritesService.version, WatchProgressService.version]),
      builder: (ctx, _) {
        final favKey = FavoritesService.keyFor(_selectedEntry);
        final isFav = FavoritesService.isFavorite(favKey);
        final progress = WatchProgressService.getProgress(_selectedEntry.url);
        final hasResume = progress != null && progress.position.inSeconds > 5;

        return Row(
          children: [
            // ── Bouton principal : Lire / Reprendre depuis X:XX ─────────────
            Expanded(
              flex: 5,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () => _launchSelected(
                    from: hasResume ? progress.position : null),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(
                  hasResume
                      ? 'REPRENDRE · ${_formatResumeShort(progress.position)}'
                      : l10n.actionSheetPlay.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // ── Télécharger ─────────────────────────────────────────────────
            // §1L-c : fond plein + bordure cyan pour rester contrasté sur le
            // dark theme (plus de bouton transparent quasi-invisible).
            Expanded(
              flex: 4,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  foregroundColor: kAccentSecondary,
                  side: BorderSide(color: kAccentSecondary.withAlpha(180), width: 1.5),
                ),
                onPressed: () => verifierEtTelecharger(
                    url: _selectedEntry.url,
                    nom: _selectedEntry.displayName,
                    context: context),
                icon: const Icon(Icons.download_rounded),
                label: Text(
                  l10n.download.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // ── Favori (§1f-A) ──────────────────────────────────────────────
            _FavoriteIconButton(
              isFav: isFav,
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                final added = await FavoritesService.toggle(favKey);
                if (!context.mounted) return;
                messenger.clearSnackBars();
                messenger.showSnackBar(SnackBar(
                  content: Text(added
                      ? '⭐ "${_selectedEntry.displayName}" ajouté aux favoris'
                      : '🗑️ "${_selectedEntry.displayName}" retiré des favoris'),
                  duration: const Duration(seconds: 2),
                ));
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildTrailerButton() {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.red),
        foregroundColor: Colors.red,
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      onPressed: _launchTrailer,
      icon: const Icon(Icons.play_circle_outline),
      label: const Text('Bande-Annonce'),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static List<M3uEntry> _deduplicateVersions(List<M3uEntry> versions) {
    final seen    = <String>{};
    final result  = <M3uEntry>[];
    final isMulti = ParsedPlaylistService.isMultiAccount;
    for (int i = 0; i < versions.length; i++) {
      final v         = versions[i];
      final qualLabel = _buildQualityLabel(v, i);
      final key = isMulti ? '$qualLabel|${v.accountId}' : qualLabel;
      if (seen.add(key)) result.add(v);
    }
    return result;
  }

  String _qualityLabel(M3uEntry v, int index) {
    final base = _buildQualityLabel(v, index);
    if (ParsedPlaylistService.isMultiAccount && v.accountId.isNotEmpty) {
      final name = ParsedPlaylistService.accountName(v.accountId);
      if (name != null) return '$base\n$name';
    }
    return base;
  }

  static String _buildQualityLabel(M3uEntry v, int index) {
    final q  = v.title.quality;
    final vl = v.title.versionLabel;
    if (q != null && vl != null) return '$q · $vl';
    if (q != null) return q;
    if (vl != null) return vl;
    return 'Standard';
  }

  static List<String> _parsePlatforms(String? groupTitle) {
    if (groupTitle == null || groupTitle.isEmpty) return [];
    final match = RegExp(r'\(([^)]+)\)').firstMatch(groupTitle);
    if (match == null) return [];
    return match.group(1)!
        .split('|')
        .map((s) => _normalizePlatform(s.trim()))
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
  }

  static String _normalizePlatform(String raw) {
    final r = raw.toUpperCase();
    if (r.contains('NETFLIX'))   return 'Netflix';
    if (r.contains('PRIME'))     return 'Prime Video';
    if (r.contains('HBO'))       return 'HBO Max';
    if (r.contains('APPLE'))     return 'Apple TV+';
    if (r.contains('STARZPLAY') || r.contains('STARZ')) return 'Starz';
    if (r.contains('PARAMOUNT')) return 'Paramount+';
    if (r.contains('DISNEY'))    return 'Disney+';
    if (r.contains('PEACOCK'))   return 'Peacock';
    if (r.contains('CANAL'))     return 'Canal+';
    if (r.contains('DAZN'))      return 'DAZN';
    if (r.contains('HULU'))      return 'Hulu';
    if (r.contains('RAKUTEN'))   return 'Rakuten TV';
    return '';
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
      default:             return Colors.grey;
    }
  }

  Widget _buildMetaTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(
            color: Theme.of(context).colorScheme.outline.withAlpha(80)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}

// ─── §1f-A : bouton favori compact (icon-only) ───────────────────────────────

class _FavoriteIconButton extends StatefulWidget {
  final bool isFav;
  final VoidCallback onTap;
  const _FavoriteIconButton({required this.isFav, required this.onTap});

  @override
  State<_FavoriteIconButton> createState() => _FavoriteIconButtonState();
}

class _FavoriteIconButtonState extends State<_FavoriteIconButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Focus(
      onFocusChange: (v) => setState(() => _focused = v),
      child: AnimatedScale(
        scale: _focused ? 1.1 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: SizedBox(
          width: 52,
          height: 52,
          child: Material(
            color: widget.isFav
                ? kAccentTertiary.withAlpha(35)
                : _focused
                    ? cs.primary.withAlpha(30)
                    : cs.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: _focused
                    ? cs.primary
                    : widget.isFav
                        ? kAccentTertiary
                        : cs.outline.withAlpha(80),
                width: (_focused || widget.isFav) ? 1.5 : 1,
              ),
            ),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(8),
              child: Icon(
                widget.isFav ? Icons.favorite : Icons.favorite_border,
                color: _focused
                    ? cs.primary
                    : widget.isFav
                        ? kAccentTertiary
                        : cs.onSurfaceVariant,
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusableChip extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isSelected;
  final Color? accentColor;
  final double? width;

  const _FocusableChip({
    required this.label,
    this.icon,
    this.onPressed,
    this.isSelected = false,
    this.accentColor,
    this.width,
  });

  @override
  State<_FocusableChip> createState() => _FocusableChipState();
}

class _FocusableChipState extends State<_FocusableChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final themeExt = Theme.of(context).extension<AetherThemeExtension>()!;
    final color = widget.accentColor ?? cs.primary;

    return Focus(
      onFocusChange: (v) => setState(() => _focused = v),
      child: AnimatedScale(
        scale: _focused ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: widget.width,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? color.withAlpha(55)
                  : _focused
                      ? color.withAlpha(30)
                      : cs.surfaceContainerHighest,
              border: Border.all(
                color: _focused
                    ? color
                    : widget.isSelected
                        ? color.withAlpha(200)
                        : cs.outlineVariant,
                width: (_focused || widget.isSelected) ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: color.withAlpha(60),
                        blurRadius: 8,
                      )
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon,
                      size: 16,
                      color: (_focused || widget.isSelected)
                          ? color
                          : cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                ],
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: (_focused || widget.isSelected)
                        ? FontWeight.bold
                        : FontWeight.w500,
                    color: (_focused || widget.isSelected)
                        ? color
                        : cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

