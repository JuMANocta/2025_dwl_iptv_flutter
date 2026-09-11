import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/themes/aether_theme_extension.dart';
import '../../core/themes/colors.dart';
import '../../core/utils/platform_tv.dart';
import '../../core/utils/user_error.dart';
import '../../widgets/tv/focusable_card.dart';
import 'boot_log.dart';
import 'boot_shell.dart';
import '../../l10n/l10n_ext.dart';

/// §bootStates — Les états de démarrage, tous rendus dans le même décor.
///
/// Chacun est volontairement « bête » : il compose du contenu, le cadre et les
/// transitions sont dans [BootShell]. `_LaunchDecider` ne garde ainsi que sa
/// logique d'aiguillage.

/// État nominal : le démarrage travaille, on montre où il en est.
///
/// §bootEscape (2026-09-09) — ⚠️ **Cet écran n'offrait AUCUNE issue.** Le seul
/// bouton de reprise vit sur [BootErrorScreen], qui n'apparaît qu'après qu'une
/// exception a été levée : tant que le réseau ne répond ni ne tombe en erreur,
/// l'utilisateur n'avait d'autre recours que de tuer l'application — ce qu'il a
/// fait, en pensant à un blocage (signalement du 2026-09-08).
///
/// ⚠️ Le bouton n'apparaît **qu'après un délai** ([_escapeAfter]). Proposé dès
/// la première seconde, il inviterait à interrompre un démarrage parfaitement
/// normal : sur un gros catalogue, l'analyse dure légitimement des dizaines de
/// secondes. Il se montre quand l'attente commence à ressembler à une panne.
class BootLoadingScreen extends StatefulWidget {
  const BootLoadingScreen({super.key, this.onSkip});

  /// Appelé quand l'utilisateur choisit de ne plus attendre. `null` = pas de
  /// sortie proposée (l'appelant décide : il n'y en a pas toujours une qui ait
  /// du sens).
  final VoidCallback? onSkip;

  /// Au bout de combien de temps la sortie est proposée.
  static const Duration escapeAfter = Duration(seconds: 25);

  @override
  State<BootLoadingScreen> createState() => _BootLoadingScreenState();
}

class _BootLoadingScreenState extends State<BootLoadingScreen> {
  bool _offerEscape = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.onSkip == null) return;
    // ⚠️ Un `Timer`, jamais un ticker ni une animation : §bootCursorTimer a
    // déjà coûté les deux tiers du CPU de l'analyse pour un curseur clignotant
    // repeint à chaque vsync. Ici, un seul réveil.
    _timer = Timer(BootLoadingScreen.escapeAfter, () {
      if (mounted) setState(() => _offerEscape = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BootShell(
      stateKey: 'loading',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BootLog(),
          if (_offerEscape && widget.onSkip != null) ...[
            const SizedBox(height: 18),
            Text(
              context.l10n.bootSlowHint,
              textAlign: TextAlign.center,
              style: GoogleFonts.sourceCodePro(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: PlatformTv.isTv ? 13 : 11.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            _BootAction(
              label: context.l10n.bootContinueAnyway,
              icon: Icons.skip_next_rounded,
              onTap: widget.onSkip!,
              filled: false,
              // ⚠️ PAS d'autofocus : sur TV, le focus arriverait sur « ne plus
              // attendre » au moment précis où l'écran est le plus fragile.
              accent: kAccentSecondary,
            ),
          ],
        ],
      ),
    );
  }
}

/// État d'échec.
///
/// **Ce qu'il corrige** : l'ancien écran affichait `Icons.error_outline` en
/// `Colors.red` **codé en dur** — donc insensible au thème — avec des boutons
/// Material nus dont le focus est à peine visible à la télécommande. Or c'est
/// exactement le moment où l'utilisateur a besoin de comprendre et d'agir.
class BootErrorScreen extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  final VoidCallback onOpenAccounts;

  const BootErrorScreen({
    super.key,
    required this.error,
    required this.onRetry,
    required this.onOpenAccounts,
  });

  @override
  Widget build(BuildContext context) {
    return BootShell(
      stateKey: 'error',
      child: _BootPanel(
        accent: kError,
        title: context.l10n.bootFailedTitle,
        message: context.l10n.bootFailedBody,
        // §userError — `error.toString()` d'origine affichait le préfixe
        // Dart natif (« HttpException: … ») et, pour tout ce qui n'a pas déjà
        // été mis en français par `playlist_service.dart`, le message brut
        // d'une exception — jamais garanti sans URL ni identifiant. Le détail
        // technique reste consultable mais ne domine pas : il s'adresse au
        // diagnostic, pas à l'utilisateur qui veut juste relancer.
        detail: describeError(error),
        primaryLabel: context.l10n.playerRetry,
        primaryIcon: Icons.refresh_rounded,
        onPrimary: onRetry,
        secondaryLabel: context.l10n.bootCheckAccounts,
        secondaryIcon: Icons.manage_accounts_outlined,
        onSecondary: onOpenAccounts,
      ),
    );
  }
}

/// État « aucun compte configuré ».
///
/// L'ergonomie d'origine est conservée telle quelle (Console web en action
/// principale sur TV, AccountsPage sur mobile, restauration `.aether`) — c'est
/// son habillage qui décrochait : `AppBar`, icône Material, ni wordmark ni glow.
class BootNoAccountScreen extends StatelessWidget {
  final VoidCallback onOpenWebConsole;
  final VoidCallback onOpenAccounts;
  final VoidCallback onRestoreBackup;

  const BootNoAccountScreen({
    super.key,
    required this.onOpenWebConsole,
    required this.onOpenAccounts,
    required this.onRestoreBackup,
  });

  @override
  Widget build(BuildContext context) {
    final bool isTv = PlatformTv.isTv;
    return BootShell(
      stateKey: 'noAccount',
      child: _BootPanel(
        accent: kAccentSecondary,
        title: context.l10n.bootNoAccountTitle,
        message: isTv
            ? context.l10n.bootNoAccountTv
            : context.l10n.bootNoAccountPhone,
        // §webConsoleOnly — Sur TV, la Console web est l'action PRINCIPALE,
        // donc celle qui prend le focus D-pad : depuis une télécommande, la
        // saisie manuelle n'est pas une option raisonnable.
        primaryLabel:
            isTv
                ? context.l10n.bootConfigureFromPhone
                : context.l10n.bootConfigureAccounts,
        primaryIcon: isTv ? Icons.phone_iphone : Icons.settings,
        onPrimary: isTv ? onOpenWebConsole : onOpenAccounts,
        // Sur mobile la Console web reste proposée en second (clavier de PC
        // confortable pour une longue URL) ; sur TV c'est la saisie manuelle.
        secondaryLabel:
            isTv
                ? context.l10n.bootEnterManually
                : context.l10n.bootConfigureWebConsole,
        secondaryIcon: isTv ? Icons.keyboard_alt_outlined : Icons.language,
        onSecondary: isTv ? onOpenAccounts : onOpenWebConsole,
        tertiaryLabel: context.l10n.bootRestoreBackup,
        tertiaryIcon: Icons.cloud_download_outlined,
        onTertiary: onRestoreBackup,
      ),
    );
  }
}

/// Panneau d'état : un titre, un message, une action dominante, des actions
/// secondaires en retrait.
///
/// La hiérarchie est volontairement franche — dans un écran de démarrage bloqué,
/// l'utilisateur doit voir *une* chose à faire, pas quatre boutons équivalents.
class _BootPanel extends StatelessWidget {
  final Color accent;
  final String title;
  final String message;
  final String? detail;

  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback onPrimary;

  final String secondaryLabel;
  final IconData secondaryIcon;
  final VoidCallback onSecondary;

  final String? tertiaryLabel;
  final IconData? tertiaryIcon;
  final VoidCallback? onTertiary;

  const _BootPanel({
    required this.accent,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.secondaryIcon,
    required this.onSecondary,
    this.detail,
    this.tertiaryLabel,
    this.tertiaryIcon,
    this.onTertiary,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ext = Theme.of(context).extension<AetherThemeExtension>();
    final bool isTv = PlatformTv.isTv;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: GoogleFonts.sourceCodePro(
            color: accent,
            fontSize: isTv ? 20 : 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          message,
          textAlign: TextAlign.center,
          style: GoogleFonts.sourceCodePro(
            color: cs.onSurfaceVariant,
            fontSize: isTv ? 15 : 12.5,
            height: 1.5,
          ),
        ),
        if (detail != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: ext?.glassCard() ??
                BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
            child: Text(
              detail!,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.sourceCodePro(
                color: cs.onSurfaceVariant.withValues(alpha: 0.55),
                fontSize: isTv ? 12 : 10.5,
                height: 1.5,
              ),
            ),
          ),
        ],
        SizedBox(height: isTv ? 28 : 22),
        _BootAction(
          label: primaryLabel,
          icon: primaryIcon,
          onTap: onPrimary,
          filled: true,
          autofocus: true,
          accent: accent,
        ),
        const SizedBox(height: 10),
        _BootAction(
          label: secondaryLabel,
          icon: secondaryIcon,
          onTap: onSecondary,
          filled: false,
          accent: accent,
        ),
        if (tertiaryLabel != null && onTertiary != null) ...[
          const SizedBox(height: 10),
          _BootAction(
            label: tertiaryLabel!,
            icon: tertiaryIcon ?? Icons.chevron_right,
            onTap: onTertiary!,
            filled: false,
            accent: accent,
          ),
        ],
      ],
    );
  }
}

/// Action du panneau — focusable au D-pad, contrairement aux boutons Material
/// nus d'avant : sur TV, un démarrage en échec devenait très vite un cul-de-sac.
class _BootAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  final bool autofocus;
  final Color accent;

  const _BootAction({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.filled,
    required this.accent,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bool isTv = PlatformTv.isTv;
    final Color fg = filled ? cs.surface : cs.onSurface;

    return FocusableCard(
      onTap: onTap,
      autofocus: autofocus,
      scaleOnFocus: false,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: isTv ? 16 : 13, horizontal: 14),
        decoration: BoxDecoration(
          color: filled ? accent : Colors.transparent,
          border: Border.all(
            color: filled ? accent : cs.outlineVariant,
            width: 1.4,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: isTv ? 22 : 18, color: fg),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.sourceCodePro(
                  color: fg,
                  fontSize: isTv ? 15 : 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
