// §playerPanel backup (audit du 2026-09-22) — `BackupContent.summary()` pour
// les 4 nouveaux champs.
//
// ⛔ NE COMPILE PAS ENCORE : `bkPartSubtitleKey`, `bkPartPlayerSettings` et
// `bkPartTrackMemory` n'existent pas dans `app_localizations.dart` tant que
// les clés ne sont pas ajoutées aux `.arb` (agent B) et `flutter gen-l10n`
// rejoué. Séparé de `backup_player_panel_fields_test.dart`, qui lui compile
// et passe dès maintenant, pour ne pas bloquer le reste de la suite.
import 'package:aetherStream/data/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _legacyJson() => <String, dynamic>{
      'appVersion': '1.20.2+158',
      'exportedAt': '2026-09-22T10:00:00.000',
      'accounts': <Map<String, dynamic>>[],
      'activeAccountId': null,
      'tmdbKey': null,
      'theme': null,
      'perf': null,
      'favorites': <String>[],
      'watchProgress': <String, dynamic>{},
    };

void main() {
  group('BackupContent.summary() — les 4 nouveaux réglages', () {
    test('rien coché → aucune des 3 nouvelles lignes', () {
      final c = BackupContent.fromJson(_legacyJson());
      expect(c.summary(), isNot(contains('sous-titres')));
      expect(c.summary(), isNot(contains('pistes')));
      expect(c.summary(), isNot(contains('lecteur')));
    });

    test('clé de sous-titres vide (« ») : PAS annoncée', () {
      final c =
          BackupContent.fromJson(_legacyJson()..['subtitleApiKey'] = '');
      expect(c.summary(), isNot(contains('sous-titres')));
    });

    test('clé de sous-titres renseignée : annoncée', () {
      final c = BackupContent.fromJson(
          _legacyJson()..['subtitleApiKey'] = 'abc123');
      expect(c.summary(), contains('sous-titres'));
    });

    test('trackPrefs présent mais les DEUX valent null : PAS annoncé '
        '(rien à mémoriser)', () {
      final c = BackupContent.fromJson(_legacyJson()
        ..['trackPrefs'] =
            <String, dynamic>{'audio': null, 'subtitle': null});
      expect(c.summary(), isNot(contains('pistes')));
    });

    test('trackPrefs avec une mémoire réelle : annoncé', () {
      final c = BackupContent.fromJson(_legacyJson()
        ..['trackPrefs'] = <String, dynamic>{'audio': 'fr', 'subtitle': null});
      expect(c.summary(), contains('pistes'));
    });

    test('videoFit seul : la ligne « réglages du lecteur » apparaît', () {
      final c =
          BackupContent.fromJson(_legacyJson()..['videoFit'] = 'zoom');
      expect(c.summary(), contains('lecteur'));
    });

    test('videoStatsEnabled seul (même false) : la ligne apparaît aussi', () {
      final c = BackupContent.fromJson(
          _legacyJson()..['videoStatsEnabled'] = false);
      expect(c.summary(), contains('lecteur'));
    });

    test('videoFit et videoStatsEnabled ensemble : UNE seule ligne, pas deux',
        () {
      final c = BackupContent.fromJson(_legacyJson()
        ..['videoFit'] = 'zoom'
        ..['videoStatsEnabled'] = true);
      final occurrences =
          RegExp('lecteur').allMatches(c.summary().toLowerCase()).length;
      expect(occurrences, 1);
    });
  });
}
