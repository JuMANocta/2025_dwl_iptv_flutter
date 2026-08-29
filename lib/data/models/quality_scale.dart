/// §qualityTruth — Le barème de définition, en UN seul endroit.
///
/// Trois lieux ont besoin de la même échelle : l'encart du lecteur
/// (`VideoStatsSnapshot`), la mesure persistée (`MeasuredQuality`) et les
/// pastilles de la fiche. Les laisser recopier chacun leur `if (h >= 1600)`
/// garantissait qu'un jour la fiche dirait « FHD » là où le lecteur dit « 4K » —
/// et l'outil ne servirait plus à rien, puisque tout son intérêt est justement
/// de confronter deux affirmations.
library;

/// Verdict de la confrontation « qualité annoncée par la liste » contre
/// « définition réellement décodée ».
enum QualityVerdict {
  /// Rien à confronter : pas d'annonce, pas de mesure, ou une annonce qui ne
  /// parle pas de définition (voir [QualityScale.compare]).
  unknown,

  /// La liste dit vrai.
  conforme,

  /// **La liste surestime** : elle vend du 4K et sert du FHD. C'est le cas qui
  /// justifie tout le dispositif.
  survendu,

  /// La liste sous-estime : annoncé HD, servi en FHD. Pas un mensonge qui lèse
  /// l'utilisateur — signalé, mais sans alarme.
  sousEstime,
}

abstract final class QualityScale {
  /// Étiquette de définition déduite d'une hauteur d'image décodée.
  static String labelForHeight(int height) {
    if (height >= 1600) return '4K';
    if (height >= 1000) return 'FHD';
    if (height >= 700) return 'HD';
    return 'SD';
  }

  /// Rang comparable d'une étiquette. `null` = ce n'est pas une définition.
  ///
  /// ⚠️ `CAM` en fait partie : §camQuality désigne le **type de source**, pas la
  /// définition — un rip de salle peut très bien être encodé en 1080p. Lui
  /// donner un rang produirait un faux « survendu » sur chaque CAM, et l'outil
  /// perdrait toute crédibilité sur les vrais cas.
  static int? rankOf(String? label) {
    switch (label?.trim().toUpperCase()) {
      case 'SD':
        return 0;
      case 'HD':
        return 1;
      case 'FHD':
        return 2;
      case '4K':
        return 3;
      default:
        return null;
    }
  }

  /// Confronte la qualité ANNONCÉE (parsing du titre,
  /// `TitleMetadata.quality`) à la définition RÉELLEMENT décodée.
  static QualityVerdict compare(String? announced, String? actual) {
    final claimed = rankOf(announced);
    final measured = rankOf(actual);
    if (claimed == null || measured == null) return QualityVerdict.unknown;
    if (claimed == measured) return QualityVerdict.conforme;
    return claimed > measured
        ? QualityVerdict.survendu
        : QualityVerdict.sousEstime;
  }
}
