import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/data/services/update_service.dart';
import 'package:aetherStream/feature/update/update_dialog.dart';
import 'package:aetherStream/widgets/memory_stats_card.dart';
import 'package:aetherStream/feature/settings/web_console/web_console_page.dart';
import 'package:aetherStream/widgets/tv/tv_initial_focus.dart';
import '../../l10n/app_localizations.dart';

/// Page À propos (§1L-e).
///
/// Remplace l'`AlertDialog` _showAbout() précédent. Aligne le style streaming
/// des autres sous-pages settings : Scaffold + RadialGradient, logo centré,
/// bloc version mono, CTA plein "Vérifier les mises à jour", liens externes
/// (GitHub / Releases) en boutons cohérents.
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> with TvInitialFocus {
  static const String _ghRepo = 'https://github.com/JuMANocta/2025_dwl_iptv_flutter';
  static const String _ghReleases = '$_ghRepo/releases';

  String _version = '—';
  String _build = '—';
  bool _loading = true;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _version = info.version;
      _build = info.buildNumber;
      _loading = false;
    });
  }

  Future<void> _checkUpdates() async {
    if (_checking) return;
    setState(() => _checking = true);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('🔍 Vérification des mises à jour…')),
    );
    final result = await UpdateService.checkForUpdateDetailed();
    if (!mounted) return;
    setState(() => _checking = false);
    // §userError — « Vous êtes à jour » n'est dit QUE si on a vraiment comparé
    // les versions ; un GitHub injoignable le dit, au lieu de rassurer à tort.
    switch (result) {
      case UpToDate():
        messenger.showSnackBar(
          const SnackBar(content: Text('Vous êtes à jour.')),
        );
      case UpdateUnavailable(reason: final reason):
        messenger.showSnackBar(
          SnackBar(content: Text('⚠️ Vérification impossible : $reason')),
        );
      case UpdateAvailable(info: final info):
        await UpdateDialog.show(context, info);
    }
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.aboutTitle),
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
                    kAccentTertiary.withAlpha(20),
                    cs.surface,
                  ],
                )
              : null,
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Logo(),
                    const SizedBox(height: 16),
                    Text(
                      'AetherStream',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Client IPTV Android — multi-comptes, EPG, replay, TMDB.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _VersionBadge(version: _version, buildNumber: _build),
                    const SizedBox(height: 20),
                    // §memStats — Section diagnostic pour profiler/débugger les
                    // gros providers (sur Fire Stick / Android TV avec ~180 Mo
                    // de playlists en mémoire, c'est utile de voir la conso).
                    const MemoryStatsCard(),
                    const SizedBox(height: 12),
                    // §tvLogs — Sur TV il n'y a pas de logcat : le journal de
                    // diagnostic se consulte depuis le téléphone en scannant le
                    // QR (et s'exporte en .txt pour être transmis).
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const WebConsolePage(initialView: 'logs'),
                        ),
                      ),
                      icon: const Icon(Icons.receipt_long),
                      label: const Text('Journal de diagnostic',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      style: FilledButton.styleFrom(
                        backgroundColor: kAccentTertiary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _checking ? null : _checkUpdates,
                      icon: _checking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Icon(Icons.system_update),
                      label: Text(
                        _checking
                            ? 'Vérification…'
                            : 'Vérifier les mises à jour',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: kAccentPrimary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // §detailsActions — boutons pleins (cohérence : plus de
                    // mélange plein/contour). Couleurs distinctes pour la lisibilité.
                    FilledButton.icon(
                      onPressed: () => _open(_ghRepo),
                      icon: const Icon(Icons.code),
                      label: const Text('Voir le code sur GitHub',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      style: FilledButton.styleFrom(
                        backgroundColor: kAccentSecondary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: () => _open(_ghReleases),
                      icon: const Icon(Icons.archive_outlined),
                      label: const Text('Toutes les releases',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      style: FilledButton.styleFrom(
                        backgroundColor: kAccentTertiary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 32),
                    _CreditFooter(),
                  ],
                ),
              ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              kAccentPrimary.withAlpha(60),
              kAccentPrimary.withAlpha(10),
              Colors.transparent,
            ],
          ),
          border: Border.all(color: kAccentPrimary.withAlpha(180), width: 2),
          boxShadow: [
            BoxShadow(
              color: kAccentPrimary.withAlpha(60),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(
          Icons.stream,
          size: 54,
          color: kAccentPrimary,
        ),
      ),
    );
  }
}

class _VersionBadge extends StatelessWidget {
  final String version;
  final String buildNumber;
  const _VersionBadge({required this.version, required this.buildNumber});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kAccentPrimary.withAlpha(80), width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.tag, size: 16, color: kAccentPrimary),
          const SizedBox(width: 8),
          Text(
            'VERSION',
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurfaceVariant,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$version+$buildNumber',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: kAccentPrimary,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _CreditFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          height: 1,
          color: cs.outlineVariant.withAlpha(80),
          margin: const EdgeInsets.symmetric(horizontal: 40),
        ),
        const SizedBox(height: 16),
        Text(
          'Made with Flutter · Media3/ExoPlayer',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: cs.onSurfaceVariant.withAlpha(180),
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}

// §memStats — La carte diagnostic mémoire vit désormais dans
// `lib/widgets/memory_stats_card.dart` (partagée avec OptimizationSettingsPage).
