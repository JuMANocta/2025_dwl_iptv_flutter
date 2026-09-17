import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aetherStream/data/services/track_preferences_service.dart';
import 'package:aetherStream/feature/settings/track_memory_summary.dart';
import 'package:aetherStream/l10n/app_localizations.dart';

/// R43 (2026-09-16) — La tuile « Langues des pistes » ne se montre que
/// lorsqu'elle SERT.
///
/// ⚠️ Le défaut corrigé : elle portait un chevron `>` — la promesse d'une
/// sous-page — alors qu'elle n'ouvrait rien ; et dans l'état par défaut (aucune
/// mémoire), un tap ne faisait rien non plus. Une tuile inerte qui promet un
/// écran est pire qu'une tuile absente.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final en = lookupAppLocalizations(const Locale('en'));
  final fr = lookupAppLocalizations(const Locale('fr'));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await TrackPreferencesService.reloadForTest();
  });

  test('aucune mémoire : pas de tuile du tout', () {
    expect(TrackPreferencesService.hasMemory, isFalse);
    expect(trackMemoryTileSubtitle(fr), isNull);
    expect(trackMemoryTileSubtitle(en), isNull);
  });

  test('une langue audio mémorisée : le sous-titre dit le GESTE', () async {
    await TrackPreferencesService.setAudio('en');
    final String? text = trackMemoryTileSubtitle(fr);
    expect(text, isNotNull);
    // Ce qui est retenu…
    expect(text, contains('Anglais'));
    // …et ce qu'un tap va faire.
    expect(text, contains('automatique'));
  });

  test('des sous-titres coupés comptent aussi', () async {
    await TrackPreferencesService.setSubtitle(
        TrackPreferencesService.kSubtitlesOff);
    expect(trackMemoryTileSubtitle(en), isNotNull);
    expect(trackMemoryTileSubtitle(en), contains('Subtitles: off'));
  });

  test('revenir à l\'automatique fait disparaître la tuile', () async {
    await TrackPreferencesService.setAudio('en');
    expect(trackMemoryTileSubtitle(fr), isNotNull);
    await TrackPreferencesService.resetToAuto();
    expect(trackMemoryTileSubtitle(fr), isNull);
  });

  test('le résumé pur, lui, ne change pas : il sert aussi dans le lecteur',
      () async {
    expect(trackMemorySummary(fr), fr.settingsTracksAuto);
    await TrackPreferencesService.setAudio('en');
    expect(trackMemorySummary(fr), fr.settingsTracksAudioLang('Anglais'));
  });
}
