import 'package:flutter/material.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/core/utils/platform_tv.dart';
import 'package:aetherStream/data/services/xmltv_service.dart';

/// Sous-page Settings (§1g) : guide des chaînes XMLTV.
///
/// Source unique : `https://xmltvfr.fr/xmltv/xmltv_tnt.xml` (TNT France).
/// Le cache est rafraîchi automatiquement toutes les 12h ; cette page permet
/// un refresh manuel + affiche l'état du cache (date du dernier chargement,
/// nombre de chaînes indexées).
class XmltvPage extends StatefulWidget {
  const XmltvPage({super.key});

  @override
  State<XmltvPage> createState() => _XmltvPageState();
}

class _XmltvPageState extends State<XmltvPage> {
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    // §19 — Auto-focus initial sur TV.
    if (PlatformTv.isTv) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) FocusScope.of(context).nextFocus();
      });
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      XmltvService.invalidate();
      await XmltvService.ensureLoaded();
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('✅ Guide des chaînes mis à jour'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('❌ Échec mise à jour : $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  String _formatAge(DateTime? loadedAt) {
    if (loadedAt == null) return 'Jamais chargé';
    final age = DateTime.now().difference(loadedAt);
    if (age.inMinutes < 1) return 'À l\'instant';
    if (age.inMinutes < 60) return 'il y a ${age.inMinutes} min';
    if (age.inHours < 24) return 'il y a ${age.inHours} h';
    return 'il y a ${age.inDays} j';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final loadedAt = XmltvService.loadedAt;
    final channels = XmltvService.channelCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Guide des chaînes'),
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
                    kAccentSecondary.withAlpha(20),
                    cs.surface,
                  ],
                )
              : null,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Bandeau statut ─────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      kAccentSecondary.withAlpha(30),
                      kAccentPrimary.withAlpha(15),
                    ],
                  ),
                  border: Border.all(
                      color: kAccentSecondary.withAlpha(120), width: 1),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: kAccentSecondary.withAlpha(30),
                        border: Border.all(
                            color: kAccentSecondary.withAlpha(180), width: 1.5),
                      ),
                      child: Icon(Icons.tv, color: kAccentSecondary, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TNT France',
                            style: TextStyle(
                              color: cs.onSurface,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            channels > 0
                                ? '$channels chaînes · ${_formatAge(loadedAt)}'
                                : 'Cache vide',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Bouton refresh ─────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _refreshing ? null : _refresh,
                  icon: _refreshing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(
                    _refreshing
                        ? 'Téléchargement en cours…'
                        : 'Forcer la mise à jour',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: kAccentSecondary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ── Bloc info source ──────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 18, color: kAccentSecondary),
                        const SizedBox(width: 8),
                        Text(
                          'Comment ça marche',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• Source publique : xmltvfr.fr (TNT France)\n'
                      '• Cache local 12 h — mise à jour silencieuse au démarrage si périmé\n'
                      '• Couvre les principales chaînes françaises (TF1, France 2, M6, ARTE…)\n'
                      '• Utilisé pour le bloc "En cours / Ensuite" + la grille replay',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
