import 'package:flutter/material.dart';

import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/core/utils/platform_tv.dart';
import 'package:aetherStream/data/services/web_console_service.dart';
import 'package:aetherStream/l10n/l10n_ext.dart';

/// §webConsolePersist — revue 2026-09-11, D1B-02 — Bandeau « console web
/// ouverte », posé à côté du bandeau hors ligne.
///
/// **Le défaut réparé.** La console survit à son écran (la télécommande du
/// téléphone doit continuer de piloter la TV) : elle restait donc joignable
/// sur le réseau local jusqu'à 30 min sans que RIEN dans l'app ne le dise.
/// Ce bandeau n'existe que tant que le serveur écoute ; absent, il ne prend
/// aucune place.
///
/// ⚠️ **Sur TV, aucun élément focusable** (`ExcludeFocus`) : un bouton en tête
/// du contenu s'insérerait dans la traversée D-pad de l'accueil (§dpadRestore).
/// L'arrêt se fait depuis l'écran Console web (Paramètres). Au doigt, un
/// bouton « Arrêter » suffit.
class WebConsoleBanner extends StatelessWidget {
  const WebConsoleBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final WebConsoleService console = WebConsoleService.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: console.running,
      builder: (context, on, _) {
        if (!on) return const SizedBox.shrink();
        final cs = Theme.of(context).colorScheme;
        final bool isTv = PlatformTv.isTv;
        return ExcludeFocus(
          excluding: isTv,
          child: Material(
            color: kAccentSecondary.withAlpha(36),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.cast_connected_rounded,
                        color: kAccentSecondary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.l10n.consoleActiveBanner,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (!isTv)
                      TextButton(
                        onPressed: console.stop,
                        child: Text(context.l10n.consoleStopServer),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
