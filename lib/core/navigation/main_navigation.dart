import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dpad/dpad.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:aetherStream/core/utils/platform_tv.dart';
import 'package:aetherStream/data/services/parsed_playlist_service.dart';
import 'package:aetherStream/feature/home/home_page.dart';
import 'package:aetherStream/feature/downloads/downloads_page.dart';
import 'package:aetherStream/feature/settings/settings_page.dart';
import 'package:aetherStream/main.dart' show checkForUpdate;

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
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      windowManager.addListener(this);
      _checkFullScreen();
    }

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

  @override
  void dispose() {
    if (Platform.isWindows) {
      windowManager.removeListener(this);
    }
    _idleUnloadTimer?.cancel();
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
    final bool isWide = MediaQuery.of(context).size.width > 700;
    final bool useRail = PlatformTv.isTv || isWide;

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
      // §3c-6 + §dpadNav — Layout TV / Wide : NavigationRail latéral. Le
      // franchissement rail ↔ contenu est géré nativement par `dpad` (régions
      // + `edge: leave`).
      return _wrapBack(Scaffold(
        body: Row(
          children: [
            DpadRegion(
              debugLabel: 'rail',
              verticalEdge: DpadEdgeBehavior.stop,
              child: _AppNavigationRail(
                selectedIndex: _navIndex,
                onDestinationSelected: _onTap,
                onOpenSettings: _openSettingsTv,
                isFullScreen: _isFullScreen,
                onToggleFullScreen: _toggleFullScreen,
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
    ));
  }

  /// §bug Back TV + §backExit — Gestion du Back à la racine.
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

// ─── NavigationRail Adapté ──────────────────────────────────────────────────

class _AppNavigationRail extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onOpenSettings;
  final bool isFullScreen;
  final VoidCallback onToggleFullScreen;

  const _AppNavigationRail({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onOpenSettings,
    required this.isFullScreen,
    required this.onToggleFullScreen,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isTv = PlatformTv.isTv;
    // §dpadNav — Le franchissement vers le contenu (→) est géré par la
    // `DpadRegion` parente (edge: leave). Plus de `Focus` custom ici.
    return NavigationRail(
        selectedIndex: selectedIndex,
        minWidth: 64,
        groupAlignment: isTv ? 0.0 : -1.0,
        labelType: NavigationRailLabelType.all,
        backgroundColor: cs.surface,
        indicatorColor: cs.primary.withAlpha(40),
        selectedIconTheme: IconThemeData(color: cs.primary),
        selectedLabelTextStyle:
            TextStyle(color: cs.primary, fontWeight: FontWeight.bold),
        onDestinationSelected: (i) {
          if (i == 3 && isTv) {
            onOpenSettings();
            return;
          }
          onDestinationSelected(i);
        },
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
            label: Text('Téléchargements'),
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
