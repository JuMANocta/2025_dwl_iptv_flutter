import 'package:flutter/material.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/feature/accounts/accounts_page.dart';
import 'package:aetherStream/feature/accounts/playlist_management_page.dart';
import 'package:aetherStream/feature/settings/about_page.dart';
import 'package:aetherStream/feature/settings/backup_page.dart';
import 'package:aetherStream/feature/settings/theme_settings_page.dart';
import 'package:aetherStream/feature/settings/tmdb_key_page.dart';
import 'package:aetherStream/feature/settings/xmltv_page.dart';
import 'package:aetherStream/widgets/tv/focusable_card.dart';

/// Hub principal des paramètres (§1b — phase 5).
///
/// Menu organisé qui sert de point d'entrée unique depuis le bouton ⚙️ de la
/// `HomePage`. Chaque item ouvre soit une sous-page existante, soit un dialog
/// d'action courte.
///
/// Sections :
///   - 👤 Comptes IPTV  → [AccountsPage]
///   - 🎨 Personnalisation → [ThemeSettingsPage]
///   - 📊 Statistiques playlist → [PlaylistManagementPage] (Recharger par compte)
///   - ℹ️ À propos (version + check MAJ in-app)
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
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

  Future<void> _openPlaylistStats() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlaylistManagementPage()),
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: isDark ? null : cs.surface,
          gradient: isDark
              ? RadialGradient(
                  center: const Alignment(0, -1.5),
                  radius: 1.4,
                  colors: [
                    kAccentPrimary.withAlpha(20),
                    cs.surface,
                  ],
                )
              : null,
        ),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            _SectionHeader(title: 'Configuration'),
            _SettingsTile(
              icon: Icons.account_circle_outlined,
              accentColor: kAccentPrimary,
              title: 'Comptes IPTV',
              subtitle: 'Providers et identifiants',
              onTap: _openAccounts,
            ),
            _SettingsTile(
              icon: Icons.movie_creation_outlined,
              accentColor: kAccentTertiary,
              title: 'Clé API TMDB',
              subtitle: 'Affiches, synopsis, casting (optionnel)',
              onTap: _openTmdbKey,
            ),
            _SettingsTile(
              icon: Icons.tv,
              accentColor: kAccentSecondary,
              title: 'Guide des chaînes',
              subtitle: 'EPG XMLTV — TNT France',
              onTap: _openXmltv,
            ),
            _SettingsTile(
              icon: Icons.palette_outlined,
              accentColor: kAccentSecondary,
              title: 'Personnalisation',
              subtitle: 'Thème, couleurs, effets cyberpunk',
              onTap: _openThemeSettings,
            ),
            const SizedBox(height: 8),
            _SectionHeader(title: 'Playlist'),
            _SettingsTile(
              icon: Icons.bar_chart,
              accentColor: kAccentPrimary,
              title: 'Statistiques playlist',
              subtitle: 'Stats par compte + recharger depuis ici',
              onTap: _openPlaylistStats,
            ),
            const SizedBox(height: 8),
            _SectionHeader(title: 'Sauvegarde'),
            _SettingsTile(
              icon: Icons.cloud_sync_outlined,
              accentColor: kAccentSecondary,
              title: 'Sauvegarde / Restauration',
              subtitle:
                  'Exporter/importer comptes, TMDB, thème, favoris (.aether chiffré)',
              onTap: _openBackup,
            ),
            const SizedBox(height: 8),
            _SectionHeader(title: 'Application'),
            _SettingsTile(
              icon: Icons.info_outline,
              accentColor: kAccentTertiary,
              title: 'À propos',
              subtitle: 'Version + vérification des mises à jour',
              onTap: _openAbout,
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
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
          color: cs.onSurfaceVariant.withAlpha(180),
        ),
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
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Material(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
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
    );
  }
}
