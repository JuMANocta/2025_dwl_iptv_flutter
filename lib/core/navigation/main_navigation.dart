import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:aetherStream/core/utils/platform_tv.dart';
import 'package:aetherStream/feature/home/home_page.dart';
import 'package:aetherStream/feature/downloads/downloads_page.dart';
import 'package:aetherStream/feature/settings/settings_page.dart';

/// Squelette de navigation principale (§1b — phases 1+4, §3c-6 TV).
///
/// 4 destinations :
///   0. Accueil          — [HomePage] (mode browse)
///   1. Recherche        — bascule [HomePage] en mode `searchMode: true`
///                          (in-place, pas de changement de page)
///   2. Téléchargements  — [DownloadsPage]
///   3. Paramètres       — [SettingsPage]
///
/// **Layout adapté** :
///   - Mobile (portrait) → `NavigationBar` bottom classique.
///   - Android TV / Windows / Écrans larges → `NavigationRail` latéral à gauche.
///
/// L'IndexedStack interne contient 3 enfants (Home, Downloads, Settings).
/// Le bouton Recherche n'ajoute pas une page : il toggle juste un drapeau
/// passé à [HomePage], qui bascule alors son contenu en vue résultats.
class MainNavigation extends StatefulWidget {
  /// Données pré-chargées par `_LaunchDecider` — propagées aux pages enfants
  /// pour éviter un double appel réseau.
  final ({String path, String accountId, String accountName}) initialData;

  const MainNavigation({super.key, required this.initialData});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> with WindowListener {
  /// Index sélectionné dans la `NavigationBar` (0=Home, 1=Search, 2=Downloads, 3=Settings).
  int _navIndex = 0;
  bool _isFullScreen = false;

  bool get _searchMode => _navIndex == 1;
  int  get _stackIndex {
    if (_navIndex == 2) return 1; // Downloads
    if (_navIndex == 3) return 2; // Settings
    return 0; // Home (mode browse ou search)
  }

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      windowManager.addListener(this);
      _checkFullScreen();
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowEnterFullScreen() {
    setState(() => _isFullScreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    setState(() => _isFullScreen = false);
  }

  Future<void> _checkFullScreen() async {
    if (Platform.isWindows) {
      final isFull = await windowManager.isFullScreen();
      if (mounted) setState(() => _isFullScreen = isFull);
    }
  }

  Future<void> _toggleFullScreen() async {
    if (Platform.isWindows) {
      final isFull = await windowManager.isFullScreen();
      await windowManager.setFullScreen(!isFull);
      if (mounted) setState(() => _isFullScreen = !isFull);
    }
  }

  void _onTap(int i) {
    if (i == _navIndex) return;
    setState(() => _navIndex = i);
  }

  @override
  Widget build(BuildContext context) {
    final bool isTv = PlatformTv.isTv;
    final bool isWide = MediaQuery.of(context).size.width > 700;
    final bool useRail = isTv || isWide;

    final stack = IndexedStack(
      index: _stackIndex,
      children: [
        HomePage(
          initialData: widget.initialData,
          searchMode: _searchMode,
          onExitSearch: () => setState(() => _navIndex = 0),
        ),
        const DownloadsPage(),
        const SettingsPage(),
      ],
    );

    if (useRail) {
      return Scaffold(
        body: Row(
          children: [
            _CustomNavigationRail(
              selectedIndex: _navIndex,
              onDestinationSelected: _onTap,
              isFullScreen: _isFullScreen,
              onToggleFullScreen: _toggleFullScreen,
            ),
            Expanded(child: stack),
          ],
        ),
      );
    }

    // Mobile : NavigationBar bottom classique.
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
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Paramètres',
          ),
        ],
      ),
    );
  }
}

// ─── NavigationRail Adapté ──────────────────────────────────────────────────

class _CustomNavigationRail extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool isFullScreen;
  final VoidCallback onToggleFullScreen;

  const _CustomNavigationRail({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.isFullScreen,
    required this.onToggleFullScreen,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      minWidth: 64,
      labelType: NavigationRailLabelType.all,
      backgroundColor: cs.surface,
      indicatorColor: cs.primary.withAlpha(40),
      selectedIconTheme: IconThemeData(color: cs.primary),
      selectedLabelTextStyle: TextStyle(color: cs.primary, fontWeight: FontWeight.bold),
      trailing: Platform.isWindows ? Expanded(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: IconButton(
              icon: Icon(isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen),
              tooltip: isFullScreen ? 'Réduire la fenêtre' : 'Plein écran',
              onPressed: onToggleFullScreen,
              color: cs.onSurfaceVariant.withAlpha(180),
            ),
          ),
        ),
      ) : null,
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
          label: Text('Downloads'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: Text('Paramètres'),
        ),
      ],
    );
  }
}
