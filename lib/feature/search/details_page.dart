import 'package:flutter/material.dart';
import '../../data/services/tmdb_service.dart';
import '../../data/models/media_model.dart';
import '../player/player_page.dart';
import '../downloads/logic/download_initiator.dart';
import 'recherche_page.dart';
import '../../l10n/app_localizations.dart';

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
    );

    if (mounted) {
      setState(() {
        _tmdbData = data;
        _isLoading = false;
      });
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

    // Formatting
    final runtime = _tmdbData?.runtimeOrEpisodeLength;
    final releaseDate = _tmdbData?.releaseDate?.split('-').first; // Juste l'année
    final companies = _tmdbData?.productionCompanies;

    // URLs
    final backdropUrl = TmdbService.getPosterUrl(backdropPath, size: 'original'); // Qualité max pour le fond

    return Scaffold(
      backgroundColor: Colors.black, // Fond profond
      body: CustomScrollView(
        slivers: [
          // 1. IMMERSIVE HEADER
          SliverAppBar(
            expandedHeight: 400.0, // Plus haut pour l'immersion
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
                          Colors.black, // Fondu total vers le noir en bas
                        ],
                        stops: [0.0, 0.6, 1.0],
                      ),
                    ),
                  ),

                  // Poster flottant et Titre (Optionnel dans le header, ou on le met dans le body)
                  // Ici on laisse juste l'image propre.
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
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber),
                          ),
                        ]
                      ],
                    ),

                  const SizedBox(height: 24),

                  // BOUTONS D'ACTION (Largeur complète)
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black, // Contraste fort
                          ),
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => PlayerPage(
                              path: widget.entry.url,
                              title: widget.entry.displayName,
                              sourceType: VideoSourceType.networkWithCache,
                            ),
                          )),
                          icon: const Icon(Icons.play_arrow),
                          label: Text(l10n.actionSheetPlay.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
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

                  // PRODUCTION & COMPAGNIES
                  if (companies != null && companies.isNotEmpty) ...[
                    const Divider(color: Colors.white10),
                    const SizedBox(height: 8),
                    Text(
                      "Production: $companies",
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                    const SizedBox(height: 40), // Espace bas de page
                  ],

                  // LOADING STATE (Si c'est long, on affiche un petit spinner discret en bas)
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
