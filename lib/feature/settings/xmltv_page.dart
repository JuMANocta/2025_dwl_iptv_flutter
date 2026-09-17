import 'package:flutter/material.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/core/themes/themes.dart';
import 'package:aetherStream/core/themes/light_palette.dart';
import 'package:aetherStream/core/utils/user_error.dart';
import 'package:aetherStream/data/services/xmltv_service.dart';
import 'package:aetherStream/widgets/tv/tv_initial_focus.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_ext.dart';

/// Sous-page Settings (§1g) : guide des chaînes XMLTV.
///
/// Source unique : `https://xmltvfr.fr/xmltv/xmltv_tnt.xml` (TNT France).
/// Le cache est rafraîchi automatiquement toutes les 24h ; cette page permet
/// un refresh manuel + affiche l'état du cache (date du dernier chargement,
/// nombre de chaînes indexées).
class XmltvPage extends StatefulWidget {
  const XmltvPage({super.key});

  @override
  State<XmltvPage> createState() => _XmltvPageState();
}

class _XmltvPageState extends State<XmltvPage> with TvInitialFocus {
  bool _refreshing = false;


  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Revue 2026-09-11, D1B-04 — `invalidate` + `ensureLoaded` relisait le
      // fichier de moins de 24 h : aucune requête ne partait, et la page
      // annonçait pourtant « Guide mis à jour ». `refresh()` télécharge
      // vraiment et dit si un guide neuf est arrivé.
      final bool fresh = await XmltvService.refresh();
      if (!mounted) return;
      messenger.clearSnackBars();
      // D4B-08 — texte noir ou blanc selon le fond d'état (le thème impose
      // du blanc, illisible sur un vert vif).
      final Color tone = fresh ? kSuccess : kWarning;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            fresh
                ? context.l10n.xmltvUpdated
                : context.l10n.xmltvUpdateUnavailable,
            style: TextStyle(color: onColorFor(tone)),
          ),
          backgroundColor: tone,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.l10n.xmltvUpdateFailed(describeError(e)),
              style: TextStyle(color: onColorFor(kError))),
          backgroundColor: kError,
        ),
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  String _formatAge(DateTime? loadedAt) {
    if (loadedAt == null) return L10n.current.xmltvNeverLoaded;
    final age = DateTime.now().difference(loadedAt);
    if (age.inMinutes < 1) return L10n.current.xmltvJustNow;
    if (age.inMinutes < 60) return L10n.current.acctAgeMinutes(age.inMinutes);
    if (age.inHours < 24) return L10n.current.acctAgeHours(age.inHours);
    return L10n.current.acctAgeDays(age.inDays);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final loadedAt = XmltvService.loadedAt;
    final channels = XmltvService.channelCount;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.xmltvTitle),
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
                                ? context.l10n.xmltvChannelsAndAge(
                                    channels, _formatAge(loadedAt))
                                // D4B-05 — « Cache vide » : en dur, et de
                                // la mécanique (§clientText).
                                : context.l10n.xmltvNoGuide,
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
                        ? context.l10n.xmltvDownloading
                        : context.l10n.xmltvForceUpdate,
                  ),
                  style: aetherFilledStyle(kAccentSecondary),
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
                          context.l10n.bkHowTitle,
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
                      context.l10n.xmltvHowBody,
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
