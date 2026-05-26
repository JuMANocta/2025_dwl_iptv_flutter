import 'package:flutter/material.dart';
import 'package:aetherStream/core/utils/platform_tv.dart';
import 'package:aetherStream/feature/home/home_page.dart';
import 'package:aetherStream/feature/downloads/downloads_page.dart';
import 'package:aetherStream/feature/settings/settings_page.dart';
import 'package:aetherStream/feature/settings/settings_apply_service.dart';
import 'package:aetherStream/feature/pairing/pairing_page.dart';
import 'package:aetherStream/data/services/pairing_service.dart';

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

  /// §18 — Sur TV, le bouton « Paramètres » du rail ouvre la webapp Settings via
  /// pairing QR (le mobile sert de télécommande de config) plutôt que le hub
  /// Material natif, hostile à la télécommande (sliders, color picker). Un
  /// fallback « Modifier sur la TV » réouvre le hub natif en mode dégradé.
  Future<void> _openSettingsTv() async {
    final result = await Navigator.of(context).push<PairingResult>(
      MaterialPageRoute(
        builder: (_) => PairingPage(
          kind: PairingKind.settings,
          onManualFallback: () {
            // Ferme la page pairing puis ouvre le hub Settings natif.
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            );
          },
        ),
      ),
    );
    if (result is PairingSettingsResult) {
      final changed = await SettingsApplyService.apply(result.patch);
      if (changed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paramètres appliqués depuis le mobile.')),
        );
      }
    }
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
      return _wrapBack(Scaffold(
        body: Row(
          children: [
            _TvNavigationRail(
              selectedIndex: _navIndex,
              onDestinationSelected: _onTap,
              onOpenSettings: _openSettingsTv,
            ),
            Expanded(child: stack),
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

  /// §bug Back TV — Intercepte le Back quand on n'est PAS sur l'onglet Accueil :
  /// au lieu de quitter l'app (route racine, rien à dépiler), on ramène vers
  /// l'Accueil (sort du mode recherche ou de l'onglet Téléchargements). Sur
  /// l'onglet Accueil, `canPop: true` → comportement natif (sortie app).
  Widget _wrapBack(Widget child) {
    return PopScope(
      canPop: _navIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        setState(() => _navIndex = 0);
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
    return NavigationRail(
      selectedIndex: selectedIndex,
      minWidth: 64,
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
    );
  }
}
