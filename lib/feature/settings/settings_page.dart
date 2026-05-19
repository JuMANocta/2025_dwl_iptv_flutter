import 'dart:io';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/data/services/parsed_playlist_service.dart';
import 'package:aetherStream/data/services/playlist_service.dart';
import 'package:aetherStream/data/services/stream_account_service.dart';
import 'package:aetherStream/data/services/update_service.dart';
import 'package:aetherStream/feature/accounts/accounts_page.dart';
import 'package:aetherStream/feature/accounts/playlist_management_page.dart';
import 'package:aetherStream/feature/settings/theme_settings_page.dart';
import 'package:aetherStream/feature/settings/tmdb_key_page.dart';
import 'package:aetherStream/feature/settings/xmltv_page.dart';
import 'package:aetherStream/feature/update/update_dialog.dart';

/// Hub principal des paramètres (§1b — phase 5).
///
/// Menu organisé qui sert de point d'entrée unique depuis le bouton ⚙️ de la
/// `HomePage`. Chaque item ouvre soit une sous-page existante, soit un dialog
/// d'action courte.
///
/// Sections :
///   - 👤 Comptes IPTV  → [AccountsPage]
///   - 🎨 Personnalisation → [ThemeSettingsPage]
///   - 🔄 Recharger la playlist (avec confirmation < 24h)
///   - ℹ️ À propos (version + check MAJ in-app)
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _reloading = false;

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

  Future<void> _reloadPlaylist() async {
    if (_reloading) return;

    // Confirmation si la playlist a moins de 24h (évite un téléchargement
    // inutile coûteux en bande passante).
    try {
      final path = await PlaylistService.playlistPath();
      final file = File(path);
      if (await file.exists()) {
        final age = DateTime.now().difference(await file.lastModified());
        if (age.inHours < 24) {
          final ok = await _confirmReload(age);
          if (ok != true) return;
        }
      }
    } catch (_) {
      // Pas de playlist actuelle → on télécharge sans confirmation
    }

    if (!mounted) return;
    setState(() => _reloading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final acc = await StreamAccountService.getCurrentAccount();
      if (acc == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Aucun compte actif.')),
        );
        return;
      }
      await PlaylistService.downloadCurrentM3U();
      ParsedPlaylistService.invalidate(acc.id);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: const Text('✅ Playlist rechargée — relance l\'app pour voir les nouveautés.'),
          backgroundColor: kAccentPrimary.withAlpha(180),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Échec du rechargement : $e')),
      );
    } finally {
      if (mounted) setState(() => _reloading = false);
    }
  }

  Future<bool?> _confirmReload(Duration age) {
    final h = age.inHours;
    final m = age.inMinutes % 60;
    final ageStr = h > 0 ? '${h}h${m > 0 ? ' ${m}min' : ''}' : '${m}min';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recharger la playlist ?'),
        content: Text(
          'Playlist récupérée il y a $ageStr.\n'
          'Recharger quand même depuis le serveur ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Recharger',
              style: TextStyle(color: kWarning, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAbout() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AetherStream'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version ${info.version}+${info.buildNumber}'),
            const SizedBox(height: 8),
            Text(
              'Client IPTV Android — multi-comptes, EPG, replay, TMDB.',
              style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _checkUpdates();
            },
            child: const Text('Vérifier les mises à jour'),
          ),
        ],
      ),
    );
  }

  Future<void> _checkUpdates() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('🔍 Vérification des mises à jour…')),
    );
    final info = await UpdateService.checkForUpdate();
    if (!mounted) return;
    if (info == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Vous êtes à jour.')),
      );
      return;
    }
    await UpdateDialog.show(context, info);
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
              subtitle: 'Détails films, séries, chaînes du compte actif',
              onTap: _openPlaylistStats,
            ),
            _SettingsTile(
              icon: Icons.refresh,
              accentColor: kWarning,
              title: 'Recharger la playlist',
              subtitle: _reloading
                  ? 'Téléchargement en cours…'
                  : 'Forcer le téléchargement depuis le serveur',
              trailing: _reloading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onTap: _reloadPlaylist,
            ),
            const SizedBox(height: 8),
            _SectionHeader(title: 'Application'),
            _SettingsTile(
              icon: Icons.info_outline,
              accentColor: kAccentTertiary,
              title: 'À propos',
              subtitle: 'Version + vérification des mises à jour',
              onTap: _showAbout,
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
  final Widget? trailing;

  const _SettingsTile({
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
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
                trailing ?? Icon(Icons.chevron_right, color: cs.onSurfaceVariant.withAlpha(160)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
