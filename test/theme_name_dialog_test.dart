// Recette AVD du 2026-09-17 — écran ROUGE (`_dependents.isEmpty`) après « OK »
// dans le dialogue « Enregistrer ce thème » : le contrôleur du champ était
// détruit dès le `pop`, pendant l'animation de sortie du dialogue. Ce test
// rejoue le geste et tombe si le contrôleur redevient détruit trop tôt.
import 'package:aetherStream/core/themes/app_theme_config.dart';
import 'package:aetherStream/core/themes/saved_themes_service.dart';
import 'package:aetherStream/core/themes/theme_service.dart';
import 'package:aetherStream/core/themes/themes.dart';
import 'package:aetherStream/feature/settings/theme_settings_page.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SavedThemesService.reloadForTest();
  });

  tearDown(() => ThemeService.config.value = AppThemeConfig.defaults);

  testWidgets('« Enregistrer sous… » puis OK : aucun écran rouge, thème gardé',
      (tester) async {
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
      home: const ThemeSettingsPage(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enregistrer sous…'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    // Le nom proposé est au SINGULIER (« Mon thème 1 », pas « Mes thèmes 1 »).
    expect(find.text('Mon thème 1'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Recette');
    await tester.tap(find.text('OK'));
    // L'animation de sortie dessine encore le champ : c'est ICI que ça tombait.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(SavedThemesService.themes.value.map((t) => t.name), ['Recette']);

    // La confirmation (snackbar) a sa minuterie : on la laisse finir.
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
  });
}
