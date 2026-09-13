// R43 — Ce que l'app RETIENT pour les pistes d'un titre à l'autre, et la
// règle « jamais un numéro » qui rend cette mémoire honnête.
//
// Le défaut d'origine : la feuille mémorisait `_trackKey(language, id)`, soit
// la langue quand la piste en avait une, SINON SON NUMÉRO — et le natif renvoie
// « unknown » pour une piste sans langue. Résultat mesuré dans le code : un
// « 1 » ou un « unknown » écrasait une vraie préférence et était ré-appliqué
// à chaque ouverture (`setPreferredAudioLanguage('unknown')`). Côté
// sous-titres, une LANGUE était mémorisée alors que rien ne la lisait.

import 'package:aetherStream/data/services/track_preferences_service.dart';
import 'package:aetherStream/feature/settings/track_memory_summary.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final AppLocalizations fr = lookupAppLocalizations(const Locale('fr'));

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TrackPreferencesService.audio = null;
    TrackPreferencesService.subtitle = null;
  });

  group('languageKeyFor — la règle « jamais un numéro »', () {
    test('une langue est gardée, normalisée', () {
      expect(TrackPreferencesService.languageKeyFor('en'), 'en');
      expect(TrackPreferencesService.languageKeyFor(' FR '), 'fr');
      expect(TrackPreferencesService.languageKeyFor('pt-BR'), 'pt-br');
      expect(TrackPreferencesService.languageKeyFor('fre'), 'fre');
    });

    test('un numéro de piste n\'est JAMAIS une clé', () {
      // C'est ce que `_trackKey` écrivait pour une piste sans langue : un
      // index, sans valeur d'un fichier à l'autre.
      expect(TrackPreferencesService.languageKeyFor('0'), isNull);
      expect(TrackPreferencesService.languageKeyFor('12'), isNull);
    });

    test('« unknown » du natif et « und » ISO ne sont pas des langues', () {
      expect(TrackPreferencesService.languageKeyFor('unknown'), isNull);
      expect(TrackPreferencesService.languageKeyFor('UNKNOWN'), isNull);
      expect(TrackPreferencesService.languageKeyFor('und'), isNull);
    });

    test('vide, nul, et les vestiges mpv rendent null', () {
      expect(TrackPreferencesService.languageKeyFor(null), isNull);
      expect(TrackPreferencesService.languageKeyFor(''), isNull);
      expect(TrackPreferencesService.languageKeyFor('   '), isNull);
      expect(TrackPreferencesService.languageKeyFor('auto'), isNull);
      expect(TrackPreferencesService.languageKeyFor('no'), isNull);
      expect(TrackPreferencesService.languageKeyFor('off'), isNull);
    });
  });

  group('init — migration des valeurs écrites par les versions précédentes', () {
    test('un numéro côté audio et une langue côté sous-titres tombent, et '
        'leurs clés sont effacées', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'track_pref_audio_v1': '1',
        'track_pref_sub_v1': 'fr',
      });

      await TrackPreferencesService.reloadForTest();

      expect(TrackPreferencesService.audio, isNull);
      expect(TrackPreferencesService.subtitle, isNull);
      final p = await SharedPreferences.getInstance();
      expect(p.containsKey('track_pref_audio_v1'), isFalse,
          reason: 'sinon la valeur serait rejouée au démarrage suivant');
      expect(p.containsKey('track_pref_sub_v1'), isFalse);
    });

    test('« unknown » côté audio tombe ; la coupure côté sous-titres reste',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'track_pref_audio_v1': 'unknown',
        'track_pref_sub_v1': TrackPreferencesService.kSubtitlesOff,
      });

      await TrackPreferencesService.reloadForTest();

      expect(TrackPreferencesService.audio, isNull);
      expect(TrackPreferencesService.subtitle,
          TrackPreferencesService.kSubtitlesOff,
          reason: 'la coupure est la SEULE mémoire de sous-titres légitime');
      final p = await SharedPreferences.getInstance();
      expect(p.containsKey('track_pref_sub_v1'), isTrue);
    });

    test('une vraie langue audio est conservée telle quelle', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'track_pref_audio_v1': 'en',
      });

      await TrackPreferencesService.reloadForTest();

      expect(TrackPreferencesService.audio, 'en');
      expect(TrackPreferencesService.subtitle, isNull);
    });
  });

  group('resetToAuto / hasMemory / version', () {
    test('revenir à l\'automatique efface les deux mémoires et prévient',
        () async {
      await TrackPreferencesService.setAudio('en');
      await TrackPreferencesService.setSubtitle(
          TrackPreferencesService.kSubtitlesOff);
      expect(TrackPreferencesService.hasMemory, isTrue);
      final before = TrackPreferencesService.version.value;

      await TrackPreferencesService.resetToAuto();

      expect(TrackPreferencesService.audio, isNull);
      expect(TrackPreferencesService.subtitle, isNull);
      expect(TrackPreferencesService.hasMemory, isFalse);
      expect(TrackPreferencesService.version.value, greaterThan(before),
          reason: 'la tuile des Réglages suit le notifieur, pas un rebuild');
      final p = await SharedPreferences.getInstance();
      expect(p.containsKey('track_pref_audio_v1'), isFalse);
      expect(p.containsKey('track_pref_sub_v1'), isFalse);
    });
  });

  group('trackMemorySummary — ce que la tuile des Réglages affiche', () {
    test('sans mémoire : « Automatique »', () {
      expect(trackMemorySummary(fr), fr.settingsTracksAuto);
    });

    test('une langue audio, nommée comme au lecteur', () {
      TrackPreferencesService.audio = 'en';
      expect(trackMemorySummary(fr),
          fr.settingsTracksAudioLang(fr.langEnglish));
    });

    test('la coupure des sous-titres', () {
      TrackPreferencesService.subtitle = TrackPreferencesService.kSubtitlesOff;
      expect(trackMemorySummary(fr), fr.settingsTracksSubsOff);
    });

    test('les deux, séparées par un point médian', () {
      TrackPreferencesService.audio = 'de';
      TrackPreferencesService.subtitle = TrackPreferencesService.kSubtitlesOff;
      expect(
        trackMemorySummary(fr),
        '${fr.settingsTracksAudioLang(fr.langGerman)} · ${fr.settingsTracksSubsOff}',
      );
    });

    test('une langue sans nom connu s\'affiche en majuscules, pas en code nu',
        () {
      TrackPreferencesService.audio = 'sv';
      expect(trackMemorySummary(fr), fr.settingsTracksAudioLang('SV'));
    });
  });
}
