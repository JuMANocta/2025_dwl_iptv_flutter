import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aetherStream/core/utils/platform_tv.dart';
import 'package:aetherStream/data/services/parsed_playlist_service.dart';
import 'package:aetherStream/feature/home/home_page.dart';
import 'package:aetherStream/feature/downloads/downloads_page.dart';
import 'package:aetherStream/feature/settings/settings_page.dart';
import 'package:aetherStream/main.dart' show checkForUpdate;

/// Squelette de navigation principale (§1b — phases 1+4, §3c-6 TV).
///
/// 3 destinations :
///   0. Accueil          — [HomePage] (mode browse)
///   1. Recherche        — bascule [HomePage] en mode `searchMode: true`
///                          (in-place, pas de changement de page)
///   2. Téléchargements  — [DownloadsPage]
///
/// **Layout adapté** :
///   - Mobile (`PlatformTv.isTv` false) → `NavigationBar` bottom classique.
///   - Android TV / Fire TV → `NavigationRail` latéral à gauche (cohérent
///     avec l'ergonomie 16:9 horizontale des TV, focusable au D-pad).
///
/// L'`IndexedStack` interne ne contient que 2 enfants (Home + Downloads).
/// Le bouton Recherche n'ajoute pas une 3e page : il toggle juste un drapeau
/// passé à [HomePage], qui bascule alors son contenu en vue résultats.
class MainNavigation extends StatefulWidget {
  /// Données pré-chargées par `_LaunchDecider` — propagées aux pages enfants
  /// pour éviter un double appel réseau.
  final ({String path, String accountId, String accountName}) initialData;

  const MainNavigation({super.key, required this.initialData});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  /// Index sélectionné dans la `NavigationBar` (0=Home, 1=Search, 2=Downloads).
  int _navIndex = 0;

  bool get _searchMode => _navIndex == 1;
  int  get _stackIndex => _navIndex == 2 ? 1 : 0;

  /// §backExit — Horodatage du dernier Back sur l'onglet Accueil (double-back).
  DateTime? _lastBackPress;

  /// §railExit — Scope dédié au contenu (la page active). Permet au rail TV
  /// d'envoyer explicitement le focus dans le contenu sur flèche droite, même
  /// si la traversée géométrique par défaut ne trouve pas de cible visible.
  final FocusScopeNode _contentScopeNode = FocusScopeNode(debugLabel: 'content');

  /// §lazyUnload — Timer périodique qui décharge de la mémoire les comptes
  /// secondaires non consultés depuis [_idleThreshold]. Le cache disque
  /// JSON.gz est conservé → rechargement ~50 ms quand un compte secondaire
  /// est re-demandé (recherche cross-comptes, action sheet multi-providers).
  Timer? _idleUnloadTimer;
  static const Duration _idleCheckInterval = Duration(minutes: 2);
  static const Duration _idleThreshold     = Duration(minutes: 5);

  @override
  void dispose() {
    _idleUnloadTimer?.cancel();
    _contentScopeNode.dispose();
    super.dispose();
  }

  /// §railExit — Appelé quand l'utilisateur appuie ←→ sur le rail TV : on
  /// focus le 1er focusable du contenu (en ordre de traversée). Fallback
  /// implicite si le scope n'a rien (la home se reconstruit) → no-op.
  void _focusContentArea() {
    final first = _contentScopeNode.traversalDescendants
        .where((n) => n.canRequestFocus && !n.skipTraversal)
        .firstOrNull;
    first?.requestFocus();
  }

  @override
  void initState() {
    super.initState();
    // §updateDelay — Délai long avant le check MAJ (laisse la home se stabiliser,
    // évite que le dialog MAJ s'affiche pendant que le focus TV se met en place
    // → user ne pouvait plus sélectionner / fermer le dialog).
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) checkForUpdate();
    });

    // §backExitHint — Sur TV uniquement, premier lancement : affiche un hint
    // discret expliquant le double-back pour quitter (sinon l'utilisateur
    // pense que Back ne fait rien sur l'Accueil au 1er essai).
    if (PlatformTv.isTv) {
      _maybeShowBackExitHint();
    }

    // §lazyUnload — Le compte actif est dans `widget.initialData.accountId` ;
    // il est marqué comme accédé avant chaque check pour ne JAMAIS être
    // déchargé (la home le lit en permanence de toute façon).
    _idleUnloadTimer = Timer.periodic(_idleCheckInterval, (_) {
      ParsedPlaylistService.markAccessed(widget.initialData.accountId);
      ParsedPlaylistService.unloadIdleSecondaries(
        activeAccountId: widget.initialData.accountId,
        idle: _idleThreshold,
      );
    });
  }

  Future<void> _maybeShowBackExitHint() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const key = 'hint_double_back_seen_v1';
      if (prefs.getBool(key) ?? false) return;
      await Future.delayed(const Duration(seconds: 4));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text(
              '💡 Pour quitter l\'application : appuie 2 fois sur Retour'),
          duration: Duration(seconds: 6),
        ));
      await prefs.setBool(key, true);
    } catch (_) {/* silent */}
  }

  void _onTap(int i) {
    if (i == _navIndex) return;
    setState(() => _navIndex = i);
  }

  /// Ouvre le hub Settings natif. §18 — Depuis que la navigation D-pad du hub
  /// fonctionne, on n'auto-lance plus le serveur de pairing : le hub natif est
  /// le chemin par défaut (zéro surcharge réseau) et propose en tout premier une
  /// entrée « Configurer depuis le téléphone » (pairing QR à la demande).
  Future<void> _openSettingsTv() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTv = PlatformTv.isTv;
    final stack = IndexedStack(
      index: _stackIndex,
      children: [
        HomePage(
          initialData: widget.initialData,
          searchMode: _searchMode,
          onExitSearch: () => setState(() => _navIndex = 0),
        ),
        const DownloadsPage(),
      ],
    );

    if (isTv) {
      // §3c-6 — Layout TV : NavigationRail latéral, focusable au D-pad.
      // Pas de bottom bar (impossible à reach avec une télécommande).
      // §railExit — Le contenu vit dans un `FocusScope` dédié pour que le rail
      // puisse y envoyer explicitement le focus sur flèche droite.
      return _wrapBack(Scaffold(
        body: Row(
          children: [
            _TvNavigationRail(
              selectedIndex: _navIndex,
              onDestinationSelected: _onTap,
              onOpenSettings: _openSettingsTv,
              onExitRight: _focusContentArea,
            ),
            Expanded(
              child: FocusScope(node: _contentScopeNode, child: stack),
            ),
          ],
        ),
      ));
    }

    // Mobile : NavigationBar bottom classique (comportement historique).
    return _wrapBack(Scaffold(
      body: stack,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: _onTap,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.search),
            label: 'Recherche',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download),
            label: 'Téléchargements',
          ),
        ],
      ),
    ));
  }

  /// §bug Back TV + §backExit — Gestion du Back à la racine :
  ///   - **Hors onglet Accueil** : ramène vers l'Accueil (sort du mode recherche
  ///     ou de l'onglet Téléchargements) — pas de sortie d'app.
  ///   - **Sur l'onglet Accueil** : **double-back** pour quitter. Le 1er Back
  ///     affiche un message ("Appuie à nouveau…") ; un 2e Back en moins de 2 s
  ///     quitte réellement l'app (`SystemNavigator.pop`). Évite les sorties
  ///     accidentelles à la télécommande TV.
  ///
  /// `canPop: false` en permanence → on intercepte toujours le Back nous-mêmes
  /// (le pop natif ne quitte jamais l'app directement).
  Widget _wrapBack(Widget child) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;

        // Pas sur l'accueil → y revenir (sort recherche / téléchargements).
        if (_navIndex != 0) {
          setState(() => _navIndex = 0);
          return;
        }

        // Sur l'accueil → double-back pour quitter.
        final now = DateTime.now();
        if (_lastBackPress != null &&
            now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
          SystemNavigator.pop(); // quitte réellement l'application
          return;
        }
        _lastBackPress = now;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Appuie à nouveau sur Retour pour quitter'),
              duration: Duration(seconds: 2),
            ),
          );
      },
      child: child,
    );
  }
}

// ─── NavigationRail TV ──────────────────────────────────────────────────────

/// Rail latéral de navigation pour Android TV / Fire TV (§3c-6).
///
/// Reprend les 3 destinations (Accueil / Recherche / Téléchargements) avec
/// un `NavigationRail` natif Flutter. Les destinations sont focusables au
/// D-pad et l'AppBar de chaque page reste libre pour son propre contenu.
///
/// 4e destination "Paramètres" : sur TV, l'icône ⚙️ de l'AppBar de
/// `HomePage` n'est pas focusable au D-pad (focus traversal du Flutter ne
/// remonte pas naturellement dans l'AppBar transparente). On ajoute donc
/// l'accès Settings comme dernier item du rail, qui pousse `SettingsPage`
/// sans modifier `selectedIndex`.
///
/// `minWidth: 64` (au lieu du 80 par défaut) : sur TV avec textScaler ×1.3,
/// le rail prenait trop de place horizontale. 64 reste lisible à 3m.
///
/// §railRevert (2026-05-25) — Retour au rail **statique** de base (§3c-6) :
/// `labelType: all` (icônes + libellés toujours visibles), sans le mécanisme
/// "réductible" (`§railFocusExpand`, FocusScope + `extended` au focus) qui
/// empêchait de sortir du menu au D-pad physique. Comportement d'origine
/// rétabli : pas de problème pour quitter le rail à la télécommande.
class _TvNavigationRail extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onOpenSettings;

  /// §railExit — Appelé quand le focus est dans le rail et que l'utilisateur
  /// appuie sur la flèche droite : la `MainNavigation` répond en focusant le
  /// 1er focusable du contenu (sinon la traversée géométrique de Flutter peut
  /// échouer si rien n'est aligné à droite des destinations).
  final VoidCallback? onExitRight;

  const _TvNavigationRail({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onOpenSettings,
    this.onExitRight,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // §railExit — Focus parent qui capture ← → quand un descendant (les
    // destinations) a le focus. arrow right → on délègue à `onExitRight`.
    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
            onExitRight != null) {
          onExitRight!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: NavigationRail(
        selectedIndex: selectedIndex,
        minWidth: 64,
        // §railCenter — Centrage vertical des destinations dans la hauteur
        // disponible (par défaut elles s'empilent en haut, ce qui laisse un
        // grand vide en bas sur TV 16:9).
        groupAlignment: 0.0,
        labelType: NavigationRailLabelType.all,
        backgroundColor: cs.surface,
        indicatorColor: cs.primary.withAlpha(40),
        selectedIconTheme: IconThemeData(color: cs.primary),
        selectedLabelTextStyle:
            TextStyle(color: cs.primary, fontWeight: FontWeight.bold),
        onDestinationSelected: (i) {
          if (i == 3) {
            // §3c-bis — Paramètres : on ne modifie pas selectedIndex (resterait
            // coincé sur "Paramètres" au retour). On pousse la route et on
            // laisse l'index courant intact.
            onOpenSettings();
            return;
          }
          onDestinationSelected(i);
        },
        destinations: const [
          NavigationRailDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: Text('Accueil'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.search),
            label: Text('Recherche'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download),
            label: Text('Téléchargements'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: Text('Paramètres'),
          ),
        ],
      ),
    );
  }
}
