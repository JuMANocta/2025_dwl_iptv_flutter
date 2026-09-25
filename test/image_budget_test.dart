// §imgRightSize (2026-09-25) — Le cache d'images selon l'appareil : quotas
// DISQUE selon l'espace libre (`imageDiskQuota`), budget RAM des images
// décodées selon la classe mémoire (`imageCacheBudgetMb`).
//
// ⛔ §imgThrash : les quotas disque avaient été relevés (TMDB 400 → 1 500,
// listes 1 200 → 4 000) parce qu'ils saturaient en une session, et le cache
// RAM sous 100 Mo faisait saccader la TV. Ces tests tiennent les deux
// planchers : seul un stockage vraiment serré descend sous les nombres d'avant,
// et le budget RAM automatique ne fait que relever.
import 'package:aetherStream/core/settings/perf_config.dart';
import 'package:aetherStream/core/settings/performance_settings_service.dart';
import 'package:aetherStream/core/utils/image_cache_config.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Les nombres d'avant §imgRightSize (fixes, quel que soit l'appareil).
const int _providerBefore = 4000;
const int _tmdbBefore = 1500;

void main() {
  group('imageDiskQuota — plus de place, plus d\'images gardées', () {
    test('sans mesure : le palier standard, jamais une réduction à l\'aveugle', () {
      expect(imageDiskQuota(), kImageDiskStandard);
      expect(imageDiskQuota(freeMb: 0), kImageDiskStandard);
      expect(imageDiskQuota(freeMb: -1), kImageDiskStandard);
    });

    test('⛔ §imgThrash — dès 2 Go libres, jamais sous les nombres d\'avant', () {
      for (final int free in [kTightStorageMb, 3000, 5000, kRoomyStorageMb - 1, kRoomyStorageMb, 64000]) {
        final ImageDiskQuota q = imageDiskQuota(freeMb: free);
        expect(q.provider, greaterThanOrEqualTo(_providerBefore), reason: '$free Mo');
        expect(q.tmdb, greaterThanOrEqualTo(_tmdbBefore), reason: '$free Mo');
      }
      expect(imageDiskQuota().provider, greaterThanOrEqualTo(_providerBefore));
      expect(imageDiskQuota().tmdb, greaterThanOrEqualTo(_tmdbBefore));
    });

    test('paliers aux seuils', () {
      expect(imageDiskQuota(freeMb: 100), kImageDiskCritical);
      expect(imageDiskQuota(freeMb: kCriticalStorageMb - 1), kImageDiskCritical);
      expect(imageDiskQuota(freeMb: kCriticalStorageMb), kImageDiskTight);
      expect(imageDiskQuota(freeMb: kTightStorageMb - 1), kImageDiskTight);
      expect(imageDiskQuota(freeMb: kTightStorageMb), kImageDiskStandard);
      expect(imageDiskQuota(freeMb: kRoomyStorageMb - 1), kImageDiskStandard);
      expect(imageDiskQuota(freeMb: kRoomyStorageMb), kImageDiskRoomy);
    });

    test('monotone : plus d\'espace libre ne réduit jamais un quota', () {
      ImageDiskQuota prev = imageDiskQuota(freeMb: 1);
      for (int free = 64; free <= 40000; free += 64) {
        final ImageDiskQuota q = imageDiskQuota(freeMb: free);
        expect(q.provider, greaterThanOrEqualTo(prev.provider), reason: '$free Mo');
        expect(q.tmdb, greaterThanOrEqualTo(prev.tmdb), reason: '$free Mo');
        prev = q;
      }
    });

    test('un stockage large garde plus que les nombres d\'avant', () {
      final ImageDiskQuota q = imageDiskQuota(freeMb: 20000);
      expect(q.provider, greaterThan(_providerBefore));
      expect(q.tmdb, greaterThan(_tmdbBefore));
    });

    test('même serré, de quoi tenir un accueil (~900 vignettes sur deux caches)', () {
      final ImageDiskQuota q = imageDiskQuota(freeMb: kTightStorageMb - 1);
      expect(q.provider + q.tmdb, greaterThanOrEqualTo(900));
      expect(q.provider, lessThan(_providerBefore));
      final ImageDiskQuota c = imageDiskQuota(freeMb: 100);
      expect(c.provider + c.tmdb, greaterThanOrEqualTo(900));
    });

    test('configure() avant la première image pose le palier mesuré', () {
      // Les caches ne sont pas ouverts dans ce test : la configuration passe.
      expect(AetherImageCache.configure(freeMb: 20000), isTrue);
      expect(AetherImageCache.quota, kImageDiskRoomy);
      expect(AetherImageCache.configure(freeMb: null), isTrue);
      expect(AetherImageCache.quota, kImageDiskStandard);
    });
  });

  group('imageCacheBudgetMb — ne fait que RELEVER', () {
    test('sans mesure : le réglage, tel quel', () {
      expect(imageCacheBudgetMb(configuredMb: 120), 120);
      expect(imageCacheBudgetMb(configuredMb: 120, memoryClassMb: 0), 120);
    });

    test('75 % de la classe mémoire, plafonné à 256 Mo', () {
      expect(imageCacheBudgetMb(configuredMb: 120, memoryClassMb: 192), 144);
      expect(imageCacheBudgetMb(configuredMb: 100, memoryClassMb: 256), 192);
      expect(imageCacheBudgetMb(configuredMb: 120, memoryClassMb: 512), kImageCacheCeilingMb);
      expect(imageCacheBudgetMb(configuredMb: 200, memoryClassMb: 1024), kImageCacheCeilingMb);
    });

    test('⛔ jamais abaissé : une box à 128 Mo garde son réglage', () {
      expect(imageCacheBudgetMb(configuredMb: 100, memoryClassMb: 128), 100);
      expect(imageCacheBudgetMb(configuredMb: 120, memoryClassMb: 64), 120);
      expect(imageCacheBudgetMb(configuredMb: 200, memoryClassMb: 192), 200);
    });

    test('⛔ jamais sous 100 Mo par le calcul automatique', () {
      for (final int mc in [16, 32, 64, 96, 128, 192, 256, 384, 512, 2048]) {
        for (final int cfg in [kFlutterImageCacheMb, 120, 150, PerfConfig.maxImageCacheMb]) {
          final int out = imageCacheBudgetMb(configuredMb: cfg, memoryClassMb: mc);
          expect(out, greaterThanOrEqualTo(kFlutterImageCacheMb));
          expect(out, greaterThanOrEqualTo(cfg));
          expect(out, lessThanOrEqualTo(cfg > kImageCacheCeilingMb ? cfg : kImageCacheCeilingMb));
        }
      }
    });

    test('appareil déclaré à faible mémoire : aucun relèvement', () {
      expect(imageCacheBudgetMb(configuredMb: 100, memoryClassMb: 512, lowRamDevice: true), 100);
    });

    test('un choix SOUS le défaut Flutter (60-90 Mo) est respecté, pas relevé', () {
      expect(imageCacheBudgetMb(configuredMb: PerfConfig.minImageCacheMb, memoryClassMb: 512), PerfConfig.minImageCacheMb);
      expect(imageCacheBudgetMb(configuredMb: 90, memoryClassMb: 256), 90);
    });

    test('les profils livrés ne descendent pas sous le défaut Flutter (relèvement possible)', () {
      for (final p in PerfConfig.presets) {
        expect(p.config.imageCacheMb, greaterThanOrEqualTo(kFlutterImageCacheMb), reason: p.name);
      }
    });
  });

  group('PerformanceSettingsService — le budget relevé est APPLIQUÉ', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    tearDown(() {
      PerformanceSettingsService.setDeviceMemory(memoryClassMb: null);
      PerformanceSettingsService.config.value = PerfConfig.defaults;
      PerformanceSettingsService.applyImageCacheLimit();
    });

    test('classe mémoire 256 Mo : le cache d\'images décodées passe à 192 Mo', () {
      PerformanceSettingsService.config.value = PerfConfig.defaults;
      PerformanceSettingsService.setDeviceMemory(memoryClassMb: 256);
      final ImageCache cache = PaintingBinding.instance.imageCache;
      expect(cache.maximumSizeBytes, 192 * 1024 * 1024);
      expect(PerformanceSettingsService.appliedImageCacheMb.value, 192);
    });

    test('sans mesure : le réglage du profil, comme avant', () {
      PerformanceSettingsService.setDeviceMemory(memoryClassMb: null);
      final int cfg = PerformanceSettingsService.config.value.imageCacheMb;
      expect(PaintingBinding.instance.imageCache.maximumSizeBytes, cfg * 1024 * 1024);
      expect(PerformanceSettingsService.appliedImageCacheMb.value, cfg);
    });

    test('lowRamDevice : pas de relèvement même avec une grande classe', () {
      PerformanceSettingsService.setDeviceMemory(memoryClassMb: 512, lowRamDevice: true);
      final int cfg = PerformanceSettingsService.config.value.imageCacheMb;
      expect(PaintingBinding.instance.imageCache.maximumSizeBytes, cfg * 1024 * 1024);
    });
  });
}
