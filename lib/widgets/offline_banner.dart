import 'package:flutter/material.dart';

import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/data/services/network_status_service.dart';
import 'package:aetherStream/l10n/l10n_ext.dart';

/// §offlineBoot (2026-09-06, lot 6) — Bandeau « hors ligne », réutilisable.
///
/// Il n'existe que quand [NetworkStatusService.offline] est vrai : le reste
/// du temps il ne prend aucune place. Posé en tête de l'accueil (les listes en
/// cache s'affichent, mais rien ne se lit en flux) et de l'écran de démarrage
/// hors ligne (les fichiers téléchargés, seuls).
class OfflineBanner extends StatelessWidget {
  /// Optionnel : « Réessayer » relance ce que l'appelant veut (le démarrage).
  final VoidCallback? onRetry;

  const OfflineBanner({super.key, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: NetworkStatusService.offline,
      builder: (context, off, _) {
        if (!off) return const SizedBox.shrink();
        final cs = Theme.of(context).colorScheme;
        return Material(
          color: kWarning.withAlpha(36),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.wifi_off_rounded, color: kWarning, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.l10n.offlineBannerTitle,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (onRetry != null)
                    TextButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(context.l10n.offlineBannerRetry),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
