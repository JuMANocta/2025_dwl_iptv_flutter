part of 'home_page.dart';

// ─── Vue résultats de recherche ──────────────────────────────────────────────

class _SearchView extends StatelessWidget {
  /// Texte saisi (déjà debouncé par le parent).
  final String query;

  /// Toutes les entrées splittées par type — réutilisées pour le filtrage.
  final Map<M3uContentType, List<M3uEntry>> byType;
  /// §1i — Appelé quand l'utilisateur tape sur une suggestion d'historique.
  /// Le parent met à jour le contrôleur de recherche avec la valeur choisie.
  final ValueChanged<String>? onSelectSuggestion;

  const _SearchView({
    required this.query,
    required this.byType,
    this.onSelectSuggestion,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (query.trim().isEmpty) {
      return _SearchEmptyState(
        cs: cs,
        onSelectSuggestion: onSelectSuggestion,
      );
    }

    final q = query.trim().toLowerCase();
    final filmsHits  = _filterAndGroup(byType[M3uContentType.movie]!,  q, M3uContentType.movie);
    final seriesHits = _filterAndGroup(byType[M3uContentType.series]!, q, M3uContentType.series);
    final tvHits     = _filterAndGroup(byType[M3uContentType.tv]!,     q, M3uContentType.tv);

    final totalGroups = filmsHits.length + seriesHits.length + tvHits.length;

    // §personSearch — La rangée Personnes se gère seule (async TMDB) et se
    // masque si elle n'a rien. On la monte TOUJOURS quand une requête est en
    // cours : sinon, chercher un réalisateur absent de la playlist afficherait
    // « Aucun résultat » alors que TMDB a bien trouvé quelqu'un.
    final persons = _PersonSection(query: query);

    final sections = <Widget>[persons];
    if (filmsHits.isNotEmpty) {
      sections.add(_ResultSection(
        title: 'Films',
        icon: Icons.movie_outlined,
        groups: filmsHits,
        type: M3uContentType.movie,
      ));
    }
    if (seriesHits.isNotEmpty) {
      sections.add(_ResultSection(
        title: 'Séries',
        icon: Icons.tv_outlined,
        groups: seriesHits,
        type: M3uContentType.series,
      ));
    }
    if (tvHits.isNotEmpty) {
      sections.add(_ResultSection(
        title: 'Chaînes',
        icon: Icons.live_tv_outlined,
        groups: tvHits,
        type: M3uContentType.tv,
      ));
    }

    if (totalGroups == 0) {
      // §12-b — Empty state unifié. §personSearch : placé APRÈS la rangée
      // Personnes (qui peut, elle, avoir trouvé quelqu'un) et centré sur la
      // hauteur restante plutôt que sur tout l'écran.
      sections.add(Padding(
        padding: const EdgeInsets.only(top: 32),
        child: EmptyState(
          icon: Icons.search_off,
          title: 'Aucun titre trouvé',
          subtitle:
              'Rien dans vos listes pour "$query". Essaie un autre mot-clé ou '
              'vérifie l\'orthographe.',
        ),
      ));
    }

    // §searchGap — Top à 0 : le champ de recherche est posé DANS la Column de
    // `searchBody` (home_page.dart), donc cette liste commence déjà sous lui.
    // L'ancien `padding.top + 76` datait de l'époque où le champ flottait par
    // -dessus en AppBar : la hauteur était comptée deux fois, d'où le grand
    // vide entre l'input et le premier résultat. Le seul espace restant vient
    // du `top: 4` de `_SearchSectionHeader`.
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
      children: sections,
    );
  }

  /// Filtre par texte + regroupe par titre (= toutes variantes d'un même film/série/chaîne).
  /// Limite : 30 groupes par type pour éviter les listes interminables.
  List<List<M3uEntry>> _filterAndGroup(
    List<M3uEntry> entries,
    String q,
    M3uContentType type,
  ) {
    bool match(M3uEntry e) =>
        e.displayName.toLowerCase().contains(q) ||
        e.rawTitle.toLowerCase().contains(q);

    // §23 — contentGroupKey est insensible à la casse (fusion cross-listes).
    String key(M3uEntry e) =>
        type == M3uContentType.tv ? tvGroupKey(e.displayName) : contentGroupKey(e);

    final byGroup = <String, List<M3uEntry>>{};
    for (final e in entries) {
      if (!match(e)) continue;
      byGroup.putIfAbsent(key(e), () => []).add(e);
    }

    // §URGENT — dédup qualité dans les groupes TV (cohérent avec _TypePage)
    if (type == M3uContentType.tv) {
      for (final k in byGroup.keys.toList()) {
        byGroup[k] = dedupeTvVersions(byGroup[k]!);
      }
    }

    // §homonymYear — FILMS et SÉRIES : même split par année que la home.
    final groups = type != M3uContentType.tv
        ? _TypePageState._splitGroupsByYear(byGroup.values)
        : byGroup.values.toList();
    if (groups.length > 30) groups.length = 30;
    return groups;
  }
}

/// §personSearch — Rangée « Personnes » (acteurs / réalisateurs) en tête des
/// résultats, alimentée par TMDB.
///
/// **Seul bloc ASYNC de la recherche** (le reste filtre la playlist en
/// mémoire, de façon synchrone) → widget dédié pour ne pas rendre tout
/// `_SearchView` stateful. La requête part sur changement de `query` (déjà
/// debouncée à 220 ms par `_HomePageState`), et un **token de requête** ignore
/// les réponses arrivées dans le désordre.
///
/// Se retire complètement (`SizedBox.shrink`) sans clé TMDB ou sans résultat :
/// l'app doit rester pleinement utilisable sans TMDB.
class _PersonSection extends StatefulWidget {
  final String query;
  const _PersonSection({required this.query});

  @override
  State<_PersonSection> createState() => _PersonSectionState();
}

class _PersonSectionState extends State<_PersonSection> {
  List<PersonHit> _hits = const [];
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void didUpdateWidget(covariant _PersonSection old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _search();
  }

  Future<void> _search() async {
    final token = ++_requestId;
    final q = widget.query.trim();
    if (q.length < 2) {
      if (_hits.isNotEmpty && mounted) setState(() => _hits = const []);
      return;
    }
    if (!await TmdbApiService.hasApiKey()) return;
    final res = await TmdbService.instance.searchPersons(q);
    // Réponse obsolète (l'utilisateur a continué à taper) → on jette.
    if (!mounted || token != _requestId) return;
    setState(() => _hits = res);
  }

  @override
  Widget build(BuildContext context) {
    if (_hits.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SearchSectionHeader(
            title: 'Personnes',
            icon: Icons.person_outline,
            count: _hits.length,
          ),
          SizedBox(
            // photo ronde 72 + nom (2 lignes) + métier + marge textScaler TV.
            height: 148,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _hits.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _PersonCard(hit: _hits[i]),
            ),
          ),
        ],
      ),
    );
  }
}

/// §personSearch — Vignette de personne : photo RONDE (code visuel qui la
/// distingue immédiatement des affiches rectangulaires) + nom + métier.
class _PersonCard extends StatelessWidget {
  final PersonHit hit;
  const _PersonCard({required this.hit});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final photo = TmdbService.getPosterUrl(hit.profilePath, size: 'w185');
    final role = hit.roleLabel;

    return FocusableCard(
      scaleOnFocus: false,
      anchorRowStart: true, // §rowAnchorDetails
      borderRadius: BorderRadius.circular(40),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ActorDetailsPage(personId: hit.id)),
      ),
      child: SizedBox(
        width: 84,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipOval(
              child: SizedBox(
                width: 72,
                height: 72,
                child: AetherImage(
                  url: photo,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  cacheWidth: 160,
                  alignment: Alignment.topCenter,
                  fallback: (_) => Container(
                    color: cs.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: Icon(Icons.person,
                        size: 32, color: cs.onSurfaceVariant),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hit.name,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (role != null)
              Text(
                role,
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}

/// §personSearch — En-tête de section de résultats (barre gradient + icône +
/// titre + compteur), extrait de `_ResultSection` pour être partagé avec la
/// rangée « Personnes » → zéro divergence visuelle entre les sections.
class _SearchSectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final int count;

  const _SearchSectionHeader({
    required this.title,
    required this.icon,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              gradient: kAetherGradient,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Icon(icon, size: 18, color: kAccentPrimary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 17,
                color: cs.onSurface,
                letterSpacing: 0.3,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<List<M3uEntry>> groups;
  final M3uContentType type;

  const _ResultSection({
    required this.title,
    required this.icon,
    required this.groups,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // §personSearch — en-tête factorisé (partagé avec _PersonSection).
          _SearchSectionHeader(title: title, icon: icon, count: groups.length),
          // §tvZoom — Largeur de vignette + hauteur pilotées par la largeur
          // réelle (poster 2:3 ou logo carré pour les chaînes).
          LayoutBuilder(
            builder: (ctx, constraints) {
              final channel = type == M3uContentType.tv;
              final cardW =
                  _responsiveTileWidth(constraints.maxWidth, channel: channel);
              return SizedBox(
                height: (channel ? cardW : cardW * 1.5) + 20,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: groups.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (ctx, i) => _HomeCard(
                    versions: groups[i],
                    type: type,
                    width: cardW,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Physics : swipe gauche/droite plus court (-20%) ─────────────────────────

/// `PageScrollPhysics` plus sensible : amplifie la vélocité au moment du release
/// → un **swipe court et rapide** suffit à changer de page (plus besoin de
/// traverser tout l'écran). Le seuil de distance (~50 %) reste celui de Flutter
/// pour les drags lents ; c'est le flick qu'on rend sensible.
///
/// `_kPageFlickBoost` ×1.8 (au lieu de ×1.15) : compromis sensibilité / pas de
/// secousse. Un seul chiffre à ajuster (monter = plus sensible).
class _FastPageScrollPhysics extends PageScrollPhysics {
  const _FastPageScrollPhysics({super.parent});

  // §pageSmooth — Seuil de bascule ABAISSÉ : un glissement d'environ 1/3 de
  // l'écran (au lieu des 50 % par défaut) suffit à passer à la page suivante.
  // On décide la page cible selon le SENS du geste (signe de la vélocité au
  // relâché) → fini le "retour à la page d'origine" quand on relâche vers la
  // moitié. Ressort par défaut conservé (snap net, pas le ressort mou précédent).
  static const double _kCommitBias = 0.18; // 0.5 - 0.18 ≈ bascule dès ~32 %

  @override
  _FastPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _FastPageScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    final tol = toleranceFor(position);
    final vp = position.viewportDimension;
    if (vp <= 0) return super.createBallisticSimulation(position, velocity);
    final page = position.pixels / vp;

    double targetPage;
    if (velocity.abs() < tol.velocity) {
      // Relâché quasi immobile → arrondi standard (nearest, seuil 0.5).
      targetPage = page.roundToDouble();
    } else if (velocity > 0) {
      // Geste vers la page suivante → bascule dès ~32 % de glissement.
      targetPage = (page + _kCommitBias).roundToDouble();
    } else {
      // Geste vers la page précédente.
      targetPage = (page - _kCommitBias).roundToDouble();
    }

    final target = (targetPage * vp)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < tol.distance) return null;
    return ScrollSpringSimulation(spring, position.pixels, target, velocity,
        tolerance: tol);
  }
}


// ─── §1i État vide de la recherche : suggestions d historique ────────────────

class _SearchEmptyState extends StatelessWidget {
  final ColorScheme cs;
  final ValueChanged<String>? onSelectSuggestion;

  const _SearchEmptyState({required this.cs, this.onSelectSuggestion});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: SearchHistoryService.version,
      builder: (_, __, ___) {
        final history = SearchHistoryService.all;
        return SingleChildScrollView(
          // §searchGap — Même vestige que dans `_SearchView` (ex-`+ 80`) : les
          // suggestions d'historique étaient poussées loin sous le champ.
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (history.isEmpty) ...[
                Center(
                  child: Column(
                    children: [
                      Icon(Icons.search,
                          size: 56,
                          color: cs.onSurfaceVariant.withAlpha(120)),
                      const SizedBox(height: 12),
                      Text(
                        "Tapez pour chercher dans votre playlist",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Films · Séries · Chaînes",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: cs.onSurfaceVariant.withAlpha(150),
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Row(
                  children: [
                    Icon(Icons.history, size: 18, color: kAccentSecondary),
                    const SizedBox(width: 8),
                    Text(
                      "Recherches récentes",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => SearchHistoryService.clear(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        "Effacer",
                        style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant.withAlpha(180)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: history
                      .map((q) => _HistoryChip(
                            query: q,
                            cs: cs,
                            onTap: () => onSelectSuggestion?.call(q),
                            onDismiss: () => SearchHistoryService.remove(q),
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _HistoryChip extends StatelessWidget {
  final String query;
  final ColorScheme cs;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _HistoryChip({
    required this.query,
    required this.cs,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
          border:
              Border.all(color: kAccentSecondary.withAlpha(60), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history,
                size: 14, color: cs.onSurfaceVariant.withAlpha(180)),
            const SizedBox(width: 6),
            Text(
              query,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onDismiss,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close,
                    size: 14, color: cs.onSurfaceVariant.withAlpha(160)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── §1i Tuile "Reprendre la chaîne" en tête de la page Chaînes ──────────────

class _LastWatchedTvTile extends StatelessWidget {
  /// Entrées TV disponibles dans la playlist actuelle — utilisé pour vérifier
  /// que la dernière chaîne regardée existe toujours avant d affiché la tuile.
  final List<M3uEntry> entries;
  const _LastWatchedTvTile({required this.entries});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: LastWatchedChannelService.version,
      builder: (_, __, ___) {
        final last = LastWatchedChannelService.current;
        if (last == null) return const SizedBox.shrink();

        // Cherche l entrée actuelle correspondante dans la playlist (pour
        // récupérer logo / displayName à jour si renommé côté provider).
        final match = entries.firstWhere(
          (e) => e.url == last.url,
          orElse: () => M3uEntry(
            url: last.url,
            type: M3uContentType.tv,
            tvgId: last.tvgId,
            logoUrl: last.logoUrl,
            title: TitleMetadata(rawTitle: last.title, baseTitle: last.title),
            accountId: "",
          ),
        );

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => showTvActionSheet(context, [match]),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    kAccentSecondary.withAlpha(40),
                    kAccentPrimary.withAlpha(20),
                  ],
                ),
                border: Border.all(
                    color: kAccentSecondary.withAlpha(120), width: 1),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 48,
                      height: 48,
                      color: Colors.black26,
                      // §imgDiskCache — cache disque partagé (AetherImage).
                      child: AetherImage(
                        url: last.logoUrl,
                        fit: BoxFit.contain,
                        cacheWidth: 144,
                        fallback: (_) =>
                            const Icon(Icons.live_tv, color: Colors.white54),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "REPRENDRE LA CHAÎNE",
                          style: TextStyle(
                            color: kAccentSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          last.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: kAetherGradient,
                      boxShadow: [
                        BoxShadow(
                            color: kAccentPrimary.withAlpha(150),
                            blurRadius: 10),
                      ],
                    ),
                    child: const Icon(Icons.play_arrow,
                        color: Colors.black, size: 22),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
