// §perfNotify (2026-09-05) — Un réglage de confort doit prendre effet TOUT DE
// SUITE, pas au prochain lancement.
//
// Le piège : `PerfConfig.==` exclut volontairement quatre réglages de confort
// (pour que la page Optimisation ne passe pas en « Personnalisé »), et un
// `ValueNotifier` refuse une valeur égale à l'ancienne. Le premier test montre
// le mécanisme sur un `ValueNotifier` nu ; les suivants prouvent que le
// notifieur du service, lui, laisse passer chacun des quatre réglages.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aetherStream/core/settings/perf_config.dart';
import 'package:aetherStream/core/settings/performance_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PerformanceSettingsService.config.value = PerfConfig.defaults;
  });

  test('témoin — un ValueNotifier nu AVALE le basculement (le bug)', () {
    final vn = ValueNotifier<PerfConfig>(PerfConfig.defaults);
    var notified = 0;
    vn.addListener(() => notified++);
    vn.value = PerfConfig.defaults.copyWith(tmdbPostersFirst: true);
    // Les deux configs sont « égales » : la nouvelle valeur est refusée.
    expect(vn.value.tmdbPostersFirst, isFalse);
    expect(notified, 0);
  });

  Future<void> expectTakesEffect(
    String label,
    PerfConfig Function(PerfConfig) flip,
    bool Function(PerfConfig) read,
  ) async {
    var notified = 0;
    void onChange() => notified++;
    PerformanceSettingsService.config.addListener(onChange);
    addTearDown(
        () => PerformanceSettingsService.config.removeListener(onChange));
    final before = PerformanceSettingsService.config.value;
    expect(read(before), isFalse, reason: '$label : point de depart');
    await PerformanceSettingsService.save(flip(before));
    expect(read(PerformanceSettingsService.config.value), isTrue,
        reason: '$label : la valeur EN MEMOIRE doit changer');
    expect(notified, 1, reason: '$label : les auditeurs doivent etre prevenus');
  }

  test('« Affiches TMDB en priorité » prend effet immédiatement', () async {
    await expectTakesEffect(
      'tmdbPostersFirst',
      (c) => c.copyWith(tmdbPostersFirst: true),
      (c) => c.tmdbPostersFirst,
    );
  });

  test('« Épisode suivant automatique » prend effet immédiatement', () async {
    PerformanceSettingsService.config.value =
        PerfConfig.defaults.copyWith(autoNextEpisode: false);
    await expectTakesEffect(
      'autoNextEpisode',
      (c) => c.copyWith(autoNextEpisode: true),
      (c) => c.autoNextEpisode,
    );
  });

  test('« Parce que tu as regardé » prend effet immédiatement', () async {
    PerformanceSettingsService.config.value =
        PerfConfig.defaults.copyWith(tmdbRowBecause: false);
    await expectTakesEffect(
      'tmdbRowBecause',
      (c) => c.copyWith(tmdbRowBecause: true),
      (c) => c.tmdbRowBecause,
    );
  });

  test('« Les mieux notés » prend effet immédiatement', () async {
    PerformanceSettingsService.config.value =
        PerfConfig.defaults.copyWith(tmdbRowTopRated: false);
    await expectTakesEffect(
      'tmdbRowTopRated',
      (c) => c.copyWith(tmdbRowTopRated: true),
      (c) => c.tmdbRowTopRated,
    );
  });

  test('la même instance ne notifie pas deux fois', () async {
    var notified = 0;
    void onChange() => notified++;
    PerformanceSettingsService.config.addListener(onChange);
    addTearDown(
        () => PerformanceSettingsService.config.removeListener(onChange));
    final same = PerformanceSettingsService.config.value;
    await PerformanceSettingsService.save(same);
    expect(notified, 0);
  });
}
