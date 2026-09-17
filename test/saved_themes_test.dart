import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aetherStream/core/themes/app_theme_config.dart';
import 'package:aetherStream/core/themes/saved_themes_service.dart';

/// §themeStudio — « Mes thèmes » : ce qui a été réglé à la main se garde.
///
/// ⚠️ Ces tests tiennent surtout la TOLÉRANCE de lecture. Un thème enregistré
/// voyage dans un `.aether` que l'on peut ouvrir avec un éditeur de texte : une
/// entrée abîmée ne doit jamais faire échouer une restauration entière, ni
/// emporter les thèmes voisins.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const AppThemeConfig mine = AppThemeConfig(
    primaryColor: Color(0xFF123456),
    accentColor: Color(0xFF654321),
    tertiaryColor: Color(0xFFABCDEF),
    favoriteColor: Color(0xFF111111),
    warningColor: Color(0xFF222222),
    errorColor: Color(0xFF333333),
    successColor: Color(0xFF444444),
    glowIntensity: 0.3,
    borderRadius: 6.0,
    themeMode: ThemeMode.dark,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SavedThemesService.reloadForTest();
  });

  group('sérialisation', () {
    test('aller-retour : le thème revient identique', () {
      final String raw =
          SavedThemesService.encode([SavedTheme(name: 'Nuit', config: mine)]);
      final list = SavedThemesService.decode(raw);
      expect(list, hasLength(1));
      expect(list.first.name, 'Nuit');
      expect(list.first.config.sameLook(mine), isTrue);
      expect(list.first.config.themeMode, ThemeMode.dark);
    });

    test('une clé absente ou vide donne une liste vide, jamais une exception',
        () {
      expect(SavedThemesService.decode(null), isEmpty);
      expect(SavedThemesService.decode(''), isEmpty);
    });

    test('un JSON cassé, ou qui n\'est pas une liste, ne lève pas', () {
      expect(SavedThemesService.decode('{pas du json'), isEmpty);
      expect(SavedThemesService.decode('"une chaine"'), isEmpty);
      expect(SavedThemesService.decode('{"n":"x"}'), isEmpty);
      // ⚠️ Le piège du `.aether` : `as List?` LÈVE sur une chaîne.
      expect(SavedThemesService.fromList('pas une liste'), isEmpty);
      expect(SavedThemesService.fromList(null), isEmpty);
    });

    test('une entrée abîmée est sautée, les voisines survivent', () {
      final String raw = jsonEncode([
        {'n': 'Bonne', 'c': mine.toJson()},
        'je ne suis pas un objet',
        {'n': 'sans config'},
        {'n': '   ', 'c': mine.toJson()}, // nom vide après nettoyage
        {'n': 'Tronquée', 'c': {'p': 1}}, // champs manquants → fromJson lève
        {'n': 'Autre', 'c': mine.toJson()},
      ]);
      final list = SavedThemesService.decode(raw);
      expect(list.map((t) => t.name), ['Bonne', 'Autre']);
    });

    test('le plafond est tenu à la LECTURE aussi', () {
      final String raw = jsonEncode([
        for (int i = 0; i < SavedThemesService.kMaxThemes + 5; i++)
          {'n': 'T$i', 'c': mine.toJson()}
      ]);
      expect(SavedThemesService.decode(raw),
          hasLength(SavedThemesService.kMaxThemes));
    });
  });

  group('noms', () {
    test('un nom est rogné, aplati et borné', () {
      expect(SavedThemesService.sanitizeName('  Mon  thème \n cyan  '),
          'Mon thème cyan');
      expect(SavedThemesService.sanitizeName('   '), isEmpty);
      expect(SavedThemesService.sanitizeName('x' * 200).length,
          SavedThemesService.kMaxNameLength);
    });

    test('enregistrer sous un nom déjà pris REMPLACE, ne duplique pas',
        () async {
      await SavedThemesService.saveAs('Nuit', mine);
      await SavedThemesService.saveAs(
          'Nuit', mine.copyWith(primaryColor: const Color(0xFF00FF41)));
      expect(SavedThemesService.themes.value, hasLength(1));
      expect(SavedThemesService.themes.value.first.config.primaryColor,
          const Color(0xFF00FF41));
    });

    test('un nom vide est refusé, et le dit', () async {
      expect(await SavedThemesService.saveAs('   ', mine), isFalse);
      expect(SavedThemesService.themes.value, isEmpty);
    });

    test('renommer vers un nom déjà pris est refusé', () async {
      await SavedThemesService.saveAs('A', mine);
      await SavedThemesService.saveAs('B', mine);
      expect(await SavedThemesService.rename(1, 'A'), isFalse);
      expect(SavedThemesService.themes.value[1].name, 'B');
      expect(await SavedThemesService.rename(1, 'C'), isTrue);
      expect(SavedThemesService.themes.value[1].name, 'C');
    });

    test('le plafond refuse le suivant au lieu de l\'avaler', () async {
      for (int i = 0; i < SavedThemesService.kMaxThemes; i++) {
        expect(await SavedThemesService.saveAs('T$i', mine), isTrue);
      }
      expect(await SavedThemesService.saveAs('de trop', mine), isFalse);
      expect(SavedThemesService.themes.value,
          hasLength(SavedThemesService.kMaxThemes));
    });
  });

  group('persistance', () {
    test('un thème enregistré survit à un redémarrage', () async {
      await SavedThemesService.saveAs('Nuit', mine);
      await SavedThemesService.reloadForTest();
      expect(SavedThemesService.themes.value, hasLength(1));
      expect(SavedThemesService.themes.value.first.name, 'Nuit');
    });

    test('supprimer puis annuler remet le thème À SA PLACE', () async {
      await SavedThemesService.saveAs('A', mine);
      await SavedThemesService.saveAs('B', mine);
      await SavedThemesService.saveAs('C', mine);
      final SavedTheme removed = SavedThemesService.themes.value[1];
      await SavedThemesService.remove(1);
      expect(SavedThemesService.themes.value.map((t) => t.name), ['A', 'C']);
      await SavedThemesService.insert(1, removed);
      expect(SavedThemesService.themes.value.map((t) => t.name),
          ['A', 'B', 'C']);
    });

    test('vider la liste efface la clé au lieu d\'écrire « [] »', () async {
      await SavedThemesService.saveAs('A', mine);
      await SavedThemesService.remove(0);
      final p = await SharedPreferences.getInstance();
      expect(p.getString('aether_saved_themes_v1'), isNull);
    });
  });

  group('faut-il proposer d\'enregistrer avant de réinitialiser ?', () {
    test('un préréglage : non, il ne se perd pas', () {
      expect(SavedThemesService.isUnsaved(AppThemeConfig.matrix, const []),
          isFalse);
      expect(SavedThemesService.isUnsaved(AppThemeConfig.nordique, const []),
          isFalse);
    });

    test('le mode clair/sombre ne fait PAS sortir du préréglage', () {
      expect(
          SavedThemesService.isUnsaved(
              AppThemeConfig.matrix.copyWith(themeMode: ThemeMode.light),
              const []),
          isFalse);
    });

    test('une couleur réglée à la main : oui', () {
      expect(
          SavedThemesService.isUnsaved(
              AppThemeConfig.matrix.copyWith(primaryColor: mine.primaryColor),
              const []),
          isTrue);
    });

    test('un arrondi changé compte aussi comme un travail à perdre', () {
      expect(
          SavedThemesService.isUnsaved(
              AppThemeConfig.matrix.copyWith(borderRadius: 3.0), const []),
          isTrue);
    });

    test('déjà enregistré : non', () {
      expect(
          SavedThemesService.isUnsaved(
              mine, [SavedTheme(name: 'Nuit', config: mine)]),
          isFalse);
    });
  });
}
