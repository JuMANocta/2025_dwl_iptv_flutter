import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/services/favorites_service.dart';
import 'package:aetherStream/data/services/parsed_playlist_service.dart';
import 'package:aetherStream/data/services/tmdb_api_service.dart';
import 'package:aetherStream/feature/downloads/logic/download_initiator.dart';
import 'package:aetherStream/feature/player/player_page.dart';
import 'package:aetherStream/feature/search/details_page.dart';
import 'package:aetherStream/feature/settings/settings_page.dart';
import 'package:aetherStream/feature/search/m3u_filter.dart';
import 'package:aetherStream/widgets/media_action_sheet.dart';
import 'package:aetherStream/widgets/media_chips.dart';

/// Page d'accueil — design streaming premium (§1b phases 2 + 3).
///
/// Layout :
///   AppBar              (compte actif + ⚙️, transparente posée sur le fond)
///   _AnimatedTabIndicator (Séries · FILMS · Chaînes — underline animé)
///   PageView de _TypePage
///     ↳ _HeroBanner     (carrousel d'items mis en avant — auto-rotation 6s)
///     ↳ _CategoryRow    (sections par catégorie M3U)
///
/// Design choices :
///   - Fond : gradient sombre subtil avec halo accent en haut
///   - Cartes : poster + overlay gradient bas + titre lisible en surimpression
///   - Headers section : barre verticale gradient 3px + titre 18 gras
///   - Hero : 16/9, auto-rotation, indicateur en dots, bouton Lire glow
class HomePage extends StatefulWidget {
  /// Données pré-chargées par `_LaunchDecider`.
  final ({String path, String accountId, String accountName}) initialData;

  /// Quand `true`, la page bascule en mode recherche in-place :
  /// barre de saisie en tête, résultats en carrousels par type.
  /// Contrôlé par `MainNavigation` via le bouton 🔍 de la `NavigationBar`.
  final bool searchMode;

  /// Callback pour sortir du mode recherche (invoqué quand l'utilisateur
  /// clique sur le bouton X dans la barre de recherche).
  final VoidCallback? onExitSearch;

  const HomePage({
    super.key,
    required this.initialData,
    this.searchMode = false,
    this.onExitSearch,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const int _initialPageIndex = 1; // Films par défaut

  late final PageController _pageController;
  int _currentIndex = _initialPageIndex;
  bool _loading = true;

  // ── État du mode recherche ─────────────────────────────────────────────
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _searchQuery = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _initialPageIndex);
    _searchCtrl.addListener(_onSearchTextChanged);
    _ensureLoaded();
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Activation du mode recherche → focus immédiat la barre de saisie
    if (widget.searchMode && !oldWidget.searchMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    }
    // Sortie du mode recherche → reset du contenu
    if (!widget.searchMode && oldWidget.searchMode) {
      _searchCtrl.clear();
      _searchFocus.unfocus();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onSearchTextChanged() {
    final txt = _searchCtrl.text;
    if (_searchQuery == txt) return;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 220), () {
      if (mounted) setState(() => _searchQuery = txt);
    });
  }

  Future<void> _ensureLoaded() async {
    if (ParsedPlaylistService.getAccount(widget.initialData.accountId) == null) {
      await ParsedPlaylistService.loadActive(
        widget.initialData.accountId,
        widget.initialData.accountName,
        widget.initialData.path,
      );
    }
    if (mounted) setState(() => _loading = false);
  }

  void _goToPage(int i) {
    _pageController.animateToPage(
      i,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: widget.searchMode
            ? _buildSearchField(cs)
            : Text(
                widget.initialData.accountName.isEmpty
                    ? 'AetherStream'
                    : widget.initialData.accountName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
        actions: widget.searchMode
            ? [
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Quitter la recherche',
                  onPressed: () => widget.onExitSearch?.call(),
                ),
                const SizedBox(width: 4),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Paramètres',
                  onPressed: _openSettings,
                ),
                const SizedBox(width: 4),
              ],
      ),
      body: Container(
        decoration: BoxDecoration(
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
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListenableBuilder(
                listenable: Listenable.merge([
                  ParsedPlaylistService.version,
                  FavoritesService.version,
                ]),
                builder: (context, _) {
                  final entries = ParsedPlaylistService
                      .entriesWithPriority(widget.initialData.accountId);
                  final byType = _splitByType(entries);

                  if (widget.searchMode) {
                    return _SearchView(
                      query: _searchQuery,
                      byType: byType,
                    );
                  }

                  return Column(
                    children: [
                      _AnimatedTabIndicator(
                        controller: _pageController,
                        currentIndex: _currentIndex,
                        counts: [
                          byType[M3uContentType.series]!.length,
                          byType[M3uContentType.movie]!.length,
                          byType[M3uContentType.tv]!.length,
                        ],
                        onTap: _goToPage,
                      ),
                      Expanded(
                        child: PageView(
                          controller: _pageController,
                          physics: const _FastPageScrollPhysics(),
                          onPageChanged: (i) =>
                              setState(() => _currentIndex = i),
                          children: [
                            _TypePage(
                              type: M3uContentType.series,
                              entries: byType[M3uContentType.series]!,
                            ),
                            _TypePage(
                              type: M3uContentType.movie,
                              entries: byType[M3uContentType.movie]!,
                            ),
                            _TypePage(
                              type: M3uContentType.tv,
                              entries: byType[M3uContentType.tv]!,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  /// Champ de saisie placé dans le `title` de l'AppBar quand searchMode est actif.
  Widget _buildSearchField(ColorScheme cs) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: kAccentSecondary.withAlpha(_searchFocus.hasFocus ? 200 : 60),
          width: _searchFocus.hasFocus ? 1.5 : 1,
        ),
        boxShadow: _searchFocus.hasFocus
            ? [BoxShadow(color: kAccentSecondary.withAlpha(50), blurRadius: 12, spreadRadius: 1)]
            : null,
      ),
      child: TextField(
        controller: _searchCtrl,
        focusNode: _searchFocus,
        textInputAction: TextInputAction.search,
        style: TextStyle(color: cs.onSurface, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Rechercher dans la playlist…',
          hintStyle: TextStyle(color: cs.onSurfaceVariant.withAlpha(140)),
          prefixIcon: Icon(Icons.search, color: kAccentSecondary, size: 22),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  splashRadius: 18,
                  onPressed: () => _searchCtrl.clear(),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  Map<M3uContentType, List<M3uEntry>> _splitByType(List<M3uEntry> all) {
    final films = <M3uEntry>[];
    final series = <M3uEntry>[];
    final tv = <M3uEntry>[];
    for (final e in all) {
      switch (e.type) {
        case M3uContentType.movie:
          films.add(e);
          break;
        case M3uContentType.series:
          series.add(e);
          break;
        case M3uContentType.tv:
          if (!isHiddenTvVariant(e.title.rawTitle)) tv.add(e);
          break;
      }
    }
    return {
      M3uContentType.movie: films,
      M3uContentType.series: series,
      M3uContentType.tv: tv,
    };
  }
}

// ─── Indicateur d'onglets animé ──────────────────────────────────────────────

class _AnimatedTabIndicator extends StatefulWidget {
  final PageController controller;
  final int currentIndex;
  final List<int> counts; // [series, films, tv]
  final ValueChanged<int> onTap;

  const _AnimatedTabIndicator({
    required this.controller,
    required this.currentIndex,
    required this.counts,
    required this.onTap,
  });

  @override
  State<_AnimatedTabIndicator> createState() => _AnimatedTabIndicatorState();
}

class _AnimatedTabIndicatorState extends State<_AnimatedTabIndicator> {
  static const _labels = ['Séries', 'Films', 'Chaînes'];

  double _page = 1.0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final p = widget.controller.page;
    if (p != null && p != _page) {
      setState(() => _page = p);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mediaQuery = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(16, mediaQuery.padding.top + 30, 16, 0),
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final tabWidth = constraints.maxWidth / 3;

          return SizedBox(
            height: 26,
            child: Stack(
              children: [
                Row(
                  children: List.generate(3, (i) {
                    final active = i == widget.currentIndex;
                    final isEmpty = widget.counts[i] == 0;
                    final color = isEmpty
                        ? cs.onSurface.withAlpha(60)
                        : active
                            ? cs.onSurface
                            : cs.onSurfaceVariant;
                    return Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: isEmpty ? null : () => widget.onTap(i),
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          style: TextStyle(
                            fontSize: active ? 20 : 14,
                            fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                            letterSpacing: active ? 0.5 : 0.2,
                            color: color,
                          ),
                          child: Center(child: Text(_labels[i])),
                        ),
                      ),
                    );
                  }),
                ),
                // Underline animé
                Positioned(
                  bottom: 0,
                  left: _page * tabWidth + tabWidth * 0.3,
                  child: Container(
                    width: tabWidth * 0.4,
                    height: 3,
                    decoration: BoxDecoration(
                      gradient: kAetherGradient,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [
                        BoxShadow(
                          color: kAccentPrimary.withAlpha(140),
                          blurRadius: 8,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Page d'un type ──────────────────────────────────────────────────────────

class _TypePage extends StatefulWidget {
  final M3uContentType type;
  final List<M3uEntry> entries;

  const _TypePage({required this.type, required this.entries});

  @override
  State<_TypePage> createState() => _TypePageState();

  /// Priorité d'affichage des catégories : "fraîches" en tête, puis alpha,
  /// puis "Autres" tout en bas.
  ///
  /// Pour les chaînes TV : la catégorie virtuelle "France" passe avant tout
  /// pour respecter le réflexe utilisateur (chaînes FR en premier dans leur
  /// ordre M3U d'origine — TF1, France 2, M6, ARTE…).
  static int _categoryPriority(String category) {
    switch (category) {
      case 'Favoris':       return -2;  // ⭐ tout en haut
      case 'France':        return -1;
      case 'New':           return 0;
      case 'Coup de cœur':  return 1;
      case 'Sélection':     return 2;
      case 'Box Office':    return 3;
      case 'Oscar':         return 4;
      case 'Cultes':        return 5;
      case 'Autres':        return 1000;
      default:              return 100;
    }
  }

  /// Détecte une chaîne TV française pour la regrouper en tête de la page Chaînes.
  /// Critères (ordre de fiabilité) :
  ///   1. tvgId se terminant par `.fr` (TF1.fr, France2.fr, M6.fr, ARTE.fr…)
  ///   2. Préfixe titre `|FR|` (convention M3U courante)
  ///   3. groupTitle contenant "FRANCE" ou "|FR|"
  static bool _isFrenchChannel(M3uEntry e) {
    final tvgId = e.tvgId?.toLowerCase() ?? '';
    if (tvgId.endsWith('.fr')) return true;
    final raw = e.title.rawTitle;
    if (RegExp(r'^\s*\|\s*FR\s*\|', caseSensitive: false).hasMatch(raw)) return true;
    final group = (e.groupTitle ?? '').toUpperCase();
    if (group.contains('FRANCE') || group.contains('|FR|')) return true;
    return false;
  }

  static IconData categoryIcon(String cat) {
    switch (cat) {
      case 'Favoris':       return Icons.star;
      case 'France':        return Icons.flag_outlined;
      case 'New':           return Icons.local_fire_department;
      case 'Coup de cœur':  return Icons.favorite;
      case 'Sélection':     return Icons.star;
      case 'Box Office':    return Icons.trending_up;
      case 'Oscar':         return Icons.emoji_events;
      case 'Cultes':        return Icons.auto_awesome;
      case 'Action':        return Icons.bolt;
      case 'Comédie':       return Icons.theater_comedy;
      case 'Horreur':       return Icons.coronavirus;
      case 'Sci-Fi':        return Icons.rocket_launch;
      case 'Romance':       return Icons.favorite_border;
      case 'Animation':     return Icons.animation;
      case 'Manga':         return Icons.brush;
      case 'Documentaire':  return Icons.menu_book;
      case 'Sport':         return Icons.sports_soccer;
      case 'Jeunesse':      return Icons.child_care;
      case 'Disney+':       return Icons.castle;
      default:              return Icons.movie_creation_outlined;
    }
  }
}

class _TypePageState extends State<_TypePage> {
  /// Limite d'items affichés dans un carrousel/grille de catégorie sur la home.
  /// Au-delà, un tile "Voir tout" est ajouté qui ouvre [CategoryListPage].
  static const int _maxItemsPerCategory = 25;

  // ── Caches (memoization) ───────────────────────────────────────────────
  // Recalculés uniquement quand l'une des sources sous-jacentes change.
  Map<String, List<List<M3uEntry>>>? _cachedByCategory;
  List<String>? _cachedCategories;
  List<List<M3uEntry>>? _cachedFeatured;
  int _cachedKey = -1;

  /// Clé d'invalidation : combinaison de la longueur d'entrées + versions des
  /// services. Si elle change → on recompute. Sinon → réutilisation du cache.
  ///
  /// `entries.length` : suffit pour détecter un ajout/suppression de compte.
  /// `ParsedPlaylistService.version` : bump si playlist re-téléchargée.
  /// `FavoritesService.version` : bump si favori toggle (impacte la catégorie
  /// virtuelle "Favoris").
  int _computeCacheKey() {
    return widget.entries.length * 1000003 +
        ParsedPlaylistService.version.value * 1009 +
        FavoritesService.version.value;
  }

  void _ensureGrouping() {
    final key = _computeCacheKey();
    if (_cachedByCategory != null && _cachedKey == key) return;

    final byCategory = _groupByCategoryThenByTitle(widget.entries, widget.type);
    final categories = byCategory.keys.toList()
      ..sort((a, b) {
        final pa = _TypePage._categoryPriority(a);
        final pb = _TypePage._categoryPriority(b);
        if (pa != pb) return pa.compareTo(pb);
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

    // Items mis en avant pour le hero : on prend la première catégorie
    // prioritaire (Favoris exclu — c'est trop intime pour un hero), max 5.
    List<List<M3uEntry>> featured = const [];
    for (final cat in categories) {
      if (cat == 'Favoris') continue;
      if (_TypePage._categoryPriority(cat) < 100) {
        featured = byCategory[cat]!.take(5).toList();
        break;
      }
    }
    if (featured.isEmpty && categories.isNotEmpty) {
      final first = categories.firstWhere(
        (c) => c != 'Autres' && c != 'Favoris',
        orElse: () => categories.first,
      );
      featured = byCategory[first]!.take(5).toList();
    }

    _cachedByCategory = byCategory;
    _cachedCategories = categories;
    _cachedFeatured = featured;
    _cachedKey = key;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) return _buildEmpty(context);

    _ensureGrouping();
    final byCategory = _cachedByCategory!;
    final categories = _cachedCategories!;
    final featured = _cachedFeatured!;

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24, top: 0),
      itemCount: categories.length + (featured.isNotEmpty ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (featured.isNotEmpty && i == 0) {
          return _HeroBanner(featured: featured, type: widget.type);
        }
        final catIdx = featured.isNotEmpty ? i - 1 : i;
        final cat = categories[catIdx];
        final allGroups = byCategory[cat]!;
        final hasMore = allGroups.length > _maxItemsPerCategory;
        final visibleGroups = hasMore
            ? allGroups.take(_maxItemsPerCategory).toList()
            : allGroups;
        return _CategoryRow(
          category: cat,
          groups: visibleGroups,
          allGroups: allGroups,
          totalCount: allGroups.length,
          hasMore: hasMore,
          type: widget.type,
          icon: _TypePage.categoryIcon(cat),
        );
      },
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (icon, label) = switch (widget.type) {
      M3uContentType.movie  => (Icons.movie_outlined, 'Aucun film'),
      M3uContentType.series => (Icons.tv_outlined, 'Aucune série'),
      M3uContentType.tv     => (Icons.live_tv_outlined, 'Aucune chaîne'),
    };
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: cs.onSurfaceVariant.withAlpha(120)),
          const SizedBox(height: 12),
          Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Map<String, List<List<M3uEntry>>> _groupByCategoryThenByTitle(
    List<M3uEntry> entries,
    M3uContentType type,
  ) {
    String groupKey(M3uEntry e) =>
        type == M3uContentType.tv ? tvGroupKey(e.displayName) : e.displayName;

    final byGroup = <String, List<M3uEntry>>{};
    for (final e in entries) {
      byGroup.putIfAbsent(groupKey(e), () => []).add(e);
    }

    final byCategory = <String, List<List<M3uEntry>>>{};
    for (final group in byGroup.values) {
      // Cas spécial chaînes TV : les chaînes françaises remontent dans une
      // catégorie virtuelle "France" — l'ordre M3U est préservé naturellement
      // par l'ordre d'itération de `byGroup.values` (Map insertion order).
      if (type == M3uContentType.tv && _TypePage._isFrenchChannel(group.first)) {
        byCategory.putIfAbsent('France', () => []).add(group);
        continue;
      }
      final cat = group
              .firstWhere(
                (e) => e.category != null && e.category!.isNotEmpty,
                orElse: () => group.first,
              )
              .category ??
          'Autres';
      byCategory.putIfAbsent(cat, () => []).add(group);
    }

    // Tri : alpha pour les catégories de genre, ordre M3U (= "récents en haut",
    // ou "ordre logique du provider" pour les chaînes FR) pour les catégories
    // prioritaires.
    for (final entry in byCategory.entries) {
      if (_TypePage._categoryPriority(entry.key) >= 100 && entry.key != 'Autres') {
        entry.value.sort((a, b) => a.first.displayName
            .toLowerCase()
            .compareTo(b.first.displayName.toLowerCase()));
      }
    }

    // ⭐ Catégorie virtuelle "Favoris" — duplique les groupes que l'utilisateur
    // a marqué comme favoris pour ce type de contenu. Ils restent visibles
    // dans leur catégorie d'origine + apparaissent en tête de page.
    final favoriteGroups = <List<M3uEntry>>[];
    for (final group in byGroup.values) {
      if (FavoritesService.isEntryFavorite(group.first)) {
        favoriteGroups.add(group);
      }
    }
    if (favoriteGroups.isNotEmpty) {
      byCategory['Favoris'] = favoriteGroups;
    }

    return byCategory;
  }
}

// ─── Hero banner rotatif ─────────────────────────────────────────────────────

class _HeroBanner extends StatefulWidget {
  final List<List<M3uEntry>> featured;
  final M3uContentType type;

  const _HeroBanner({required this.featured, required this.type});

  @override
  State<_HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<_HeroBanner> {
  late final PageController _ctrl;
  Timer? _timer;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = PageController();
    _scheduleNext();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _scheduleNext() {
    _timer?.cancel();
    if (widget.featured.length <= 1) return;
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || !_ctrl.hasClients) return;
      final next = (_current + 1) % widget.featured.length;
      _ctrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });
  }

  Future<void> _openItem(BuildContext context, List<M3uEntry> versions) async {
    if (versions.isEmpty) return;
    final entry = versions.first;
    if (widget.type == M3uContentType.tv) {
      await showTvActionSheet(context, versions);
      return;
    }
    final hasTmdb = await TmdbApiService.hasApiKey();
    if (!context.mounted) return;
    if (hasTmdb) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DetailsPage(entry: entry, versions: versions),
      ));
    } else {
      await showMediaActionSheet(context, entry);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: _ctrl,
                onPageChanged: (i) => setState(() => _current = i),
                itemCount: widget.featured.length,
                itemBuilder: (ctx, i) {
                  final versions = widget.featured[i];
                  return _HeroSlide(
                    versions: versions,
                    type: widget.type,
                    onPlay: () => _openItem(ctx, versions),
                  );
                },
              ),
              // Indicateur dots en bas-droite
              if (widget.featured.length > 1)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: Row(
                    children: List.generate(widget.featured.length, (i) {
                      final active = i == _current;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 280),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: active ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: active
                              ? kAccentPrimary
                              : Colors.white.withAlpha(120),
                          borderRadius: BorderRadius.circular(3),
                          boxShadow: active
                              ? [BoxShadow(color: kAccentPrimary.withAlpha(180), blurRadius: 6)]
                              : null,
                        ),
                      );
                    }),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroSlide extends StatelessWidget {
  final List<M3uEntry> versions;
  final M3uContentType type;
  final VoidCallback onPlay;

  const _HeroSlide({
    required this.versions,
    required this.type,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final entry = versions.first;
    final logoUrl = versions
        .map((e) => e.logoUrl)
        .firstWhere((l) => l != null && l.isNotEmpty, orElse: () => null);

    final fallbackIcon = switch (type) {
      M3uContentType.movie  => Icons.movie_outlined,
      M3uContentType.series => Icons.tv_outlined,
      M3uContentType.tv     => Icons.live_tv_outlined,
    };

    return Stack(
      fit: StackFit.expand,
      children: [
        // Image de fond floutée + agrandie (utilise le poster comme backdrop)
        if (logoUrl != null && logoUrl.isNotEmpty)
          Image.network(
            logoUrl,
            fit: BoxFit.cover,
            color: Colors.black.withAlpha(80),
            colorBlendMode: BlendMode.darken,
            errorBuilder: (_, __, ___) => Container(color: kAccentPrimary.withAlpha(20)),
          )
        else
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [kAccentPrimary.withAlpha(35), kAccentSecondary.withAlpha(35)],
              ),
            ),
          ),
        // Gradient sombre pour la lisibilité
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                Colors.black.withAlpha(40),
                Colors.black.withAlpha(180),
              ],
            ),
          ),
        ),
        // Contenu : poster à gauche + infos à droite
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Poster mis en avant
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 110,
                  height: 165,
                  color: Colors.black26,
                  child: logoUrl != null && logoUrl.isNotEmpty
                      ? Image.network(
                          logoUrl,
                          fit: type == M3uContentType.tv ? BoxFit.contain : BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(fallbackIcon, color: Colors.white54, size: 40),
                        )
                      : Icon(fallbackIcon, color: Colors.white54, size: 40),
                ),
              ),
              const SizedBox(width: 16),
              // Bloc texte + bouton
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: kAccentPrimary.withAlpha(50),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: kAccentPrimary.withAlpha(180), width: 1),
                      ),
                      child: Text(
                        _featuredLabel(type),
                        style: TextStyle(
                          color: kAccentPrimary,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      entry.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        height: 1.15,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 36,
                      child: ElevatedButton.icon(
                        onPressed: onPlay,
                        icon: const Icon(Icons.play_arrow, size: 20),
                        label: const Text('Lire'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kAccentPrimary,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          elevation: 6,
                          shadowColor: kAccentPrimary.withAlpha(180),
                          textStyle: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Tap sur la zone vide → ouvre l'item
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: InkWell(onTap: onPlay),
          ),
        ),
      ],
    );
  }

  String _featuredLabel(M3uContentType t) => switch (t) {
        M3uContentType.movie  => 'À LA UNE',
        M3uContentType.series => 'NOUVELLE SÉRIE',
        M3uContentType.tv     => 'EN DIRECT',
      };
}

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
                if (hasMore)
                  TextButton.icon(
                    onPressed: () => _openCategoryListPage(context),
                    icon: Text('$totalCount',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: kAccentPrimary)),
                    label: Icon(Icons.chevron_right, size: 18, color: kAccentPrimary),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                  // Adapte le nombre de colonnes à la largeur disponible
                  // (3 sur smartphone, 4-5 sur tablette).
                  const spacing = 8.0;
                  final cols = constraints.maxWidth >= 600 ? 5 : 3;
                  final tileWidth = (constraints.maxWidth - spacing * (cols - 1)) / cols;
                  final tiles = <Widget>[
                    ...groups.map((g) => _HomeCard(
                          versions: g,
                          type: type,
                          width: tileWidth,
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
                    spacing: spacing,
                    runSpacing: spacing,
                    children: tiles,
                  );
                },
              ),
            )
          else
            SizedBox(
              // Films/Séries : poster 130 × 1.5 = 195 + paddings ≈ 215
              height: 215,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: groups.length + (hasMore ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (ctx, i) {
                  if (hasMore && i == groups.length) {
                    return _SeeAllTile(
                      type: type,
                      remaining: totalCount - groups.length,
                      width: 130,
                      onTap: () => _openCategoryListPage(context),
                    );
                  }
                  return _HomeCard(versions: groups[i], type: type);
                },
              ),
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

    return InkWell(
      onTap: onTap,
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
              border: Border.all(color: kAccentPrimary.withAlpha(120), width: 1),
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
                  child: const Icon(Icons.arrow_forward, color: Colors.black, size: 22),
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

class CategoryListPage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isTv = type == M3uContentType.tv;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: Row(
          children: [
            Icon(icon, size: 20, color: kAccentPrimary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                category,
                style: const TextStyle(fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${groups.length}',
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
      body: Container(
        decoration: BoxDecoration(
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
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              const spacing = 10.0;
              // Films/séries : 3 cols phone / 4 tablette / 5 large
              // Chaînes      : 3 cols phone / 5 tablette
              final width = constraints.maxWidth - 24;
              final int cols;
              if (isTv) {
                cols = constraints.maxWidth >= 600 ? 5 : 3;
              } else {
                cols = constraints.maxWidth >= 900
                    ? 5
                    : constraints.maxWidth >= 600
                        ? 4
                        : 3;
              }
              final tileWidth = (width - spacing * (cols - 1)) / cols;

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                child: Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: groups
                      .map((g) => _HomeCard(
                            versions: g,
                            type: type,
                            width: tileWidth,
                          ))
                      .toList(),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

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

  Future<void> _onTap() async {
    if (widget.versions.isEmpty) return;
    final entry = widget.versions.first;
    if (widget.type == M3uContentType.tv) {
      await showTvActionSheet(context, widget.versions);
      return;
    }
    final hasTmdb = await TmdbApiService.hasApiKey();
    if (!mounted) return;
    if (hasTmdb) {
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

    await showModalBottomSheet<void>(
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
                          ? Image.network(entry.logoUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink())
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
            // ── Lire (direct, sans action sheet) ──────────────────────────
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: const Text('Lire'),
              onTap: () {
                Navigator.pop(sheetCtx);
                FavoritesService.add(favKey);
                final badge = switch (widget.type) {
                  M3uContentType.movie  => PlayerBadgeType.movie,
                  M3uContentType.series => PlayerBadgeType.series,
                  M3uContentType.tv     => PlayerBadgeType.live,
                };
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerPage(
                  path: entry.url,
                  title: entry.displayName,
                  sourceType: VideoSourceType.network,
                  badgeType: badge,
                )));
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
                  leading: Icon(
                    isFav ? Icons.favorite : Icons.favorite_border,
                    color: isFav ? kAccentTertiary : null,
                  ),
                  title: Text(
                    isFav ? 'Retirer des favoris' : 'Ajouter aux favoris',
                    style: TextStyle(color: isFav ? kAccentTertiary : null),
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
    final logoUrl = widget.versions
        .map((e) => e.logoUrl)
        .firstWhere((l) => l != null && l.isNotEmpty, orElse: () => null);

    final isTv = widget.type == M3uContentType.tv;
    final cardWidth = widget.width ?? (isTv ? 120.0 : 130.0);
    final imageAspectRatio = isTv ? 1.0 : 2 / 3;

    final fallbackIcon = switch (widget.type) {
      M3uContentType.movie  => Icons.movie_outlined,
      M3uContentType.series => Icons.tv_outlined,
      M3uContentType.tv     => Icons.live_tv_outlined,
    };

    return GestureDetector(
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
                    // Titre en surimpression bas
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: Text(
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
                    ),
                  ],
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

// ─── Vue résultats de recherche ──────────────────────────────────────────────

class _SearchView extends StatelessWidget {
  /// Texte saisi (déjà debouncé par le parent).
  final String query;

  /// Toutes les entrées splittées par type — réutilisées pour le filtrage.
  final Map<M3uContentType, List<M3uEntry>> byType;

  const _SearchView({required this.query, required this.byType});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (query.trim().isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 56, color: cs.onSurfaceVariant.withAlpha(120)),
            const SizedBox(height: 12),
            Text(
              'Tapez pour chercher dans votre playlist',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              'Films · Séries · Chaînes',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant.withAlpha(150), fontSize: 12),
            ),
          ],
        ),
      );
    }

    final q = query.trim().toLowerCase();
    final filmsHits  = _filterAndGroup(byType[M3uContentType.movie]!,  q, M3uContentType.movie);
    final seriesHits = _filterAndGroup(byType[M3uContentType.series]!, q, M3uContentType.series);
    final tvHits     = _filterAndGroup(byType[M3uContentType.tv]!,     q, M3uContentType.tv);

    final totalGroups = filmsHits.length + seriesHits.length + tvHits.length;

    if (totalGroups == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 56, color: cs.onSurfaceVariant.withAlpha(120)),
            const SizedBox(height: 12),
            Text(
              'Aucun résultat pour "$query"',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    final sections = <Widget>[];
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

    return ListView(
      padding: EdgeInsets.fromLTRB(0, MediaQuery.of(context).padding.top + 76, 0, 24),
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

    String key(M3uEntry e) =>
        type == M3uContentType.tv ? tvGroupKey(e.displayName) : e.displayName;

    final byGroup = <String, List<M3uEntry>>{};
    for (final e in entries) {
      if (!match(e)) continue;
      byGroup.putIfAbsent(key(e), () => []).add(e);
    }

    final groups = byGroup.values.toList();
    if (groups.length > 30) groups.length = 30;
    return groups;
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
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
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
                    '${groups.length}',
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
          SizedBox(
            height: type == M3uContentType.tv ? 140 : 215,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: groups.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (ctx, i) => _HomeCard(
                versions: groups[i],
                type: type,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Physics : swipe gauche/droite plus court (-20%) ─────────────────────────

/// `PageScrollPhysics` plus sensible : amplifie modérément la vélocité au
/// moment du release pour atteindre le seuil de tolérance plus facilement.
///
/// Multiplicateur ×1.15 (au lieu de ×1.3) : compromis entre sensibilité
/// (un swipe court suffit à changer de page) et fluidité du snap (pas de
/// secousse abrupte sur les drags moyens).
class _FastPageScrollPhysics extends PageScrollPhysics {
  const _FastPageScrollPhysics({super.parent});

  @override
  _FastPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _FastPageScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    return super.createBallisticSimulation(position, velocity * 1.15);
  }
}

