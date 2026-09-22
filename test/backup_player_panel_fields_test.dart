// §playerPanel backup (audit du 2026-09-22) — Les 4 réglages retrouvés
// absents de `.aether` : mémoire des pistes (§trackMemory), clé du
// fournisseur de sous-titres en ligne, format d'image du lecteur, affichage
// des infos vidéo. Même garde-fou que `backup_content_test.dart` pour
// `hiddenRegions` : une sauvegarde qui ne connaît pas ces champs doit se
// restaurer SANS RIEN TOUCHER localement, jamais une exception ni une valeur
// imposée.
//
// ⚠️ Les assertions sur `BackupContent.summary()` vivent dans
// `backup_player_panel_summary_test.dart`, PAS ici : les accesseurs l10n
// `bkPartSubtitleKey`/`bkPartPlayerSettings`/`bkPartTrackMemory` n'existent
// pas encore (agent B les ajoute aux `.arb`) — ce fichier-ci doit compiler et
// passer DÈS MAINTENANT.
import 'dart:convert';

import 'package:aetherStream/data/services/backup_service.dart';
import 'package:aetherStream/data/services/subtitle_api_service.dart';
import 'package:aetherStream/data/services/track_preferences_service.dart';
import 'package:aetherStream/feature/player/video_fit.dart';
import 'package:aetherStream/feature/player/video_stats.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sauvegarde minimale, ANTÉRIEURE aux 4 champs §playerPanel — ni l'un ni
/// l'autre n'apparaît dans le JSON, exactement comme un vrai vieux `.aether`.
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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BackupContent.fromJson — tolérance à l\'absence (JSON pur)', () {
    test('les 4 champs sont null sur une sauvegarde antérieure', () {
      final c = BackupContent.fromJson(_legacyJson());
      expect(c.subtitleApiKey, isNull);
      expect(c.trackPrefs, isNull);
      expect(c.videoFit, isNull);
      expect(c.videoStatsEnabled, isNull);
    });

    test('subtitleApiKey « » (vide) : présent, distinct de absent', () {
      final c =
          BackupContent.fromJson(_legacyJson()..['subtitleApiKey'] = '');
      expect(c.subtitleApiKey, '');
    });

    test('subtitleApiKey renseignée : conservée telle quelle', () {
      final c = BackupContent.fromJson(
          _legacyJson()..['subtitleApiKey'] = 'abc123');
      expect(c.subtitleApiKey, 'abc123');
    });

    test('trackPrefs d\'un type inattendu : ignoré, comme hiddenRegions', () {
      final c = BackupContent.fromJson(_legacyJson()..['trackPrefs'] = 'fr,no');
      expect(c.trackPrefs, isNull);
    });

    test('trackPrefs présent, deux clés : conservées telles quelles', () {
      final c = BackupContent.fromJson(_legacyJson()
        ..['trackPrefs'] = <String, dynamic>{'audio': 'fr', 'subtitle': null});
      expect(c.trackPrefs, {'audio': 'fr', 'subtitle': null});
    });

    test('videoFit : nom conservé tel quel (la validation vient plus tard)',
        () {
      final c =
          BackupContent.fromJson(_legacyJson()..['videoFit'] = 'zoom');
      expect(c.videoFit, 'zoom');
    });

    test('videoStatsEnabled false : distinct de absent', () {
      final c = BackupContent.fromJson(
          _legacyJson()..['videoStatsEnabled'] = false);
      expect(c.videoStatsEnabled, isFalse);
    });
  });

  group('BackupContent — aller-retour JSON', () {
    test('les 4 champs survivent à un aller-retour à l\'identique', () {
      final j = _legacyJson()
        ..['subtitleApiKey'] = 'abc123'
        ..['trackPrefs'] = <String, dynamic>{'audio': 'fr', 'subtitle': 'no'}
        ..['videoFit'] = 'zoom'
        ..['videoStatsEnabled'] = true;
      final once = BackupContent.fromJson(j);
      final twice = BackupContent.fromJson(
          jsonDecode(jsonEncode(once.toJson())) as Map<String, dynamic>);
      expect(twice.subtitleApiKey, once.subtitleApiKey);
      expect(twice.trackPrefs, once.trackPrefs);
      expect(twice.videoFit, once.videoFit);
      expect(twice.videoStatsEnabled, once.videoStatsEnabled);
    });

    test('null survit à l\'aller-retour (pas transformé en valeur imposée)',
        () {
      final once = BackupContent.fromJson(_legacyJson());
      final twice = BackupContent.fromJson(
          jsonDecode(jsonEncode(once.toJson())) as Map<String, dynamic>);
      expect(twice.subtitleApiKey, isNull);
      expect(twice.trackPrefs, isNull);
      expect(twice.videoFit, isNull);
      expect(twice.videoStatsEnabled, isNull);
    });
  });

  group('VideoFitPreference.fromName — pur', () {
    test('nom connu rend le mode', () {
      expect(VideoFitPreference.fromName('zoom'), VideoFitMode.zoom);
      expect(VideoFitPreference.fromName('original'), VideoFitMode.original);
      expect(VideoFitPreference.fromName('stretch'), VideoFitMode.stretch);
    });
    test('nom inconnu (sauvegarde d\'une version plus récente) rend null', () {
      expect(VideoFitPreference.fromName('panoramique'), isNull);
    });
    test('null rend null', () {
      expect(VideoFitPreference.fromName(null), isNull);
    });
  });

  group('TrackPreferencesService.isValidSubtitleMemory — pur', () {
    test('null (automatique) est valide', () {
      expect(TrackPreferencesService.isValidSubtitleMemory(null), isTrue);
    });
    test('kSubtitlesOff est valide', () {
      expect(
        TrackPreferencesService.isValidSubtitleMemory(
            TrackPreferencesService.kSubtitlesOff),
        isTrue,
      );
    });
    test('une langue n\'est JAMAIS valide en mémoire de sous-titres (R43)',
        () {
      expect(TrackPreferencesService.isValidSubtitleMemory('fr'), isFalse);
    });
  });

  group('BackupService.applyBackup — restauration des 4 champs', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      SubtitleApiService.resetForTest();
    });

    test('clé de sous-titres : absente du fichier → ne touche pas à la clé '
        'locale', () async {
      await SubtitleApiService.saveApiKey('deja-la');
      final content = BackupContent.fromJson(_legacyJson());
      await BackupService.applyBackup(content);
      expect(await SubtitleApiService.getApiKey(), 'deja-la');
    });

    test('clé de sous-titres : « » explicite → efface la clé locale',
        () async {
      await SubtitleApiService.saveApiKey('deja-la');
      final content =
          BackupContent.fromJson(_legacyJson()..['subtitleApiKey'] = '');
      await BackupService.applyBackup(content);
      expect(await SubtitleApiService.getApiKey(), isNull);
    });

    test('clé de sous-titres : valeur → remplace la clé locale', () async {
      final content = BackupContent.fromJson(
          _legacyJson()..['subtitleApiKey'] = 'nouvelle-cle');
      await BackupService.applyBackup(content);
      expect(await SubtitleApiService.getApiKey(), 'nouvelle-cle');
    });

    test('mémoire des pistes : champ absent → ne touche à rien', () async {
      await TrackPreferencesService.reloadForTest();
      await TrackPreferencesService.setAudio('en');
      final content = BackupContent.fromJson(_legacyJson());
      await BackupService.applyBackup(content);
      expect(TrackPreferencesService.audio, 'en');
    });

    test('mémoire des pistes : audio null explicite → repasse en '
        'automatique (un vrai choix, pas une absence)', () async {
      await TrackPreferencesService.reloadForTest();
      await TrackPreferencesService.setAudio('en');
      final content = BackupContent.fromJson(_legacyJson()
        ..['trackPrefs'] =
            <String, dynamic>{'audio': null, 'subtitle': null});
      await BackupService.applyBackup(content);
      expect(TrackPreferencesService.audio, isNull);
    });

    test('mémoire des pistes : audio valide → appliqué', () async {
      await TrackPreferencesService.reloadForTest();
      final content = BackupContent.fromJson(_legacyJson()
        ..['trackPrefs'] =
            <String, dynamic>{'audio': 'pt-br', 'subtitle': null});
      await BackupService.applyBackup(content);
      expect(TrackPreferencesService.audio, 'pt-br');
    });

    test('mémoire des pistes : sous-titre = un NUMÉRO → ignoré (R43), '
        'mémoire locale intacte', () async {
      await TrackPreferencesService.reloadForTest();
      await TrackPreferencesService.setSubtitle(
          TrackPreferencesService.kSubtitlesOff);
      final content = BackupContent.fromJson(_legacyJson()
        ..['trackPrefs'] = <String, dynamic>{'audio': null, 'subtitle': '1'});
      await BackupService.applyBackup(content);
      expect(TrackPreferencesService.subtitle,
          TrackPreferencesService.kSubtitlesOff);
    });

    test('mémoire des pistes : sous-titre = une LANGUE → ignoré (R43)',
        () async {
      await TrackPreferencesService.reloadForTest();
      final content = BackupContent.fromJson(_legacyJson()
        ..['trackPrefs'] = <String, dynamic>{'audio': null, 'subtitle': 'fr'});
      await BackupService.applyBackup(content);
      expect(TrackPreferencesService.subtitle, isNot('fr'));
    });

    test('mémoire des pistes : sous-titre coupé (kSubtitlesOff) → appliqué',
        () async {
      await TrackPreferencesService.reloadForTest();
      final content = BackupContent.fromJson(_legacyJson()
        ..['trackPrefs'] = <String, dynamic>{
          'audio': null,
          'subtitle': TrackPreferencesService.kSubtitlesOff,
        });
      await BackupService.applyBackup(content);
      expect(TrackPreferencesService.subtitle,
          TrackPreferencesService.kSubtitlesOff);
    });

    test('format d\'image : nom inconnu → ne touche à rien', () async {
      VideoFitPreference.set(VideoFitMode.zoom);
      final content = BackupContent.fromJson(
          _legacyJson()..['videoFit'] = 'panoramique');
      await BackupService.applyBackup(content);
      expect(VideoFitPreference.current, VideoFitMode.zoom);
    });

    test('format d\'image : nom connu → appliqué', () async {
      final content =
          BackupContent.fromJson(_legacyJson()..['videoFit'] = 'stretch');
      await BackupService.applyBackup(content);
      expect(VideoFitPreference.current, VideoFitMode.stretch);
    });

    test('infos vidéo : absent → ne touche à rien', () async {
      VideoStatsPreference.set(true);
      final content = BackupContent.fromJson(_legacyJson());
      await BackupService.applyBackup(content);
      expect(VideoStatsPreference.enabled, isTrue);
    });

    test('infos vidéo : false explicite → appliqué (même si c\'est le '
        'défaut, absent ≠ false)', () async {
      VideoStatsPreference.set(true);
      final content = BackupContent.fromJson(
          _legacyJson()..['videoStatsEnabled'] = false);
      await BackupService.applyBackup(content);
      expect(VideoStatsPreference.enabled, isFalse);
    });
  });
}
