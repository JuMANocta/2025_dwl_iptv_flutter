import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/core/themes/app_theme_config.dart';
import 'package:aetherStream/core/themes/saved_themes_service.dart';
import 'package:aetherStream/data/services/backup_service.dart';

/// §themeStudio — « Mes thèmes » voyage dans le `.aether`.
///
/// ⚠️ La règle que ces tests tiennent est celle de §langRegion : **`null` et
/// liste vide ne veulent pas dire la même chose**. Une sauvegarde faite avant
/// cette clé ne doit pas EFFACER les thèmes de l'appareil qui la restaure ;
/// une sauvegarde qui porte une liste vide, elle, dit bien « aucun ».
void main() {
  BackupContent base({Object? savedThemes, bool includeKey = true}) {
    final Map<String, dynamic> j = {
      'appVersion': '1.19.3+155',
      'exportedAt': DateTime(2026, 9, 16).toIso8601String(),
      'accounts': <Object?>[],
      'activeAccountId': null,
      'tmdbKey': null,
      'theme': AppThemeConfig.matrix.toJson(),
      'favorites': <String>[],
      'watchProgress': <String, dynamic>{},
    };
    if (includeKey) j['savedThemes'] = savedThemes;
    return BackupContent.fromJson(j);
  }

  test('aller-retour : deux thèmes enregistrés survivent au fichier', () {
    final List<Map<String, dynamic>> themes = SavedThemesService.toJsonList([
      SavedTheme(name: 'Nuit', config: AppThemeConfig.nordique),
      SavedTheme(name: 'Néon', config: AppThemeConfig.synthwave),
    ]);
    final BackupContent c = base(savedThemes: themes);
    final String encoded = jsonEncode(c.toJson());
    final BackupContent back =
        BackupContent.fromJson(jsonDecode(encoded) as Map<String, dynamic>);

    final list = SavedThemesService.fromList(back.savedThemes);
    expect(list.map((t) => t.name), ['Nuit', 'Néon']);
    expect(list.first.config.sameLook(AppThemeConfig.nordique), isTrue);
    expect(list.last.config.sameLook(AppThemeConfig.synthwave), isTrue);
  });

  test('clé ABSENTE : `null`, donc on ne touche à rien à la restauration', () {
    expect(base(includeKey: false).savedThemes, isNull);
    expect(base(savedThemes: null).savedThemes, isNull);
  });

  test('liste VIDE : un choix explicite, pas la même chose que `null`', () {
    expect(base(savedThemes: <Object?>[]).savedThemes, isEmpty);
    expect(base(savedThemes: <Object?>[]).savedThemes, isNotNull);
  });

  test('un type inattendu ne fait pas échouer toute la restauration', () {
    // ⚠️ `j['savedThemes'] as List?` LÈVERAIT ici, et une sauvegarde entière
    // serait refusée pour un accessoire (le piège de §langRegion).
    expect(base(savedThemes: 'une chaîne').savedThemes, isNull);
    expect(base(savedThemes: 42).savedThemes, isNull);
    expect(base(savedThemes: {'n': 'x'}).savedThemes, isNull);
  });

  test('une entrée abîmée est sautée, les voisines passent', () {
    final BackupContent c = base(savedThemes: [
      {'n': 'Bonne', 'c': AppThemeConfig.tron.toJson()},
      'pas un objet',
      {'n': 'Autre', 'c': AppThemeConfig.classic.toJson()},
    ]);
    // Trois entrées lues (les non-objets deviennent des objets vides)…
    expect(c.savedThemes, hasLength(2));
    // …et le tri final ne garde que ce qui est un thème.
    expect(SavedThemesService.fromList(c.savedThemes).map((t) => t.name),
        ['Bonne', 'Autre']);
  });

  test('le résumé COMPTE les thèmes enregistrés', () {
    final BackupContent c = base(savedThemes: [
      {'n': 'A', 'c': AppThemeConfig.tron.toJson()},
      {'n': 'B', 'c': AppThemeConfig.classic.toJson()},
    ]);
    expect(c.summary(), contains('2 thèmes enregistrés'));
    // Rien à compter → rien à dire. ⚠️ « thème » tout court reste présent :
    // c'est le thème COURANT, qui n'a rien à voir avec la liste.
    expect(base(savedThemes: <Object?>[]).summary(),
        isNot(contains('enregistré')));
  });

  test('le thème COURANT et les thèmes enregistrés sont deux choses', () {
    final BackupContent c = base(savedThemes: <Object?>[]);
    expect(c.theme, isNotNull);
    expect(c.savedThemes, isEmpty);
  });
}
