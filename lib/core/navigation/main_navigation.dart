import 'package:flutter/material.dart';
import 'package:aetherStream/feature/home/home_page.dart';
import 'package:aetherStream/feature/downloads/downloads_page.dart';

/// Squelette de navigation principale (§1b — phases 1+4).
///
/// 3 boutons dans la `NavigationBar` :
///   0. Accueil          — [HomePage] (mode browse)
///   1. Recherche        — bascule [HomePage] en mode `searchMode: true`
///                          (in-place, pas de changement de page)
///   2. Téléchargements  — [DownloadsPage]
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
    return Scaffold(
      body: IndexedStack(
        index: _stackIndex,
        children: [
          HomePage(
            initialData: widget.initialData,
            searchMode: _searchMode,
            onExitSearch: () => setState(() => _navIndex = 0),
          ),
          const DownloadsPage(),
        ],
      ),
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
