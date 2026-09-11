import "package:flutter/material.dart";

import '../l10n/l10n_ext.dart';

class InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const InfoRow({super.key, required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).textTheme.bodySmall?.color),
        const SizedBox(width: 8),
        // Revue 2026-09-11, D4B-05 — « label : » est la typographie
        // FRANÇAISE (espace avant les deux-points) ; l'anglais n'en met pas.
        // `L10n.current` (repli français) : ce widget se construit aussi hors
        // de `Localizations`.
        Text(L10n.current.infoRowLabel(label),
            style: Theme.of(context).textTheme.bodySmall),
        const Spacer(),
        Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
