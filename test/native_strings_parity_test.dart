import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Revue 2026-09-11, D2B-17 / D3L-02 — Les textes des notifications NATIVES.
///
/// Le cliquet l10n ne lit que `lib/` : ces tests tiennent le côté Android.
///   1. `values/` (français, défaut) et `values-en/` portent les MÊMES clés —
///      sinon Android retombe sur le français pour la clé manquante (et le
///      lint `MissingTranslation` peut casser un build release) ;
///   2. aucun libellé français ne revient en dur dans le Kotlin de l'app ;
///   3. le paquet vendoré lit bien le nom de canal que l'app définit.
void main() {
  const String res = 'android/app/src/main/res';
  final RegExp stringName = RegExp(r'<string name="([^"]+)"');

  Set<String> keysOf(String path) => stringName
      .allMatches(File(path).readAsStringSync())
      .map((m) => m.group(1)!)
      .toSet();

  test('values/ et values-en/ portent exactement les mêmes clés', () {
    final Set<String> fr = keysOf('$res/values/strings.xml');
    final Set<String> en = keysOf('$res/values-en/strings.xml');
    expect(fr, isNotEmpty);
    expect(fr.difference(en), isEmpty, reason: 'absentes en anglais');
    expect(en.difference(fr), isEmpty, reason: 'absentes du défaut');
  });

  test('plus aucun libellé de notification français en dur dans le Kotlin', () {
    const List<String> kotlin = [
      'android/app/src/main/kotlin/com/juman/aetherstream/AetherDownloadService.kt',
      'android/app/src/main/kotlin/com/juman/aetherstream/AetherCastService.kt',
      'android/app/src/main/kotlin/com/juman/aetherstream/MainActivity.kt',
    ];
    const List<String> banned = [
      '"Annuler"',
      '"Arrêter"',
      '"Lecture"',
      '"Téléchargement"',
      '"Téléchargements"',
      '"Diffusion en cours"',
      '"Diffusion Chromecast"',
      '"Échec du téléchargement"',
    ];
    for (final String path in kotlin) {
      // Le CODE seulement : les commentaires (français par convention)
      // citent volontiers le bouton « "Annuler" ».
      final String src = File(path)
          .readAsLinesSync()
          .where((l) {
            final String t = l.trimLeft();
            return !t.startsWith('//') &&
                !t.startsWith('*') &&
                !t.startsWith('/*');
          })
          .join('\n');
      for (final String literal in banned) {
        expect(src.contains(literal), isFalse, reason: '$path : $literal');
      }
    }
  });

  test('le nom du canal de lecture lu par le paquet vendoré existe', () {
    final Set<String> keys = keysOf('$res/values/strings.xml');
    const String handler = 'packages/aether_video/android/src/main/kotlin/com/'
        'huddlecommunity/better_native_video_player/handlers/'
        'VideoPlayerNotificationHandler.kt';
    final String src = File(handler).readAsStringSync();
    for (final String name in const [
      'notif_channel_playback',
      'notif_channel_playback_desc',
    ]) {
      expect(keys, contains(name));
      expect(src, contains('"$name"'));
    }
  });
}
