import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/services/tmdb_service.dart';
import '../../data/models/media_model.dart';
import '../player/player_page.dart';
import '../downloads/logic/download_initiator.dart';
import 'recherche_page.dart';
import '../../l10n/app_localizations.dart';
import 'actor_details_page.dart';

class DetailsPage extends StatefulWidget {
  final M3uEntry entry;
  const DetailsPage({super.key, required this.entry});

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends State<DetailsPage> {
  Media? _tmdbData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final service = TmdbService.instance;
    final data = await service.getFullDetails(
      widget.entry.displayName,
      isTv: widget.entry.isSerie,
      explicitYear: widget.entry.title.year,
      groupTitle: widget.entry.groupTitle,
    );

    if (mounted) {
      setState(() {
        _tmdbData = data;
        _isLoading = false;
      });
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

    // Data extraction
    final backdropPath = _tmdbData?.backdropPath;
    final overview = _tmdbData?.overview;
    final rating = _tmdbData?.voteAverage ?? 0.0;

    final castList = _tmdbData?.cast;
    final hasTrailer = _tmdbData?.trailerKey != null;

    // Formatting
    final runtime = _tmdbData?.runtimeOrEpisodeLength;
    final releaseDate = _tmdbData?.releaseDate?.split('-').first;
    final companies = _tmdbData?.productionCompanies;

    // URLs
    final backdropUrl = TmdbService.getPosterUrl(backdropPath, size: 'original');

    return Scaffold(
      backgroundColor: Colors.black,
      body: CustomScrollView(
        slivers: [
          // 1. IMMERSIVE HEADER
          SliverAppBar(
            expandedHeight: 400.0,
            pinned: true,
            stretch: true,
            backgroundColor: Colors.black,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Image Backdrop
                  if (backdropUrl != null && hasTmdbData)
                    Image.network(
                      backdropUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade900),
                    )
                  else
                    Container(color: Colors.grey.shade900),

                  // Gradient Cyberpunk (Noir vers Transparent)
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black45,
                          Colors.black,
                        ],
                        stops: [0.0, 0.6, 1.0],
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
                  // TITRE (Héros)
                  Text(
                    widget.entry.displayName,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // LIGNE DE MÉTADONNÉES (Année • Durée • Note)
                  if (hasTmdbData)
                    Row(
                      children: [
                        if (releaseDate != null) _buildMetaTag(releaseDate, Colors.grey),
                        if (runtime != null) ...[
                          const SizedBox(width: 8),
                          const Text("•", style: TextStyle(color: Colors.grey)),
                          const SizedBox(width: 8),
                          _buildMetaTag(runtime, Colors.grey),
                        ],
                        const Spacer(),
                        if (rating > 0) ...[
                          const Icon(Icons.star, color: Colors.amber, size: 20),
                          const SizedBox(width: 4),
                          Text(
                            rating.toStringAsFixed(1),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.amber),
                          ),
                        ]
                      ],
                    ),

                  const SizedBox(height: 24),

                  // BOUTONS D'ACTION (Jouer / Télécharger)
                  Row(
                    children: [
                      // Bouton JOUER
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                          ),
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => PlayerPage(
                              path: widget.entry.url,
                              title: widget.entry.displayName,
                              sourceType: VideoSourceType.network,
                              badgeType: widget.entry.type == M3uContentType.series ? PlayerBadgeType.series : PlayerBadgeType.movie,
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
                            side: const BorderSide(color: Colors.white30),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => verifierEtTelecharger(
                              url: widget.entry.url, nom: widget.entry.displayName, context: context),
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
                  if (hasTmdbData) ...[
                    Text("Synopsis", style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white70)),
                    const SizedBox(height: 8),
                    Text(
                      overview ?? "Données classifiées.",
                      style: const TextStyle(color: Colors.grey, height: 1.5, fontSize: 15),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // 🎯 CASTING PRINCIPAL (ActionChips cliquables)
                  if (hasTmdbData && castList != null && castList.isNotEmpty) ...[
                    Text("Casting principal", style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.white70)),
                    const Divider(color: Colors.white10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: castList.map((actor) {
                        return ActionChip(
                          avatar: const Icon(Icons.person, size: 18, color: Colors.amber),
                          label: Text(actor),
                          onPressed: () => _searchActor(actor), // 🎯 APPEL VERS TMDB
                          backgroundColor: Colors.white12,
                          labelStyle: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
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
                        backgroundColor: Colors.grey.shade900,
                        labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
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
                        Text("Disponible sur", style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.white70)),
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
                    const Divider(color: Colors.white10),
                    const SizedBox(height: 8),
                    Text(
                      "Production: $companies",
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
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
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}
