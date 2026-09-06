// §langRegion — Le champ « langues / régions masquées » dans une sauvegarde
// `.aether`.
//
// ⚠️ **La règle tient en une phrase** : une sauvegarde qui ne connaît pas ce
// champ (toutes celles d'avant) doit se restaurer sans erreur ET sans rien
// cocher. C'est ce que ces tests verrouillent — le reste du contenu n'est pas
// testé ici, il dépend de services de plateforme.
import 'dart:convert';

import 'package:aetherStream/data/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Une sauvegarde minimale, telle que la produisait une version antérieure.
Map<String, dynamic> _legacyJson() => <String, dynamic>{
      'appVersion': '1.17.0+1',
      'exportedAt': '2026-08-30T07:26:00.000',
      'accounts': <Map<String, dynamic>>[],
      'activeAccountId': null,
      'tmdbKey': null,
      'theme': null,
      'perf': null,
      'favorites': <String>[],
      'watchProgress': <String, dynamic>{},
    };

void main() {
  group('§langRegion — lecture tolérante du champ régions', () {
    test('champ ABSENT (vieille sauvegarde) : null, aucune exception', () {
      final c = BackupContent.fromJson(_legacyJson());
      expect(c.hiddenRegions, isNull);
      expect(c.summary(), isNot(contains('masquée')));
    });

    test('champ null explicite : null', () {
      final c = BackupContent.fromJson(_legacyJson()..['hiddenRegions'] = null);
      expect(c.hiddenRegions, isNull);
    });

    test('liste vide : liste vide, et rien dans le résumé', () {
      final c = BackupContent.fromJson(
          _legacyJson()..['hiddenRegions'] = <String>[]);
      expect(c.hiddenRegions, isEmpty);
      expect(c.summary(), isNot(contains('masquée')));
    });

    test('liste valide : conservée, et annoncée dans le résumé', () {
      final c = BackupContent.fromJson(
          _legacyJson()..['hiddenRegions'] = <String>['AR', 'TR']);
      expect(c.hiddenRegions, ['AR', 'TR']);
      expect(c.summary(), contains('2 langues masquées'));
    });

    test('une seule région : le résumé reste au singulier', () {
      final c = BackupContent.fromJson(
          _legacyJson()..['hiddenRegions'] = <String>['AR']);
      expect(c.summary(), contains('1 langue masquée'));
      expect(c.summary(), isNot(contains('langues')));
    });

    test('type INATTENDU : ignoré sans planter', () {
      // Un fichier corrompu ou d'une autre version ne doit pas faire échouer
      // toute la restauration pour un champ accessoire.
      final c = BackupContent.fromJson(
          _legacyJson()..['hiddenRegions'] = 'AR,TR');
      expect(c.hiddenRegions, isNull);
    });

    test('entrées non-textuelles : écartées, les autres survivent', () {
      final c = BackupContent.fromJson(
          _legacyJson()..['hiddenRegions'] = <dynamic>['AR', 42, null, 'TR']);
      expect(c.hiddenRegions, ['AR', 'TR']);
    });
  });

  group('§langRegion — aller-retour', () {
    test('ce qui est écrit est relu à l\'identique', () {
      final j = _legacyJson()..['hiddenRegions'] = <String>['AR', 'TR'];
      final once = BackupContent.fromJson(j);
      final twice = BackupContent.fromJson(
          jsonDecode(jsonEncode(once.toJson())) as Map<String, dynamic>);
      expect(twice.hiddenRegions, once.hiddenRegions);
    });

    test('null survit à l\'aller-retour (pas transformé en liste vide)', () {
      final once = BackupContent.fromJson(_legacyJson());
      final twice = BackupContent.fromJson(
          jsonDecode(jsonEncode(once.toJson())) as Map<String, dynamic>);
      expect(twice.hiddenRegions, isNull,
          reason: 'null = « le fichier ne sait pas », pas « rien de masqué »');
    });
  });
}
