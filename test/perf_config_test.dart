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
        // Valeur DANS les bornes : sous le plancher, la lecture clampe et le
        // roundtrip ne peut pas être l'identité (§imgThrash a relevé le
        // plancher de 20 à 60).
        imageCacheMb: 80,
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
      final cfg = PerfConfig.fromJson(const {'hcc': 999, 'mir': 0, 'icm': 9999});
      expect(cfg.heroCardCount, PerfConfig.maxHeroCards);
      expect(cfg.maxItemsPerRow, PerfConfig.minItemsPerRow);
      expect(cfg.imageCacheMb, PerfConfig.maxImageCacheMb);
    });

    test('§imgMemCache — cache image RAM jamais nul (plancher)', () {
      // À 0 Mo le scroll re-décoderait chaque vignette à chaque frame :
      // le plancher protège d'un réglage (ou d'un JSON) destructeur.
      final cfg = PerfConfig.fromJson(const {'icm': 0});
      expect(cfg.imageCacheMb, PerfConfig.minImageCacheMb);
      expect(cfg.imageCacheMb, greaterThan(0));
    });

    test('§imgThrash — aucun profil ne descend au niveau qui provoque le thrash',
        () {
      // ⚠️ Ce test verrouillait EXACTEMENT l'inverse : il exigeait que les
      // profils passent SOUS le défaut Flutter (100 Mo), au motif que le cache
      // disque absorbait les évictions. C'était faux — réduire ce cache ne
      // réduit pas la mémoire nécessaire pour afficher un écran, ça force à
      // re-décoder en boucle. Résultat : TV saccadée et vignettes qui
      // clignotaient, surtout au profil « Performance » que l'app propose
      // justement sur box TV.
      for (final p in PerfConfig.presets) {
        expect(p.config.imageCacheMb,
            greaterThanOrEqualTo(PerfConfig.minImageCacheMb),
            reason: '${p.name} sous le plancher anti-thrash');
      }
      // Le profil le plus léger doit rester dans l'ordre de grandeur du défaut
      // Flutter : on allège par le hero et les vignettes, pas par le cache.
      expect(PerfConfig.performance.imageCacheMb, greaterThanOrEqualTo(80));
      // Confort reste le plus généreux des trois.
      expect(PerfConfig.performance.imageCacheMb,
          lessThanOrEqualTo(PerfConfig.defaults.imageCacheMb));
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
