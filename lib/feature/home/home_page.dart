import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:aetherStream/core/diagnostics/jank_meter.dart';
import 'package:aetherStream/core/diagnostics/log_buffer.dart';
import 'package:aetherStream/core/settings/performance_settings_service.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/services/favorites_service.dart';
import 'package:aetherStream/data/services/last_watched_channel_service.dart';
import 'package:aetherStream/data/services/parsed_playlist_service.dart';
import 'package:aetherStream/data/services/playlist_reload_service.dart';
import 'package:aetherStream/data/services/playlist_service.dart';
import 'package:aetherStream/data/services/search_history_service.dart';
import 'package:aetherStream/data/services/stream_account_service.dart';
import 'package:aetherStream/data/services/tmdb_api_service.dart';
import 'package:aetherStream/data/services/tmdb_poster_cache.dart';
import 'package:aetherStream/data/services/tmdb_group_alias_service.dart';
import 'package:aetherStream/data/services/tmdb_service.dart';
import 'package:aetherStream/data/services/watch_progress_service.dart';
import 'package:aetherStream/feature/accounts/accounts_page.dart';
import 'package:aetherStream/feature/downloads/logic/download_initiator.dart';
import 'package:aetherStream/feature/player/player_page.dart';
import 'package:aetherStream/feature/search/actor_details_page.dart';
import 'package:aetherStream/feature/search/details_page.dart';
import 'package:aetherStream/feature/settings/settings_page.dart';
import 'package:aetherStream/feature/search/m3u_filter.dart';
import 'package:aetherStream/widgets/aether_image.dart';
import 'package:aetherStream/widgets/confirm_reload_dialog.dart';
import 'package:aetherStream/widgets/media_action_sheet.dart';
import 'package:aetherStream/widgets/media_chips.dart';
import 'package:aetherStream/widgets/measured_quality_badge.dart';
import 'package:aetherStream/data/services/inferred_category_service.dart';
import 'package:aetherStream/widgets/empty_state.dart';
import 'package:aetherStream/widgets/tv/focusable_card.dart';
import 'package:aetherStream/widgets/tv/tv_initial_focus.dart';
import 'package:aetherStream/widgets/tv/focusable_chip.dart';
import 'package:aetherStream/widgets/tv/tv_adaptive_modal.dart';
import 'package:dpad/dpad.dart';
import 'package:aetherStream/core/utils/platform_tv.dart';
import 'package:aetherStream/core/utils/app_snackbar.dart';
import 'package:aetherStream/core/utils/user_error.dart';
import 'package:aetherStream/main.dart' show appRouteObserver;

// §lotD — Découpage du fichier (3400+ lignes) en `part` : même librairie, donc
// les classes privées (_HomeCard, _HeroFanBanner…) restent partagées sans
// changer leur visibilité. Les imports ci-dessus couvrent aussi les parts.
part 'home_card.dart';
part 'home_hero_fan.dart';
part 'home_category.dart';
part 'home_search.dart';

/// Page d'accueil — design streaming premium (§1b phases 2 + 3, §navUX).
///
/// Layout (§navUX — hero en TOP, tabs SOUS le hero) :
///   AppBar              (⚙️ uniquement, transparente posée sur le fond)
///   PageView de _TypePage
///     ↳ _HeroFanBanner  (jeu de cartes empilées — TOUTES les pages, §heroUnify)
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

  /// §unloadGuard — Vrai tant que l'accueil est la route VISIBLE (aucune route
  /// empilée par-dessus).
  ///
  /// Lu par le timer de déchargement de `MainNavigation` : décharger les listes
  /// secondaires pendant que l'accueil est affiché le **vide sous les yeux de
  /// l'utilisateur** — plus de catégories, plus de vignettes — et rien ne les
  /// recharge, puisque la ré-hydratation §lazyUnload est accrochée à
  /// `didPopNext`, qui ne se produit jamais si on ne quitte pas la page.
  static bool isForeground = false;

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

class _HomePageState extends State<HomePage> with RouteAware {
  static const int _initialPageIndex = 1; // Films par défaut

  late final PageController _pageController;
  int _currentIndex = _initialPageIndex;
  /// §initBoot — Initialement `true` UNIQUEMENT si la playlist active n'a pas
  /// encore été parsée (cas rares : changement de compte runtime, hot reload).
  /// Au boot normal, `main._initializeApp` a déjà appelé `loadActive` → la
  /// home apparait sans spinner intermédiaire (pas de flash hors-écran
  /// AetherStream).
  bool _loading = false;

  /// §perfBg — Écoute manuelle des notifiers globaux (playlist / favoris /
  /// progression) pour pouvoir IGNORER les notifications quand la home est en
  /// arrière-plan (player devant). Avant : un `ListenableBuilder` rebuild la
  /// home toutes les ~10 s (le player sauve la progression périodiquement) →
  /// repaints invisibles = saccades sur TV. Maintenant : `_inBackground` gate
  /// l'appel à `setState` ; on rattrape une éventuelle MAJ ratée à la sortie
  /// via `_pendingRefresh`.
  late final Listenable _homeListenable;
  bool _inBackground = false;
  bool _pendingRefresh = false;

  /// Compte actif courant — peut changer en cours de session si l'utilisateur
  /// modifie la priorité dans `AccountsPage`. On lit la valeur initiale dans
  /// [widget.initialData], puis on l'aligne sur le notifier.
  late String _activeAccountId;
  late String _activeAccountName;

  /// §reloadKeep — Vrai pendant un rechargement lancé par le ↻ de l'AppBar :
  /// le bouton est désactivé, un second tap ne relance pas un téléchargement.
  bool _refreshing = false;

  // ── État du mode recherche ─────────────────────────────────────────────
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _searchQuery = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _initialPageIndex);
    // §dpadNav — Sur TV, on épingle la PageView (cf. _pinPageOnTv) : l'auto-scroll
    // de dpad ne doit pas la faire glisser vers Séries/Chaînes.
    if (PlatformTv.isTv) _pageController.addListener(_pinPageOnTv);
    _searchCtrl.addListener(_onSearchTextChanged);
    _searchFocus.addListener(_onSearchFocusChanged);
    _activeAccountId = widget.initialData.accountId;
    _activeAccountName = widget.initialData.accountName;
    // §initBoot — Si la playlist active a déjà été parsée par `_initializeApp`,
    // on saute le spinner ; sinon on l'affiche le temps que `_ensureLoaded`
    // termine (cas hot reload / changement de compte runtime).
    if (_activeAccountId.isNotEmpty &&
        ParsedPlaylistService.getAccount(_activeAccountId) == null) {
      _loading = true;
    }
    _ensureLoaded(initialPath: widget.initialData.path);
    StreamAccountService.currentAccountIdNotifier
        .addListener(_onCurrentAccountChanged);

    // §perfBg — Écoute manuelle gated par _inBackground (cf. doc du champ).
    // §perfSettings — les réglages d'optimisation (hero, vignettes/rangée)
    // rebuildent la home en live comme le reste.
    _homeListenable = Listenable.merge([
      ParsedPlaylistService.version,
      FavoritesService.version,
      WatchProgressService.version,
      PerformanceSettingsService.config,
      // §inferredCat — notifieur GROUPÉ (une fois toutes les 5 s au plus), donc
      // sûr à mettre ici : il entre dans la clé de regroupement.
      InferredCategoryService.version,
      // §tmdbMerge — La table de fusion change la CLÉ de regroupement : sans
      // elle ici, l'accueil garderait son regroupement mémoïsé d'avant fusion.
      TmdbGroupAliasService.version,
    ]);
    _homeListenable.addListener(_onHomeNotifier);

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // §perfBg — Abonnement RouteAware : permet de savoir si une route est
    // poussée par-dessus la home (player → didPushNext) pour ignorer les
    // notifications playlist/favoris/progression pendant la lecture.
    final route = ModalRoute.of(context);
    if (route is PageRoute) appRouteObserver.subscribe(this, route);
    // §unloadGuard — L'accueil est visible dès qu'il est monté ; `didPopNext`
    // n'est appelé qu'au RETOUR d'une autre route, jamais à la première
    // apparition.
    HomePage.isForeground = true;
  }

  @override
  void didPushNext() {
    _inBackground = true;
    HomePage.isForeground = false;
    // §perfBgFull — Cancel debounce recherche (timer de 220 ms pendant frappe) :
    // sinon il peut fire pendant la lecture et provoquer un setState dans la
    // home invisible derrière le player → CPU pour rien + contention décodeur.
    _searchDebounce?.cancel();
    _searchDebounce = null;
  }

  @override
  void didPopNext() {
    _inBackground = false;
    HomePage.isForeground = true;
    // §lazyUnload — Si des comptes secondaires ont été déchargés pendant qu'on
    // était sur le player, on les re-précharge depuis le cache disque JSON.gz
    // (~50 ms par compte). Idempotent : skip ceux déjà en mémoire.
    _rehydrateSecondariesIfNeeded();
    // Rejouer une éventuelle notification ignorée pendant l'arrière-plan.
    if (_pendingRefresh && mounted) {
      _pendingRefresh = false;
      setState(() {});
    }
  }

  Future<void> _rehydrateSecondariesIfNeeded() async {
    try {
      final accounts = await StreamAccountService.listAccounts();
      final current  = await StreamAccountService.getCurrentAccount();
      final others   = accounts.where((a) => a.id != current?.id).toList();
      if (others.isEmpty) return;
      // Vérifie qu'au moins un compte secondaire a été déchargé.
      final missing = others.any(
          (a) => ParsedPlaylistService.getAccount(a.id) == null);
      if (!missing) return;
      await ParsedPlaylistService.preloadOthersFromDisk(others);
    } catch (_) {/* silent — pas de cache disque = re-DL au prochain boot */}
  }

  void _onHomeNotifier() {
    if (_inBackground) {
      _pendingRefresh = true;
      return;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    _homeListenable.removeListener(_onHomeNotifier);
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
    // §jankMeter + §tabSwitchCost — Le changement d'onglet est le geste que
    // l'utilisateur décrit comme « lourd ». La fenêtre se referme après la
    // transition, et la purge de la sonde laisse encore remonter les frames
    // de reconstruction — qui sont justement les plus chères.
    JankMeter.beginSpan('onglet $_currentIndex → $i');
    if (PlatformTv.isTv) {
      // §dpadNav — Changement de section INSTANTANÉ sur TV (pas de glissement
      // horizontal de la PageView, donc plus de « secousse »). On fixe l'index
      // AVANT le jump pour que le pin (_pinPageOnTv) ne l'annule pas.
      if (_currentIndex != i) setState(() => _currentIndex = i);
      _pageController.jumpToPage(i);
      // §3c Phase 2 — L'ancienne page (qui portait le chip d'onglet focusé) est
      // exclue du focus → on ré-acquiert une cible dans la page désormais
      // visible, sinon le focus reste en limbo.
      //
      // ⚠️ §tvExitPage — Cette ré-acquisition vivait dans `onPageChanged`, ce
      // qui la déclenchait à CHAQUE notification de la vue, y compris le
      // rebond du pin après une dérive : le focus était alors déplacé sans que
      // l'utilisateur ait rien demandé. Sur TV, seul `_goToPage` est un
      // changement d'onglet VOULU — c'est donc ici, et nulle part ailleurs.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) FocusScope.of(context).nextFocus();
        JankMeter.endSpan();
      });
      return;
    }
    _pageController
        .animateToPage(
          i,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeInOut,
        )
        .then((_) => JankMeter.endSpan());
  }

  /// §dpadNav — TV : repince la PageView sur la page courante dès qu'un
  /// auto-scroll dpad (`ensureVisible`) la pousse de quelques pixels (ce qui
  /// donnait l'effet de saut ←/→ vers Séries/Chaînes quand on navigue dans une
  /// rangée). Corrigé dans la même frame → aucun flicker visible. Le changement
  /// d'onglet volontaire passe `_currentIndex` d'abord (cf. _goToPage) → non annulé.
  void _pinPageOnTv() {
    if (!_pageController.hasClients) return;
    final page = _pageController.page;
    if (page == null || page == _currentIndex.toDouble()) return;
    // §tvExitPage — trace : savoir QUI pousse la PageView hors de son index.
    DiagnosticLog.trace(
        '📄 pin: PageView à ${page.toStringAsFixed(3)} → retour sur $_currentIndex');
    _pageController.jumpToPage(_currentIndex);
  }

  /// §3c Phase 2 + §tabBack — Wrappe une page du PageView : retire du focus les
  /// pages non visibles (offstage) et scope la traversée directionnelle à la
  /// page courante.
  ///
  /// §tabBack — Ce garde-fou était **réservé à la TV** (`if (!PlatformTv.isTv)
  /// return wrapped;`), et c'est ce qui produisait le bug « Retour = un onglet
  /// vers la gauche » signalé sur téléphone : on quitte une fiche depuis
  /// Chaînes et on revient sur Films ; depuis Films, on revient sur Séries.
  ///
  /// Mécanique : au dépilement, le repli de focus de `dpad`
  /// (`DpadMarks.initialCandidate`) vise le **premier nœud marqué `entry` du
  /// scope**. Les pages voisines de la `PageView` sont construites et, sur
  /// mobile, restaient **focusables** — le premier `entry` disponible est donc
  /// celui de la page d'INDEX INFÉRIEUR, c'est-à-dire celle de gauche. Le focus
  /// y atterrit, `DpadScroll.ensureVisible` remonte tous les scrollables
  /// ancêtres… dont la `PageView`, qui glisse jusqu'à lui. D'où le décalage
  /// d'exactement un onglet, toujours vers la gauche.
  ///
  /// ⚠️ On active donc `ExcludeFocus` sur **toutes** les plateformes : une page
  /// hors écran ne doit jamais être candidate au focus, la question n'a rien de
  /// spécifique à la TV.
  /// ⚠️ En revanche l'autre garde-fou, `_pinPageOnTv`, reste **TV seulement** :
  /// il ramène la `PageView` sur `_currentIndex` à chaque frame où elle s'en
  /// écarte, ce qui combattrait le **glissement au doigt** sur mobile. Retirer
  /// la cible du focus suffit ; épingler la vue casserait le swipe.
  Widget _pageFocusWrap(int index, Widget child) {
    // §pageSmooth — RepaintBoundary isole le layer de chaque page → pendant le
    // slide horizontal, peindre une page ne re-peint pas l'autre (compositing
    // moins coûteux = moins de saccades sur les pages lourdes carrousels+hero).
    final wrapped = RepaintBoundary(child: child);
    // §dpadNav — Chaque page = une `DpadRegion` (nav par régions + mémoire,
    // remplace l'ancienne FocusTraversalGroup/_TvRailsTraversalPolicy qui
    // entrait en conflit avec le moteur dpad). ExcludeFocus garde les pages
    // offstage (PageView adjacentes) hors du focus.
    return ExcludeFocus(
      excluding: _currentIndex != index,
      child: DpadRegion(debugLabel: 'homePage$index', child: wrapped),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
  }

  /// §refreshHome — Re-télécharge la liste du compte actif (pipeline §xtreamApi :
  /// JSON API puis fallback get.php) et la re-parse. Tient l'utilisateur au
  /// courant via snackbars succès/erreur.
  ///
  /// §reloadKeep — Passe par `PlaylistReloadService.reloadAccount`, le MÊME
  /// chemin que « Recharger » d'une carte : plus de `deleteForAccountId` à la
  /// main avant le téléchargement, donc un échec réseau laisse l'ancienne liste
  /// en place au lieu de vider l'accueil. Même confirmation si la liste a moins
  /// de 24 h, même anti-double-tap ([_refreshing]).
  Future<void> _refreshActivePlaylist() async {
    if (_refreshing) return;
    final account = await StreamAccountService.getAccount(_activeAccountId);
    if (!mounted) return;
    if (account == null) {
      AppSnackBar.show(context, 'Aucun compte actif à recharger');
      return;
    }

    final Duration? age = await PlaylistReloadService.cacheAge(account.id);
    if (!mounted) return;
    if (PlaylistReloadService.shouldConfirm(age)) {
      final bool? ok = await showConfirmReloadDialog(
        context,
        accountLabel: account.label,
        age: age!,
      );
      if (ok != true || !mounted) return;
    }

    setState(() => _refreshing = true);
    final messenger = ScaffoldMessenger.of(context);
    AppSnackBar.show(context, 'Rafraîchissement de la playlist…',
        duration: const Duration(seconds: 4));
    try {
      // Le compte actif = le compte principal → chemin `downloadCurrentM3U()`
      // (messages d'erreur précis). `reloadFromDisk` swap la mémoire en une
      // frame et bumpe `ParsedPlaylistService.version` → la home rebuild seule.
      await PlaylistReloadService.reloadAccount(account, isPriority: true);
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('✅ Playlist rafraîchie'),
          duration: Duration(seconds: 2),
        ));
    } catch (e) {
      if (!mounted) return;
      // §userError — jamais `$e` brut à l'écran (URL + identifiants Xtream).
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('❌ ${describeError(e)}'),
          duration: const Duration(seconds: 4),
        ));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    // §heroFan ergo / §heroUnify — Le hero "fan" (désormais utilisé par TOUTES
    // les pages, y compris Chaînes) remonte jusqu'au status bar : l'inclinaison
    // des cartes laisse le coin haut-droit libre pour les icônes refresh/⚙️ qui
    // flottent par-dessus. Même topInset partout → zéro saut vertical au swipe.
    final liftedTopInset = statusBarHeight + 4;

    return Scaffold(
      extendBodyBehindAppBar: true,
      // §searchTopGap — En mode recherche, PAS d'AppBar : elle ne portait qu'un
      // petit arrow_back et réservait toute une rangée `kToolbarHeight` au-dessus
      // du champ (espace vide gênant). L'arrow_back est désormais intégré DANS la
      // rangée du champ (cf. `searchBody`), et le champ remonte juste sous la
      // status bar. En mode navigation, l'AppBar transparente habituelle (hero
      // derrière + refresh/⚙️).
      appBar: widget.searchMode
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              scrolledUnderElevation: 0,
              elevation: 0,
              // §navUX — Plus de nom de compte dans le title (déjà visible dans
              // SettingsPage → Comptes IPTV). Ça libère la barre du haut.
              title: null,
              // §3c-bis — Sur TV, l'icône ⚙️ est redondante avec la destination
              // "Paramètres" du NavigationRail latéral.
              actions: [
                // §loadingLine — Le décompte des listes en cours de chargement
                // a quitté le bandeau pour venir ici : même information, zéro
                // hauteur prise à l'accueil.
                const SecondaryAccountsCounter(),
                // §refreshHome — Rafraîchissement du compte actif sans passer
                // par Paramètres → Comptes IPTV.
                IconButton(
                  icon: _refreshing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  tooltip: 'Recharger la playlist',
                  // §reloadKeep — désactivé pendant le rechargement (anti-double-tap).
                  onPressed: _refreshing ? null : _refreshActivePlaylist,
                ),
                if (!PlatformTv.isTv)
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
            : Builder(
                builder: (context) {
                  // §perfBigList — split mémoïsé : recalculé seulement quand la
                  // playlist ou le compte change, PAS à chaque bump Favoris /
                  // WatchProgress. §perfBg — le rebuild de la home est déclenché
                  // via `_onHomeNotifier` (`setState` gated par `_inBackground`).
                  final byType = _byTypeMemoized();

                  // §tabPersist — On garde le PageView (browse) MONTÉ en
                  // permanence via un IndexedStack : entrer/sortir de la
                  // recherche ne détache plus le `_pageController` → l'onglet
                  // sélectionné ne se réinitialise plus à Films (bug "retour à
                  // Films" au toggle recherche). La recherche est un calque
                  // frère, pas un remplacement de l'arbre.
                  // §1L-a — Grand champ recherche dans le body (sous l'AppBar
                  // transparente) au lieu d'un mini-champ dans le title.
                  final Widget searchBody = Column(
                      children: [
                        // §searchTopGap — juste la status bar + petite marge
                        // (avant : + kToolbarHeight, qui poussait le champ très
                        // bas pour rien). L'arrow_back est inline avec le champ.
                        SizedBox(height: MediaQuery.of(context).padding.top + 6),
                        Padding(
                          // §searchGap — bottom réduit (12 → 8) : combiné au
                          // `top: 4` de l'en-tête de section, il ne reste que
                          // ~12 px entre l'input et le premier résultat.
                          padding: const EdgeInsets.fromLTRB(4, 4, 16, 8),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back),
                                tooltip: 'Quitter la recherche',
                                onPressed: () => widget.onExitSearch?.call(),
                              ),
                              Expanded(child: _buildSearchField(cs)),
                            ],
                          ),
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

                  final Widget browseBody = Stack(
                    children: [
                      Positioned.fill(
                        child: PageView(
                    // §tabPersist — restaure la page courante si le PageView est
                    // recréé (ex: cycle `_loading` lors d'un changement de
                    // compte / refresh) → l'onglet ne retombe pas sur Films.
                    key: const PageStorageKey('homeTypePages'),
                    controller: _pageController,
                    // §3c-7 — Sur TV : pas de swipe horizontal (la nav
                    // Films/Séries/Chaînes se fait via les tabs cliquables
                    // au D-pad, sinon le focus tombe dans le PageView qui
                    // scrolle dans tous les sens).
                    physics: PlatformTv.isTv
                        ? const NeverScrollableScrollPhysics()
                        : const _FastPageScrollPhysics(),
                    // §heroSwipePerf — Pré-construit/peint les pages adjacentes
                    // (hors écran) → la page entrante n'est plus peinte À FROID
                    // au démarrage du swipe (le hero fan = ~7 cartes avec
                    // saveLayer + ombres floutées, très coûteux au 1er paint).
                    // Supprime la saccade de début de glissement.
                    allowImplicitScrolling: true,
                    onPageChanged: (i) {
                      // §tvExitPage — Sur TV, la `PageView` ne bouge JAMAIS
                      // d'elle-même : le swipe y est désactivé
                      // (`NeverScrollableScrollPhysics`) et tout changement
                      // d'onglet volontaire passe par `_goToPage`, qui fixe
                      // `_currentIndex` **avant** le saut. Sur TV, la vue n'est
                      // donc jamais la source de vérité de l'onglet courant :
                      // un `onPageChanged` qui s'en écarte est, par
                      // construction, une DÉRIVE — l'auto-scroll de focus
                      // (`DpadScroll.ensureVisible` remonte TOUS les
                      // scrollables ancêtres, `PageView` comprise). Mesuré sur
                      // émulateur Android TV : « 📄 pin: PageView à 1.010 » à
                      // chaque déplacement dans une rangée.
                      //
                      // ⚠️ L'adopter était le vrai piège : `_currentIndex`
                      // devenait la dérive, et `_pinPageOnTv` — censé protéger
                      // l'onglet — se mettait à DÉFENDRE le mauvais. On sortait
                      // d'une chaîne et on restait bloqué sur « Films ».
                      if (PlatformTv.isTv) {
                        if (i != _currentIndex) {
                          DiagnosticLog.trace(
                              '📄 onPageChanged REJETÉ (dérive) : $i ≠ $_currentIndex');
                          _pinPageOnTv();
                        }
                        return;
                      }
                      DiagnosticLog.trace(
                          '📄 onPageChanged: $_currentIndex → $i');
                      setState(() => _currentIndex = i);
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
                          // §heroUnify — même topInset que films/séries → le
                          // hero fan des Chaînes démarre à la même hauteur (plus
                          // de saut vertical au swipe). `defaultTopInset` n'est
                          // plus utilisé que par le calcul (gardé pour réf).
                          topInset: liftedTopInset,
                          tabsBuilder: buildTabs,
                        ),
                      ),
                    ],
                        ),
                      ),
                      // §loadingLine — Témoin de chargement des listes
                      // secondaires, en SURIMPRESSION (cf. la classe).
                      const Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        child: _SecondaryAccountsProgressLine(),
                      ),
                    ],
                  );

                  // §tabPersist — Browse (PageView) en index 0 = toujours
                  // monté ; recherche en index 1. StackFit.expand pour que les
                  // Column(Expanded) reçoivent une hauteur bornée. ExcludeFocus
                  // sur l'enfant caché → le D-pad TV ne tombe pas dans la page
                  // invisible.
                  return IndexedStack(
                    sizing: StackFit.expand,
                    index: widget.searchMode ? 1 : 0,
                    children: [
                      ExcludeFocus(excluding: widget.searchMode, child: browseBody),
                      ExcludeFocus(excluding: !widget.searchMode, child: searchBody),
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

class _AnimatedTabIndicator extends StatelessWidget {
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

  static const _labels = ['Séries', 'Films', 'Chaînes'];
  // §navHeight — Barre plus haute + police plus grande : meilleure cible
  // tactile et lisibilité (l'ancienne 26px/20px était petite à viser).
  static const double _barHeight = 38;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // §navUX — Le tab indicator est injecté SOUS le hero dans la liste de
    // _TypePage, donc plus besoin d'offset status bar (le ListView gère son
    // padding-top via widget.topInset).
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final tabWidth = constraints.maxWidth / 3;

          return SizedBox(
            height: _barHeight,
            child: Stack(
              children: [
                Row(
                  children: List.generate(3, (i) {
                    final active = i == currentIndex;
                    final isEmpty = counts[i] == 0;
                    final color = isEmpty
                        ? cs.onSurface.withAlpha(60)
                        : active
                            ? cs.onSurface
                            : cs.onSurfaceVariant;
                    // §3c Phase 1 — FocusableChip rend l'onglet atteignable au
                    // D-pad (avant : GestureDetector tap-only → impossible de
                    // changer de section Séries/Films/Chaînes à la télécommande).
                    //
                    // §emptyTab — Un onglet VIDE reste grisé mais focusable et
                    // tapable : il mène à l'`EmptyState` de la page (explication
                    // + CTA « Gérer les comptes ») au lieu de ne rien faire. Les
                    // trois `_TypePage` existent toujours dans la `PageView`,
                    // et `_buildEmpty` garde la barre d'onglets pour revenir.
                    return Expanded(
                      child: FocusableChip(
                        onTap: () => onTap(i),
                        borderRadius: BorderRadius.circular(8),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onTap(i),
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                            style: TextStyle(
                              fontSize: active ? 22 : 16,
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
                // §pageSmooth — Underline piloté par un AnimatedBuilder écoutant
                // le PageController : SEUL l'underline se re-peint à chaque frame
                // du swipe (avant : `setState` de TOUTE la barre 60×/s sur 2
                // instances → jank). Le reste (textes/tabs) ne rebuild qu'au
                // commit d'onglet (currentIndex).
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: controller,
                    builder: (ctx, _) {
                      final page = controller.hasClients
                          ? (controller.page ?? currentIndex.toDouble())
                          : currentIndex.toDouble();
                      return Align(
                        alignment: Alignment.bottomLeft,
                        child: Padding(
                          padding: EdgeInsets.only(
                              left: page * tabWidth + tabWidth * 0.3),
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
                      );
                    },
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

/// §loadingLine — Témoin de chargement des listes secondaires.
///
/// **Ce que ça remplace, et pourquoi.** C'était un bandeau pleine largeur
/// (`_SecondaryAccountsLoadingBanner`) posé DANS la colonne, au-dessus du
/// `PageView` : il réservait la hauteur de la barre d'état + une roue de 14 px
/// + une phrase de 12 px. Il ne prenait donc pas seulement de la place — il
/// **décalait toute l'accueil vers le bas**, puis, l'hydratation terminée,
/// disparaissait d'un coup et la page **remontait**. Ce saut se lit comme un
/// défaut d'affichage, alors que tout allait bien.
///
/// Ici, le témoin est en **surimpression** : un filet de 2 px sous la barre
/// d'état. Coût vertical **zéro**, donc plus rien ne bouge quand il s'en va.
/// Le décompte, lui, vit dans la barre du haut ([SecondaryAccountsCounter]) —
/// il n'a pas disparu, il a changé de place.
class _SecondaryAccountsProgressLine extends StatelessWidget {
  const _SecondaryAccountsProgressLine();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, AccountLoadState>>(
      valueListenable: ParsedPlaylistService.loadStates,
      builder: (ctx, states, _) {
        final loading = states.values
            .where((v) =>
                v == AccountLoadState.downloading ||
                v == AccountLoadState.parsing)
            .length;
        if (loading == 0) return const SizedBox.shrink();
        return Padding(
          // Sous la barre d'état : le body passe derrière elle
          // (`extendBodyBehindAppBar`), un filet à 0 serait invisible.
          padding: EdgeInsets.only(top: MediaQuery.of(ctx).padding.top),
          child: SizedBox(
            height: 2,
            child: LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: kAccentPrimary.withAlpha(30),
              valueColor: AlwaysStoppedAnimation<Color>(
                  kAccentPrimary.withAlpha(190)),
            ),
          ),
        );
      },
    );
  }
}

/// §loadingLine — Décompte « n/N » des listes chargées, dans la barre du haut.
///
/// Reprend l'information que portait l'ancien bandeau — savoir pourquoi les
/// contenus d'une liste « manquent » encore — sans lui rendre sa hauteur. Muet
/// dès que tout est chargé.
class SecondaryAccountsCounter extends StatelessWidget {
  const SecondaryAccountsCounter({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, AccountLoadState>>(
      valueListenable: ParsedPlaylistService.loadStates,
      builder: (ctx, states, _) {
        final total = states.length;
        final loading = states.values
            .where((v) =>
                v == AccountLoadState.downloading ||
                v == AccountLoadState.parsing)
            .length;
        if (loading == 0 || total == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '${total - loading}/$total',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: kAccentPrimary.withAlpha(210),
            ),
          ),
        );
      },
    );
  }
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
      // §radioCat — Les webradios passent APRÈS les genres, juste avant
      // « Autres » : elles restent accessibles, sans plus occuper la tête de
      // l'onglet Chaînes.
      case 'Radio':         return 900;
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

  /// §radioCat — La chaîne est-elle une **webradio** ?
  ///
  /// Les catégories « France » et consorts étaient noyées sous les webradios
  /// (RADIO CLASSIQUE, ADO FR, ADO @WORK, CHÉRIE FM, ÉVASION FM…), toutes
  /// affublées du même drapeau tricolore : c'est le PREMIER écran de l'onglet
  /// Chaînes, et les vraies chaînes y devenaient invisibles.
  ///
  /// ⚠️ **Le test porte sur la CATÉGORIE du fournisseur, jamais sur le nom de
  /// la chaîne.** Mesuré sur les listes réelles, une règle par nom
  /// (`\bRADIO\b` / `\bFM\b`) masquerait de VRAIES chaînes de télévision :
  /// `ICI RADIO-CANADA TÉLÉ OTTAWA`, `RADIO CAPITAL TV`, `RADIO BIRIKINA TV`,
  /// `RADIO MONTE CARLO`… Le fournisseur, lui, range ses radios dans un groupe
  /// dédié — c'est un signal exact, et il ne coûte rien de le croire.
  ///
  /// ⚠️ `CANADA` est exclu explicitement : un groupe « RADIO-CANADA » désigne
  /// un diffuseur de télévision, pas un bouquet de radios.
  static final RegExp _reRadioGroup = RegExp(r'\bRADIOS?\b');

  static bool _isRadioChannel(M3uEntry e) {
    final group = (e.groupTitle ?? '').toUpperCase();
    if (group.isEmpty || group.contains('CANADA')) return false;
    return _reRadioGroup.hasMatch(group);
  }

  static IconData categoryIcon(String cat) {
    switch (cat) {
      case 'Favoris':       return Icons.star;
      case 'France':        return Icons.flag_outlined;
      case 'Radio':         return Icons.radio_outlined; // §radioCat
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

/// §tabSwitchCost — Un groupement calculé, conservé HORS de l'état de la page.
///
/// ## Le défaut mesuré
///
/// `PageView(allowImplicitScrolling: true)` ne garde vivantes que les pages
/// `index ± 1` : sur trois onglets, passer de Chaînes à Films **détruit** la
/// page Séries, et y revenir la reconstruit. Or les caches de groupement
/// étaient des champs d'ÉTAT — ils mouraient avec la page. Le retour repayait
/// donc, **dans une seule frame synchrone**, un regroupement O(n) sur toutes
/// les entrées du type plus la composition du hero.
///
/// Relevé sur un Galaxy S25 en build profile (écran 120 Hz, budget 8,3 ms) :
/// **161,9 ms de construction Dart sur UNE frame**, 16 frames ratées sur 18.
/// Vingt budgets d'affilée : ce n'est pas une impression de lourdeur, c'est un
/// blocage.
///
/// ## Pourquoi pas `AutomaticKeepAliveClientMixin`
///
/// C'était le réflexe, et la mesure l'a écarté :
/// - les trois pages sont **déjà vivantes** sur l'onglet Films (le défaut au
///   démarrage) — garder la page n'aurait rien changé au cas le plus courant ;
/// - chaque page vivante épingle ses images décodées dans `ImageCache._liveImages`,
///   qui **échappe au budget** de `PerfConfig.imageCacheMb` ;
/// - `InferredCategoryService.version` avance toutes les ~5 s pendant le
///   défilement d'une liste sans `group-title` : le groupement s'invalide de
///   lui-même, et trois pages vivantes le recalculeraient **trois fois**.
///
/// Ici, rien ne reste vivant en plus : seul le RÉSULTAT survit.
///
/// ⚠️ Le mémo garde le groupement **PUR**, sans la catégorie virtuelle ⭐ :
/// `_ensureFavoriteCategory` mute la map en place (`remove` / `[]=`), donc la
/// page en reçoit une **copie superficielle**. Sans ça, la première page qui
/// affiche des favoris les inscrirait dans le mémo, et les deux autres les
/// hériteraient — y compris après leur suppression.
/// §tabSwitchCost — Le hero composé, conservé hors de l'état de la page.
///
/// ⚠️ Le commentaire d'origine de `_ensureFeatured` annonçait un « cache
/// SÉPARÉ (léger) ». C'est faux : la composition interroge la progression de
/// lecture **pour chaque URL de chaque version de chaque groupe**, donc elle
/// est en O(entrées), pas en O(groupes) — du même ordre que le regroupement
/// lui-même. À chaque page reconstruite, elle repassait entièrement.
///
/// La clé est comparée **champ par champ** plutôt que réduite à une somme :
/// une somme d'entiers se collisionne, et une collision ici afficherait un
/// hero périmé sans qu'on sache pourquoi.
@immutable
class _FeaturedMemo {
  final int groupingKey;
  final int favoritesVersion;
  final int watchVersion;
  final int maxFeatured;

  /// Comparé par IDENTITÉ : `TmdbService.getTrending` rend la même instance
  /// tant que son cache de 24 h est valide.
  final List<TrendingTitle>? trending;

  /// Lecture seule après composition — rien ne le mute, il peut donc être
  /// partagé par référence entre les pages.
  final List<List<M3uEntry>> featured;

  const _FeaturedMemo({
    required this.groupingKey,
    required this.favoritesVersion,
    required this.watchVersion,
    required this.maxFeatured,
    required this.trending,
    required this.featured,
  });

  bool matches({
    required int groupingKey,
    required int favoritesVersion,
    required int watchVersion,
    required int maxFeatured,
    required List<TrendingTitle>? trending,
  }) =>
      this.groupingKey == groupingKey &&
      this.favoritesVersion == favoritesVersion &&
      this.watchVersion == watchVersion &&
      this.maxFeatured == maxFeatured &&
      identical(this.trending, trending);
}

@immutable
class _GroupingMemo {
  /// Identité de la liste d'entrées : `_byTypeMemoized` réutilise la même
  /// instance tant que playlist et compte actif ne changent pas. Comparer par
  /// `identical` couvre donc le changement de compte **sans** que
  /// `_groupingKey()` ait à le connaître — il ne le connaît pas.
  final List<M3uEntry> source;
  final int key;

  /// Retenu à part pour pouvoir jeter les mémos d'une playlist qui n'est plus
  /// chargée : sans ça, ils garderaient en vie tout le graphe d'entrées d'un
  /// compte déchargé, et annuleraient le bénéfice du déchargement.
  final int playlistVersion;

  final Map<String, List<List<M3uEntry>>> byCategory;
  final List<List<M3uEntry>> groups;
  final List<String> categories;

  const _GroupingMemo({
    required this.source,
    required this.key,
    required this.playlistVersion,
    required this.byCategory,
    required this.groups,
    required this.categories,
  });
}

class _TypePageState extends State<_TypePage> {
  /// §tabSwitchCost — Un mémo par type, donc **trois au maximum**.
  static final Map<M3uContentType, _GroupingMemo> _sharedGrouping =
      <M3uContentType, _GroupingMemo>{};

  /// §tabSwitchCost — Un hero composé par type.
  static final Map<M3uContentType, _FeaturedMemo> _sharedFeatured =
      <M3uContentType, _FeaturedMemo>{};

  /// §tabSwitchCost — Les tendances TMDB sont une donnée **du type**, pas de
  /// l'instance de page.
  ///
  /// ⚠️ Sans ça, le mémo du hero ne servait à rien au retour d'onglet : une
  /// page reconstruite repartait avec `_trendingTitles == null`, ne
  /// reconnaissait donc pas le hero mémorisé (composé AVEC les tendances), et
  /// recalculait tout — pour ensuite le recalculer une SECONDE fois quand
  /// `_loadTrending` répondait depuis son cache mémoire, c'est-à-dire
  /// immédiatement. Deux passes O(entrées) par changement d'onglet.
  static final Map<M3uContentType, List<TrendingTitle>> _sharedTrending =
      <M3uContentType, List<TrendingTitle>>{};

  // ⚠️ Pas de `clearSharedGrouping()` de confort : `_TypePageState` est privée
  // à cette bibliothèque, donc aucun test ne peut l'atteindre — et il n'existe
  // AUCUN test sur l'accueil (vérifié : rien dans `test/` ne monte un widget de
  // `feature/home/`). La purge se fait donc là où elle a un sens, dans
  // `_ensureGrouping`, sur la version de playlist. La vérification de ce lot
  // est une MESURE sur appareil, pas une suite de tests.
  // §perfSettings — La limite d'items par carrousel (« Voir tout » au-delà)
  // n'est plus une constante : elle vient de `PerfConfig.maxItemsPerRow`
  // (réglable dans Paramètres → Optimisation). Appliquée au RENDU (take(N)
  // dans l'itemBuilder) → un changement à chaud = simple rebuild, aucune
  // invalidation des caches de groupement.

  // ── Caches (memoization) — §perfBigList ─────────────────────────────────
  // CRUCIAL avec une grosse playlist (Ultimate ~600k entrées) : le GROUPEMENT
  // par catégorie/titre est O(n) sur des centaines de milliers d'entrées. Il ne
  // dépend QUE des entrées + playlist. Le HERO "featured" (reprise)
  // dépend EN PLUS de WatchProgress, qui bump toutes les 10 s en lecture ET au
  // retour du player → on cache les deux SÉPARÉMENT pour ne PAS re-grouper 500k
  // entrées à chaque tick de progression (cause d'un gros freeze au retour du
  // player avec Ultimate).
  //
  // §favAudit (2026-08-05) — Les FAVORIS ont été sortis de la clé de
  // groupement pour la même raison : ils n'influencent qu'une catégorie
  // VIRTUELLE (⭐, qui duplique des groupes déjà calculés). Tant qu'ils en
  // faisaient partie, **chaque appui sur un cœur re-groupait toute la
  // playlist** — le « temps d'attente sur certains favoris » signalé. La
  // rangée ⭐ est désormais recalculée seule (`_ensureFavoriteCategory`), en
  // O(groupes) au lieu de O(entrées) + regroupement + tri.
  Map<String, List<List<M3uEntry>>>? _cachedByCategory;
  List<String>? _cachedCategories;
  List<List<M3uEntry>>? _cachedFeatured;
  /// Liste PLATE de tous les groupes (source de la catégorie ⭐). Nécessaire
  /// séparément : `_cachedByCategory` duplique des groupes ('New', 'Favoris'),
  /// on ne peut donc pas la reconstruire depuis ses valeurs.
  List<List<M3uEntry>>? _cachedGroups;
  int _cachedGroupingKey = -1;
  int _cachedFeaturedKey = -1;
  int _cachedFavoritesKey = -1;

  // §trending — Titres tendance TMDB de la semaine (chargés une fois, cache
  // 24h côté service). Null tant que pas chargé / pas de clé TMDB. Le croisement
  // avec la playlist se fait dans `_ensureFeatured` (titres → groupes dispo).
  //
  // §tabSwitchCost — Stockés par TYPE et non dans l'instance : une page
  // reconstruite les retrouve immédiatement (cf. `_sharedTrending`).
  List<TrendingTitle>? get _trendingTitles => _sharedTrending[widget.type];

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
    // ⚠️ Ne RIEN faire si les tendances n'ont pas bougé. Le service rend la
    // même instance tant que son cache de 24 h tient : sans ce test, chaque
    // montage de page invalidait le hero et relançait une composition
    // O(entrées) pour un résultat identique.
    if (identical(list, _sharedTrending[widget.type])) return;
    setState(() {
      _sharedTrending[widget.type] = list;
      _cachedFeaturedKey = -1; // invalide le hero → recompute avec les tendances
    });
  }

  /// §parseAudit2026-06-30 — Délègue à `TitleMetadata.computeGroupKey`
  /// (unicode-aware : conserve les accents) au lieu d'une regex ASCII-only
  /// dupliquée qui strippait les accents ("Café" → "caf" au lieu de "café") →
  /// pouvait faire échouer silencieusement le matching tendances TMDB sur les
  /// titres accentués alors que la fusion cross-listes M3U (qui utilise déjà
  /// computeGroupKey) fonctionnait pour les mêmes titres. Un seul endroit fait
  /// désormais autorité pour "qu'est-ce qu'un titre normalisé" dans l'app.
  static String _normTitle(String s) => TitleMetadata.computeGroupKey(s);

  /// Clé du GROUPEMENT (coûteux) : entrées + playlist. **PAS** WatchProgress
  /// (sinon re-groupement complet toutes les 10 s en lecture) ni les favoris
  /// (§favAudit — sinon re-groupement complet à chaque cœur).
  int _groupingKey() =>
      widget.entries.length * 1000003 +
      ParsedPlaylistService.version.value * 1009 +
      // §inferredCat — Les catégories déduites changent le RANGEMENT, donc le
      // groupement doit être refait quand elles avancent. Sûr uniquement parce
      // que ce compteur est groupé côté service (cf. §favAudit).
      InferredCategoryService.version.value * 10007 +
      // §tmdbMerge — La table de fusion modifie la CLÉ de chaque groupe : elle
      // doit entrer dans la clé de cache, sinon l'accueil garde le regroupement
      // d'avant fusion jusqu'au prochain changement de playlist.
      TmdbGroupAliasService.version.value * 100003;

  /// Tri des catégories : priorité (Favoris → France → New → …) puis alpha.
  static List<String> _sortCategories(Map<String, dynamic> byCategory) =>
      byCategory.keys.toList()
        ..sort((a, b) {
          final pa = _TypePage._categoryPriority(a);
          final pb = _TypePage._categoryPriority(b);
          if (pa != pb) return pa.compareTo(pb);
          return a.toLowerCase().compareTo(b.toLowerCase());
        });

  /// Groupe par catégorie puis par titre. Mémoïsé sur [_groupingKey], **et**
  /// sur [_sharedGrouping] pour survivre à la destruction de la page
  /// (§tabSwitchCost).
  void _ensureGrouping() {
    final key = _groupingKey();
    if (_cachedByCategory != null && _cachedGroupingKey == key) {
      // Groupement toujours valide, mais un cœur a pu changer entre-temps.
      _ensureFavoriteCategory();
      return;
    }

    // §tabSwitchCost — Le mémo partagé d'abord : c'est lui qui évite de
    // repayer un regroupement complet quand le `PageView` a détruit puis
    // reconstruit cette page.
    final _GroupingMemo? memo = _sharedGrouping[widget.type];
    if (memo != null &&
        memo.key == key &&
        identical(memo.source, widget.entries)) {
      _adoptGrouping(memo, key);
      return;
    }

    final res = _groupByCategoryThenByTitle(widget.entries, widget.type);
    final int playlistVersion = ParsedPlaylistService.version.value;

    // ⚠️ Purge des mémos d'une AUTRE version de playlist : ils retiendraient le
    // graphe d'entrées d'un compte peut-être déchargé depuis.
    _sharedGrouping.removeWhere(
      (_, m) => m.playlistVersion != playlistVersion,
    );
    // Le hero référence les mêmes groupes : le purger avec eux, sinon il
    // retiendrait à lui seul le graphe d'entrées d'un compte déchargé.
    _sharedFeatured.clear();

    final _GroupingMemo fresh = _GroupingMemo(
      source: widget.entries,
      key: key,
      playlistVersion: playlistVersion,
      byCategory: res.byCategory,
      groups: res.groups,
      categories: _sortCategories(res.byCategory),
    );
    _sharedGrouping[widget.type] = fresh;
    _adoptGrouping(fresh, key);
  }

  /// Installe un groupement partagé dans l'état de CETTE page.
  ///
  /// ⚠️ `byCategory` et `categories` sont **copiés**, pas partagés :
  /// `_ensureFavoriteCategory` les mute en place pour injecter la catégorie
  /// virtuelle ⭐. Sans la copie, les favoris d'une page fuiraient dans le
  /// mémo, donc dans les autres pages — et y survivraient à leur suppression.
  /// La copie est superficielle : quelques dizaines d'entrées, aucune liste de
  /// groupe recopiée.
  void _adoptGrouping(_GroupingMemo memo, int key) {
    _cachedByCategory =
        Map<String, List<List<M3uEntry>>>.of(memo.byCategory);
    _cachedGroups = memo.groups;
    _cachedCategories = List<String>.of(memo.categories);
    _cachedGroupingKey = key;
    _cachedFeaturedKey = -1; // groupement changé → forcer le recalcul du hero
    _cachedFavoritesKey = -1; // …et celui de la rangée ⭐
    _ensureFavoriteCategory();
  }

  /// §favAudit — Recalcule la SEULE catégorie virtuelle ⭐ Favoris, mémoïsée sur
  /// `FavoritesService.version`. Coût : un `isEntryFavorite` par groupe (et non
  /// par entrée), sans re-groupement ni re-tri sauf apparition/disparition de
  /// la rangée.
  void _ensureFavoriteCategory() {
    final favKey = FavoritesService.version.value;
    if (_cachedFavoritesKey == favKey) return;
    _cachedFavoritesKey = favKey;

    final byCategory = _cachedByCategory!;
    final hadRow = byCategory.containsKey('Favoris');

    final favorites = <List<M3uEntry>>[];
    for (final group in _cachedGroups!) {
      if (FavoritesService.isEntryFavorite(group.first)) favorites.add(group);
    }

    if (favorites.isEmpty) {
      byCategory.remove('Favoris');
    } else {
      byCategory['Favoris'] = favorites;
    }

    // Le tri ne dépend que du JEU de catégories : inutile de le refaire quand
    // la rangée ⭐ change seulement de contenu.
    if (hadRow != byCategory.containsKey('Favoris')) {
      _cachedCategories = _sortCategories(byCategory);
    }
    // Le hero TV met les chaînes favorites en tête (`byCategory['Favoris']`),
    // et le fallback films/séries parcourt les catégories → à recomposer.
    _cachedFeaturedKey = -1;
  }

  /// Compose le hero "featured" (reprise + nouveautés) à partir du groupement
  /// déjà calculé. Dépend de WatchProgress → cache SÉPARÉ (léger) pour ne pas
  /// re-grouper à chaque tick de progression.
  void _ensureFeatured() {
    // §perfSettings — le nombre de cartes du hero est réglable : il fait
    // partie de la clé de cache pour recomposer le hero quand il change.
    final maxFeatured = PerformanceSettingsService.config.value.heroCardCount;
    final key = WatchProgressService.version.value * 1000003 + maxFeatured;
    if (_cachedFeatured != null && _cachedFeaturedKey == key) return;

    // §tabSwitchCost — Le mémo partagé avant de recomposer : c'est ce qui
    // évite de repayer une passe O(entrées) quand le `PageView` a détruit puis
    // reconstruit cette page.
    final int favoritesVersion = FavoritesService.version.value;
    final int watchVersion = WatchProgressService.version.value;
    final _FeaturedMemo? memo = _sharedFeatured[widget.type];
    if (memo != null &&
        memo.matches(
          groupingKey: _cachedGroupingKey,
          favoritesVersion: favoritesVersion,
          watchVersion: watchVersion,
          maxFeatured: maxFeatured,
          trending: _trendingTitles,
        )) {
      _cachedFeatured = memo.featured;
      _cachedFeaturedKey = key;
      return;
    }

    final byCategory = _cachedByCategory!;
    final categories = _cachedCategories!;

    // §heroFan — Composition du hero :
    //   - films/séries : reprise (triées lastWatched desc) + tendances TMDB
    //     prioritaires non-déjà-incluses → max `maxFeatured` cartes empilées
    //   - TV : pas de notion "en cours" (live) → favoris / catégorie prio
    final maxResume = math.min(8, maxFeatured);
    final featured = <List<M3uEntry>>[];

    if (widget.type != M3uContentType.tv) {
      // §heroFanDedup — La catégorie virtuelle "Favoris" duplique les références
      // de groupes qui vivent aussi dans leur catégorie d'origine. On dédupe
      // pour éviter qu'un film favori en cours de lecture apparaisse 2× dans le
      // hero. §homonymYear — la clé inclut l'année (films splittés par année) :
      // sinon "Vengeance 1990" et "Vengeance 2022" (même displayName) seraient
      // re-fusionnés ici.
      final allGroups = <List<M3uEntry>>[];
      final seenNames = <String>{};
      for (final groups in byCategory.values) {
        for (final group in groups) {
          final dedupKey =
              '${group.first.displayName}|${group.first.title.year ?? ''}';
          if (seenNames.add(dedupKey)) {
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
        // §trendingYear — Un titre peut avoir PLUSIEURS groupes (homonymes
        // splittés par année, §homonymYear). On garde la liste des candidats
        // et on choisit celui dont l'année matche le retour TMDB → fini le
        // "mauvais film d'une autre époque" remonté par le hero Tendances.
        final byName = <String, List<List<M3uEntry>>>{};
        for (final g in allGroups) {
          byName.putIfAbsent(_normTitle(g.first.displayName), () => []).add(g);
        }
        // §trendingYearProx — Tolérance d'écart d'année (en années) entre le
        // retour TMDB et le candidat playlist. Les tendances sont l'ACTUALITÉ
        // (films récents), donc l'année doit coller de près : au-delà, c'est un
        // homonyme d'une autre époque qu'on NE promeut PAS dans le hero.
        // Off-by-one toléré (décalage de sortie selon pays).
        const yearTol = 1;
        List<M3uEntry>? pick(String norm, String? tmdbYear) {
          final cands = byName[norm];
          if (cands == null || cands.isEmpty) return null;
          final mostRecent = ([...cands]
                ..sort((a, b) =>
                    (b.first.title.year ?? '').compareTo(a.first.title.year ?? '')))
              .first;
          final ty = int.tryParse(tmdbYear ?? '');
          // Pas d'année TMDB exploitable (souvent les séries) → permissif :
          // le titre est le seul signal, on prend la plus récente.
          if (ty == null) return mostRecent;

          List<M3uEntry>? bestClose;
          var bestDelta = 1 << 30;
          var anyYearKnown = false;
          for (final c in cands) {
            final cy = int.tryParse(c.first.title.year ?? '');
            if (cy == null) continue;
            anyYearKnown = true;
            if (cy == ty) return c; // match d'année exact
            final d = (cy - ty).abs();
            if (d < bestDelta) {
              bestDelta = d;
              bestClose = c;
            }
          }
          // Aucun candidat daté → titre seul, permissif.
          if (!anyYearKnown) return mostRecent;
          // Le plus proche est-il dans la tolérance ? Sinon on REJETTE (homonyme
          // d'une autre époque) → la tendance suivante sera tentée à la place.
          if (bestClose != null && bestDelta <= yearTol) return bestClose;
          return null;
        }

        for (final t in trending) {
          if (featured.length >= maxFeatured) break;
          var hit = pick(_normTitle(t.title), t.year);
          if (hit == null && t.originalTitle != null) {
            hit = pick(_normTitle(t.originalTitle!), t.year);
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
      // §favHeroTv + §heroTvFill — Chaînes : le hero met d'abord en avant les
      // chaînes FAVORITES, PUIS complète avec les chaînes des catégories
      // prioritaires (France/New/…) jusqu'à `maxFeatured` → hero toujours
      // étoffé même avec peu (ou pas) de favoris. Dédup par displayName.
      final seen = <String>{};
      void addUpTo(Iterable<List<M3uEntry>> groups) {
        for (final g in groups) {
          if (featured.length >= maxFeatured) break;
          if (seen.add(g.first.displayName)) featured.add(g);
        }
      }

      addUpTo(byCategory['Favoris'] ?? const []);
      // `categories` est déjà trié par priorité (Favoris → France → New →
      // genres → Autres) : on parcourt dans l'ordre pour remplir le hero.
      for (final cat in categories) {
        if (cat == 'Favoris') continue;
        if (featured.length >= maxFeatured) break;
        addUpTo(byCategory[cat]!);
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

    _sharedFeatured[widget.type] = _FeaturedMemo(
      groupingKey: _cachedGroupingKey,
      favoritesVersion: favoritesVersion,
      watchVersion: watchVersion,
      maxFeatured: maxFeatured,
      trending: _trendingTitles,
      featured: featured,
    );
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
    // §perfSettings — le hero peut être coupé par l'utilisateur (Fire Stick) :
    // tout le calcul d'offsets/itemCount ci-dessous suit automatiquement.
    final perf = PerformanceSettingsService.config.value;
    final hasHero = perf.heroEnabled && featured.isNotEmpty;
    final hasTabs = widget.tabsBuilder != null;
    final showLastWatchedSlot = widget.type == M3uContentType.tv;

    final heroOffset = hasHero ? 1 : 0;
    final tabsOffset = hasTabs ? 1 : 0;
    final lastWatchedOffset = showLastWatchedSlot ? 1 : 0;
    final headerCount = heroOffset + tabsOffset + lastWatchedOffset;

    // §jankMeter — Sonde de fluidité du défilement VERTICAL de l'accueil.
    //
    // ⚠️ Les carrousels horizontaux sont imbriqués dedans, et les notifications
    // de défilement REMONTENT l'arbre : c'est le filtre `depth == 0` de la
    // sonde qui empêche cette mesure-ci d'avaler les frames des rangées.
    return JankScrollProbe(
      label: 'accueil vertical · ${widget.type.name}',
      child: ListView.builder(
      // §rowStorageKey — Case de sauvegarde PROPRE à cette liste.
      //
      // Flutter identifie l'emplacement où un scrollable range sa position par
      // la **chaîne des `PageStorageKey` au-dessus de lui**. L'accueil n'en
      // portait qu'UN SEUL (`homeTypePages`, sur la PageView des onglets) :
      // cette liste verticale, TOUS les carrousels horizontaux et la grille des
      // chaînes résolvaient donc vers la MÊME case, et se réécrivaient dessus.
      //
      // Effet mesuré sur téléphone : descendre l'accueil jusqu'en bas y inscrit
      // l'offset vertical (des milliers de pixels) ; en remontant, chaque
      // rangée reconstruite RELIT cet offset et se cale à son extrémité droite,
      // première carte coupée par le bord. Une rangée jamais touchée
      // horizontalement se retrouvait ainsi déplacée — d'où « les carrousels
      // partent vers la gauche quand on remonte ».
      //
      // ⚠️ Une `ValueKey` ne suffit PAS : `PageStorageBucket` ne collecte que
      // les clés de type `PageStorageKey`. La `ValueKey('cat_…')` de §tvExitPage
      // sert à l'identité des éléments, pas au rangement des positions.
      key: PageStorageKey('homeRows_${widget.type.name}'),
      padding: EdgeInsets.only(top: widget.topInset, bottom: 24),
      // §dpadHeroDown — cache vertical élargi (défaut 250 px) : la 1re rangée
      // sous le pli doit être CONSTRUITE pour exister comme candidat de focus
      // D-pad (dpad ignore les nodes non buildés) — sinon un ⬇ « perdu »
      // retombe sur le rail (seule cible toujours construite).
      // (même précédent que home_category §focusScroll : ScrollCacheExtent
      // n'est pas exporté par material dans cette version → ancien param.)
      // ignore: deprecated_member_use
      cacheExtent: 800,
      itemCount: headerCount + categories.length,
      itemBuilder: (ctx, i) {
        var cursor = 0;
        if (hasHero) {
          if (i == cursor) {
            // §heroUnify — TOUTES les pages (y compris Chaînes) utilisent le
            // hero "fan" → même hauteur/position au swipe entre Séries/Films/
            // Chaînes. Avant : TV avait un banner 16/9 plus court + un topInset
            // différent → l'ensemble "sautait" verticalement en passant dessus.
            // §dpadHeroDown — DpadRegion PROPRE : sans elle, le hero est membre
            // de la grande région homePageN dont les cartes de carrousel sont
            // exclues (sous-régions row_) → ⬇ ne trouvait aucun candidat
            // in-region et préférait scroller la page en cascade (0,8 viewport
            // auto-répété) jusqu'à perdre le focus → atterrissage rail
            // « Paramètres ». En petite région, le scroll est borné (échec
            // immédiat) → edge leave → cross-région → cible in-beam correcte
            // (tabs / 1re rangée) avec entry/mémoire.
            return DpadRegion(
              memoryKey: 'hero_${widget.type.name}',
              child: _HeroFanBanner(featured: featured, type: widget.type),
            );
          }
          cursor += 1;
        }
        if (hasTabs) {
          if (i == cursor) {
            // §dpadHeroDown — même isolement que le hero (cf. ci-dessus).
            return DpadRegion(
              memoryKey: 'home_tabs',
              child: widget.tabsBuilder!(ctx),
            );
          }
          cursor += 1;
        }
        if (showLastWatchedSlot) {
          if (i == cursor) {
            return DpadRegion(
              memoryKey: 'home_last_watched',
              child: _LastWatchedTvTile(entries: widget.entries),
            );
          }
          cursor += 1;
        }
        final catIdx = i - cursor;
        final cat = categories[catIdx];
        final allGroups = byCategory[cat]!;
        // §navUX — Favoris affichés sans limite (l'utilisateur les a curatés
        // lui-même, on ne les tronque pas à 25). Les autres catégories gardent
        // le plafond + la tuile "Voir tout".
        final isFav = cat == 'Favoris';
        final hasMore = !isFav && allGroups.length > perf.maxItemsPerRow;
        final visibleGroups = hasMore
            ? allGroups.take(perf.maxItemsPerRow).toList()
            : allGroups;
        return _CategoryRow(
          // §tvExitPage — Clé de CONTENU, pas de position.
          //
          // ⚠️ Sans elle, Flutter apparie les éléments par INDEX : lancer une
          // chaîne l'ajoute aux favoris, la rangée « Favoris » apparaît ou
          // grandit, tout se décale d'un cran — et l'élément (donc le
          // `FocusNode`) de la carte d'où l'on est parti se retrouve à décrire
          // une AUTRE chaîne. Mesuré sur les vraies listes : on repartait de
          // « ALBAYANE » et on revenait sur « MGG TV CANADA ». La mémoire de
          // focus ne peut pas être juste si l'identité des éléments ne l'est
          // pas.
          key: ValueKey('cat_${widget.type.name}_$cat'),
          category: cat,
          groups: visibleGroups,
          allGroups: allGroups,
          totalCount: allGroups.length,
          hasMore: hasMore,
          type: widget.type,
          icon: _TypePage.categoryIcon(cat),
        );
      },
      ),
    );
  }

  /// §emptyHome — État vide d'un onglet, aligné sur `EmptyState` (même widget
  /// que la recherche et les téléchargements) : un titre, une explication et
  /// un CTA vers les comptes — avant, une icône grise et deux mots, sans issue.
  ///
  /// ⚠️ La barre Séries/Films/Chaînes reste affichée au-dessus : depuis
  /// §emptyTab un onglet vide est atteignable, et sur TV (pas de swipe) c'est
  /// la SEULE façon de revenir sur un onglet plein. Sans hero pour la porter,
  /// elle descend sous l'AppBar transparente (`kToolbarHeight`) pour ne pas
  /// passer sous les icônes ↻/⚙️.
  Widget _buildEmpty(BuildContext context) {
    final (icon, label) = switch (widget.type) {
      M3uContentType.movie  => (Icons.movie_outlined, 'Aucun film'),
      M3uContentType.series => (Icons.tv_outlined, 'Aucune série'),
      M3uContentType.tv     => (Icons.live_tv_outlined, 'Aucune chaîne'),
    };
    final empty = EmptyState(
      icon: icon,
      title: label,
      subtitle: 'Aucune de tes listes n\'en contient. '
          'Recharge une liste ou ajoute un compte.',
      ctaLabel: 'Gérer les comptes',
      ctaIcon: Icons.manage_accounts_outlined,
      onCtaTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AccountsPage()),
      ),
    );
    final tabs = widget.tabsBuilder;
    if (tabs == null) return empty;
    return Column(
      children: [
        SizedBox(height: widget.topInset + kToolbarHeight),
        tabs(context),
        Expanded(child: empty),
      ],
    );
  }

  /// §homonymYear — Sépare les groupes-titre (FILMS et SÉRIES) qui mélangent
  /// plusieurs années (homonymes/remakes). 0 ou 1 année distincte → groupe
  /// inchangé (fusion conservée, les versions sans année rejoignent l'unique
  /// année). ≥2 années → un sous-groupe par année + un pour les sans-année.
  static List<List<M3uEntry>> _splitGroupsByYear(
      Iterable<List<M3uEntry>> titleGroups) {
    final out = <List<M3uEntry>>[];
    for (final group in titleGroups) {
      final years = group.map((e) => e.title.year).whereType<String>().toSet();
      if (years.length <= 1) {
        out.add(group);
      } else {
        final byYear = <String, List<M3uEntry>>{};
        for (final e in group) {
          byYear.putIfAbsent(e.title.year ?? '', () => []).add(e);
        }
        out.addAll(byYear.values);
      }
    }
    return out;
  }

  /// §favAudit — Retourne AUSSI la liste plate des groupes : `byCategory`
  /// duplique certains groupes ('New'), on ne peut donc pas la reconstruire
  /// depuis ses valeurs. Elle sert de source à la catégorie ⭐, recalculée
  /// indépendamment.
  ({
    Map<String, List<List<M3uEntry>>> byCategory,
    List<List<M3uEntry>> groups,
  }) _groupByCategoryThenByTitle(
    List<M3uEntry> entries,
    M3uContentType type,
  ) {
    // §23 — contentGroupKey est insensible à la casse (fusion cross-listes).
    String groupKey(M3uEntry e) =>
        type == M3uContentType.tv ? tvGroupKey(e.displayName) : contentGroupKey(e);

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

    // §homonymYear — FILMS et SÉRIES : split intelligent par année. On a groupé
    // par titre (fusion cross-listes maximale), puis on sépare UNIQUEMENT les
    // groupes contenant plusieurs années distinctes (vrais homonymes/remakes :
    // "Vengeance" 1990 vs 2022). Les titres mono-année (≈99 %) restent fusionnés.
    // TV exclu (pas d'année pertinente).
    final groups = type != M3uContentType.tv
        ? _splitGroupsByYear(byGroup.values)
        : byGroup.values.toList();

    // §newByAdded — Quand le catalogue porte des timestamps `addedAt` (pipeline
    // Xtream JSON), la catégorie « New » devient VIRTUELLE (calculée par récence
    // d'ajout, plus bas). On ne colle alors plus l'étiquette provider
    // "Récemment ajouté" comme catégorie PRIMAIRE (sinon un film récent serait
    // sorti de son genre). En fallback M3U/get.php (pas de timestamp), on
    // conserve le comportement historique (label provider 'New').
    final hasAddedData = type != M3uContentType.tv &&
        groups.any((g) => g.any((e) => e.addedAt != null));

    String pickCategory(List<M3uEntry> group) {
      String? newLabel;
      for (final e in group) {
        final c = e.category;
        if (c == null || c.isEmpty) continue;
        if (c == 'New') {
          newLabel = c;
          continue;
        }
        return c; // vrai genre / région → prioritaire
      }
      // §inferredCat — Aucune catégorie fournie par la liste : on retombe sur
      // celle DÉDUITE des genres TMDB, apprise quand la vignette a résolu son
      // affiche. Indispensable pour les listes au format « Ultimate », qui ne
      // portent aucun `group-title` (mesuré : 153 062 entrées sur 153 062) et
      // tombaient donc intégralement dans « Autres ».
      final inferred = InferredCategoryService.get(contentGroupKey(group.first));
      if (inferred != null) return inferred;
      if (newLabel != null && !hasAddedData) return newLabel;
      return 'Autres';
    }

    final byCategory = <String, List<List<M3uEntry>>>{};
    for (final group in groups) {
      // Cas spécial chaînes TV : les chaînes françaises remontent dans une
      // catégorie virtuelle "France" — l'ordre M3U est préservé naturellement
      // par l'ordre d'itération de `byGroup.values` (Map insertion order).
      // §radioCat — Testé AVANT « France » : une webradio française coche les
      // deux, et c'est bien dans « Radio » qu'elle doit atterrir.
      if (type == M3uContentType.tv && _TypePage._isRadioChannel(group.first)) {
        byCategory.putIfAbsent('Radio', () => []).add(group);
        continue;
      }
      if (type == M3uContentType.tv && _TypePage._isFrenchChannel(group.first)) {
        byCategory.putIfAbsent('France', () => []).add(group);
        continue;
      }
      byCategory.putIfAbsent(pickCategory(group), () => []).add(group);
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

    // 🔥 §newByAdded — Rangée « New » VIRTUELLE par récence d'ajout (`addedAt`),
    // toutes listes fusionnées (bien meilleur que le match texte du group-title
    // provider, qui ne profitait pas de la fusion multi-listes). Hybride :
    // fenêtre 30 jours, bornée [20, 60] → jamais vide ni surchargée. addedAt du
    // groupe = MAX parmi ses versions (un film ré-ajouté sur N'IMPORTE quelle
    // liste compte comme récent). Duplique les groupes (ils restent dans leur
    // genre). Seulement si le catalogue porte des timestamps (Xtream JSON).
    if (hasAddedData) {
      final dated = <(int, List<M3uEntry>)>[];
      for (final group in groups) {
        int? ts;
        for (final e in group) {
          final a = e.addedAt;
          if (a != null && (ts == null || a > ts)) ts = a;
        }
        if (ts != null) dated.add((ts, group));
      }
      if (dated.isNotEmpty) {
        dated.sort((a, b) => b.$1.compareTo(a.$1)); // plus récent en tête
        final nowS = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        const windowS = 30 * 24 * 3600; // 30 jours
        var recent = dated.where((e) => nowS - e.$1 <= windowS).toList();
        if (recent.length < 20) recent = dated.take(20).toList(); // plancher
        if (recent.length > 60) recent = recent.take(60).toList(); // plafond
        byCategory['New'] = recent.map((e) => e.$2).toList();
      }
    }

    // ⭐ La catégorie virtuelle "Favoris" n'est PLUS calculée ici (§favAudit) :
    // elle est injectée par `_ensureFavoriteCategory` à partir de `groups`,
    // pour qu'un changement de favori ne relance pas tout ce groupement.
    // §homonymYear — cette source est bien `groups` (post-split films), donc
    // cohérente avec les rangées de catégories. (Les favoris restent keyés par
    // titre → un homonyme favorisé fait remonter ses variantes par année ;
    // edge case rare, acceptable, et évite une migration risquée des favoris
    // existants.)
    return (byCategory: byCategory, groups: groups);
  }
}

