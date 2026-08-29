import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/themes/aether_theme_extension.dart';
import '../../core/themes/colors.dart';
import '../../core/utils/platform_tv.dart';
import '../../widgets/tv/focusable_card.dart';
import 'boot_log.dart';
import 'boot_shell.dart';

/// §bootStates — Les états de démarrage, tous rendus dans le même décor.
///
/// Chacun est volontairement « bête » : il compose du contenu, le cadre et les
/// transitions sont dans [BootShell]. `_LaunchDecider` ne garde ainsi que sa
/// logique d'aiguillage.

/// État nominal : le démarrage travaille, on montre où il en est.
class BootLoadingScreen extends StatelessWidget {
  const BootLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const BootShell(stateKey: 'loading', child: BootLog());
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
        title: 'Démarrage interrompu',
        message: 'L\'application n\'a pas réussi à charger ta playlist.',
        // Le détail technique reste consultable mais ne domine pas : il
        // s'adresse au diagnostic, pas à l'utilisateur qui veut juste relancer.
        detail: error.toString(),
        primaryLabel: 'Réessayer',
        primaryIcon: Icons.refresh_rounded,
        onPrimary: onRetry,
        secondaryLabel: 'Vérifier les comptes',
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
        title: 'Aucun compte configuré',
        message: isTv
            ? 'Scanne un QR code avec ton téléphone pour gérer tes playlists '
                'sans avoir à taper à la télécommande.'
            : 'Ajoute un compte pour commencer.',
        // §webConsoleOnly — Sur TV, la Console web est l'action PRINCIPALE,
        // donc celle qui prend le focus D-pad : depuis une télécommande, la
        // saisie manuelle n'est pas une option raisonnable.
        primaryLabel:
            isTv ? 'Configurer depuis mon téléphone' : 'Configurer les comptes',
        primaryIcon: isTv ? Icons.phone_iphone : Icons.settings,
        onPrimary: isTv ? onOpenWebConsole : onOpenAccounts,
        // Sur mobile la Console web reste proposée en second (clavier de PC
        // confortable pour une longue URL) ; sur TV c'est la saisie manuelle.
        secondaryLabel:
            isTv ? 'Saisir manuellement' : 'Configurer via Console web',
        secondaryIcon: isTv ? Icons.keyboard_alt_outlined : Icons.language,
        onSecondary: isTv ? onOpenAccounts : onOpenWebConsole,
        tertiaryLabel: 'Restaurer une sauvegarde',
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
