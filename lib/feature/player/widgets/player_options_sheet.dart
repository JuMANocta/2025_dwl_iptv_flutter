import 'package:flutter/material.dart';

import '../../../core/themes/colors.dart';
import '../../../widgets/tv/focusable_card.dart';
import '../../../widgets/tv/tv_adaptive_modal.dart';

/// §tvPlayerNav — Panneau d'OPTIONS du lecteur : le « centre de contrôle » TV
/// ouvert via ↑ à la télécommande (mobile peut aussi y accéder). Tous les items
/// sont des [FocusableCard] → navigables au D-pad, contrairement aux boutons
/// inline (GestureDetector) inatteignables sur TV. Regroupe : pistes audio/
/// sous-titres, vitesse, épisode suivant.
Future<void> showPlayerOptions(
  BuildContext context, {
  required bool hasNext,
  required String speedLabel,
  required VoidCallback onTracks,
  required VoidCallback onSpeed,
  VoidCallback? onNext,
}) {
  return showAdaptiveActionSheet<void>(
    context: context,
    scrollable: false,
    builder: (_) => _OptionsBody(
      title: 'Options',
      icon: Icons.tune_rounded,
      children: [
        // §tvOptionsOrder — « Épisode suivant » EN PREMIER (série en cours) :
        // c'est l'action la plus fréquente du panneau, elle reçoit le focus
        // initial au D-pad au lieu d'être en dernière position.
        if (onNext != null)
          _OptionRow(
            icon: Icons.skip_next_rounded,
            accent: kAccentTertiary,
            title: 'Épisode suivant',
            subtitle: "Passer à l'épisode suivant",
            onTap: onNext,
          ),
        _OptionRow(
          icon: Icons.subtitles_rounded,
          accent: kAccentSecondary,
          title: 'Pistes audio & sous-titres',
          subtitle: 'Langue audio · activer les sous-titres',
          onTap: onTracks,
        ),
        _OptionRow(
          icon: Icons.speed_rounded,
          accent: kAccentPrimary,
          title: 'Vitesse de lecture',
          subtitle: speedLabel,
          onTap: onSpeed,
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
  const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  return showAdaptiveActionSheet<void>(
    context: context,
    scrollable: false,
    builder: (_) => _OptionsBody(
      title: 'Vitesse',
      icon: Icons.speed_rounded,
      children: [
        for (final s in speeds)
          _OptionRow(
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

class _OptionsBody extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _OptionsBody(
      {required this.title, required this.icon, required this.children});

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
                Row(
                  children: [
                    Icon(icon, color: kAccentPrimary, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      title,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _OptionRow({
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
