import 'package:flutter/material.dart';

import '../core/themes/colors.dart';
import '../data/models/m3u_entry.dart';
import '../data/models/quality_scale.dart';
import '../data/services/measured_quality_service.dart';

/// §qualityTruth — Pastille « qualité réellement servie », posée sur une
/// vignette.
///
/// La qualité affichée partout ailleurs vient du **titre** fourni par la liste.
/// Cette pastille, elle, ne dit que ce qui a été **mesuré à la lecture** — et
/// ne s'affiche donc pas tant que le contenu n'a jamais été lu : mieux vaut se
/// taire qu'affirmer sans preuve.
///
/// Deux niveaux de bruit, délibérés :
///   - liste **qui survend** → pastille rouge pleine, `⚠`. C'est le seul cas
///     qui demande l'attention de l'utilisateur.
///   - tout le reste → pastille sombre discrète. Une home entière de badges
///     criards n'apprendrait plus rien à personne.
class MeasuredQualityBadge extends StatelessWidget {
  /// Toutes les variantes du contenu (qualités, comptes…).
  final List<M3uEntry> versions;

  const MeasuredQualityBadge({super.key, required this.versions});

  @override
  Widget build(BuildContext context) {
    // Une mesure peut tomber pendant qu'on est dans le lecteur, la home restant
    // montée derrière : sans cet abonnement, la pastille n'apparaîtrait qu'au
    // prochain démarrage.
    return ValueListenableBuilder<int>(
      valueListenable: MeasuredQualityService.version,
      builder: (_, __, ___) => _build(),
    );
  }

  Widget _build() {
    final pick = _pick();
    if (pick == null) return const SizedBox.shrink();
    final (label, verdict) = pick;

    final survendu = verdict == QualityVerdict.survendu;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: survendu ? kError : Colors.black.withAlpha(160),
        borderRadius: BorderRadius.circular(4),
        border: survendu
            ? null
            : Border.all(color: Colors.white.withAlpha(40), width: 0.8),
      ),
      child: Text(
        survendu ? '⚠ $label' : label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          height: 1.2,
          color: survendu ? Colors.white : _tint(label),
        ),
      ),
    );
  }

  /// Choisit ce que la pastille annonce pour un GROUPE de versions.
  ///
  /// Un mensonge prime sur une bonne nouvelle : dès qu'une variante est
  /// survendue, c'est elle qu'on montre, même si une autre du groupe est
  /// honnête — c'est la seule information qui change une décision. Sinon on
  /// annonce la **meilleure** définition mesurée du groupe, puisque c'est celle
  /// que l'utilisateur obtiendra en lançant.
  (String, QualityVerdict)? _pick() {
    String? bestLabel;
    int bestRank = -1;
    for (final v in versions) {
      final measured = MeasuredQualityService.get(v.url);
      if (measured == null) continue;
      final verdict = measured.verdictFor(v.title.quality);
      if (verdict == QualityVerdict.survendu) {
        return (measured.definitionLabel, verdict);
      }
      final rank = QualityScale.rankOf(measured.definitionLabel) ?? -1;
      if (rank > bestRank) {
        bestRank = rank;
        bestLabel = measured.definitionLabel;
      }
    }
    return bestLabel == null
        ? null
        : (bestLabel, QualityVerdict.conforme);
  }

  /// Couleur du code qualité informatif (identique aux badges du reste de
  /// l'app), pour que « FHD » mesuré et « FHD » annoncé se lisent pareil.
  static Color _tint(String label) => switch (label) {
        '4K' => kQuality4K,
        'FHD' => kQualityFHD,
        'HD' => kQualityHD,
        'SD' => kQualitySD,
        _ => kQualityUnknown,
      };
}
