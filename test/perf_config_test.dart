import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/core/settings/perf_config.dart';

/// §perfSettings — Verrouille la sérialisation de `PerfConfig` (réglages
/// d'optimisation Fire Stick). Points critiques :
///   - rétro-compat : le champ `perf` est nouveau dans les backups `.aether`
///     et de futures clés pourront s'ajouter au modèle → toute clé absente
///     doit retomber sur sa valeur par défaut, jamais crasher ;
///   - clamps à la lecture : un JSON forgé/corrompu (valeurs hors bornes) ne
///     doit pas produire un hero à 0 carte ou une rangée à 10 000 vignettes.
void main() {
  group('PerfConfig — sérialisation', () {
    test('roundtrip toJson/fromJson → identique', () {
      const cfg = PerfConfig(
        heroEnabled: false,
        heroAutoRotate: false,
        heroCardCount: 8,
        maxItemsPerRow: 10,
      );
      expect(PerfConfig.fromJson(cfg.toJson()), cfg);
    });

    test('JSON vide (vieux backup sans section perf) → defaults', () {
      expect(PerfConfig.fromJson(const {}), PerfConfig.defaults);
    });

    test('clé partielle → les champs absents retombent sur defaults', () {
      final cfg = PerfConfig.fromJson(const {'he': false});
      expect(cfg.heroEnabled, false);
      expect(cfg.heroAutoRotate, PerfConfig.defaults.heroAutoRotate);
      expect(cfg.maxItemsPerRow, PerfConfig.defaults.maxItemsPerRow);
    });

    test('valeurs hors bornes → clampées à la lecture', () {
      final cfg = PerfConfig.fromJson(const {'hcc': 999, 'mir': 0});
      expect(cfg.heroCardCount, PerfConfig.maxHeroCards);
      expect(cfg.maxItemsPerRow, PerfConfig.minItemsPerRow);
    });
  });

  group('PerfConfig — presets', () {
    test('Confort == defaults (le profil par défaut EST le comportement historique)', () {
      expect(PerfConfig.presets.first.config, PerfConfig.defaults);
    });

    test('les 3 profils sont distincts (détection du profil actif fiable)', () {
      final configs = PerfConfig.presets.map((p) => p.config).toSet();
      expect(configs.length, PerfConfig.presets.length);
    });

    test('copyWith produit un état « Personnalisé » ≠ de tout preset', () {
      final custom = PerfConfig.defaults.copyWith(maxItemsPerRow: 20);
      for (final p in PerfConfig.presets) {
        expect(custom == p.config, false);
      }
    });
  });
}
