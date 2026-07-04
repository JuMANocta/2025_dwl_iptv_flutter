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

  static const int minHeroCards = 5;
  static const int maxHeroCards = 15;
  static const int minItemsPerRow = 5;
  static const int maxItemsPerRowLimit = 25;

  const PerfConfig({
    required this.heroEnabled,
    required this.heroAutoRotate,
    required this.heroCardCount,
    required this.maxItemsPerRow,
  });

  // ── Presets ───────────────────────────────────────────────────────────────

  /// Confort = comportement historique de l'app (défaut).
  static const PerfConfig defaults = PerfConfig(
    heroEnabled: true,
    heroAutoRotate: true,
    heroCardCount: 15,
    maxItemsPerRow: 15,
  );

  /// Hero conservé mais immobile, rangées allégées.
  static const PerfConfig equilibre = PerfConfig(
    heroEnabled: true,
    heroAutoRotate: false,
    heroCardCount: 10,
    maxItemsPerRow: 10,
  );

  /// Fire Stick / box faible : hero coupé (les valeurs hero restent cohérentes
  /// si l'utilisateur le réactive ensuite à la main).
  static const PerfConfig performance = PerfConfig(
    heroEnabled: false,
    heroAutoRotate: false,
    heroCardCount: 8,
    maxItemsPerRow: 10,
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
      );

  PerfConfig copyWith({
    bool? heroEnabled,
    bool? heroAutoRotate,
    int? heroCardCount,
    int? maxItemsPerRow,
  }) =>
      PerfConfig(
        heroEnabled: heroEnabled ?? this.heroEnabled,
        heroAutoRotate: heroAutoRotate ?? this.heroAutoRotate,
        heroCardCount: heroCardCount ?? this.heroCardCount,
        maxItemsPerRow: maxItemsPerRow ?? this.maxItemsPerRow,
      );

  // Égalité champ-à-champ → détection du preset actif dans la page.
  @override
  bool operator ==(Object other) =>
      other is PerfConfig &&
      other.heroEnabled == heroEnabled &&
      other.heroAutoRotate == heroAutoRotate &&
      other.heroCardCount == heroCardCount &&
      other.maxItemsPerRow == maxItemsPerRow;

  @override
  int get hashCode =>
      Object.hash(heroEnabled, heroAutoRotate, heroCardCount, maxItemsPerRow);
}
