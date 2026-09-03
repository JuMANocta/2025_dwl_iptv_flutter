import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/boot/boot_status.dart';
import '../../core/utils/platform_tv.dart';

/// §bootLog — Le journal de démarrage.
///
/// **Avant** : une seule ligne, remplacée à chaque étape. On ne voyait jamais le
/// chemin parcouru, et un démarrage long paraissait figé.
///
/// **Maintenant** : les étapes franchies restent affichées, en retrait, avec
/// **le temps qu'elles ont pris** ; l'étape courante est en couleur primaire,
/// suivie d'un curseur clignotant, son pourcentage aligné à droite.
///
/// Les durées ne sont pas décoratives : sur TV il n'y a pas de logcat, et c'est
/// le seul moyen de savoir où partent les secondes du démarrage. On mesure avant
/// d'optimiser.
class BootLog extends StatelessWidget {
  const BootLog({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bool isTv = PlatformTv.isTv;
    final double fontSize = isTv ? 16 : 12.5;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Étapes terminées ────────────────────────────────────────────────
        // Notifieur SÉPARÉ de `step` : sans ça, chacun des ~101 paliers de
        // progression du parsing reconstruirait toute la liste.
        ValueListenableBuilder<List<BootStepDone>>(
          valueListenable: BootStatus.history,
          builder: (_, done, __) {
            if (done.isEmpty) return const SizedBox.shrink();
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final BootStepDone d in done)
                  _LogLine(
                    prefix: '✓',
                    label: d.label,
                    trailing: d.durationLabel,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.45),
                    fontSize: fontSize,
                  ),
              ],
            );
          },
        ),

        // ── Étape courante + barre ──────────────────────────────────────────
        ValueListenableBuilder<BootStep>(
          valueListenable: BootStatus.step,
          builder: (_, step, __) {
            final String? pct = step.progress == null
                ? null
                : '${(step.progress! * 100).round()} %';
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LogLine(
                  prefix: '▸',
                  label: step.label,
                  trailing: pct,
                  color: cs.primary,
                  fontSize: fontSize,
                  cursor: true,
                ),
                // §bootPercent — Le détail vit sur sa PROPRE ligne, de hauteur
                // RÉSERVÉE.
                //
                // ⚠️ Le coller au libellé était le réflexe, et c'est un piège :
                // le `Text` de `_LogLine` n'a pas de `maxLines`, donc son
                // `TextOverflow.ellipsis` ne s'applique jamais — un libellé
                // trop long **passe à la ligne** au lieu d'être tronqué. Il
                // pousse alors la barre vers le bas, les `Spacer` du décor
                // re-centrent tout le bloc, et l'écran de démarrage sursaute à
                // chaque palier. Sur téléphone, « // analyse du catalogue… »
                // occupe déjà 24 des ~31 caractères tenables.
                //
                // Hauteur réservée en permanence : sans elle, l'apparition et
                // la disparition du détail produiraient le même sursaut.
                SizedBox(
                  height: fontSize * 1.7,
                  child: step.detail == null
                      ? null
                      : _LogLine(
                          prefix: ' ',
                          label: step.detail!,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.55),
                          fontSize: fontSize,
                        ),
                ),
                SizedBox(height: isTv ? 14 : 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: isTv ? 6 : 4,
                    value: step.progress, // null = indéterminée
                    backgroundColor: cs.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Une ligne du journal : préfixe, libellé, et valeur alignée à droite.
///
/// L'alignement en colonnes (monospace + `trailing` à droite) est ce qui fait la
/// différence entre « du texte qui défile » et « un journal ».
class _LogLine extends StatelessWidget {
  final String prefix;
  final String label;
  final String? trailing;
  final Color color;
  final double fontSize;
  final bool cursor;

  const _LogLine({
    required this.prefix,
    required this.label,
    required this.color,
    required this.fontSize,
    this.trailing,
    this.cursor = false,
  });

  @override
  Widget build(BuildContext context) {
    final TextStyle style = GoogleFonts.sourceCodePro(
      color: color,
      fontSize: fontSize,
      letterSpacing: 0.8,
      height: 1.7,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(prefix, style: style),
        const SizedBox(width: 8),
        // ⚠️ `maxLines: 1` est OBLIGATOIRE : sans lui, `TextOverflow.ellipsis`
        // ne s'applique pas (le texte a une hauteur libre, donc il revient à la
        // ligne au lieu d'être tronqué) et la mise en page du décor sursaute.
        Expanded(
          child: Text(
            label,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (cursor) _BlinkingCursor(color: color, fontSize: fontSize),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          Text(trailing!, style: style),
        ],
      ],
    );
  }
}

/// §bootMotion — Curseur clignotant.
///
/// La seule animation continue de l'écran, et volontairement minuscule :
/// quelques pixels repeints deux fois par seconde, isolés dans un
/// [RepaintBoundary]. Négligeable même sur Fire Stick, où le CPU est par
/// ailleurs occupé à parser le catalogue.
class _BlinkingCursor extends StatefulWidget {
  final Color color;
  final double fontSize;

  const _BlinkingCursor({required this.color, required this.fontSize});

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1060),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Opacity(
          // Créneau franc plutôt qu'un fondu : c'est un curseur de terminal.
          opacity: _ctrl.value < 0.5 ? 1 : 0,
          child: Text(
            '▌',
            style: GoogleFonts.sourceCodePro(
              color: widget.color,
              fontSize: widget.fontSize,
              height: 1.7,
            ),
          ),
        ),
      ),
    );
  }
}
