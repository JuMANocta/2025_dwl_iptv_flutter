import 'package:flutter/material.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/core/themes/aether_theme_extension.dart';
import 'package:aetherStream/feature/accounts/accounts_page.dart';
import 'package:aetherStream/feature/settings/about_page.dart';
import 'package:aetherStream/feature/settings/backup_page.dart';
import 'package:aetherStream/feature/settings/theme_settings_page.dart';
import 'package:aetherStream/feature/settings/tmdb_key_page.dart';
import 'package:aetherStream/feature/settings/xmltv_page.dart';

/// Hub principal des paramètres (§1b — phase 5).
///
/// Menu organisé qui sert de point d'entrée unique depuis le bouton ⚙️ de la
/// `HomePage`. Chaque item ouvre soit une sous-page existante, soit un dialog
/// d'action courte.
///
/// Sections :
///   - 👤 Comptes IPTV  → [AccountsPage]
///   - 🎨 Personnalisation → [ThemeSettingsPage]
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
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Paramètres'),
        backgroundColor: Colors.transparent,
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
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _SectionHeader(title: 'Configuration'),
              _SettingsTile(
                icon: Icons.account_circle_outlined,
                accentColor: kAccentPrimary,
                title: 'Comptes IPTV',
                subtitle: 'Providers, stats playlist & recharger',
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

class _SettingsTile extends StatefulWidget {
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
  State<_SettingsTile> createState() => _SettingsTileState();
}

class _SettingsTileState extends State<_SettingsTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ext = Theme.of(context).extension<AetherThemeExtension>()!;
    final isFocused = _focused;
    final radius = BorderRadius.circular(ext.borderRadius);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Material(
        color:
            isFocused ? widget.accentColor.withAlpha(40) : cs.surfaceContainer,
        borderRadius: radius,
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: (v) => setState(() => _focused = v),
          borderRadius: radius,
          splashColor: widget.accentColor.withAlpha(30),
          highlightColor: widget.accentColor.withAlpha(15),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: isFocused ? widget.accentColor : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: widget.accentColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(
                        ext.borderRadius > 10 ? 10 : ext.borderRadius),
                    border: Border.all(
                        color: widget.accentColor.withAlpha(80), width: 1),
                  ),
                  child: Icon(widget.icon, color: widget.accentColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: isFocused
                        ? widget.accentColor
                        : cs.onSurfaceVariant.withAlpha(160)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
