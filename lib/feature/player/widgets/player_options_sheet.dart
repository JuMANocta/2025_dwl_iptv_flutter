import 'package:flutter/material.dart';

import '../../../core/themes/colors.dart';
import '../../../widgets/tv/focusable_card.dart';
import '../../../widgets/tv/tv_adaptive_modal.dart';
import '../video_fit.dart';

/// §tourFix — LA liste des vitesses de lecture, unique pour toute l'app.
///
/// Elle existait en DOUBLE (ici et dans `PlayerControls._speeds`), chacune
/// alimentant son propre état : le badge inline et la coche du sous-menu
/// pouvaient se contredire (badge TV figé à 1.0×). La vitesse n'a plus qu'un
/// propriétaire (`_PlayerPageState._speed`) et une seule liste — celle-ci.
const List<double> kPlaybackSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

/// §tvPlayerNav — Panneau d'OPTIONS du lecteur : le « centre de contrôle » TV
/// ouvert via ↑ à la télécommande (mobile peut aussi y accéder). Tous les items
/// sont des [FocusableCard] → navigables au D-pad, contrairement aux boutons
/// inline (GestureDetector) inatteignables sur TV. Regroupe : pistes audio/
/// sous-titres, vitesse, épisode suivant.
Future<void> showPlayerOptions(
  BuildContext context, {
  required bool hasNext,
  required String speedLabel,
  required VideoFitMode fitMode,
  required bool statsEnabled,
  required VoidCallback onTracks,
  required VoidCallback onSpeed,
  required VoidCallback onFit,
  required VoidCallback onToggleStats,
  VoidCallback? onNext,
}) {
  return showAdaptiveActionSheet<void>(
    context: context,
    scrollable: false,
    builder: (_) => OptionsSheetBody(
      title: 'Options',
      icon: Icons.tune_rounded,
      children: [
        // §tvOptionsOrder — « Épisode suivant » EN PREMIER (série en cours) :
        // c'est l'action la plus fréquente du panneau, elle reçoit le focus
        // initial au D-pad au lieu d'être en dernière position.
        if (onNext != null)
          OptionSheetRow(
            icon: Icons.skip_next_rounded,
            accent: kAccentTertiary,
            title: 'Épisode suivant',
            subtitle: "Passer à l'épisode suivant",
            onTap: onNext,
          ),
        OptionSheetRow(
          icon: Icons.subtitles_rounded,
          accent: kAccentSecondary,
          title: 'Pistes audio & sous-titres',
          subtitle: 'Langue audio · activer les sous-titres',
          onTap: onTracks,
        ),
        OptionSheetRow(
          icon: Icons.speed_rounded,
          accent: kAccentPrimary,
          title: 'Vitesse de lecture',
          subtitle: speedLabel,
          onTap: onSpeed,
        ),
        // §videoFit — Format d'image : le sous-titre annonce le mode ACTIF,
        // pas l'action. Sur TV c'est le seul endroit où on peut lire l'état
        // courant (le bouton inline du lecteur n'existe qu'au tactile).
        OptionSheetRow(
          icon: fitMode.icon,
          accent: kAccentSecondary,
          title: "Format d'image",
          subtitle: '${fitMode.label} · ${fitMode.description}',
          onTap: onFit,
        ),
        // §videoStats — Interrupteur de l'encart de diagnostic. EN DERNIER :
        // c'est un outil de mise au point, pas une action de lecture, il ne
        // doit pas passer devant « Épisode suivant » au focus D-pad.
        OptionSheetRow(
          icon: statsEnabled ? Icons.speed_outlined : Icons.query_stats_rounded,
          accent: kAccentTertiary,
          title: 'Infos vidéo',
          subtitle: statsEnabled
              ? 'Affichées · toucher pour masquer'
              : 'Décodage, résolution, images/s, pertes',
          selected: statsEnabled,
          onTap: onToggleStats,
        ),
      ],
    ),
  );
}

/// §videoFit — Sous-menu Format d'image, focusable D-pad.
Future<void> showVideoFitMenu(
  BuildContext context, {
  required VideoFitMode current,
  required ValueChanged<VideoFitMode> onSelect,
}) {
  return showAdaptiveActionSheet<void>(
    context: context,
    scrollable: false,
    builder: (_) => OptionsSheetBody(
      title: "Format d'image",
      icon: Icons.aspect_ratio_rounded,
      children: [
        for (final mode in VideoFitMode.values)
          OptionSheetRow(
            icon: mode == current ? Icons.check_circle_rounded : mode.icon,
            accent: kAccentSecondary,
            title: mode.label,
            subtitle: mode.description,
            selected: mode == current,
            onTap: () => onSelect(mode),
          ),
      ],
    ),
  );
}

/// §tvPlayerNav — Sous-menu Vitesse (0.5×→2×), focusable D-pad.
Future<void> showSpeedMenu(
  BuildContext context, {
  required double current,
  required ValueChanged<double> onSelect,
}) {
  return showAdaptiveActionSheet<void>(
    context: context,
    scrollable: false,
    builder: (_) => OptionsSheetBody(
      title: 'Vitesse',
      icon: Icons.speed_rounded,
      children: [
        for (final s in kPlaybackSpeeds)
          OptionSheetRow(
            icon: s == current
                ? Icons.check_circle_rounded
                : Icons.play_arrow_rounded,
            accent: kAccentPrimary,
            title: s == 1.0 ? '1.0×  ·  Normal' : '$s×',
            subtitle: null,
            selected: s == current,
            onTap: () => onSelect(s),
          ),
      ],
    ),
  );
}

class OptionsSheetBody extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const OptionsSheetBody({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxH = MediaQuery.of(context).size.height * 0.72;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Titre vide = pas d'en-tête du tout : garder l'icône seule
                // laisserait une pastille orpheline au-dessus du contenu.
                if (title.isNotEmpty) ...[
                  Row(
                    children: [
                      Icon(icon, color: kAccentPrimary, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OptionSheetRow extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  const OptionSheetRow({
    super.key,
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: FocusableCard(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          decoration: BoxDecoration(
            color: selected ? accent.withAlpha(26) : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? accent : cs.outlineVariant,
              width: selected ? 1.6 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                        color: accent.withAlpha(70),
                        blurRadius: 14,
                        spreadRadius: -3),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withAlpha(28),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accent.withAlpha(90)),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 15,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: cs.onSurfaceVariant.withAlpha(140)),
            ],
          ),
        ),
      ),
    );
  }
}
