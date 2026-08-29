import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/services/remote_control_service.dart';

/// §mediaKeys — Avant ce lot, AUCUNE touche média n'était captée : ni côté
/// Dart, ni côté Android, ni par `media_kit`. PLAY, PAUSE, STOP et l'avance
/// rapide de la télécommande ne faisaient rien du tout.
///
/// La table est volontairement une donnée pure : elle se teste sans widget, et
/// c'est elle qui garantit que le `Dpad` racine route bien vers le vocabulaire
/// d'actions déjà utilisé par la télécommande web.
void main() {
  group('kMediaKeyActions', () {
    test('les 8 touches média des télécommandes TV sont couvertes', () {
      expect(kMediaKeyActions.keys, containsAll(<LogicalKeyboardKey>[
        LogicalKeyboardKey.mediaPlayPause,
        LogicalKeyboardKey.mediaPlay,
        LogicalKeyboardKey.mediaPause,
        LogicalKeyboardKey.mediaStop,
        LogicalKeyboardKey.mediaFastForward,
        LogicalKeyboardKey.mediaRewind,
        LogicalKeyboardKey.mediaTrackNext,
        LogicalKeyboardKey.mediaTrackPrevious,
      ]));
    });

    test('PLAY et PAUSE sont des actions distinctes, pas une bascule', () {
      // Router PAUSE sur `playpause` relancerait la lecture d'une vidéo déjà
      // en pause — c'est le piège que ce test verrouille.
      expect(kMediaKeyActions[LogicalKeyboardKey.mediaPlay], 'play');
      expect(kMediaKeyActions[LogicalKeyboardKey.mediaPause], 'pause');
      expect(kMediaKeyActions[LogicalKeyboardKey.mediaPlayPause], 'playpause');
    });

    test('avance/recul réutilisent le vocabulaire de seek existant', () {
      expect(kMediaKeyActions[LogicalKeyboardKey.mediaFastForward], 'seekfwd');
      expect(kMediaKeyActions[LogicalKeyboardKey.mediaRewind], 'seekback');
    });

    test('aucune touche média ne détourne une direction du D-pad', () {
      // Si une action directionnelle apparaissait ici, une touche média
      // déplacerait le focus au lieu d\'agir sur la lecture.
      const directional = <String>{'up', 'down', 'left', 'right', 'ok'};
      for (final action in kMediaKeyActions.values) {
        expect(directional.contains(action), isFalse,
            reason: 'action « $action » réservée à la navigation');
      }
    });

    test('aucune touche n\'est mappée deux fois sur la même action', () {
      final values = kMediaKeyActions.values.toList();
      expect(values.toSet(), hasLength(values.length));
    });
  });
}
