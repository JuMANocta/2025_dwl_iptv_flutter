part of 'home_page.dart';

// ─── Section : une catégorie ─────────────────────────────────────────────────

class _CategoryRow extends StatelessWidget {
  final String category;

  /// Groupes effectivement affichés dans le carrousel/grille (max 25).
  final List<List<M3uEntry>> groups;

  /// Liste complète, transmise à [CategoryListPage] quand l'utilisateur
  /// tape sur "Voir tout".
  final List<List<M3uEntry>> allGroups;
  final int totalCount;
  final bool hasMore;
  final M3uContentType type;
  final IconData icon;

  const _CategoryRow({
    super.key,
    required this.category,
    required this.groups,
    required this.allGroups,
    required this.totalCount,
    required this.hasMore,
    required this.type,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header : barre verticale gradient + icône + titre + count
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
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
                    category,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                      color: cs.onSurface,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                // Bouton "Voir tout" si plus de 25 items, sinon juste le compteur.
                // §tvRails — Sur TV, ce bouton d'en-tête est RETIRÉ du focus :
                // il formait une "rangée" intermédiaire focusable entre deux
                // carrousels → la navigation ↑/↓ s'arrêtait dessus (on
                // "sélectionnait le compteur"). La tuile "Voir tout" en fin de
                // carrousel (`_SeeAllTile`, atteignable en allant à droite) offre
                // déjà la même action → aucune perte de fonctionnalité.
                if (hasMore)
                  ExcludeFocus(
                    excluding: PlatformTv.isTv,
                    child: TextButton.icon(
                      onPressed: () => _openCategoryListPage(context),
                      icon: Text('$totalCount',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: kAccentPrimary)),
                      label: Icon(Icons.chevron_right,
                          size: 18, color: kAccentPrimary),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 0),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  )
                else
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$totalCount',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Films / Séries → carrousel horizontal (poster 2:3, narration visuelle)
          // Chaînes        → grille (logo carré, balayage rapide façon télécommande)
          if (type == M3uContentType.tv)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: LayoutBuilder(
                builder: (ctx, constraints) {
                  // §tvZoom — Colonnes pilotées par la largeur réelle
                  // (3 sur smartphone, 6-8 sur TV/large) → plus de chaînes
                  // visibles au lieu de gros logos zoomés.
                  const spacing = 8.0;
                  final cols =
                      _responsiveColumns(constraints.maxWidth, channel: true);
                  final tileWidth =
                      (constraints.maxWidth - spacing * (cols - 1)) / cols;
                  final tiles = <Widget>[
                    ...groups.asMap().entries.map((e) => _HomeCard(
                          // §tvExitPage — Clé de CONTENU (cf. _CategoryRow).
                          key: ValueKey(FavoritesService.keyFor(e.value.first)),
                          versions: e.value,
                          type: type,
                          width: tileWidth,
                          // §dpadRowEntry — 1re tuile = point d'entrée de la grille.
                          isEntry: e.key == 0,
                        )),
                    if (hasMore)
                      _SeeAllTile(
                        type: type,
                        remaining: totalCount - groups.length,
                        width: tileWidth,
                        onTap: () => _openCategoryListPage(context),
                      ),
                  ];
                  return Wrap(
                    alignment: WrapAlignment.center,
                    spacing: spacing,
                    runSpacing: spacing,
                    children: tiles,
                  );
                },
              ),
            )
          else
            // §tvZoom — Largeur de poster + hauteur du carrousel pilotées par
            // la largeur réelle de l'écran (poster 2:3). Smartphone ≈ 130 px /
            // 215 ; TV large ≈ 140 px mais bien plus de posters visibles.
            LayoutBuilder(
              builder: (ctx, constraints) {
                final cardW =
                    _responsiveTileWidth(constraints.maxWidth, channel: false);
                // §tvFocus — Sur TV, le contour de focus (scale 1.05 + glow
                // ~17px + bordure) déborde au-dessus/en-dessous de la vignette.
                // On réserve une marge verticale (48) ET on peint dans cette
                // marge via le padding du ListView ; `Clip.none` évite que le
                // ListView rogne le contour aux bords de la rangée.
                final vSlack = PlatformTv.isTv ? 48.0 : 20.0;
                // §carouselRewindTouch — RETIRÉ le 2026-08-29 (régression
                // critique, cf. §pageViewRewind). `Scrollable.maybeOf(n.context)`
                // ne rendait PAS le carrousel émetteur mais un scrollable
                // ancêtre — dont la `PageView` des onglets, qui est elle aussi
                // horizontale. Elle devenait la « rangée active », et le
                // rembobinage la ramenait à sa page 0 : l'accueil sautait sur
                // « Séries » en boucle et devenait inutilisable.
                //
                // Le rembobinage reste actif au D-pad (§carouselScrollDir), où
                // il est correct. Ne PAS remettre de déclencheur tactile sans
                // vérifier que le scrollable transmis est bien le carrousel.
                return DpadRegion(
                  // §carouselScrollDir — Entrée par la GAUCHE, décision
                  // INVERSÉE par rapport à §dpadNav.
                  //
                  // La rangée avait une mémoire de colonne persistante
                  // (`memoryKey` + `DpadEnterBehavior.restore` par défaut) :
                  // ↑/↓ y ramenait la carte quittée, façon Netflix. En
                  // pratique, remonter la page rouvrait donc les carrousels
                  // loin à droite, sur les derniers titres, au lieu de leur
                  // début — c'est le bug §carouselScrollDir.
                  //
                  // ⚠️ `isEntry: i == 0` (plus bas) était déjà posé mais
                  // n'était JAMAIS consulté : dans `resolveEnter`, le mode
                  // `restore` court-circuite l'item d'entrée tant qu'il a une
                  // mémoire — et `memoryKey` la faisait justement survivre à
                  // tous les rebuilds. Passer en `entry` est ce qui lui rend
                  // la main ; retirer la clé évite d'entretenir une mémoire
                  // que plus personne ne lit.
                  //
                  // ← au bord part toujours vers le rail (edge: leave défaut).
                  enter: DpadEnterBehavior.entry,
                  child: SizedBox(
                    height: cardW * 1.5 + vSlack,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: PlatformTv.isTv ? Clip.none : Clip.hardEdge,
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: PlatformTv.isTv ? 24 : 0,
                      ),
                      // §focusScroll — Cache plus large que la valeur par défaut
                      // (250 px) : sur TV, la dernière tuile "Voir tout" (en bout
                      // de carrousel) n'était pas encore buildée quand le focus
                      // arrivait → focus directionnel sautait dessus une fois,
                      // sans effet. ~2 cartes en avance suffit pour la rendre
                      // toujours dans l'arbre de focus.
                      // ignore: deprecated_member_use
                      cacheExtent: 600,
                      itemCount: groups.length + (hasMore ? 1 : 0),
                      // §ergo — écartement un peu plus large entre les cartes
                      // (10 → 16) pour aérer le carrousel sans toucher au style.
                      separatorBuilder: (_, __) => const SizedBox(width: 16),
                      itemBuilder: (ctx, i) {
                        if (hasMore && i == groups.length) {
                          return _SeeAllTile(
                            type: type,
                            remaining: totalCount - groups.length,
                            width: cardW,
                            onTap: () => _openCategoryListPage(context),
                          );
                        }
                        return _HomeCard(
                          // §tvExitPage — Clé de CONTENU (cf. _CategoryRow).
                          key: ValueKey(FavoritesService.keyFor(groups[i].first)),
                          versions: groups[i],
                          type: type,
                          width: cardW,
                          // §dpadRowEntry — 1re carte = point d'entrée de la
                          // rangée (↓ se cale à gauche, pas à droite).
                          isEntry: i == 0,
                        );
                      },
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  void _openCategoryListPage(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CategoryListPage(
        category: category,
        groups: allGroups,
        type: type,
        icon: icon,
      ),
    ));
  }
}

// ─── Tile "Voir tout" — 26ème vignette ouvrant la page complète ──────────────

class _SeeAllTile extends StatelessWidget {
  final M3uContentType type;
  final int remaining;
  final double width;
  final VoidCallback onTap;

  const _SeeAllTile({
    required this.type,
    required this.remaining,
    required this.width,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isTv = type == M3uContentType.tv;
    final aspectRatio = isTv ? 1.0 : 2 / 3;

    // §tvErgo — FocusableCard (et non InkWell nu) pour afficher le glow Matrix
    // au focus D-pad, cohérent avec les _HomeCard voisines du carrousel/grille.
    // Tuile de même taille que les cartes → le scale(1.05) par défaut convient.
    // §rowAnchor — même ancrage début-de-rangée que les _HomeCard voisines.
    return FocusableCard(
      onTap: onTap,
      anchorRowStart: true,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: width,
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  kAccentPrimary.withAlpha(40),
                  kAccentSecondary.withAlpha(40),
                ],
              ),
              border:
                  Border.all(color: kAccentPrimary.withAlpha(120), width: 1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: kAetherGradient,
                    boxShadow: [
                      BoxShadow(
                        color: kAccentPrimary.withAlpha(150),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.arrow_forward,
                      color: Colors.black, size: 22),
                ),
                const SizedBox(height: 10),
                Text(
                  'Voir tout',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '+$remaining',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
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

// ─── Page complète d'une catégorie (accessible via "Voir tout") ──────────────

class CategoryListPage extends StatefulWidget {
  final String category;
  final List<List<M3uEntry>> groups;
  final M3uContentType type;
  final IconData icon;

  const CategoryListPage({
    super.key,
    required this.category,
    required this.groups,
    required this.type,
    required this.icon,
  });

  @override
  State<CategoryListPage> createState() => _CategoryListPageState();
}

class _CategoryListPageState extends State<CategoryListPage> with TvInitialFocus {
  // §quickwin — scroll-to-top sur les grosses catégories (2000+ items) :
  // remonter au D-pad sur TV/Fire Stick était pénible.
  final ScrollController _scrollController = ScrollController();
  bool _showScrollTop = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    // FAB visible après ~2 écrans de scroll.
    final show =
        _scrollController.hasClients && _scrollController.offset > 1200;
    if (show != _showScrollTop) setState(() => _showScrollTop = show);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isTv = widget.type == M3uContentType.tv;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: Row(
          children: [
            Icon(widget.icon, size: 20, color: kAccentPrimary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.category,
                style: const TextStyle(fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${widget.groups.length}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      extendBodyBehindAppBar: true,
      // §dpadAlign — La grille « Voir tout » n'avait pas de région propre : elle
      // naviguait dans le scope global, sans mémoire de colonne ni bord défini.
      floatingActionButton: _showScrollTop
          ? FloatingActionButton.small(
              backgroundColor: kAccentPrimary,
              foregroundColor: Colors.black,
              onPressed: () => _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOut,
              ),
              child: const Icon(Icons.keyboard_arrow_up),
            )
          : null,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: isDark ? null : cs.surface,
          gradient: isDark
              ? RadialGradient(
                  center: const Alignment(0, -1.2),
                  radius: 1.4,
                  colors: [
                    kAccentPrimary.withAlpha(28),
                    cs.surface,
                  ],
                )
              : null,
        ),
        child: SafeArea(
          child: DpadRegion(
            debugLabel: 'categoryGrid',
            memoryKey: 'category_${widget.type.name}_${widget.category}',
            child: LayoutBuilder(
            builder: (ctx, constraints) {
              const spacing = 10.0;
              // §tvZoom — Colonnes pilotées par la largeur réelle (3 sur
              // smartphone, 6-9 sur TV/large) au lieu de plafonner à 5 → la
              // page « Voir tout » n'affiche plus de vignettes géantes sur TV.
              final width = constraints.maxWidth - 24;
              final cols =
                  _responsiveColumns(constraints.maxWidth, channel: isTv);
              final tileWidth = (width - spacing * (cols - 1)) / cols;

              // §20 — Rendu lazy : GridView.builder ne construit que les
              // cellules visibles (+ cacheExtent), au lieu du Wrap qui
              // instanciait TOUTES les cartes au mount. Indispensable pour les
              // catégories à 2000+ items (freeze + OOM sur Fire Stick sinon).
              // La card est un poster pur (AspectRatio = imageAspectRatio) →
              // childAspectRatio identique pour des cellules à la bonne hauteur.
              final childAspectRatio = isTv ? 1.0 : 2 / 3;
              return GridView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                  childAspectRatio: childAspectRatio,
                ),
                itemCount: widget.groups.length,
                itemBuilder: (_, i) => _HomeCard(
                  versions: widget.groups[i],
                  type: widget.type,
                  width: tileWidth,
                  isEntry: i == 0,
                ),
              );
            },
            ),
          ),
        ),
      ),
    );
  }
}
