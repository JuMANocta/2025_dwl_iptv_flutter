import 'package:flutter/material.dart';
import 'package:aetherStream/core/utils/platform_tv.dart';
import 'package:aetherStream/feature/home/home_page.dart';
import 'package:aetherStream/feature/downloads/downloads_page.dart';

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

  void _onTap(int i) {
    if (i == _navIndex) return;
    setState(() => _navIndex = i);
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
      return Scaffold(
        body: Row(
          children: [
            _TvNavigationRail(
              selectedIndex: _navIndex,
              onDestinationSelected: _onTap,
            ),
            Expanded(child: stack),
          ],
        ),
      );
    }

    // Mobile : NavigationBar bottom classique (comportement historique).
    return Scaffold(
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
    );
  }
}

// ─── NavigationRail TV ──────────────────────────────────────────────────────

/// Rail latéral de navigation pour Android TV / Fire TV (§3c-6).
///
/// Reprend les 3 destinations (Accueil / Recherche / Téléchargements) avec
/// un `NavigationRail` natif Flutter. Les destinations sont focusables au
/// D-pad et l'AppBar de chaque page reste libre pour son propre contenu.
class _TvNavigationRail extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const _TvNavigationRail({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      labelType: NavigationRailLabelType.all,
      backgroundColor: cs.surface,
      indicatorColor: cs.primary.withAlpha(40),
      selectedIconTheme: IconThemeData(color: cs.primary),
      selectedLabelTextStyle: TextStyle(color: cs.primary, fontWeight: FontWeight.bold),
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
      ],
    );
  }
}
