part of 'home_page.dart';

// ─── Carte poster avec overlay gradient + titre ─────────────────────────────

class _HomeCard extends StatefulWidget {
  final List<M3uEntry> versions;
  final M3uContentType type;

  /// Largeur explicite (mode grille). Si null, valeur par défaut selon type
  /// (130 pour films/séries en carousel, 120 pour TV en carousel).
  final double? width;

  /// §dpadRowEntry — `true` pour la 1re carte (gauche) d'un carrousel : point
  /// d'entrée dpad de la rangée → ↓ depuis une rangée du dessus se cale à gauche.
  final bool isEntry;

  const _HomeCard(
      {super.key,
      required this.versions,
      required this.type,
      this.width,
      this.isEntry = false});

  @override
  State<_HomeCard> createState() => _HomeCardState();
}

class _HomeCardState extends State<_HomeCard> {
  bool _pressed = false;

  /// §Ultimate — affiche TMDB résolue à la volée quand le M3U ne fournit aucun
  /// `tvg-logo` (VOD Ultimate). Reste null pour les chaînes TV et les entrées
  /// déjà pourvues d'un logo.
  String? _tmdbPoster;

  /// §logoFallback — Adresses d'image du groupe, dans l'ordre de préférence.
  ///
  /// ⚠️ Remplace l'ancien test `_hasM3uLogo` (« au moins une version porte un
  /// `tvg-logo` »), qui **court-circuitait TMDB dès qu'une seule adresse
  /// existait, même MORTE** : on perdait alors l'affiche ET, depuis
  /// §inferredCat, la catégorie. C'est désormais l'ÉCHEC de chargement qui
  /// décide, pas la simple présence d'une chaîne de caractères.
  List<String> get _logoCandidates =>
      ParsedPlaylistService.logoCandidates(widget.versions);

  @override
  void initState() {
    super.initState();
    // §logoFallback — Sans aucune adresse, inutile d'attendre un échec de
    // chargement qui n'arrivera jamais : on résout tout de suite. Sinon on
    // laisse `AetherImage` essayer les adresses, et son `onAllFailed` nous
    // rappellera si toutes échouent.
    if (_logoCandidates.isEmpty) _resolveTmdbPosterIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _HomeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Le recyclage des cartes (ListView/Grid) réutilise l'élément avec d'autres
    // versions → on relance la résolution si le groupe a changé.
    if (oldWidget.versions.first.url != widget.versions.first.url) {
      _tmdbPoster = null;
      if (_logoCandidates.isEmpty) _resolveTmdbPosterIfNeeded();
    }
  }

  /// §logoFallback — Repli TMDB : soit aucune adresse n'existe, soit toutes ont
  /// échoué à charger. Films et séries uniquement.
  ///
  /// ⚠️ Idempotent : `TmdbPosterCache` dédoublonne les appels concurrents et
  /// met même les résultats négatifs en cache, donc être rappelé plusieurs fois
  /// pour un même titre ne coûte rien.
  void _resolveTmdbPosterIfNeeded() {
    if (_tmdbPoster != null) return;
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
      // §inferredCat — Même clé que le regroupement de l'accueil : la catégorie
      // apprise ici s'applique donc à TOUTES les variantes du titre, quel que
      // soit le compte d'où elles viennent.
      categoryKey: contentGroupKey(entry),
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
                      // §imgDiskCache — cache disque partagé (AetherImage).
                      // §imgThrash — décodage calé sur les 50 px réels.
                      child: AetherImage(
                        url: entry.logoUrl,
                        fit: BoxFit.cover,
                        cacheWidth: decodeWidthFor(context, 50),
                      ),
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
                  FavoritesService.addEntry(entry);
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerPage(
                    path: entry.url,
                    title: entry.displayName,
                    // §stallCount — rattache les blocages au fournisseur.
                    accountId: entry.accountId,
                    // §watchContext a/b — badges qualité + saison/épisode.
                    qualityTag: entry.title.qualityOrDefault,
                    episodeTag: entry.title.seasonEpisodeLabel,
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
                        // §resumeUnify — clear sur toutes les versions.
                        for (final v in widget.versions) {
                          WatchProgressService.clearProgress(v.url);
                        }
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
                      // §undoTv — On demande AVANT de fermer la feuille : sur TV
                      // `confirmOrUndo` ouvre un dialogue, qui exige un contexte
                      // encore monté. Le `pop` passe après, et seulement si
                      // l'oubli a bien eu lieu.
                      onTap: () async {
                        final snapshot = progress;
                        final clearedUrl = entry.url;
                        final done = await confirmOrUndo(
                          sheetCtx,
                          title: 'Oublier la reprise ?',
                          question:
                              'La position de lecture de ce titre sera oubliée.',
                          confirmLabel: 'Oublier',
                          doneMessage: 'Reprise oubliée',
                          action: () async {
                            for (final v in widget.versions) {
                              await WatchProgressService.clearProgress(v.url);
                            }
                          },
                          onUndo: () {
                            WatchProgressService.saveProgress(
                              clearedUrl,
                              snapshot.position,
                              snapshot.duration,
                            );
                          },
                        );
                        if (done && sheetCtx.mounted) Navigator.pop(sheetCtx);
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
                final isFav = FavoritesService.isEntryFavorite(entry);
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
                    await FavoritesService.toggleEntry(entry);
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
    // §logoFallback — Toutes les adresses du groupe, puis l'affiche TMDB une
    // fois résolue. `AetherImage` descend la liste à chaque échec.
    final logoCandidates = <String>[
      ..._logoCandidates,
      if (_tmdbPoster != null) _tmdbPoster!,
    ];
    final logoUrl = logoCandidates.isEmpty ? null : logoCandidates.first;

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
    // §rowAnchor — dans un carrousel horizontal, la carte focusée se cale à
    // GAUCHE du viewport (la suite de la rangée défile devant, façon Netflix)
    // au lieu de rester collée au bord droit. Sans effet dans les grilles
    // (pas de scrollable horizontal ancêtre).
    return FocusableCard(
      decorateOnly: true,
      entry: widget.isEntry,
      anchorRowStart: true,
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
                    // Image — §imgDiskCache : cache DISQUE (les vignettes se
                    // re-téléchargeaient à chaque affichage, le cache mémoire
                    // étant évincé sous pression sur box faible).
                    // §imgPerf — cap de décodage conservé à 360 px (carte
                    // poster ~120-200 px).
                    AetherImage(
                      url: logoUrl,
                      alternates: logoCandidates.skip(1).toList(),
                      // §logoFallback — Toutes les adresses du fournisseur ont
                      // échoué : c'est le moment de demander l'affiche à TMDB
                      // (et, au passage, la catégorie — cf. §inferredCat).
                      onAllFailed: _resolveTmdbPosterIfNeeded,
                      fit: isTv ? BoxFit.contain : BoxFit.cover,
                      // §imgThrash — était 360 en dur, pour une vignette qui
                      // mesure ~120-145 px logiques : ~3× de RAM gaspillée par
                      // image, d'où la saturation du cache et le re-décodage
                      // permanent sur TV.
                      cacheWidth: decodeWidthFor(context, cardWidth),
                      fallback: (_) => _fallback(fallbackIcon, cs),
                      showFallbackWhileLoading: true,
                    ),
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
                    // Titre en surimpression bas (+ année pour films/séries →
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
                          if (widget.type != M3uContentType.tv &&
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
                    // §qualityTruth — Pastille « qualité réellement servie »,
                    // en haut à droite. Muette tant que le contenu n'a jamais
                    // été lu. Vaut aussi pour les chaînes TV : une chaîne
                    // annoncée FHD qui sert du 720p se voit ici.
                    Positioned(
                      top: 6,
                      right: 6,
                      child: MeasuredQualityBadge(versions: widget.versions),
                    ),
                    // §menuHint — Le menu d'appui long est le raccourci
                    // principal de l'app : Lire, Reprendre, Oublier la
                    // reprise, Télécharger et Favoris n'existent QUE là. Rien
                    // ne l'annonçait — ni « ⋯ », ni coin corné, ni un mot dans
                    // l'accueil guidé (§audit0903 n° 17).
                    //
                    // ⚠️ **Non focusable, volontairement** : un focusable
                    // imbriqué dans une `FocusableCard` n'est candidat dans
                    // AUCUNE direction depuis dpad 3.0 (§dpadChildFocus) — il
                    // serait donc décoratif à la télécommande. D'où l'affichage
                    // au tactile seul, là où il est réellement utilisable ; sur
                    // téléviseur, l'appui long sur OK reste la voie d'accès.
                    if (!PlatformTv.isTv)
                      Positioned(
                        top: 0,
                        left: 0,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _onLongPress,
                          child: const SizedBox(
                            width: 40,
                            height: 40,
                            child: Center(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Color(0xB3000000),
                                  shape: BoxShape.circle,
                                ),
                                child: Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(Icons.more_horiz,
                                      size: 16, color: Colors.white),
                                ),
                              ),
                            ),
                          ),
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

