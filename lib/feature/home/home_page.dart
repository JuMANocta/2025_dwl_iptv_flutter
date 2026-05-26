import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/services/favorites_service.dart';
import 'package:aetherStream/data/services/last_watched_channel_service.dart';
import 'package:aetherStream/data/services/parsed_playlist_service.dart';
import 'package:aetherStream/data/services/playlist_service.dart';
import 'package:aetherStream/data/services/search_history_service.dart';
import 'package:aetherStream/data/services/stream_account_service.dart';
import 'package:aetherStream/data/services/tmdb_api_service.dart';
import 'package:aetherStream/data/services/tmdb_poster_cache.dart';
import 'package:aetherStream/data/services/tmdb_service.dart';
import 'package:aetherStream/data/services/watch_progress_service.dart';
import 'package:aetherStream/feature/downloads/logic/download_initiator.dart';
import 'package:aetherStream/feature/player/player_page.dart';
import 'package:aetherStream/feature/search/details_page.dart';
import 'package:aetherStream/feature/settings/settings_page.dart';
import 'package:aetherStream/feature/search/m3u_filter.dart';
import 'package:aetherStream/widgets/media_action_sheet.dart';
import 'package:aetherStream/widgets/media_chips.dart';
import 'package:aetherStream/widgets/empty_state.dart';
import 'package:aetherStream/widgets/tv/focusable_card.dart';
import 'package:aetherStream/widgets/tv/focusable_chip.dart';
import 'package:aetherStream/widgets/tv/tv_adaptive_modal.dart';
import 'package:aetherStream/core/utils/platform_tv.dart';

/// §tvRails — Politique de traversée focus "façon Netflix" pour la home TV.
///
/// Problème corrigé : la traversée directionnelle par défaut (géométrique)
/// conserve la position horizontale en montant/descendant. Depuis le MILIEU
/// d'un carrousel, ↓ atterrissait au milieu de la rangée suivante — et si cette
/// rangée n'a qu'1-2 éléments (ex: ⭐ Favoris), aucun n'était sous le curseur →
/// la rangée était carrément **sautée**.
///
/// Comportement voulu : ↑/↓ = changement de RANGÉE, et on se cale toujours sur
/// l'élément le **plus à gauche** de la rangée cible (point d'entrée stable).
/// ←/→ gardent le comportement géométrique par défaut (déplacement intra-rangée
/// + sortie vers le NavigationRail à gauche).
///
/// Le NavigationRail (menu latéral) est exclu des candidats ↑/↓ : il s'étend sur
/// toute la hauteur et serait sinon vu comme "l'élément le plus à gauche" de
/// chaque bande.
class _TvRailsTraversalPolicy extends ReadingOrderTraversalPolicy {
  /// Tolérance verticale (px) pour considérer deux éléments comme sur la même
  /// rangée (centres Y proches malgré le scale focus / paddings).
  static const double _rowTolerance = 30.0;

  bool _isInNavigationRail(FocusNode node) {
    final ctx = node.context;
    if (ctx == null) return false;
    return ctx.findAncestorWidgetOfExactType<NavigationRail>() != null;
  }

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    // ←/→ et navigation dans le rail : comportement par défaut.
    if (direction == TraversalDirection.left ||
        direction == TraversalDirection.right ||
        _isInNavigationRail(currentNode)) {
      return super.inDirection(currentNode, direction);
    }

    final scope = currentNode.nearestScope;
    if (scope == null) return super.inDirection(currentNode, direction);

    final candidates = scope.traversalDescendants
        .where((n) =>
            n.canRequestFocus &&
            !n.skipTraversal &&
            !_isInNavigationRail(n))
        .toList();
    if (candidates.isEmpty) return super.inDirection(currentNode, direction);

    final curCenterY = currentNode.rect.center.dy;

    // Cherche le centre Y de la rangée immédiatement au-dessus/en-dessous.
    double? targetRowY;
    for (final n in candidates) {
      final cy = n.rect.center.dy;
      if ((cy - curCenterY).abs() <= _rowTolerance) continue; // même rangée
      if (direction == TraversalDirection.down && cy > curCenterY) {
        if (targetRowY == null || cy < targetRowY) targetRowY = cy;
      } else if (direction == TraversalDirection.up && cy < curCenterY) {
        if (targetRowY == null || cy > targetRowY) targetRowY = cy;
      }
    }
    if (targetRowY == null) {
      // Pas de rangée dans cette direction → laisser le défaut (peut sortir du
      // groupe, ex: remonter vers le hero/onglets).
      return super.inDirection(currentNode, direction);
    }

    // Parmi la rangée cible, prendre l'élément le plus à gauche.
    FocusNode? target;
    for (final n in candidates) {
      if ((n.rect.center.dy - targetRowY).abs() > _rowTolerance) continue;
      if (target == null || n.rect.left < target.rect.left) target = n;
    }
    if (target == null) return super.inDirection(currentNode, direction);

    requestFocusCallback(target);
    return true;
  }
}

/// Page d'accueil — design streaming premium (§1b phases 2 + 3, §navUX).
///
/// Layout (§navUX — hero en TOP, tabs SOUS le hero) :
///   AppBar              (⚙️ uniquement, transparente posée sur le fond)
///   PageView de _TypePage
///     ↳ _HeroBanner     (carrousel 16/9 d'items mis en avant — auto-rotation 6s)
///     ↳ _AnimatedTabIndicator (Séries · Films · Chaînes — injectées par parent)
///     ↳ _LastWatchedTvTile    (page TV uniquement — "Reprendre la chaîne")
///     ↳ _CategoryRow    (Favoris ⭐ d'abord, puis France/New/genres alpha)
///
/// Design choices :
///   - Fond : gradient sombre subtil avec halo accent en haut
///   - Cartes : poster + overlay gradient bas + titre lisible en surimpression
///   - Headers section : barre verticale gradient 3px + titre 18 gras
///   - Hero : 16/9, auto-rotation, indicateur en dots, bouton Lire glow
///   - Favoris : pas de plafond 25 (l'utilisateur les a curatés lui-même)
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

  /// Compte actif courant — peut changer en cours de session si l'utilisateur
  /// modifie la priorité dans `AccountsPage`. On lit la valeur initiale dans
  /// [widget.initialData], puis on l'aligne sur le notifier.
  late String _activeAccountId;
  late String _activeAccountName;

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
    _searchFocus.addListener(_onSearchFocusChanged);
    _activeAccountId = widget.initialData.accountId;
    _activeAccountName = widget.initialData.accountName;
    _ensureLoaded(initialPath: widget.initialData.path);
    StreamAccountService.currentAccountIdNotifier
        .addListener(_onCurrentAccountChanged);

    // §3c-bis #3 — Auto-focus initial sur TV. Sans ça, le focus reste à la
    // racine du tree (invisible) → l'utilisateur appuie au hasard pour trouver
    // où il est. On déclenche `nextFocus()` après la 1re frame pour avancer
    // sur le 1er widget focusable visible (NavigationRail → première card).
    // 2 post-frames pour laisser le temps aux carrousels async d'être montés.
    if (PlatformTv.isTv && !widget.searchMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          FocusScope.of(context).nextFocus();
        });
      });
    }
  }

  void _onSearchFocusChanged() {
    if (mounted) setState(() {});
  }

  /// Réagit aux changements de compte prioritaire effectués dans `AccountsPage`.
  /// Recharge le M3U + parsed playlist du nouveau compte actif et déclenche un
  /// rebuild de la home + des résultats de recherche.
  Future<void> _onCurrentAccountChanged() async {
    final newId = StreamAccountService.currentAccountIdNotifier.value;
    if (newId == null || newId == _activeAccountId) return;
    final acc = await StreamAccountService.getAccount(newId);
    if (!mounted || acc == null) return;
    setState(() {
      _activeAccountId = newId;
      _activeAccountName = acc.label;
      _loading = true;
    });
    await _ensureLoaded();
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
    _searchFocus.removeListener(_onSearchFocusChanged);
    _searchFocus.dispose();
    _pageController.dispose();
    StreamAccountService.currentAccountIdNotifier
        .removeListener(_onCurrentAccountChanged);
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

  /// Garantit que le compte actif courant est chargé en mémoire :
  /// - si déjà parsé → retour immédiat
  /// - sinon → télécharge le M3U si manquant + parse + cache disque
  Future<void> _ensureLoaded({String? initialPath}) async {
    final id = _activeAccountId;
    if (id.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      if (ParsedPlaylistService.getAccount(id) == null) {
        // Sans chemin connu (changement de compte runtime) → s'appuyer sur
        // PlaylistService pour résoudre/télécharger le M3U du compte courant.
        final path = initialPath ?? await PlaylistService.getOrDownloadPlaylist();
        await ParsedPlaylistService.loadActive(id, _activeAccountName, path);
      }
    } catch (e) {
      debugPrint('❌ HomePage._ensureLoaded: $e');
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

  /// §3c Phase 2 — Wrappe une page du PageView pour la navigation TV :
  /// retire du focus les pages non visibles (offstage) et scope la traversée
  /// directionnelle à la page courante. Neutre hors TV.
  Widget _pageFocusWrap(int index, Widget child) {
    // §pageSmooth — RepaintBoundary isole le layer de chaque page → pendant le
    // slide horizontal, peindre une page ne re-peint pas l'autre (compositing
    // moins coûteux = moins de saccades sur les pages lourdes carrousels+hero).
    final wrapped = RepaintBoundary(child: child);
    if (!PlatformTv.isTv) return wrapped;
    return ExcludeFocus(
      excluding: _currentIndex != index,
      // §tvRails — ↑/↓ change de rangée et se cale à gauche (cf. politique).
      child: FocusTraversalGroup(
        policy: _TvRailsTraversalPolicy(),
        child: wrapped,
      ),
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
    final statusBarHeight = MediaQuery.of(context).padding.top;
    // §heroFan ergo — Pour movie/series, le hero "fan" remonte jusqu'au status
    // bar : l'inclinaison des cartes laisse le coin haut-droit libre pour
    // l'icône ⚙️ qui flotte par-dessus. Pour TV (hero 16/9 plein largeur),
    // on conserve l'offset AppBar sinon le titre du hero entre en collision
    // avec l'icône.
    final liftedTopInset = statusBarHeight + 4;
    final defaultTopInset = statusBarHeight + kToolbarHeight;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        // §navUX — Plus de nom de compte dans le title (il est déjà visible
        // dans SettingsPage → Comptes IPTV → bandeau "COMPTE ACTIF"). Ça libère
        // la barre du haut et laisse le hero respirer.
        // §1L-a — En mode recherche : arrow_back à gauche (retour intuitif),
        // pas de title (le grand champ dans le body fait office de header).
        leading: widget.searchMode
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Quitter la recherche',
                onPressed: () => widget.onExitSearch?.call(),
              )
            : null,
        title: null,
        // §3c-bis — Sur TV, l'icône ⚙️ est redondante avec la 4e destination
        // "Paramètres" du NavigationRail latéral (et inaccessible au D-pad de
        // toute façon, le focus traversal ne remonte pas dans l'AppBar).
        actions: (widget.searchMode || PlatformTv.isTv)
            ? const []
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
        // width/height infinity → force le Container à occuper toute la zone du
        // body. Sans ça, si l'enfant (ex: empty state du _SearchView qui retourne
        // un simple Padding) a une taille intrinsèque petite, le Container se
        // dimensionne sur l'enfant → le gradient/thème ne s'applique que sur la
        // hauteur réelle de l'enfant (régression visuelle "thème sur une partie").
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
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListenableBuilder(
                listenable: Listenable.merge([
                  ParsedPlaylistService.version,
                  FavoritesService.version,
                  WatchProgressService.version,
                ]),
                builder: (context, _) {
                  // §perfBigList — split mémoïsé : recalculé seulement quand la
                  // playlist ou le compte change, PAS à chaque bump Favoris /
                  // WatchProgress (qui déclenchent aussi ce ListenableBuilder).
                  final byType = _byTypeMemoized();

                  if (widget.searchMode) {
                    // §1L-a — Grand champ recherche dans le body (sous l'AppBar
                    // transparente) au lieu d'un mini-champ dans le title.
                    return Column(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).padding.top +
                              kToolbarHeight,
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                          child: _buildSearchField(cs),
                        ),
                        Expanded(
                          child: _SearchView(
                            query: _searchQuery,
                            byType: byType,
                            onSelectSuggestion: (q) {
                              _searchCtrl.text = q;
                              _searchCtrl.selection =
                                  TextSelection.fromPosition(
                                TextPosition(offset: q.length),
                              );
                              SearchHistoryService.record(q);
                            },
                          ),
                        ),
                      ],
                    );
                  }

                  // §navUX — Builder de la barre Séries/Films/Chaînes injectée
                  // sous le hero dans chaque _TypePage. Toutes les instances
                  // écoutent le même PageController → l'underline reste synchro
                  // au swipe horizontal.
                  Widget buildTabs(BuildContext ctx) {
                    return _AnimatedTabIndicator(
                      controller: _pageController,
                      currentIndex: _currentIndex,
                      counts: [
                        byType[M3uContentType.series]!.length,
                        byType[M3uContentType.movie]!.length,
                        byType[M3uContentType.tv]!.length,
                      ],
                      onTap: _goToPage,
                    );
                  }

                  return PageView(
                    controller: _pageController,
                    // §3c-7 — Sur TV : pas de swipe horizontal (la nav
                    // Films/Séries/Chaînes se fait via les tabs cliquables
                    // au D-pad, sinon le focus tombe dans le PageView qui
                    // scrolle dans tous les sens).
                    physics: PlatformTv.isTv
                        ? const NeverScrollableScrollPhysics()
                        : const _FastPageScrollPhysics(),
                    onPageChanged: (i) {
                      setState(() => _currentIndex = i);
                      // §3c Phase 2 — Après un changement d'onglet sur TV,
                      // l'ancienne page (avec le chip d'onglet focusé) est
                      // exclue du focus → on ré-acquiert le focus dans la page
                      // désormais visible pour ne pas le laisser en limbo.
                      if (PlatformTv.isTv) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) FocusScope.of(context).nextFocus();
                        });
                      }
                    },
                    children: [
                      // §3c Phase 2 — Chaque page du PageView est wrappée :
                      //  • ExcludeFocus : sur TV, les 2 pages NON visibles
                      //    (offstage à gauche/droite) sont retirées du focus →
                      //    le D-pad ne « saute » plus vers une carte invisible
                      //    (cause majeure du focus erratique signalée à l'audit).
                      //  • FocusTraversalGroup : scope la traversée directionnelle
                      //    à la page courante (sortie vers le rail toujours
                      //    possible si aucune cible dans la direction).
                      _pageFocusWrap(
                        0,
                        _TypePage(
                          // Key sur _activeAccountId : si l'utilisateur change de
                          // compte prioritaire, on force le rebuild complet du
                          // _TypePage (memoization invalidée).
                          key: ValueKey('series_$_activeAccountId'),
                          type: M3uContentType.series,
                          entries: byType[M3uContentType.series]!,
                          topInset: liftedTopInset,
                          tabsBuilder: buildTabs,
                        ),
                      ),
                      _pageFocusWrap(
                        1,
                        _TypePage(
                          key: ValueKey('movie_$_activeAccountId'),
                          type: M3uContentType.movie,
                          entries: byType[M3uContentType.movie]!,
                          topInset: liftedTopInset,
                          tabsBuilder: buildTabs,
                        ),
                      ),
                      _pageFocusWrap(
                        2,
                        _TypePage(
                          key: ValueKey('tv_$_activeAccountId'),
                          type: M3uContentType.tv,
                          entries: byType[M3uContentType.tv]!,
                          topInset: defaultTopInset,
                          tabsBuilder: buildTabs,
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  /// Champ de saisie placé dans le body sous l'AppBar quand searchMode est actif.
  /// §1L-a : hauteur 56, police 16, contentPadding plus aéré. Le X interne
  /// efface uniquement le texte (le retour à la home se fait via arrow_back).
  Widget _buildSearchField(ColorScheme cs) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: kAccentSecondary.withAlpha(_searchFocus.hasFocus ? 200 : 60),
          width: _searchFocus.hasFocus ? 1.5 : 1,
        ),
        boxShadow: _searchFocus.hasFocus
            ? [BoxShadow(color: kAccentSecondary.withAlpha(50), blurRadius: 14, spreadRadius: 1)]
            : null,
      ),
      child: TextField(
        controller: _searchCtrl,
        focusNode: _searchFocus,
        textInputAction: TextInputAction.search,
        style: TextStyle(color: cs.onSurface, fontSize: 16),
        onSubmitted: (q) {
          // §1i — Enregistrer la requête dans l'historique au submit (Enter).
          SearchHistoryService.record(q);
        },
        decoration: InputDecoration(
          hintText: 'Rechercher dans la playlist…',
          hintStyle: TextStyle(
            color: cs.onSurfaceVariant.withAlpha(140),
            fontSize: 16,
          ),
          prefixIcon: Icon(Icons.search, color: kAccentSecondary, size: 24),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  tooltip: 'Effacer',
                  splashRadius: 20,
                  onPressed: () => _searchCtrl.clear(),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  // ── §perfBigList — split par type mémoïsé ───────────────────────────────
  Map<M3uContentType, List<M3uEntry>>? _cachedByType;
  String? _cachedByTypeKey;

  /// Retourne le split films/séries/TV du compte actif, recalculé UNIQUEMENT
  /// quand la playlist (`version`) ou le compte actif change. Réutilise les
  /// listes pré-splittées de `ParsedPlaylistService` (zéro re-parcours des 600k
  /// entrées) et applique le masquage TV (séparateurs déco / variantes cachées).
  Map<M3uContentType, List<M3uEntry>> _byTypeMemoized() {
    final key = '${ParsedPlaylistService.version.value}|$_activeAccountId';
    if (_cachedByType != null && _cachedByTypeKey == key) return _cachedByType!;

    final raw = ParsedPlaylistService.byTypeWithPriority(_activeAccountId);
    final tv = raw[M3uContentType.tv]!
        .where((e) => !isHiddenTvVariant(e.title.rawTitle))
        .toList();
    final byType = {
      M3uContentType.movie: raw[M3uContentType.movie]!,
      M3uContentType.series: raw[M3uContentType.series]!,
      M3uContentType.tv: tv,
    };
    _cachedByType = byType;
    _cachedByTypeKey = key;
    return byType;
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

    // §navUX — Le tab indicator est maintenant injecté SOUS le hero dans la
    // liste de _TypePage, donc plus besoin d'offset status bar (le ListView
    // gère lui-même son padding-top via widget.topInset).
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
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
                    // §3c Phase 1 — FocusableChip rend l'onglet atteignable au
                    // D-pad (avant : GestureDetector tap-only → impossible de
                    // changer de section Séries/Films/Chaînes à la télécommande).
                    return Expanded(
                      child: FocusableChip(
                        enabled: !isEmpty,
                        onTap: isEmpty ? null : () => widget.onTap(i),
                        borderRadius: BorderRadius.circular(8),
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

// ─── Densité responsive (§tvZoom) ────────────────────────────────────────────

/// Largeur cible d'une vignette selon la largeur disponible.
///
/// Smartphone (~390 dp) → ~130 px (comportement historique inchangé). Tablette /
/// Android TV (largeur logique large) → on conserve des vignettes ~130-145 px et
/// on en affiche **davantage**, au lieu d'étirer 3 vignettes géantes. Corrige
/// l'effet « tout zoomé » sur TV où le layout était figé en dp téléphone.
double _responsiveTileWidth(double available, {required bool channel}) {
  final cols = _responsiveColumns(available, channel: channel);
  return available / cols;
}

/// Nombre de colonnes / vignettes visibles cible selon la largeur disponible.
/// Vignette cible : ~130 px pour les chaînes (logo carré), ~145 px pour les
/// posters 2:3. Borné [3, 10] pour rester lisible à 3 m sans micro-vignettes.
int _responsiveColumns(double available, {required bool channel}) {
  // §tvSizeRevert (2026-05-25) — Retour au dimensionnement de BASE (celui du
  // début du support Android TV, §3c). Les itérations §tvZoom/§tv4K/§tv4K-bis
  // (branche TV par largeur cible puis colonnes fixes) ont rendu le carrousel
  // minuscule sur device. Faute de pouvoir lire les logs sur la TV, on supprime
  // toute la logique TV spécifique : TV et mobile partagent la même formule
  // (carrousel un peu grand mais correct, jugé OK par l'utilisateur).
  final target = channel ? 130.0 : 145.0;
  return (available / target).round().clamp(3, 10);
}

// ─── Page d'un type ──────────────────────────────────────────────────────────

class _TypePage extends StatefulWidget {
  final M3uContentType type;
  final List<M3uEntry> entries;

  /// Padding en haut de la liste (status bar + AppBar) pour que le hero ne
  /// soit pas caché derrière l'AppBar transparente (extendBodyBehindAppBar).
  final double topInset;

  /// Construit la barre Séries/Films/Chaînes insérée juste sous le hero.
  /// Le parent partage la même `_pageController` entre toutes les instances
  /// pour que l'underline reste cohérent au swipe.
  final WidgetBuilder? tabsBuilder;

  const _TypePage({
    super.key,
    required this.type,
    required this.entries,
    this.topInset = 0,
    this.tabsBuilder,
  });

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
      default:
        // §Ultimate — régions étrangères (Italie, Arabe, Turquie…) reléguées
        // sous les genres FR (100) mais au-dessus d'Autres (1000).
        if (kForeignRegionLabels.contains(category)) return 500;
        return 100;
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
  /// Réduit de 25 → 15 (§ergo) : carrousels plus courts = scroll horizontal
  /// allégé (surtout au D-pad TV) et moins d'affiches TMDB à résoudre/charger.
  static const int _maxItemsPerCategory = 15;

  // ── Caches (memoization) — §perfBigList ─────────────────────────────────
  // CRUCIAL avec une grosse playlist (Ultimate ~600k entrées) : le GROUPEMENT
  // par catégorie/titre est O(n) sur des centaines de milliers d'entrées. Il ne
  // dépend QUE des entrées + playlist + favoris. Le HERO "featured" (reprise)
  // dépend EN PLUS de WatchProgress, qui bump toutes les 10 s en lecture ET au
  // retour du player → on cache les deux SÉPARÉMENT pour ne PAS re-grouper 500k
  // entrées à chaque tick de progression (cause d'un gros freeze au retour du
  // player avec Ultimate).
  Map<String, List<List<M3uEntry>>>? _cachedByCategory;
  List<String>? _cachedCategories;
  List<List<M3uEntry>>? _cachedFeatured;
  int _cachedGroupingKey = -1;
  int _cachedFeaturedKey = -1;

  // §trending — Titres tendance TMDB de la semaine (chargés une fois, cache
  // 24h côté service). Null tant que pas chargé / pas de clé TMDB. Le croisement
  // avec la playlist se fait dans `_ensureFeatured` (titres → groupes dispo).
  List<TrendingTitle>? _trendingTitles;

  @override
  void initState() {
    super.initState();
    // Tendances seulement pour films/séries (pas de matching TMDB sur le live TV).
    if (widget.type != M3uContentType.tv) _loadTrending();
  }

  /// §trending — Charge les tendances TMDB du type courant (movie/series) et
  /// force un recalcul du hero pour y injecter les titres dispo.
  Future<void> _loadTrending() async {
    final isTv = widget.type == M3uContentType.series; // series → /trending/tv
    final list = await TmdbService.instance.getTrending(isTv: isTv);
    if (!mounted) return;
    setState(() {
      _trendingTitles = list;
      _cachedFeaturedKey = -1; // invalide le hero → recompute avec les tendances
    });
  }

  /// Normalisation titre (identique à ActorDetailsPage) pour le matching exact
  /// TMDB ↔ playlist : minuscules, sans ponctuation/apostrophes, espaces réduits.
  static String _normTitle(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r"['’`´]"), '')
      .replaceAll(RegExp(r'[^\w\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Clé du GROUPEMENT (coûteux) : entrées + playlist + favoris. **PAS**
  /// WatchProgress (sinon re-groupement complet toutes les 10 s en lecture).
  int _groupingKey() =>
      widget.entries.length * 1000003 +
      ParsedPlaylistService.version.value * 1009 +
      FavoritesService.version.value * 1013;

  /// Groupe par catégorie puis par titre. Mémoïsé sur [_groupingKey].
  void _ensureGrouping() {
    final key = _groupingKey();
    if (_cachedByCategory != null && _cachedGroupingKey == key) return;

    final byCategory = _groupByCategoryThenByTitle(widget.entries, widget.type);
    final categories = byCategory.keys.toList()
      ..sort((a, b) {
        final pa = _TypePage._categoryPriority(a);
        final pb = _TypePage._categoryPriority(b);
        if (pa != pb) return pa.compareTo(pb);
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

    _cachedByCategory = byCategory;
    _cachedCategories = categories;
    _cachedGroupingKey = key;
    _cachedFeaturedKey = -1; // groupement changé → forcer le recalcul du hero
  }

  /// Compose le hero "featured" (reprise + nouveautés) à partir du groupement
  /// déjà calculé. Dépend de WatchProgress → cache SÉPARÉ (léger) pour ne pas
  /// re-grouper à chaque tick de progression.
  void _ensureFeatured() {
    final key = WatchProgressService.version.value;
    if (_cachedFeatured != null && _cachedFeaturedKey == key) return;

    final byCategory = _cachedByCategory!;
    final categories = _cachedCategories!;

    // §heroFan — Composition du hero :
    //   - films/séries : 5 reprise (triées lastWatched desc) + 5 nouveautés
    //     prioritaires non-déjà-incluses → max 10 cartes empilées
    //   - TV : pas de notion "en cours" (live) → max 5 cartes catégorie prio
    const maxFeatured = 10;
    const maxResume = 5;
    final featured = <List<M3uEntry>>[];

    if (widget.type != M3uContentType.tv) {
      // §heroFanDedup — La catégorie virtuelle "Favoris" duplique les références
      // de groupes qui vivent aussi dans leur catégorie d'origine. On dédupe par
      // `displayName` pour éviter qu'un film favori en cours de lecture apparaisse
      // 2× dans le hero.
      final allGroups = <List<M3uEntry>>[];
      final seenNames = <String>{};
      for (final groups in byCategory.values) {
        for (final group in groups) {
          if (seenNames.add(group.first.displayName)) {
            allGroups.add(group);
          }
        }
      }
      final resumeWithTime = <({List<M3uEntry> group, DateTime t})>[];
      for (final group in allGroups) {
        final p = WatchProgressService.getProgressForAny(
          group.map((e) => e.url),
        );
        if (p != null && p.ratio < 0.95) {
          resumeWithTime.add((group: group, t: p.lastWatched));
        }
      }
      resumeWithTime.sort((a, b) => b.t.compareTo(a.t));
      final resumeKeys = <String>{};
      for (final item in resumeWithTime.take(maxResume)) {
        featured.add(item.group);
        resumeKeys.add(item.group.first.displayName);
      }

      // §trending — Complète avec les TENDANCES TMDB de la semaine DISPONIBLES
      // dans la playlist (remplace les anciennes "nouveautés" du hero, déjà
      // listées dans la rangée horizontale dessous). Les reprises restent en
      // tête. Matching exact sur titre localisé OU original (ordre TMDB conservé).
      bool usedTrending = false;
      final trending = _trendingTitles;
      if (trending != null && trending.isNotEmpty) {
        final byName = <String, List<M3uEntry>>{};
        for (final g in allGroups) {
          byName.putIfAbsent(_normTitle(g.first.displayName), () => g);
        }
        for (final t in trending) {
          if (featured.length >= maxFeatured) break;
          var hit = byName[_normTitle(t.title)];
          if (hit == null && t.originalTitle != null) {
            hit = byName[_normTitle(t.originalTitle!)];
          }
          if (hit == null) continue;
          final name = hit.first.displayName;
          if (resumeKeys.contains(name)) continue;
          if (featured.any((f) => f.first.displayName == name)) continue;
          featured.add(hit);
          usedTrending = true;
        }
      }

      // Fallback : pas de clé TMDB / aucune tendance dispo → comportement
      // historique (catégories prioritaires) pour ne pas laisser le hero vide.
      if (!usedTrending) {
        for (final cat in categories) {
          if (featured.length >= maxFeatured) break;
          if (cat == 'Favoris') continue;
          if (_TypePage._categoryPriority(cat) >= 100) continue;
          for (final group in byCategory[cat]!) {
            if (featured.length >= maxFeatured) break;
            if (resumeKeys.contains(group.first.displayName)) continue;
            featured.add(group);
          }
        }
      }
    } else {
      // TV : comportement historique (catégorie prioritaire, max 5).
      for (final cat in categories) {
        if (cat == 'Favoris') continue;
        if (_TypePage._categoryPriority(cat) < 100) {
          featured.addAll(byCategory[cat]!.take(5));
          break;
        }
      }
    }

    // Fallback si rien trouvé (playlist sans catégorie prioritaire ni reprise).
    if (featured.isEmpty && categories.isNotEmpty) {
      final first = categories.firstWhere(
        (c) => c != 'Autres' && c != 'Favoris',
        orElse: () => categories.first,
      );
      featured.addAll(byCategory[first]!.take(5));
    }

    _cachedFeatured = featured;
    _cachedFeaturedKey = key;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) return _buildEmpty(context);

    _ensureGrouping();
    _ensureFeatured();
    final byCategory = _cachedByCategory!;
    final categories = _cachedCategories!;
    final featured = _cachedFeatured!;

    // §navUX — Ordre des items de la liste :
    //   1. Hero (carrousel "en avant")
    //   2. Tabs Séries · Films · Chaînes (injectées par le parent)
    //   3. _LastWatchedTvTile (uniquement page TV)
    //   4. Catégories : Favoris d'abord (priorité -2), puis France/New/etc.
    final hasHero = featured.isNotEmpty;
    final hasTabs = widget.tabsBuilder != null;
    final showLastWatchedSlot = widget.type == M3uContentType.tv;

    final heroOffset = hasHero ? 1 : 0;
    final tabsOffset = hasTabs ? 1 : 0;
    final lastWatchedOffset = showLastWatchedSlot ? 1 : 0;
    final headerCount = heroOffset + tabsOffset + lastWatchedOffset;

    return ListView.builder(
      padding: EdgeInsets.only(top: widget.topInset, bottom: 24),
      itemCount: headerCount + categories.length,
      itemBuilder: (ctx, i) {
        var cursor = 0;
        if (hasHero) {
          if (i == cursor) {
            // §heroFan — fan "jeu de cartes" pour films/séries (avec reprise
            // en tête), hero 16/9 classique pour les chaînes TV.
            return widget.type == M3uContentType.tv
                ? _HeroBanner(featured: featured, type: widget.type)
                : _HeroFanBanner(featured: featured, type: widget.type);
          }
          cursor += 1;
        }
        if (hasTabs) {
          if (i == cursor) return widget.tabsBuilder!(ctx);
          cursor += 1;
        }
        if (showLastWatchedSlot) {
          if (i == cursor) return _LastWatchedTvTile(entries: widget.entries);
          cursor += 1;
        }
        final catIdx = i - cursor;
        final cat = categories[catIdx];
        final allGroups = byCategory[cat]!;
        // §navUX — Favoris affichés sans limite (l'utilisateur les a curatés
        // lui-même, on ne les tronque pas à 25). Les autres catégories gardent
        // le plafond + la tuile "Voir tout".
        final isFav = cat == 'Favoris';
        final hasMore = !isFav && allGroups.length > _maxItemsPerCategory;
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

    // §URGENT — Dédoublonne les qualités identiques au sein d'un groupe TV
    // (provider qui expose 2× "TF1 FHD" → un seul bouton FHD dans la sheet).
    if (type == M3uContentType.tv) {
      for (final k in byGroup.keys.toList()) {
        byGroup[k] = dedupeTvVersions(byGroup[k]!);
      }
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
    // §bugfix — Les séries vont toujours sur DetailsPage (picker saison/épisode
    // construit depuis la playlist), même sans clé TMDB : sinon l'action sheet
    // ne lit que le 1er épisode et l'utilisateur ne peut pas choisir.
    if (hasTmdb || entry.type == M3uContentType.series) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DetailsPage(entry: entry, versions: versions),
      ));
    } else {
      await showMediaActionSheet(context, entry);
    }
  }

  @override
  Widget build(BuildContext context) {
    final core = ClipRRect(
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
        );

    // §tvSizeRevert — Retour à la base : ratio 16/9 pour tous (le cap TV à 32 %
    // §tvZoom rapetissait le hero). Comportement du début du support Android TV.
    final Widget sized = AspectRatio(aspectRatio: 16 / 9, child: core);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      child: sized,
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

// ─── Hero "fan" — empilement carte de jeu (§heroFan) ─────────────────────────
//
// Affiche jusqu'à 10 cartes empilées en éventail. Auto-rotation 6s qui fait
// défiler les cartes (chaque tick = la carte suivante devient active). Les
// premières cartes sont en cours de lecture (`WatchProgressService`, triées
// par `lastWatched` desc), suivies par les nouveautés prioritaires. Tap sur
// la carte centrale → ouverture du media ; tap sur une carte secondaire →
// elle vient prendre la position centrale.

class _HeroFanBanner extends StatefulWidget {
  final List<List<M3uEntry>> featured;
  final M3uContentType type;

  const _HeroFanBanner({required this.featured, required this.type});

  @override
  State<_HeroFanBanner> createState() => _HeroFanBannerState();
}

class _HeroFanBannerState extends State<_HeroFanBanner>
    with SingleTickerProviderStateMixin {
  static const _autoDuration = Duration(seconds: 6);
  static const _animDuration = Duration(milliseconds: 520);

  late final AnimationController _animCtrl;
  Timer? _timer;

  /// §3c Phase 2 — Sur TV, quand le hero est focusé au D-pad, on met l'auto-
  /// rotation en pause : sinon la rotation 6 s ferait basculer la carte active
  /// sous le focus (perte/saut de focus). Reprend dès qu'on quitte le hero.
  bool _focusPaused = false;

  /// Position lissée (peut être fractionnaire). On ne wrap PAS sur [0, N) :
  /// la valeur incrémente continument et chaque carte calcule son `delta`
  /// modulo N avec le plus court chemin → wrap visuel naturel.
  double _from = 0;
  double _to = 0;
  double _current = 0;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: _animDuration)
      ..addListener(_onTick);
    _scheduleNext();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animCtrl
      ..removeListener(_onTick)
      ..dispose();
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    setState(() {
      final t = Curves.easeOutCubic.transform(_animCtrl.value);
      _current = _from + (_to - _from) * t;
    });
  }

  void _scheduleNext() {
    _timer?.cancel();
    if (widget.featured.length <= 1 || _focusPaused) return;
    _timer = Timer.periodic(_autoDuration, (_) {
      if (!mounted) return;
      _advance();
    });
  }

  /// Met en pause / reprend l'auto-rotation selon l'état de focus (TV).
  void _setFocusPaused(bool paused) {
    if (_focusPaused == paused) return;
    _focusPaused = paused;
    if (paused) {
      _timer?.cancel();
    } else {
      _scheduleNext();
    }
  }

  void _advance() {
    _from = _current;
    _to = _from + 1;
    _animCtrl.forward(from: 0);
  }

  /// Anime jusqu'à la carte `targetIdx` en empruntant le plus court chemin
  /// circulaire (gauche ou droite).
  void _gotoCard(int targetIdx) {
    final n = widget.featured.length.toDouble();
    final currentMod = _current % n;
    double delta = targetIdx - currentMod;
    delta = delta % n;
    if (delta > n / 2) delta -= n;
    _from = _current;
    _to = _current + delta;
    _animCtrl.forward(from: 0);
    _scheduleNext();
  }

  double _shortestDelta(int i) {
    final n = widget.featured.length.toDouble();
    double delta = i - _current;
    delta = delta % n;
    if (delta > n / 2) delta -= n;
    return delta;
  }

  Future<void> _openItem(BuildContext context, List<M3uEntry> versions) async {
    if (versions.isEmpty) return;
    final entry = versions.first;
    final hasTmdb = await TmdbApiService.hasApiKey();
    if (!context.mounted) return;
    // §bugfix — Les séries vont toujours sur DetailsPage (picker saison/épisode
    // construit depuis la playlist), même sans clé TMDB : sinon l'action sheet
    // ne lit que le 1er épisode et l'utilisateur ne peut pas choisir.
    if (hasTmdb || entry.type == M3uContentType.series) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DetailsPage(entry: entry, versions: versions),
      ));
    } else {
      await showMediaActionSheet(context, entry);
    }
  }

  void _onCardTap(BuildContext context, int i) {
    final n = widget.featured.length;
    final currentIdx = ((_current.round() % n) + n) % n;
    if (i == currentIdx) {
      _openItem(context, widget.featured[i]);
    } else {
      _gotoCard(i);
    }
  }

  // ── Swipe manuel (§heroFan ergo) ───────────────────────────────────────────
  // Le `GestureDetector` au niveau du Stack capture les drags horizontaux
  // AVANT que la PageView parent (Séries/Films/Chaînes) puisse les revendiquer.
  // → swipe sur le hero = navigation entre cartes uniquement, jamais switch
  // de type. Le tap reste géré par l'InkWell de la carte (gestures distincts).

  void _onDragStart(DragStartDetails details) {
    _timer?.cancel();
    if (_animCtrl.isAnimating) _animCtrl.stop();
  }

  void _onDragUpdate(DragUpdateDetails details, double cardSpacing) {
    if (cardSpacing <= 0) return;
    setState(() {
      _current -= details.delta.dx / cardSpacing;
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (widget.featured.length <= 1) {
      _scheduleNext();
      return;
    }
    final v = details.primaryVelocity ?? 0;
    // Vélocité forte → bias dans la direction du swipe ; faible → snap nearest.
    int target;
    if (v.abs() > 300) {
      target = (v < 0) ? _current.floor() + 1 : _current.ceil() - 1;
    } else {
      target = _current.round();
    }
    _from = _current;
    _to = target.toDouble();
    _animCtrl.forward(from: 0);
    _scheduleNext();
  }

  void _onDragCancel() {
    // Annulation (ex: bascule app) → snap nearest pour rester aligné.
    _from = _current;
    _to = _current.round().toDouble();
    _animCtrl.forward(from: 0);
    _scheduleNext();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.featured.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final screenW = constraints.maxWidth;
        // §tvSizeRevert — Pas de cap de hauteur TV (le §tvZoom 30 % rapetissait
        // le hero). Retour au dimensionnement de base.
        final cardW = math.min(screenW * 0.48, 220.0);
        final cardH = cardW * 1.45;
        final containerH = cardH + 60;
        // 1 carte d'écart visuel = ~22 % de la largeur d'une carte.
        // Sensibilité du drag : 1 unité de `_current` = `cardSpacing` pixels.
        final cardSpacing = cardW * 0.22;

        // Pour le z-order : on trie par |delta| desc → grandes valeurs au début
        // de la liste = dessinées en premier = derrière.
        final cards = <({int i, double delta})>[];
        for (var i = 0; i < widget.featured.length; i++) {
          final d = _shortestDelta(i);
          if (d.abs() <= 3) cards.add((i: i, delta: d));
        }
        cards.sort((a, b) => b.delta.abs().compareTo(a.delta.abs()));

        final Widget fan = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: (d) => _onDragUpdate(d, cardSpacing),
          onHorizontalDragEnd: _onDragEnd,
          onHorizontalDragCancel: _onDragCancel,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 18),
            child: SizedBox(
              height: containerH,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  for (final c in cards)
                    _buildFannedCard(context, c.i, c.delta, cardW, cardH),
                  Positioned(bottom: 4, child: _buildDots()),
                ],
              ),
            ),
          ),
        );

        // §3c Phase 2 — Sur TV, le hero "fan" devient une cible de focus UNIQUE
        // et stable (les InkWell internes sont exclus du focus dans
        // `_buildFannedCard`). OK ouvre la carte active ; le focus met l'auto-
        // rotation en pause pour ne pas faire glisser la carte sous le D-pad.
        if (!PlatformTv.isTv) return fan;
        final n = widget.featured.length;
        final activeIndex = n == 0 ? 0 : ((_current.round() % n) + n) % n;
        return FocusableChip(
          onTap: () => _onCardTap(context, activeIndex),
          onFocusChange: _setFocusPaused,
          borderRadius: BorderRadius.circular(16),
          child: fan,
        );
      },
    );
  }

  Widget _buildFannedCard(
    BuildContext context,
    int i,
    double delta,
    double w,
    double h,
  ) {
    final absDelta = delta.abs();
    final isActive = absDelta < 0.5;

    final rotation = delta * 0.08; // ~4.5° par rang
    final offsetX = delta * (w * 0.22);
    final offsetY = math.min(absDelta * 14.0, 42.0);
    final scale = math.max(0.55, 1.0 - absDelta * 0.07);
    final opacity = math.max(0.0, 1.0 - absDelta * 0.32).clamp(0.0, 1.0);

    return Transform(
      transform: Matrix4.identity()
        ..translateByDouble(offsetX, offsetY, 0, 1)
        ..rotateZ(rotation)
        ..scaleByDouble(scale, scale, 1, 1),
      alignment: Alignment.bottomCenter,
      child: Opacity(
        opacity: opacity,
        child: SizedBox(
          width: w,
          height: h,
          // §3c Phase 2 — Sur TV, les InkWell des cartes empilées sont exclus du
          // focus : seule la cible unique (FocusableChip du build) est focusable.
          child: ExcludeFocus(
            excluding: PlatformTv.isTv,
            child: _HeroFanCard(
              versions: widget.featured[i],
              type: widget.type,
              isActive: isActive,
              onTap: () => _onCardTap(context, i),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDots() {
    final n = widget.featured.length;
    final currentIdx = ((_current.round() % n) + n) % n;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(n, (i) {
        final active = i == currentIdx;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active ? kAccentPrimary : Colors.white.withAlpha(120),
            borderRadius: BorderRadius.circular(3),
            boxShadow: active
                ? [BoxShadow(color: kAccentPrimary.withAlpha(180), blurRadius: 6)]
                : null,
          ),
        );
      }),
    );
  }
}

class _HeroFanCard extends StatelessWidget {
  final List<M3uEntry> versions;
  final M3uContentType type;
  final bool isActive;
  final VoidCallback onTap;

  const _HeroFanCard({
    required this.versions,
    required this.type,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final entry = versions.first;
    final progress = WatchProgressService.getProgressForAny(
      versions.map((e) => e.url),
    );
    final hasResume = progress != null && progress.ratio < 0.95;
    final logoUrl = versions
        .map((e) => e.logoUrl)
        .firstWhere((l) => l != null && l.isNotEmpty, orElse: () => null);

    final fallbackIcon = switch (type) {
      M3uContentType.movie => Icons.movie_outlined,
      M3uContentType.series => Icons.tv_outlined,
      M3uContentType.tv => Icons.live_tv_outlined,
    };

    // §heroFan 3D — fond blanc visible comme tranche de carte (padding 3 px)
    // + box-shadow stack pour simuler l'épaisseur "papier empilé" sur la carte
    // active (les voisines gardent une ombre douce simple pour ne pas saturer).
    final shadows = isActive
        ? const <BoxShadow>[
            // Tranche : 5 ombres "dures" (blurRadius=0) qui s'enchaînent en
            // diagonale → tranche d'une carte épaisse vue de 3/4.
            BoxShadow(color: Color(0xFFEDEDED), offset: Offset(1, 1.5), blurRadius: 0),
            BoxShadow(color: Color(0xFFD2D2D2), offset: Offset(2, 3), blurRadius: 0),
            BoxShadow(color: Color(0xFFA8A8A8), offset: Offset(3, 4.5), blurRadius: 0),
            BoxShadow(color: Color(0xFF7E7E7E), offset: Offset(4, 6), blurRadius: 0),
            BoxShadow(color: Color(0xFF4A4A4A), offset: Offset(5, 7.5), blurRadius: 0),
            // Ombre portée principale (douce, sous le stack).
            BoxShadow(
              color: Color(0xCC000000),
              offset: Offset(8, 14),
              blurRadius: 24,
            ),
          ]
        : <BoxShadow>[
            BoxShadow(
              color: Colors.black.withAlpha(140),
              offset: const Offset(4, 6),
              blurRadius: 12,
            ),
          ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white, // → visible en tranche grâce au padding 3 px.
        borderRadius: BorderRadius.circular(14),
        boxShadow: shadows,
      ),
      padding: const EdgeInsets.all(3),
      child: ClipRRect(
        // Rayon intérieur (= 14 - 3) pour des coins concentriques propres.
        borderRadius: BorderRadius.circular(11),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
            if (logoUrl != null && logoUrl.isNotEmpty)
              Image.network(
                logoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallback(fallbackIcon),
              )
            else
              _fallback(fallbackIcon),
            // Gradient sombre en bas pour la lisibilité du titre.
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withAlpha(210),
                  ],
                ),
              ),
            ),
            if (hasResume)
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: kAccentSecondary.withAlpha(230),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: kAccentSecondary.withAlpha(120),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.play_arrow, size: 14, color: Colors.black),
                      SizedBox(width: 2),
                      Text(
                        'REPRENDRE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Positioned(
              left: 10,
              right: 10,
              bottom: hasResume ? 12 : 10,
              child: Text(
                entry.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  shadows: [
                    Shadow(
                        blurRadius: 4,
                        color: Colors.black.withAlpha(220)),
                  ],
                ),
              ),
            ),
            if (hasResume)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: progress.ratio,
                  backgroundColor: Colors.black.withAlpha(130),
                  valueColor: AlwaysStoppedAnimation(kAccentSecondary),
                  minHeight: 4,
                ),
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fallback(IconData icon) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kAccentPrimary.withAlpha(35),
            kAccentSecondary.withAlpha(35),
          ],
        ),
      ),
      child: Center(
        child: Icon(icon, size: 70, color: Colors.white.withAlpha(80)),
      ),
    );
  }
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
                  // §tvZoom — Colonnes pilotées par la largeur réelle
                  // (3 sur smartphone, 6-8 sur TV/large) → plus de chaînes
                  // visibles au lieu de gros logos zoomés.
                  const spacing = 8.0;
                  final cols = _responsiveColumns(constraints.maxWidth, channel: true);
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
                return SizedBox(
                  height: cardW * 1.5 + vSlack,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: PlatformTv.isTv ? Clip.none : Clip.hardEdge,
                    padding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: PlatformTv.isTv ? 24 : 0,
                    ),
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
                        versions: groups[i],
                        type: type,
                        width: cardW,
                      );
                    },
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
    return FocusableCard(
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

class _CategoryListPageState extends State<CategoryListPage> {
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
    final show = _scrollController.hasClients && _scrollController.offset > 1200;
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
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              const spacing = 10.0;
              // §tvZoom — Colonnes pilotées par la largeur réelle (3 sur
              // smartphone, 6-9 sur TV/large) au lieu de plafonner à 5 → la
              // page « Voir tout » n'affiche plus de vignettes géantes sur TV.
              final width = constraints.maxWidth - 24;
              final cols = _responsiveColumns(constraints.maxWidth, channel: isTv);
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
                        messenger.showSnackBar(SnackBar(
                          content: const Text('Reprise oubliée'),
                          duration: const Duration(seconds: 4),
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
    // §Ultimate — fallback affiche TMDB quand le M3U ne fournit aucun tvg-logo.
    final logoUrl = widget.versions
        .map((e) => e.logoUrl)
        .firstWhere((l) => l != null && l.isNotEmpty, orElse: () => null)
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

    if (totalGroups == 0) {
      // §12-b — Empty state unifié pour la recherche.
      return EmptyState(
        icon: Icons.search_off,
        title: 'Aucun résultat',
        subtitle: 'Rien à afficher pour "$query". Essaie un autre mot-clé ou vérifie l\'orthographe.',
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

    // §URGENT — dédup qualité dans les groupes TV (cohérent avec _TypePage)
    if (type == M3uContentType.tv) {
      for (final k in byGroup.keys.toList()) {
        byGroup[k] = dedupeTvVersions(byGroup[k]!);
      }
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
          padding: EdgeInsets.fromLTRB(
              16, MediaQuery.of(context).padding.top + 80, 16, 24),
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
                      child: (last.logoUrl != null && last.logoUrl!.isNotEmpty)
                          ? Image.network(last.logoUrl!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(
                                  Icons.live_tv,
                                  color: Colors.white54))
                          : const Icon(Icons.live_tv, color: Colors.white54),
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
