import 'package:flutter/material.dart';

import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/feature/downloads/downloads_page.dart';
import 'package:aetherStream/l10n/l10n_ext.dart';
import 'package:aetherStream/widgets/offline_banner.dart';

/// §offlineBoot (2026-09-06, lot 6) — Le démarrage a échoué SANS réseau et
/// des fichiers téléchargés existent : au lieu de « Démarrage interrompu »,
/// les fichiers, tout de suite, coiffés du bandeau hors ligne.
///
/// Le retour du réseau relance le démarrage sans rien demander
/// (`_LaunchDecider` écoute `NetworkStatusService.offline`) ; le bouton
/// « Réessayer » du bandeau sert à ne pas attendre le sondage (15 s).
class BootOfflineScreen extends StatelessWidget {
  final VoidCallback onRetry;

  const BootOfflineScreen({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(
        children: [
          OfflineBanner(onRetry: onRetry),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: kWarning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.offlineBootMessage,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          const Expanded(child: DownloadsPage()),
        ],
      ),
    );
  }
}
