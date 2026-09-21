import 'package:aetherStream/core/themes/app_theme_config.dart';
import 'package:aetherStream/core/themes/themes.dart';
import 'package:aetherStream/data/services/track_preferences_service.dart';
import 'package:aetherStream/feature/search/m3u_filter.dart';
import 'package:aetherStream/feature/settings/region_filter_page.dart';
import 'package:aetherStream/feature/settings/track_memory_summary.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// R43 → §settingsTidy (2026-09-21) — La mémoire des pistes vit dans la page
/// « Langues et régions », en tête, et plus dans une tuile des Paramètres.
///
/// Ce qui est tenu ici : la section dit TOUJOURS ce qui s'appliquera au
/// prochain titre (« Automatique… » quand rien n'est retenu), et le geste
/// « Revenir à l'automatique » n'existe que lorsqu'il SERT — l'ancienne tuile
/// promettait une sous-page par son chevron et ne faisait rien sans mémoire.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final en = lookupAppLocalizations(const Locale('en'));
  final fr = lookupAppLocalizations(const Locale('fr'));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await TrackPreferencesService.reloadForTest();
  });

  group('résumé pur', () {
    test('aucune mémoire : « Automatique »', () {
      expect(TrackPreferencesService.hasMemory, isFalse);
      expect(trackMemorySummary(fr), fr.settingsTracksAuto);
      expect(trackMemorySummary(en), en.settingsTracksAuto);
    });

    test('une langue audio mémorisée se lit en clair', () async {
      await TrackPreferencesService.setAudio('en');
      expect(trackMemorySummary(fr), fr.settingsTracksAudioLang('Anglais'));
    });

    test('des sous-titres coupés comptent aussi', () async {
      await TrackPreferencesService.setSubtitle(
          TrackPreferencesService.kSubtitlesOff);
      expect(trackMemorySummary(en), contains('Subtitles: off'));
    });

    test('revenir à l\'automatique rend « Automatique »', () async {
      await TrackPreferencesService.setAudio('en');
      await TrackPreferencesService.resetToAuto();
      expect(trackMemorySummary(fr), fr.settingsTracksAuto);
    });
  });

  group('page Langues et régions', () {
    Future<void> pumpPage(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: const [Locale('fr'), Locale('en')],
        theme: darkTheme(AppThemeConfig.defaults),
        home: const RegionFilterPage(),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('sans mémoire : la section dit « Automatique », sans bouton',
        (tester) async {
      await pumpPage(tester);
      expect(find.text(fr.settingsTracks.toUpperCase()), findsOneWidget);
      expect(find.text(fr.settingsTracksAuto), findsOneWidget);
      expect(find.text(fr.settingsTracksResetConfirm), findsNothing);
      // La liste des régions suit, sous son propre titre.
      expect(find.text(fr.regionHideSection.toUpperCase()), findsOneWidget);
    });

    testWidgets('avec une mémoire : le résumé ET le geste, qui suivent le service',
        (tester) async {
      await TrackPreferencesService.setAudio('en');
      await pumpPage(tester);
      expect(find.text(fr.settingsTracksAudioLang('Anglais')), findsOneWidget);
      expect(find.text(fr.settingsTracksResetConfirm), findsOneWidget);

      // Oublié ailleurs (lecteur) : la page suit par le notifieur.
      await TrackPreferencesService.resetToAuto();
      await tester.pumpAndSettle();
      expect(find.text(fr.settingsTracksAuto), findsOneWidget);
      expect(find.text(fr.settingsTracksResetConfirm), findsNothing);
    });
  });

  test('« Brésil — VO sous-titrée » : clé inchangée, rangée juste après Brésil',
      () {
    // ⛔ La clé est persistée (réglage, cache, `.aether`) : elle ne bouge pas.
    expect(kLegRegionLabel, 'Legendado (sous-titré PT)');
    final int br = kHideableRegionLabels.indexOf('Brésil');
    expect(kHideableRegionLabels[br + 1], kLegRegionLabel);
    expect(fr.regLegendado, contains('Brésil'));
    expect(en.regLegendado, contains('Brazil'));
  });
}
