import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/core/utils/platform_tv.dart';
import 'package:aetherStream/data/services/parsed_playlist_service.dart';
import 'package:aetherStream/data/services/stream_account_service.dart';
import 'package:aetherStream/data/services/update_service.dart';
import 'package:aetherStream/feature/update/update_dialog.dart';

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

class _AboutPageState extends State<AboutPage> {
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
    // §19 — Auto-focus initial sur TV (sur "Vérifier MAJ").
    if (PlatformTv.isTv) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) FocusScope.of(context).nextFocus();
      });
    }
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
    final info = await UpdateService.checkForUpdate();
    if (!mounted) return;
    setState(() => _checking = false);
    if (info == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Vous êtes à jour.')),
      );
      return;
    }
    await UpdateDialog.show(context, info);
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
        title: const Text('À propos'),
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
                    const _MemoryStatsCard(),
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
          'Made with Flutter · MediaKit · libmpv',
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

// ─── §memStats — Section diagnostic mémoire ─────────────────────────────────

class _MemoryStatsCard extends StatefulWidget {
  const _MemoryStatsCard();

  @override
  State<_MemoryStatsCard> createState() => _MemoryStatsCardState();
}

class _MemoryStatsCardState extends State<_MemoryStatsCard> {
  ({int rssMb, int maxRssMb, List<({String label, int entries, int diskMb})> accounts})? _stats;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final rss = (ProcessInfo.currentRss / (1024 * 1024)).round();
      final maxRss = (ProcessInfo.maxRss / (1024 * 1024)).round();
      final accounts = await StreamAccountService.listAccounts();
      final supportDir = await getApplicationSupportDirectory();
      final docsDir = await getApplicationDocumentsDirectory();
      final list = <({String label, int entries, int diskMb})>[];
      for (final acc in accounts) {
        final entries = ParsedPlaylistService.getAccount(acc.id)?.entries.length ?? 0;
        // playlist M3U
        final m3u = File('${docsDir.path}/playlist_${acc.id}.m3u');
        // parsed cache JSON.gz
        final json = File('${supportDir.path}/parsed_playlist_${acc.id}.json.gz');
        int disk = 0;
        if (await m3u.exists()) disk += await m3u.length();
        if (await json.exists()) disk += await json.length();
        list.add((
          label: acc.label,
          entries: entries,
          diskMb: (disk / (1024 * 1024)).round(),
        ));
      }
      if (!mounted) return;
      setState(() => _stats = (rssMb: rss, maxRssMb: maxRss, accounts: list));
    } catch (_) {
      // silencieux
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = _stats;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: kAccentPrimary.withAlpha(60),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.memory, size: 16, color: kAccentPrimary),
              const SizedBox(width: 8),
              Text(
                'MÉMOIRE & STOCKAGE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: kAccentPrimary,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 16),
                onPressed: _busy ? null : _refresh,
                tooltip: 'Rafraîchir',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (s == null)
            Text(
              'Calcul en cours…',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            )
          else ...[
            _statRow(context, 'RAM process',
                '${s.rssMb} Mo (peak ${s.maxRssMb} Mo)'),
            const SizedBox(height: 6),
            for (final a in s.accounts)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _statRow(
                  context,
                  a.label,
                  '${a.entries.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ')} entrées · ${a.diskMb} Mo disque',
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _statRow(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}
