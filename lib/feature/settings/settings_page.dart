import 'package:flutter/material.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/core/utils/platform_tv.dart';
import 'package:aetherStream/feature/accounts/accounts_page.dart';
import 'package:aetherStream/feature/settings/about_page.dart';
import 'package:aetherStream/feature/settings/backup_page.dart';
import 'package:aetherStream/feature/settings/optimization_settings_page.dart';
import 'package:aetherStream/feature/settings/theme_settings_page.dart';
import 'package:aetherStream/feature/settings/tmdb_key_page.dart';
import 'package:aetherStream/feature/settings/xmltv_page.dart';
import 'package:aetherStream/feature/settings/region_filter_page.dart';
import 'package:aetherStream/feature/settings/web_console/web_console_page.dart';
import 'package:aetherStream/data/services/favorites_service.dart';
import 'package:aetherStream/data/services/watch_progress_service.dart';
import 'package:aetherStream/data/services/search_history_service.dart';
import 'package:aetherStream/data/services/last_watched_channel_service.dart';
import 'package:aetherStream/widgets/tv/focusable_card.dart';
import 'package:aetherStream/widgets/tv/tv_initial_focus.dart';
import 'package:aetherStream/widgets/tv/tv_adaptive_modal.dart';
import '../../l10n/app_localizations.dart';

/// Hub principal des paramètres (§1b — phase 5).
///
/// Menu organisé qui sert de point d'entrée unique depuis le bouton ⚙️ de la
/// `HomePage`. Chaque item ouvre soit une sous-page existante, soit un dialog
/// d'action courte.
///
/// Sections :
///   - 👤 Comptes IPTV  → [AccountsPage] (stats + recharger par compte intégrés)
///   - 🎨 Personnalisation → [ThemeSettingsPage]
///   - ℹ️ À propos (version + check MAJ in-app)
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with TvInitialFocus {
  Future<void> _openAccounts() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AccountsPage()),
    );
  }

  Future<void> _openThemeSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ThemeSettingsPage()),
    );
  }

  Future<void> _openOptimisation() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OptimizationSettingsPage()),
    );
  }

  Future<void> _openTmdbKey() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TmdbKeyPage()),
    );
  }

  Future<void> _openXmltv() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const XmltvPage()),
    );
  }

  Future<void> _openRegionFilter() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RegionFilterPage()),
    );
  }

  Future<void> _openAbout() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AboutPage()),
    );
  }

  Future<void> _openBackup() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BackupPage()),
    );
  }

  /// §18 — Ouvre la **Console web** depuis la TV. Couvre comptes IPTV, TMDB,
  /// EPG, thème, sauvegarde, télécommande et à propos en une seule webapp
  /// servie sur le LAN. Remplace la pairing webapp §18 Phase A (devenue
  /// orpheline et retirée — la Console web est le canal officiel).
  Future<void> _openPhoneConfig() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WebConsolePage()),
    );
  }

  /// §resetUsage — Remet à zéro les **données d'usage** (favoris, reprises de
  /// lecture films & séries, historique de recherche, dernière chaîne regardée)
  /// SANS toucher aux comptes IPTV, à la clé TMDB, au thème ni au filtre
  /// langues/régions. Pratique pour repartir d'une liste de favoris propre
  /// (ex. après corruption). Action destructive → confirmation obligatoire.
  Future<void> _resetUsageData() async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cs.surfaceContainerHigh,
        title: const Text('Réinitialiser les données ?'),
        content: const Text(
          'Vide les favoris, les reprises de lecture (films & séries), '
          "l'historique de recherche et la dernière chaîne regardée.\n\n"
          'Conserve les comptes IPTV, la clé TMDB, le thème et les filtres '
          'langues/régions.\n\n'
          'Cette action est irréversible.',
        ),
        actions: [
          TextButton(
          // §safeFocus — Sur TV, le focus d'entrée d'un dialogue n'est pas
          // maîtrisé : il peut tomber sur le bouton destructeur, et OK est le
          // geste RÉFLEXE à la télécommande (§dlErgo l'avait déjà établi pour
          // les téléchargements). Constaté en conditions réelles le 2026-09-01 :
          // en visant le banc d'essai, le focus a atterri sur « Réinitialiser
          // les données d'usage ».
          //
          // ⚠️ L'autofocus va sur le bouton SÛR, jamais sur l'action. Sans
          // effet au tactile — c'est un correctif TV qui ne change rien sur
          // mobile.
          autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: kError, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Réinitialiser'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await Future.wait([
      FavoritesService.clear(),
      WatchProgressService.clearAll(),
      SearchHistoryService.clear(),
      LastWatchedChannelService.clear(),
    ]);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text("🧹 Données d'usage réinitialisées"),
        backgroundColor: kSuccess,
      ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.settingsTitle),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          // §settingsBg — Dégradé diagonal BI-COULEUR (vert primaire → surface →
          // magenta tertiaire), plus présent que l'ancien radial mono-teinte
          // quasi effacé. Alphas bas → le texte reste parfaitement lisible.
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    kAccentPrimary.withAlpha(36),
                    cs.surface,
                    kAccentTertiary.withAlpha(32),
                  ]
                : [
                    kAccentPrimary.withAlpha(16),
                    cs.surface,
                    kAccentTertiary.withAlpha(14),
                  ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            // §18 — Sur TV, on propose EN PREMIER l'accès à la Console web
            // (entrée prioritaire pour la télécommande, focusée d'emblée). Lance
            // un mini-serveur HTTP local + QR : le mobile devient une console
            // complète (comptes, sauvegarde, thème, TMDB, EPG, télécommande,
            // à propos). Aucun serveur tant que cette entrée n'est pas choisie.
            if (PlatformTv.isTv) ...[
              _SectionHeader(title: 'Piloter depuis le téléphone'),
              _SettingsTile(
                icon: Icons.smartphone,
                accentColor: kAccentPrimary,
                title: 'Console web',
                subtitle:
                    'Comptes, sauvegarde, thème, EPG, TMDB + télécommande (QR)',
                onTap: _openPhoneConfig,
              ),
              const SizedBox(height: 8),
            ],
            // §settingsGroups — 3 groupes, chacun une couleur d'accent du thème.
            // ── Groupe 1 : Sources & comptes (vert) ────────────────────────
            _SectionHeader(title: 'Sources & comptes', color: kAccentPrimary),
            _SettingsTile(
              icon: Icons.account_circle_outlined,
              accentColor: kAccentPrimary,
              title: 'Comptes IPTV',
              subtitle: 'Providers, stats playlist & recharger',
              onTap: _openAccounts,
            ),
            _SettingsTile(
              icon: Icons.movie_creation_outlined,
              accentColor: kAccentPrimary,
              title: 'Clé API TMDB',
              subtitle: 'Affiches, synopsis, casting (optionnel)',
              onTap: _openTmdbKey,
            ),
            _SettingsTile(
              icon: Icons.tv,
              accentColor: kAccentPrimary,
              title: 'Guide des chaînes',
              subtitle: 'EPG XMLTV — TNT France',
              onTap: _openXmltv,
            ),
            const SizedBox(height: 8),
            // ── Groupe 2 : Affichage (cyan) ────────────────────────────────
            _SectionHeader(title: 'Affichage', color: kAccentSecondary),
            _SettingsTile(
              icon: Icons.translate,
              accentColor: kAccentSecondary,
              title: 'Langues / régions',
              subtitle: 'Masquer le contenu étranger (réduit la mémoire)',
              onTap: _openRegionFilter,
            ),
            _SettingsTile(
              icon: Icons.palette_outlined,
              accentColor: kAccentSecondary,
              title: 'Personnalisation',
              subtitle: 'Thème, couleurs, effets cyberpunk',
              onTap: _openThemeSettings,
            ),
            // §perfSettings — Optimisation Fire Stick / box faibles.
            _SettingsTile(
              icon: Icons.speed,
              accentColor: kAccentSecondary,
              title: 'Optimisation',
              subtitle: 'Profils performance, hero, vignettes, mémoire',
              onTap: _openOptimisation,
            ),
            const SizedBox(height: 8),
            // ── Groupe 3 : Sauvegarde & application (magenta) ──────────────
            _SectionHeader(
                title: 'Sauvegarde & application', color: kAccentTertiary),
            _SettingsTile(
              icon: Icons.cloud_sync_outlined,
              accentColor: kAccentTertiary,
              title: 'Sauvegarde / Restauration',
              subtitle:
                  'Exporter/importer comptes, TMDB, thème, favoris (.aether chiffré)',
              onTap: _openBackup,
            ),
            _SettingsTile(
              icon: Icons.info_outline,
              accentColor: kAccentTertiary,
              title: 'À propos',
              subtitle: 'Version + vérification des mises à jour',
              onTap: _openAbout,
            ),
            // §resetUsage — Action destructive : accent kError (rouge) en
            // exception assumée du code couleur du groupe, pour signaler le danger.
            _SettingsTile(
              icon: Icons.delete_sweep_outlined,
              accentColor: kError,
              title: "Réinitialiser les données d'usage",
              subtitle: 'Vide favoris, reprises & historique (garde comptes & thème)',
              onTap: _resetUsageData,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Widgets internes ────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  /// §settingsGroups — Couleur du groupe : barre verticale + titre teinté.
  /// Si null, rendu neutre (gris, comportement historique).
  final Color? color;
  const _SectionHeader({required this.title, this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 20, 6),
      child: Row(
        children: [
          if (c != null) ...[
            Container(
              width: 4,
              height: 14,
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: c ?? cs.onSurfaceVariant.withAlpha(180),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color accentColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      // §3c-bis — Wrap FocusableCard (decorateOnly) pour afficher le focus
      // Matrix glow au D-pad sur TV. Sans ce wrap, le user naviguait dans la
      // liste sans aucun feedback visuel et avait l'impression d'être bloqué.
      // Le tap mobile reste géré par l'InkWell interne (decorateOnly).
      child: FocusableCard(
        decorateOnly: true,
        // §tvErgo — pas de scale (tuile pleine largeur → débordait à l'écran).
        scaleOnFocus: false,
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        // §tvErgo — ExcludeFocus : l'InkWell interne est focusable par défaut et
        // créait un 2e arrêt D-pad par tuile (doublon de sélection, sans glow).
        // On le retire de la traversée ; seul le Focus du FocusableCard reste.
        // Le tap tactile mobile fonctionne toujours (ExcludeFocus n'affecte que
        // le focus, pas les événements pointeur).
        child: ExcludeFocus(
          child: Material(
          color: cs.surfaceContainer,
          // §settingsBorder — Bordure de la tuile dans la couleur de l'icône
          // (= couleur du groupe) → renforce le code couleur, tuiles moins plates.
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: accentColor.withAlpha(70), width: 1),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            splashColor: accentColor.withAlpha(30),
            highlightColor: accentColor.withAlpha(15),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accentColor.withAlpha(30),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: accentColor.withAlpha(80), width: 1),
                    ),
                    child: Icon(icon, color: accentColor, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: cs.onSurfaceVariant.withAlpha(160)),
                ],
              ),
            ),
          ),
          ),
        ),
      ),
    );
  }
}
