import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dpad/dpad.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aetherStream/core/utils/platform_tv.dart';
import 'package:aetherStream/data/services/parsed_playlist_service.dart';
import 'package:aetherStream/feature/home/home_page.dart';
import 'package:aetherStream/feature/downloads/downloads_page.dart';
import 'package:aetherStream/feature/settings/settings_page.dart';
import 'package:aetherStream/core/navigation/focus_route_memory.dart';
import 'package:aetherStream/data/services/stream_account_service.dart';
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
    super.dispose();
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

    // §lazyUnload + §unloadGuard — Décharge les listes secondaires restées
    // inutilisées, MAIS jamais pendant que l'accueil est affiché.
    //
    // ⚠️ **Le bug que ça corrige** (constaté sur appareil avec 4 listes) : les
    // accesseurs ne « touchent » les comptes qu'à chaque RECONSTRUCTION de
    // l'accueil. Une home simplement laissée à l'écran, sans interaction,
    // n'en reconstruit aucune — au bout de 5 minutes le timer déchargeait donc
    // 3 comptes sur 4 **sous les yeux de l'utilisateur**. Résultat observé :
    // toutes les catégories disparaissent et il ne reste que « Autres », parce
    // que le seul compte encore chargé n'apporte aucun libellé de catégorie.
    // Et rien ne revient : la ré-hydratation §lazyUnload est accrochée à
    // `didPopNext`, qui ne se déclenche que si on QUITTE la page.
    //
    // Le déchargement garde tout son sens quand on est ailleurs (lecteur,
    // téléchargements, réglages) : c'est là qu'il libère de la mémoire sans que
    // personne ne regarde, et le retour re-précharge depuis le cache disque.
    //
    // ⚠️ On protège le compte principal **COURANT** et non celui du lancement :
    // `widget.initialData.accountId` est figé, alors que l'utilisateur peut
    // changer de principal depuis AccountsPage — l'ancien code protégeait alors
    // le mauvais compte.
    _idleUnloadTimer = Timer.periodic(_idleCheckInterval, (_) {
      final activeId = StreamAccountService.currentAccountIdNotifier.value ??
          widget.initialData.accountId;
      ParsedPlaylistService.markAccessed(activeId);
      if (HomePage.isForeground && _navIndex == 0) return;
      ParsedPlaylistService.unloadIdleSecondaries(
        activeAccountId: activeId,
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

  /// §dpadRestore — Focus mémorisé pour chaque onglet, au moment où on le quitte.
  ///
  /// La bascule d'onglet ne pousse aucune route, mais elle détruit quand même
  /// les focusables (l'`IndexedStack` et les `ExcludeFocus` de la home) : le
  /// nœud focalisé meurt, et le filet de `dpad` retombe sur la 1re carte de
  /// l'accueil en faisant défiler la liste tout en haut. On rend donc le focus
  /// nous-mêmes, exactement comme [FocusRouteMemory] le fait pour les routes.
  final Map<int, FocusSnapshot> _tabFocus = <int, FocusSnapshot>{};

  void _onTap(int i) {
    if (i == _navIndex) return;
    _tabFocus[_navIndex] = FocusSnapshot.capture();
    setState(() => _navIndex = i);
    _tabFocus[i]?.restore();
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
      // §3c-6 + §dpadNav — Layout TV : NavigationRail latéral, focusable au
      // D-pad. Le franchissement rail ↔ contenu est géré nativement par `dpad`
      // (régions + `edge: leave`) → plus besoin de l'ancienne machinerie
      // §railExit (FocusScopeNode + focusInDirection). Le rail = région à bord
      // vertical `stop` (on n'en sort pas par le haut/bas) ; → (droite) part vers
      // le contenu, ← (gauche) au bord du contenu revient au rail.
      return _wrapBack(Scaffold(
        body: Row(
          children: [
            DpadRegion(
              debugLabel: 'rail',
              verticalEdge: DpadEdgeBehavior.stop,
              child: _TvNavigationRail(
                selectedIndex: _navIndex,
                onDestinationSelected: _onTap,
                onOpenSettings: _openSettingsTv,
              ),
            ),
            Expanded(
              child: DpadRegion(debugLabel: 'content', child: stack),
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
        // §navBarSlim — La barre Material 3 fait 80 px de haut par défaut, ce
        // qui est beaucoup sur un téléphone où l'écran sert surtout à afficher
        // des affiches. Ramenée à 68 (−15 %).
        //
        // ⚠️ On garde les libellés : les retirer aurait gagné plus de place,
        // mais trois icônes seules (maison / loupe / flèche) se devinent moins
        // bien qu'on ne le croit, et c'est un repère permanent de l'app.
        height: 68,
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
          _onTap(0); // §dpadRestore — passe par la mémoire de focus d'onglet
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

  const _TvNavigationRail({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // §dpadNav — Le franchissement vers le contenu (→) est géré par la
    // `DpadRegion` parente (edge: leave). Plus de `Focus` custom ici.
    //
    // §dpadAlign — Le rail garde volontairement le focus NATIF de Material
    // (pas de `FocusableCard` par destination) : §railRevert documente qu'une
    // personnalisation du focus ici avait déjà empêché de sortir du menu à la
    // télécommande. On se limite donc au visuel : `focusColor` très marqué, pour
    // que la destination focusée se voie à 3 m comme le reste de l'application.
    return Theme(
      data: Theme.of(context).copyWith(
        focusColor: cs.primary.withAlpha(90),
      ),
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
