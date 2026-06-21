part of 'home_page.dart';

// ─── Carte poster avec overlay gradient + titre ─────────────────────────────

class _HomeCard extends StatefulWidget {
  final List<M3uEntry> versions;
  final M3uContentType type;

  /// Largeur explicite (mode grille). Si null, valeur par défaut selon type
  /// (130 pour films/séries en carousel, 120 pour TV en carousel).
  final double? width;

  const _HomeCard({required this.versions, required this.type, this.width});

  @override
  State<_HomeCard> createState() => _HomeCardState();
}

class _HomeCardState extends State<_HomeCard> {
  bool _pressed = false;

  /// §Ultimate — affiche TMDB résolue à la volée quand le M3U ne fournit aucun
  /// `tvg-logo` (VOD Ultimate). Reste null pour les chaînes TV et les entrées
  /// déjà pourvues d'un logo.
  String? _tmdbPoster;

  /// True dès que les versions portent un `tvg-logo` exploitable.
  bool get _hasM3uLogo => widget.versions
      .any((e) => e.logoUrl != null && e.logoUrl!.isNotEmpty);

  @override
  void initState() {
    super.initState();
    _resolveTmdbPosterIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _HomeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Le recyclage des cartes (ListView/Grid) réutilise l'élément avec d'autres
    // versions → on relance la résolution si le groupe a changé.
    if (oldWidget.versions.first.url != widget.versions.first.url) {
      _tmdbPoster = null;
      _resolveTmdbPosterIfNeeded();
    }
  }

  /// Lance un fallback TMDB uniquement pour films/séries sans logo M3U.
  void _resolveTmdbPosterIfNeeded() {
    if (_hasM3uLogo) return;
    if (widget.type == M3uContentType.tv) return; // les chaînes ont leur logo
    final entry = widget.versions.first;
    final query = entry.displayName;
    if (query.trim().isEmpty) return;
    final isTv = widget.type == M3uContentType.series;
    final year = entry.title.year;

    // Cache déjà résolu → consommation synchrone, pas de setState inutile.
    if (TmdbPosterCache.isResolved(query, isTv, year)) {
      _tmdbPoster = TmdbPosterCache.cached(query, isTv, year);
      return;
    }

    TmdbPosterCache.resolve(
      query: query,
      isTv: isTv,
      year: year,
      groupTitle: entry.groupTitle,
    ).then((url) {
      if (!mounted || url == null) return;
      setState(() => _tmdbPoster = url);
    });
  }

  Future<void> _onTap() async {
    if (widget.versions.isEmpty) return;
    final entry = widget.versions.first;
    if (widget.type == M3uContentType.tv) {
      await showTvActionSheet(context, widget.versions);
      return;
    }
    final hasTmdb = await TmdbApiService.hasApiKey();
    if (!mounted) return;
    // §bugfix — voir _openItem : une série va sur DetailsPage même sans TMDB
    // (sinon l'action sheet ne lit que le 1er épisode, pas de choix possible).
    if (hasTmdb || entry.type == M3uContentType.series) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DetailsPage(entry: entry, versions: widget.versions),
      ));
    } else {
      await showMediaActionSheet(context, entry);
    }
  }

  /// Menu contextuel sur appui long — actions rapides sans passer par la fiche.
  Future<void> _onLongPress() async {
    if (widget.versions.isEmpty) return;
    HapticFeedback.mediumImpact();
    final entry = widget.versions.first;
    final favKey = FavoritesService.keyFor(entry);

    // §3c-4 — bifurque mobile/TV pour le menu contextuel long-press.
    await showAdaptiveActionSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // En-tête : poster + titre
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 50,
                      height: widget.type == M3uContentType.tv ? 50 : 75,
                      child: (entry.logoUrl != null && entry.logoUrl!.isNotEmpty)
                          ? Image.network(entry.logoUrl!, fit: BoxFit.cover, cacheWidth: 150, gaplessPlayback: true, errorBuilder: (_, __, ___) => const SizedBox.shrink())
                          : const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      entry.displayName,
                      style: Theme.of(sheetCtx).textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // ── Lire (direct, avec reprise §1e si dispo) ──────────────────
            ValueListenableBuilder<int>(
              valueListenable: WatchProgressService.version,
              builder: (_, __, ___) {
                // Reprise impossible sur TV live → on garde le simple "Lire".
                final progress = widget.type == M3uContentType.tv
                    ? null
                    : WatchProgressService.getProgressForAny(
                        widget.versions.map((e) => e.url),
                      );
                final hasResume = progress != null && progress.position.inSeconds > 5;

                final badge = switch (widget.type) {
                  M3uContentType.movie  => PlayerBadgeType.movie,
                  M3uContentType.series => PlayerBadgeType.series,
                  M3uContentType.tv     => PlayerBadgeType.live,
                };

                void play({Duration? from}) {
                  Navigator.pop(sheetCtx);
                  FavoritesService.add(favKey);
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerPage(
                    path: entry.url,
                    title: entry.displayName,
                    sourceType: VideoSourceType.network,
                    badgeType: badge,
                    startPosition: from,
                  )));
                }

                if (!hasResume) {
                  return ListTile(
                    leading: const Icon(Icons.play_arrow),
                    title: const Text('Lire'),
                    onTap: () => play(),
                  );
                }

                final mm = progress.position.inMinutes.remainder(60);
                final ss = progress.position.inSeconds.remainder(60);
                final hh = progress.position.inHours;
                final label = hh > 0
                    ? '${hh}h${mm.toString().padLeft(2, '0')}'
                    : '${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}';

                return Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.play_arrow, color: kAccentSecondary),
                      title: Text(
                        'Reprendre depuis $label',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: kAccentSecondary,
                        ),
                      ),
                      subtitle: LinearProgressIndicator(
                        value: progress.ratio,
                        minHeight: 3,
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation(kAccentSecondary),
                      ),
                      onTap: () => play(from: progress.position),
                    ),
                    ListTile(
                      leading: const Icon(Icons.restart_alt),
                      title: const Text('Lire depuis le début'),
                      dense: true,
                      onTap: () {
                        WatchProgressService.clearProgress(entry.url);
                        play();
                      },
                    ),
                    // §forgetResume — Efface la reprise sans lancer la lecture.
                    // Clear sur toutes les variantes du groupe (FHD + HD…) pour
                    // que le film disparaisse vraiment de la pile "Reprendre".
                    ListTile(
                      leading: Icon(Icons.history_toggle_off, color: kWarning),
                      title: Text(
                        'Oublier la reprise',
                        style: TextStyle(fontSize: 13, color: kWarning),
                      ),
                      dense: true,
                      onTap: () async {
                        final snapshot = progress;
                        final clearedUrl = entry.url;
                        final messenger = ScaffoldMessenger.of(context);
                        Navigator.pop(sheetCtx);
                        for (final v in widget.versions) {
                          await WatchProgressService.clearProgress(v.url);
                        }
                        AppSnackBar.showVia(messenger, SnackBar(
                          content: const Text('Reprise oubliée'),
                          duration: const Duration(seconds: 5),
                          action: SnackBarAction(
                            label: 'Annuler',
                            onPressed: () {
                              WatchProgressService.saveProgress(
                                clearedUrl,
                                snapshot.position,
                                snapshot.duration,
                              );
                            },
                          ),
                        ));
                      },
                    ),
                  ],
                );
              },
            ),
            // ── Voir les détails (action sheet ou fiche TMDB) ─────────────
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Voir les détails'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _onTap();
              },
            ),
            // ── Télécharger (films/séries uniquement) ─────────────────────
            if (widget.type != M3uContentType.tv)
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('Télécharger'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  final releaseYear = widget.type == M3uContentType.movie ? entry.title.year : null;
                  verifierEtTelecharger(
                    url: entry.url,
                    nom: buildDownloadName(entry),
                    releaseYear: releaseYear,
                    context: context,
                  );
                },
              ),
            // ── Toggle favori ─────────────────────────────────────────────
            ValueListenableBuilder<int>(
              valueListenable: FavoritesService.version,
              builder: (ctx, _, __) {
                final isFav = FavoritesService.isFavorite(favKey);
                return ListTile(
                  // §themePlus — couleur favori unifiée (kFavorite partout).
                  leading: Icon(
                    isFav ? Icons.favorite : Icons.favorite_border,
                    color: isFav ? kFavorite : null,
                  ),
                  title: Text(
                    isFav ? 'Retirer des favoris' : 'Ajouter aux favoris',
                    style: TextStyle(color: isFav ? kFavorite : null),
                  ),
                  onTap: () async {
                    await FavoritesService.toggle(favKey);
                    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                  },
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entry = widget.versions.first;
    // §23 — politique image « plus grosse liste ».
    // §Ultimate — fallback affiche TMDB quand le M3U ne fournit aucun tvg-logo.
    final logoUrl = ParsedPlaylistService.bestLogoUrl(widget.versions)
        ?? _tmdbPoster;

    final isTv = widget.type == M3uContentType.tv;
    final cardWidth = widget.width ?? (isTv ? 120.0 : 130.0);
    final imageAspectRatio = isTv ? 1.0 : 2 / 3;

    final fallbackIcon = switch (widget.type) {
      M3uContentType.movie  => Icons.movie_outlined,
      M3uContentType.series => Icons.tv_outlined,
      M3uContentType.tv     => Icons.live_tv_outlined,
    };

    // §3c-3 — Wrap focus TV (decorateOnly = la card garde son GestureDetector
    // et son anim _pressed). Sur TV, la bordure glow + scale 1.05 sont gérés
    // par FocusableCard ; sur mobile, FocusableCard est neutre.
    return FocusableCard(
      decorateOnly: true,
      onTap: _onTap,
      onLongPress: _onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: _onTap,
        onLongPress: _onLongPress,
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: SizedBox(
            width: cardWidth,
            child: AspectRatio(
              aspectRatio: imageAspectRatio,
              child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: cs.surfaceContainerHighest,
                border: Border.all(
                  color: kAccentPrimary.withAlpha(40),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(80),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Image
                    if (logoUrl != null && logoUrl.isNotEmpty)
                      Image.network(
                        logoUrl,
                        fit: isTv ? BoxFit.contain : BoxFit.cover,
                        // §imgPerf — Carte poster ~120-200 px ; on cap le
                        // décodage à 360 px. Combiné à `gaplessPlayback`, plus
                        // de flash blanc / re-décodage au rebuild (focus, auto-
                        // rotation, version bumps).
                        cacheWidth: 360,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) =>
                            _fallback(fallbackIcon, cs),
                        loadingBuilder: (_, child, progress) =>
                            progress == null ? child : _fallback(fallbackIcon, cs),
                      )
                    else
                      _fallback(fallbackIcon, cs),
                    // Gradient bottom overlay pour la lisibilité du titre
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.55, 1.0],
                            colors: [
                              Colors.transparent,
                              Colors.black.withAlpha(220),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Titre en surimpression bas (+ année pour les films →
                    // distingue les homonymes/remakes séparés par §homonymYear).
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            entry.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              height: 1.2,
                              shadows: [
                                Shadow(color: Colors.black, blurRadius: 4),
                              ],
                            ),
                          ),
                          if (widget.type == M3uContentType.movie &&
                              entry.title.year != null)
                            Text(
                              entry.title.year!,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withAlpha(190),
                                height: 1.3,
                                shadows: const [
                                  Shadow(color: Colors.black, blurRadius: 4),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    // §1e — Barre de progression "reprendre depuis…" :
                    // visible si l'utilisateur a regardé l'une des variantes du
                    // groupe sans aller jusqu'au bout (TV exclu — pas de durée).
                    if (!isTv)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ValueListenableBuilder<int>(
                          valueListenable: WatchProgressService.version,
                          builder: (_, __, ___) {
                            final p = WatchProgressService.getProgressForAny(
                              widget.versions.map((e) => e.url),
                            );
                            if (p == null || p.ratio <= 0) {
                              return const SizedBox.shrink();
                            }
                            return LinearProgressIndicator(
                              value: p.ratio,
                              minHeight: 3,
                              backgroundColor: Colors.white24,
                              valueColor: AlwaysStoppedAnimation(kAccentSecondary),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _fallback(IconData icon, ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(icon, size: 36, color: cs.onSurfaceVariant.withAlpha(120)),
    );
  }
}

