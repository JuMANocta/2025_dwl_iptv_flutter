import 'package:flutter/material.dart';

/// §perfSettings — Configuration des optimisations de rendu, sérialisable pour
/// SharedPreferences (même pattern que `AppThemeConfig`).
///
/// Cible : Fire Stick et box faibles. L'utilisateur choisit lui-même ce qu'il
/// coupe au lieu qu'on devine une config unique — le hero fan (empilement de
/// cartes + ombres = le plus gros poste de coût au 1er paint) et le nombre de
/// vignettes par rangée sont les leviers principaux.
@immutable
class PerfConfig {
  /// Affiche le hero fan en tête de la home.
  final bool heroEnabled;

  /// Auto-rotation 6 s du hero (repaints périodiques). Sans effet si
  /// [heroEnabled] est false. Le swipe/tap manuel reste toujours actif.
  final bool heroAutoRotate;

  /// Nombre de cartes empilées dans le hero (bornes [minHeroCards]-[maxHeroCards]).
  final int heroCardCount;

  /// Vignettes affichées par rangée de catégorie avant la tuile « Voir tout »
  /// (bornes [minItemsPerRow]-[maxItemsPerRowLimit]). Favoris exemptés (jamais
  /// tronqués).
  final int maxItemsPerRow;

  /// Plafond du cache image **en mémoire** (Mo), appliqué à
  /// `PaintingBinding.instance.imageCache` (défaut Flutter : 100 Mo).
  ///
  /// ⚠️ **§imgThrash — corrigé le 2026-08-05.** La version précédente
  /// descendait SOUS le défaut Flutter (80 / 60 / **40** Mo) en présentant la
  /// baisse comme un gain : le cache disque absorbant les évictions, on croyait
  /// pouvoir réduire sans dommage. C'était faux. Réduire ce cache ne réduit pas
  /// la mémoire nécessaire pour AFFICHER un écran : ça force seulement à
  /// re-décoder en boucle, ce qui a rendu la TV saccadée et fait clignoter les
  /// vignettes (elles disparaissaient puis revenaient).
  ///
  /// Le vrai levier était ailleurs : décoder les images à leur taille
  /// d'affichage (cf. `decodeWidthFor`), ce qui divise leur coût par ~3. À
  /// mémoire égale, le cache contient donc désormais 3× plus de vignettes.
  final int imageCacheMb;

  /// §autoNextEp — Enchaîne automatiquement l'épisode suivant à la fin d'un
  /// épisode, après un court décompte annulable.
  ///
  /// Volontairement **hors des profils** de performance : c'est un choix de
  /// confort, pas un levier de fluidité — les 3 presets le laissent donc
  /// intact. `true` par défaut, comme sur les plateformes de streaming.
  ///
  /// Ne s'applique jamais aux chaînes live ni au replay, et jamais au
  /// franchissement de saison (qui demande toujours une confirmation).
  final bool autoNextEpisode;

  static const int minHeroCards = 5;
  static const int maxHeroCards = 15;
  static const int minItemsPerRow = 5;
  static const int maxItemsPerRowLimit = 25;

  /// §imgThrash — Plancher relevé de 20 à 60 Mo : en dessous, le cache ne tient
  /// même plus un écran d'accueil et le thrash est garanti.
  static const int minImageCacheMb = 60;
  static const int maxImageCacheMb = 200;

  const PerfConfig({
    required this.heroEnabled,
    required this.heroAutoRotate,
    required this.heroCardCount,
    required this.maxItemsPerRow,
    required this.imageCacheMb,
    this.autoNextEpisode = true,
  });

  // ── Presets ───────────────────────────────────────────────────────────────

  /// Confort = comportement historique de l'app (défaut).
  static const PerfConfig defaults = PerfConfig(
    heroEnabled: true,
    heroAutoRotate: true,
    heroCardCount: 15,
    maxItemsPerRow: 15,
    imageCacheMb: 120,
  );

  /// Hero conservé mais immobile, rangées allégées.
  static const PerfConfig equilibre = PerfConfig(
    heroEnabled: true,
    heroAutoRotate: false,
    heroCardCount: 10,
    maxItemsPerRow: 10,
    imageCacheMb: 100,
  );

  /// Fire Stick / box faible : hero coupé (les valeurs hero restent cohérentes
  /// si l'utilisateur le réactive ensuite à la main).
  ///
  /// ⚠️ §imgThrash — Le cache image N'EST PLUS le levier d'allègement de ce
  /// profil : c'est lui qui provoquait les saccades TV, or ce profil est celui
  /// que §perfAutoSuggest propose justement sur box TV. On allège désormais par
  /// le hero et le nombre de vignettes ; le cache reste au niveau du défaut
  /// Flutter.
  static const PerfConfig performance = PerfConfig(
    heroEnabled: false,
    heroAutoRotate: false,
    heroCardCount: 8,
    maxItemsPerRow: 10,
    imageCacheMb: 80,
  );

  /// Profils affichés dans OptimizationSettingsPage. Un état ne correspondant
  /// à aucun preset = « Personnalisé » (implicite, rien n'est stocké pour ça).
  static const presets = [
    (
      name: 'Confort',
      subtitle: 'Défaut',
      icon: Icons.weekend_outlined,
      config: defaults,
    ),
    (
      name: 'Équilibré',
      subtitle: 'Hero fixe',
      icon: Icons.balance,
      config: equilibre,
    ),
    (
      name: 'Performance',
      subtitle: 'Fire Stick',
      icon: Icons.speed,
      config: performance,
    ),
  ];

  // ── Sérialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'he': heroEnabled,
        'har': heroAutoRotate,
        'hcc': heroCardCount,
        'mir': maxItemsPerRow,
        'icm': imageCacheMb,
        'ane': autoNextEpisode,
      };

  /// Clés optionnelles + valeurs clampées à la lecture → rétro-compat des
  /// backups `.aether` et des futures évolutions du modèle.
  factory PerfConfig.fromJson(Map<String, dynamic> j) => PerfConfig(
        heroEnabled: j['he'] as bool? ?? defaults.heroEnabled,
        heroAutoRotate: j['har'] as bool? ?? defaults.heroAutoRotate,
        heroCardCount: (j['hcc'] as int? ?? defaults.heroCardCount)
            .clamp(minHeroCards, maxHeroCards),
        maxItemsPerRow: (j['mir'] as int? ?? defaults.maxItemsPerRow)
            .clamp(minItemsPerRow, maxItemsPerRowLimit),
        imageCacheMb: (j['icm'] as int? ?? defaults.imageCacheMb)
            .clamp(minImageCacheMb, maxImageCacheMb),
        autoNextEpisode: j['ane'] as bool? ?? defaults.autoNextEpisode,
      );

  PerfConfig copyWith({
    bool? heroEnabled,
    bool? heroAutoRotate,
    int? heroCardCount,
    int? maxItemsPerRow,
    int? imageCacheMb,
    bool? autoNextEpisode,
  }) =>
      PerfConfig(
        heroEnabled: heroEnabled ?? this.heroEnabled,
        heroAutoRotate: heroAutoRotate ?? this.heroAutoRotate,
        heroCardCount: heroCardCount ?? this.heroCardCount,
        maxItemsPerRow: maxItemsPerRow ?? this.maxItemsPerRow,
        imageCacheMb: imageCacheMb ?? this.imageCacheMb,
        autoNextEpisode: autoNextEpisode ?? this.autoNextEpisode,
      );

  // Égalité champ-à-champ → détection du preset actif dans la page.
  @override
  bool operator ==(Object other) =>
      other is PerfConfig &&
      other.heroEnabled == heroEnabled &&
      other.heroAutoRotate == heroAutoRotate &&
      other.heroCardCount == heroCardCount &&
      other.maxItemsPerRow == maxItemsPerRow &&
      other.imageCacheMb == imageCacheMb;
  // NB : `autoNextEpisode` est volontairement EXCLU de l'égalité — c'est un
  // réglage de confort, pas un paramètre de profil. L'inclure ferait basculer
  // la page en « Personnalisé » dès qu'on touche l'interrupteur.

  @override
  int get hashCode => Object.hash(
      heroEnabled, heroAutoRotate, heroCardCount, maxItemsPerRow, imageCacheMb);
}
