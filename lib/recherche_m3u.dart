// lib/recherche_m3u.dart
//
// ✅ Fichier de compatibilité
// Cette page “recherche_m3u” existait dans l’ancien flux (mono-compte).
// Désormais, toute la logique de recherche & parsing est unifiée dans
// `lib/recherche.dart` (RecherchePage).
//
// Ce wrapper conserve les anciens imports/navigations éventuels
// en redirigeant simplement vers `RecherchePage`.

import 'package:flutter/material.dart';
import 'recherche.dart';

/// Ancienne entrée probable : garde la compat de routage.
class RechercheM3U extends StatelessWidget {
  const RechercheM3U({super.key});

  @override
  Widget build(BuildContext context) {
    return const RecherchePage();
  }
}

/// Variante possible selon l’ancien code : on expose aussi un alias.
class RechercheM3UPage extends StatelessWidget {
  const RechercheM3UPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const RecherchePage();
  }
}
