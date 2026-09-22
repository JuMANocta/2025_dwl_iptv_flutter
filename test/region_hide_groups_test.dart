import 'package:aetherStream/core/themes/app_theme_config.dart';
import 'package:aetherStream/core/themes/themes.dart';
import 'package:aetherStream/data/services/track_preferences_service.dart';
import 'package:aetherStream/feature/search/category_labels.dart';
import 'package:aetherStream/feature/search/m3u_filter.dart';
import 'package:aetherStream/feature/settings/region_filter_page.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// §regionMerge (2026-09-21) — « Langues et régions » réunit les DOUBLONS en
/// une case (Brésil + VO sous-titrée + Novidades, UK + USA, ex-Yougoslavie +
/// Bosnie + Croatie), sans toucher aux clés persistées.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fr = lookupAppLocalizations(const Locale('fr'));
  final en = lookupAppLocalizations(const Locale('en'));

  test('chaque clé masquable est dans UNE ligne et une seule', () {
    final List<String> flat =
        hideableRegionRows().expand((row) => row).toList();
    expect(flat.toSet().length, flat.length, reason: 'une clé en double');
    expect(flat.toSet(), kHideableRegionLabels.toSet());
  });

  test('les groupes ne réunissent que des clés masquables', () {
    for (final group in kRegionHideGroups.values) {
      for (final key in group) {
        expect(kHideableRegionLabels, contains(key), reason: key);
      }
    }
  });

  test('Algérie et Portugal restent des cases à part (choix utilisateur)', () {
    final rows = hideableRegionRows();
    expect(rows, contains(equals(['Algérie'])));
    expect(rows, contains(equals(['Portugal'])));
  });

  test('chaque groupe a un libellé traduit, différent dans les deux langues',
      () {
    for (final group in kRegionHideGroups.values) {
      final String f = regionRowLabel(group, fr);
      final String e = regionRowLabel(group, en);
      expect(f, isNot(contains(' · ')), reason: 'groupe sans libellé : $group');
      expect(f, isNot(e), reason: group.first);
    }
  });

  test('la VO reste en dernier, le reste suit son libellé affiché', () {
    for (final l10n in [fr, en]) {
      final rows = sortedRegionRows(l10n);
      expect(rows.last, [kVoRegionLabel]);
      final labels =
          rows.take(rows.length - 1).map((r) => regionRowLabel(r, l10n));
      expect(labels.first.toLowerCase().startsWith('a'), isTrue);
    }
  });

  testWidgets('cocher « Brésil » masque ses TROIS clés', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await TrackPreferencesService.reloadForTest();
    tester.view.physicalSize = const Size(1080, 12000);
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

    expect(find.text(fr.regBrazilGroup), findsOneWidget);
    // Les clés réunies n'ont plus de case à elles.
    expect(find.text(fr.regLegendado), findsNothing);
    expect(find.text('Novidades'), findsNothing);
    expect(find.text('USA'), findsNothing);

    await tester.tap(find.text(fr.regBrazilGroup));
    await tester.pumpAndSettle();
    final tile = tester.widget<CheckboxListTile>(find.ancestor(
        of: find.text(fr.regBrazilGroup),
        matching: find.byType(CheckboxListTile)));
    expect(tile.value, isTrue);
    // « Appliquer » apparaît : la sélection a changé (les trois clés).
    expect(find.text(fr.commonApply), findsOneWidget);
  });
}
