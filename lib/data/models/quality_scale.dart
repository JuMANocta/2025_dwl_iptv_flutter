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
  /// §qualityScope (2026-09-11, signalé par l'utilisateur) — Étiquette de
  /// définition d'une image décodée, d'après ses DEUX dimensions : le palier
  /// retenu est le plus haut des deux.
  ///
  /// ⚠️ La hauteur seule MENTAIT sur tous les films au format large : un FHD
  /// en 2,40:1 est encodé 1920×**800** (les bandes noires ne sont pas
  /// encodées) → classé « HD », et la fiche accusait la liste d'avoir
  /// « survendu ». Idem 1280×536 (HD scope → « SD ») et 3840×1600/1392 (4K
  /// scope). La largeur rattrape le format large ; la hauteur rattrape le 4:3
  /// et le pillarbox (1440×1080 reste FHD).
  ///
  /// Seuils à ~83 % du nominal, comme ceux de la hauteur : largeur 3200 / 1600
  /// / 1100 (3840, 1920, 1280), hauteur 1600 / 1000 / 700 (2160, 1080, 720).
  static String labelFor({required int width, required int height}) {
    final int byW = width >= 3200 ? 3 : width >= 1600 ? 2 : width >= 1100 ? 1 : 0;
    final int byH = height >= 1600 ? 3 : height >= 1000 ? 2 : height >= 700 ? 1 : 0;
    return const ['SD', 'HD', 'FHD', '4K'][byW > byH ? byW : byH];
  }

  /// Étiquette d'après la SEULE hauteur — pour une mesure dont la largeur est
  /// inconnue. ⚠️ Fausse sur un format large : préférer [labelFor].
  static String labelForHeight(int height) => labelFor(width: 0, height: height);

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
