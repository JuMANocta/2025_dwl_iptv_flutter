import 'package:flutter/material.dart';

import '../../l10n/l10n_ext.dart';

/// §3c-bis #5 — Un réglage continu, pilotable à la TÉLÉCOMMANDE.
///
/// **Le défaut corrigé** : sur TV, un `Slider` est inutilisable au D-pad — les
/// flèches ← → sont mangées par le curseur et la valeur saute par grands
/// intervalles. On le remplace donc par deux `IconButton` − / + (focusables
/// nativement) encadrant une barre de progression qui montre où l'on en est.
///
/// ⚠️ §boundFocus — `onPressed` n'est JAMAIS `null` à la borne : un bouton
/// désactivé SORT de la traversée alors qu'il a le focus, et la télécommande
/// se retrouve nulle part. Ce sont [_decrement] / [_increment] qui ne font
/// rien une fois la borne atteinte (clamp + test d'égalité) ; seule la couleur
/// dit que c'est fini.
///
/// §themeStudio (2026-09-16) — Sorti de `theme_settings_page.dart`, où il
/// était privé : la roue de couleurs en a besoin pour ses trois réglages
/// teinte / saturation / luminosité, et une seconde copie aurait dérivé.
class TvStepperRow extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final double step;
  final Color color;
  final ValueChanged<double> onChanged;

  const TvStepperRow({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.color,
    required this.onChanged,
  });

  void _decrement() {
    final next = (value - step).clamp(min, max);
    if (next != value) onChanged(next);
  }

  void _increment() {
    final next = (value + step).clamp(min, max);
    if (next != value) onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final ratio = ((value - min) / (max - min)).clamp(0.0, 1.0);
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: _decrement,
          color: value > min ? color : color.withAlpha(70),
          tooltip: context.l10n.commonDecrease,
        ),
        Expanded(
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: color.withAlpha(40),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: ratio,
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: _increment,
          color: value < max ? color : color.withAlpha(70),
          tooltip: context.l10n.commonIncrease,
        ),
      ],
    );
  }
}
