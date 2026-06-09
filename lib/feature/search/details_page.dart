import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/themes/colors.dart';
import '../../core/utils/platform_tv.dart';
import '../../data/services/favorites_service.dart';
import '../../data/services/tmdb_service.dart';
import '../../data/services/tmdb_api_service.dart';
import '../settings/tmdb_key_page.dart';
import '../../data/services/parsed_playlist_service.dart';
import '../../data/services/stream_account_service.dart';
import '../../data/services/watch_progress_service.dart';
import '../../data/services/xtream_api_service.dart';
import '../../core/utils/app_snackbar.dart';
import '../../data/models/media_model.dart';
import '../player/player_page.dart';
import '../downloads/logic/download_initiator.dart';
import '../../data/models/m3u_entry.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/tv/focusable_chip.dart';
import '../../widgets/tv/focusable_card.dart';
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
  /// §quickwin — clé TMDB configurée ? (distinct de `hasTmdb` = données reçues).
  /// `true` par défaut pour éviter un flash du CTA avant le check async.
  bool _hasTmdbKey = true;
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
      _applyInitialEpisodeSelection();
    } else if (widget.entry.type == M3uContentType.series) {
      // §xtreamEpisodes — Pas d'épisodes trouvés dans le M3U parsé : c'est
      // probablement une entrée série issue de la JSON API (un seul stub par
      // série, sans épisodes). On va les chercher à la demande via
      // `XtreamApiService.fetchEpisodes(seriesId)` — lazy load, on ne pré-
      // charge pas les 19 000+ séries au boot.
      _uniqueVersions = _deduplicateVersions(widget.versions);
      _selectedEntry  = _uniqueVersions.isNotEmpty ? _uniqueVersions.first : widget.entry;
      _fetchEpisodesFromXtreamApi();
    } else {
      _uniqueVersions = _deduplicateVersions(widget.versions);
      _selectedEntry  = _uniqueVersions.isNotEmpty ? _uniqueVersions.first : widget.entry;
    }

    _loadData();

    // §quickwin — check clé TMDB pour le CTA "Active TMDB" (sans clé, pas
    // d'affiches/synopsis/casting → on incite à en configurer une).
    TmdbApiService.hasApiKey().then((v) {
      if (mounted) setState(() => _hasTmdbKey = v);
    });
  }

  @override
  void dispose() {
    _episodeScrollController.dispose();
    super.dispose();
  }

  /// §xtreamEpisodes — Applique la sélection initiale d'épisode après que
  /// `_seasonEpisodes` est rempli (que ce soit via le parser M3U OU via le
  /// lazy fetch de la JSON API). Factorisé pour pouvoir être appelé depuis
  /// initState ET depuis `_fetchEpisodesFromXtreamApi`.
  void _applyInitialEpisodeSelection() {
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
        _selectedEntry   = _uniqueVersions.isNotEmpty
            ? _uniqueVersions.first
            : group.best;
        return;
      }
    }
    _episodeSelected = false;
    _uniqueVersions  = const [];
    _selectedEntry   = widget.entry;
  }

  /// §xtreamEpisodes — Récupère les épisodes via la JSON API Xtream à la
  /// demande (séries listées en stubs au boot, épisodes chargés à l'ouverture).
  Future<void> _fetchEpisodesFromXtreamApi() async {
    final seriesId = _extractSeriesIdFromUrl(widget.entry.url);
    if (seriesId == null) return;
    final account = await StreamAccountService.getAccount(widget.entry.accountId);
    if (account == null) return;

    final episodes = await XtreamApiService.fetchEpisodes(account, seriesId);
    if (!mounted || episodes.isEmpty) return;

    // Regroupement saison → épisode → versions (1 seule version par épisode
    // côté API, mais on garde la structure pour rester compatible avec le
    // pipeline existant qui gère les épisodes en doublon).
    final tmp = <int, Map<int, List<M3uEntry>>>{};
    for (final ep in episodes) {
      final s = ep.title.seasonNumber;
      final e = ep.title.episodeNumber;
      if (s == null || e == null) continue;
      tmp.putIfAbsent(s, () => {}).putIfAbsent(e, () => []).add(ep);
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

    if (!mounted) return;
    setState(() {
      _seasonEpisodes = {for (final s in sortedSeasons) s: result[s]!};
      _selectedSeason = null;
      _applyInitialEpisodeSelection();
    });
  }

  /// Extrait le `series_id` d'une URL stub `/series/{user}/{pass}/{id}`
  /// (sans extension). Retourne `null` si :
  /// - URL pas de format `series`
  /// - dernier segment a une extension (= URL d'épisode, pas un stub)
  /// - dernier segment pas un entier
  static int? _extractSeriesIdFromUrl(String url) {
    try {
      final segments = Uri.parse(url).pathSegments;
      if (segments.length < 4 || segments[0].toLowerCase() != 'series') {
        return null;
      }
      final last = segments.last;
      if (last.contains('.')) return null; // c'est une URL d'épisode
      return int.tryParse(last);
    } catch (_) {
      return null;
    }
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
      ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(
        SnackBar(content: Text("TMDB n'a pas trouvé de fiche pour $actorName.")),
      );
    }
  }

  /// Ouvre la bande-annonce dans l'app YouTube / le navigateur externe.
  /// (Lecteur in-app §trailerInApp retiré : beaucoup de trailers de studios
  /// désactivent l'embedding → injouables dans un lecteur tiers.)
  Future<void> _launchTrailer() async {
    final key = _tmdbData?.trailerKey;
    if (key == null || key.isEmpty) return;
    final url = Uri.parse('https://www.youtube.com/watch?v=$key');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  // §quickwin — Bandeau incitant à configurer TMDB (affiché si pas de clé).
  Widget _buildTmdbCta(ColorScheme cs) {
    return Material(
      color: kAccentPrimary.withAlpha(20),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TmdbKeyPage()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.movie_filter_outlined, color: kAccentPrimary, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Active TMDB',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                            fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      'Affiches, synopsis et casting. Config rapide au QR depuis ton mobile.',
                      style: TextStyle(
                          color: cs.onSurfaceVariant, fontSize: 12, height: 1.3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  // §tvDetailsShrink — Réglages de réduction de la fiche sur TV (faciles à
  // ajuster d'un seul nombre) :
  //   - backdrop : fraction de la hauteur écran (clamp 180-300) vs 360 fixe mobile
  //   - largeur max de la colonne d'infos (centrée) → évite le texte étalé
  //   - échelle du texte de la fiche (0.85 = -15%) pour réduire "toute la partie infos"
  static const double _kTvBackdropFraction = 0.42;
  static const double _kTvContentMaxWidth = 820.0;
  static const double _kTvContentTextScale = 0.85;

  /// Enveloppe le contenu de la fiche pour le réduire sur TV : largeur max
  /// centrée + texte mis à l'échelle. Neutre sur mobile.
  Widget _tvShrinkContent(BuildContext context, bool isTv, Widget child) {
    if (!isTv) return child;
    final mq = MediaQuery.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _kTvContentMaxWidth),
        child: MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(_kTvContentTextScale),
          ),
          child: child,
        ),
      ),
    );
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
    // §quickwin — fallback affiche playlist quand pas de backdrop TMDB.
    // Sans clé TMDB, le header était un rectangle gris : on récupère la 1re
    // logoUrl non vide (versions affichées → épisode courant → entrée).
    final String? playlistPoster = <String?>[
      ..._uniqueVersions.map((e) => e.logoUrl),
      _currentEpisode.logoUrl,
      widget.entry.logoUrl,
    ].firstWhere((l) => l != null && l.isNotEmpty, orElse: () => null);
    final String? headerUrl    = headerPath != null
        ? TmdbService.getPosterUrl(headerPath,
            size: (_episodeSelected && stillPath != null) ? 'w780' : 'original')
        : playlistPoster;

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

    // §tvDetailsShrink — Sur TV, la fiche paraissait énorme : backdrop fixe 360px
    // (énorme part d'un écran à hauteur logique courte) + colonne d'infos étalée
    // sur toute la largeur + texte natif. On réduit les 3 leviers, uniquement sur
    // TV (mobile inchangé). Tunables ci-dessous.
    final bool isTvPlatform = PlatformTv.isTv;
    final double screenH = MediaQuery.sizeOf(context).height;
    final double headerHeight = isTvPlatform
        ? (screenH * _kTvBackdropFraction).clamp(180.0, 300.0)
        : 360.0;

    return Scaffold(
      backgroundColor: cs.surface,
      body: CustomScrollView(
        slivers: [
          // ── HEADER ────────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: headerHeight,
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
            child: _tvShrinkContent(
              context,
              isTvPlatform,
              Padding(
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

                  // §quickwin — CTA discret si aucune clé TMDB configurée.
                  if (!_hasTmdbKey) ...[
                    _buildTmdbCta(cs),
                    const SizedBox(height: 16),
                  ],

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

                  // CASTING — vignettes acteurs avec photo (carrousel horizontal)
                  if (hasTmdb && _tmdbData!.castMembers.isNotEmpty) ...[
                    Text('Casting principal',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                    Divider(color: cs.outlineVariant),
                    SizedBox(
                      // §castPhotos — hauteur = photo portrait 2:3 (92×138) + nom
                      // (2 lignes) + rôle + marge pour le textScaler TV ×1.3.
                      height: 218,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        // §focusScroll — cache plus large pour que la nav D-pad
                        // trouve toujours la card suivante dans l'arbre de focus.
                        // ignore: deprecated_member_use
                        cacheExtent: 600,
                        itemCount: _tmdbData!.castMembers.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (_, i) =>
                            _CastCard(member: _tmdbData!.castMembers[i]),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ]
                  // Fallback : anciens noms seuls si pas de casting enrichi.
                  else if (hasTmdb && _tmdbData!.cast.isNotEmpty) ...[
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
                          .map((a) => ActionChip(
                                avatar: Icon(Icons.person,
                                    size: 16, color: kAccentSecondary),
                                label: Text(a),
                                onPressed: () => _searchActor(a),
                                backgroundColor: cs.surfaceContainerHighest,
                                labelStyle: TextStyle(
                                    color: cs.onSurface,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500),
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
          ),
        ],
      ),
    );
  }

  // ── Navigateur série ────────────────────────────────────────────────────────

  Widget _buildSeriesNavigator(ColorScheme cs, AppLocalizations l10n) {
    final hasSeasons = _seasonEpisodes.isNotEmpty;
    final totalSeasons = _seasonEpisodes.length;
    final totalEpisodes =
        _seasonEpisodes.values.fold<int>(0, (acc, eps) => acc + eps.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── §seasonsUI — En-tête de section "SAISONS" + total ────────────────
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  gradient: kAetherGradient,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'SAISONS',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: kAccentPrimary,
                ),
              ),
              if (hasSeasons) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    totalSeasons == 1
                        ? '$totalSeasons saison · $totalEpisodes épisodes'
                        : '$totalSeasons saisons · $totalEpisodes épisodes',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // ── SAISONS (chips contour néon cohérent avec le style fiche) ────────
        if (!hasSeasons)
          // §xtreamEpisodes — état chargement pendant le fetch async des épisodes
          // (lazy load via XtreamApiService.fetchEpisodes), si on est sur une
          // série stub issue de la JSON API.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(kAccentPrimary),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Chargement des épisodes…',
                  style: TextStyle(
                      fontSize: 13, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _seasonEpisodes.entries.map((entry) {
                final sNum = entry.key;
                final epCount = entry.value.length;
                final isSelected = sNum == _selectedSeason;
                final accent = isSelected ? kAccentPrimary : cs.onSurfaceVariant;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FocusableChip(
                    onTap: () => _selectSeason(sNum),
                    borderRadius: BorderRadius.circular(14),
                    child: GestureDetector(
                      onTap: isSelected ? null : () => _selectSeason(sNum),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? kAccentPrimary.withAlpha(28)
                              : cs.surfaceContainer,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? kAccentPrimary
                                : cs.outline.withAlpha(40),
                            width: isSelected ? 1.8 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: kAccentPrimary.withAlpha(70),
                                    blurRadius: 12,
                                    spreadRadius: -2,
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Saison ${sNum.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                                color: accent,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 1),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? kAccentPrimary.withAlpha(45)
                                    : cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$epCount ép.',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: accent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
                  // §3c Phase 1 — FocusableChip : l'épisode devient sélectionnable
                  // au D-pad (avant : GestureDetector tap-only). onTap toujours
                  // défini → l'épisode courant garde le focus.
                  child: FocusableChip(
                    onTap: () => _selectEpisode(group),
                    borderRadius: BorderRadius.circular(8),
                    child: GestureDetector(
                    onTap: isCurrent ? null : () => _selectEpisode(group),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 52,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? cs.primary.withAlpha(40)
                            : cs.surfaceContainerHighest,
                        border: Border.all(
                          color: isCurrent
                              ? cs.primary
                              : cs.outlineVariant,
                          width: isCurrent ? 1.5 : 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'E${group.episodeNumber.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isCurrent
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isCurrent
                              ? cs.primary
                              : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
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
        // §3c Phase 1 — FocusableChip : la version FHD/HD devient sélectionnable
        // au D-pad (avant : GestureDetector tap-only).
        return FocusableChip(
          onTap: () => setState(() => _selectedEntry = v),
          borderRadius: BorderRadius.circular(8),
          child: GestureDetector(
          onTap: () => setState(() => _selectedEntry = v),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: selected ? color.withAlpha(55) : color.withAlpha(20),
              border: Border.all(
                color: selected ? color.withAlpha(200) : color.withAlpha(60),
                width: selected ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: color,
                height: 1.3,
              ),
            ),
          ),
          ),
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
                // §nextEpPortrait — On supprime la restauration portrait du
                // dispose du player courant (qui sinon écraserait, ~300 ms plus
                // tard, le landscape du player suivant → épisode en portrait).
                PlayerPage.suppressOrientationRestore = true;
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

        // §detailsActions — Deux lignes au même gabarit 75/25 : action principale
        // (75 %) + action secondaire (25 %, même taille de chaque côté).
        //   Ligne 1 : Lire/Reprendre + Oublier la reprise (si reprise).
        //   Ligne 2 : Télécharger + Favori.
        // Boutons pleins avec bordure fine + glow coloré (cf. _glowButton).
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Ligne 1 : Lire / Reprendre (75 %) + Oublier (25 %) ──────────
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _glowButton(
                    color: kAccentPrimary,
                    onPressed: () => _launchSelected(
                        from: hasResume ? progress.position : null),
                    child: _btnContent(
                      Icons.play_arrow_rounded,
                      hasResume
                          ? 'REPRENDRE · ${_formatResumeShort(progress.position)}'
                          : l10n.actionSheetPlay.toUpperCase(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Slot droit TOUJOURS présent (gabarit 75/25 constant, aligné
                // avec la ligne Télécharger/Favori). Actif = Oublier la reprise ;
                // sans reprise = placeholder désactivé "vide" (comme un favori
                // inactif) → évite que "Lire" s'étire à 100 %.
                Expanded(
                  flex: 1,
                  child: _glowButton(
                    color: kWarning,
                    onPressed: hasResume ? () => _forgetResume(progress) : null,
                    child: const Icon(Icons.history_toggle_off),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // ── Ligne 2 : Télécharger (75 %) + Favori (25 %) ────────────────
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _glowButton(
                    color: kAccentSecondary,
                    onPressed: () => verifierEtTelecharger(
                        url: _selectedEntry.url,
                        nom: _selectedEntry.displayName,
                        context: context),
                    child: _btnContent(
                        Icons.download_rounded, l10n.download.toUpperCase()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: _glowButton(
                    color: kFavorite,
                    active: isFav,
                    onPressed: () async {
                      final added = await FavoritesService.toggle(favKey);
                      if (!mounted) return;
                      AppSnackBar.show(
                        context,
                        added
                            ? '⭐ "${_selectedEntry.displayName}" ajouté aux favoris'
                            : '🗑️ "${_selectedEntry.displayName}" retiré des favoris',
                      );
                    },
                    child: Icon(isFav ? Icons.favorite : Icons.favorite_border),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// §detailsActions — Bouton d'action style **contour néon** : bordure ET texte
  /// à la couleur du thème [color], fond quasi transparent (léger voile teinté),
  /// + glow coloré. [active] `false` ou `onPressed == null` → bouton **grisé**
  /// (bord + texte éteints, pas de glow) tout en gardant le gabarit. Sert aussi
  /// d'indicateur d'état (ex. favori allumé/éteint).
  Widget _glowButton({
    required Color color,
    required VoidCallback? onPressed,
    required Widget child,
    bool active = true,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lit = active && onPressed != null;
    // Éteint : gris discret adapté au mode (nuit/jour).
    final dimmed = isDark ? Colors.white38 : Colors.black38;
    final fg = lit ? color : dimmed; // bordure + texte + icône
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: lit
            ? [
                BoxShadow(
                  color: color.withAlpha(70),
                  blurRadius: 14,
                  spreadRadius: -2,
                ),
              ]
            : null,
      ),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          foregroundColor: fg,
          disabledForegroundColor: dimmed,
          // Léger voile teinté quand allumé pour un peu de corps, sinon transparent.
          backgroundColor:
              lit ? color.withAlpha(isDark ? 26 : 16) : Colors.transparent,
          side: BorderSide(color: fg, width: 1.6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: onPressed,
        child: child,
      ),
    );
  }

  /// Contenu icône + libellé centré pour un [_glowButton] (le texte s'ellipse).
  Widget _btnContent(IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      );

  /// §forgetResume — Efface la reprise du film en cours + snackbar UNDO 4 s
  /// (restauration via `saveProgress` du snapshot). Comportement identique à
  /// l'action sheet / long-press home.
  Future<void> _forgetResume(WatchProgress snapshot) async {
    await WatchProgressService.clearProgress(_selectedEntry.url);
    if (!mounted) return;
    AppSnackBar.showCustom(
      context,
      SnackBar(
        content: const Text('Reprise oubliée'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Annuler',
          onPressed: () {
            WatchProgressService.saveProgress(
              _selectedEntry.url,
              snapshot.position,
              snapshot.duration,
            );
          },
        ),
      ),
    );
  }

  Widget _buildTrailerButton() {
    // §detailsActions — Aligné sur le style des autres boutons (_glowButton :
    // plein + bordure + glow). Couleur du thème (tertiaire) au lieu du rouge
    // hors-thème, pour rester cohérent (vert=Lire, cyan=Télécharger, magenta=BA).
    return _glowButton(
      color: kAccentTertiary,
      onPressed: _launchTrailer,
      child: _btnContent(Icons.play_circle_outline, 'BANDE-ANNONCE'),
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

/// §castPhotos — Vignette d'acteur (photo + nom + rôle) du carrousel casting de
/// la fiche détail. Tap → [ActorDetailsPage] (id direct, sans recherche par nom).
/// Mobile + TV (focus glow via [FocusableCard], sans scale pour ne pas déborder
/// la rangée à hauteur fixe).
class _CastCard extends StatelessWidget {
  final CastMember member;
  const _CastCard({required this.member});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final photoUrl = TmdbService.getPosterUrl(member.profilePath, size: 'w185');

    // §castPhotos — portrait 2:3 (92×138) : les photos TMDB sont des portraits ;
    // un cadre quasi carré + BoxFit.cover recadrait sur la bouche.
    Widget placeholder() => Container(
          width: 92,
          height: 138,
          color: cs.surfaceContainerHighest,
          child: Icon(Icons.person, color: cs.onSurfaceVariant, size: 36),
        );

    return FocusableCard(
      scaleOnFocus: false,
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ActorDetailsPage(personId: member.id)),
      ),
      child: SizedBox(
        width: 92,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: photoUrl != null
                  ? Image.network(
                      photoUrl,
                      width: 92,
                      height: 138,
                      fit: BoxFit.cover,
                      // Cadre sur le haut → garde le visage (yeux) plutôt que de
                      // recentrer sur le bas (bouche/menton).
                      alignment: Alignment.topCenter,
                      errorBuilder: (_, __, ___) => placeholder(),
                    )
                  : placeholder(),
            ),
            const SizedBox(height: 6),
            // §tvRails — Le texte est mis en retrait (horizontal + bas) pour ne
            // pas coller à la bordure/glow de focus de la FocusableCard.
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface),
                  ),
                  if (member.character != null && member.character!.isNotEmpty)
                    Text(
                      member.character!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
