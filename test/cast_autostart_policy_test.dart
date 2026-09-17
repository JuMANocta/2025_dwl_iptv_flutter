import 'package:aetherStream/feature/player/cast_autostart_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lot 6b / §castLocal — La tuile « Diffuser » d'un téléchargement ne connaît
/// pas les pistes audio du fichier : elle ouvre le lecteur, qui ouvre la
/// feuille Cast une fois les pistes énumérées. Ouvrir trop tôt rendrait la
/// réserve sur le son AVEUGLE — c'est-à-dire exactement le défaut qu'on
/// cherche à éviter (un AC3 parti sans son, §castSend).
void main() {
  bool open({
    bool requested = true,
    bool alreadyOpened = false,
    bool playing = true,
    int audioTrackCount = 2,
    Duration waited = const Duration(milliseconds: 300),
  }) =>
      shouldOpenCastSheetOnStart(
        requested: requested,
        alreadyOpened: alreadyOpened,
        playing: playing,
        audioTrackCount: audioTrackCount,
        waited: waited,
      );

  group('§castLocal — ouverture automatique de la feuille Cast', () {
    test('le cas nominal : ça joue et les pistes sont connues', () {
      expect(open(), isTrue);
    });

    test('sans demande, jamais', () {
      expect(open(requested: false), isFalse);
    });

    test('⛔ jamais AVANT que les pistes soient énumérées', () {
      expect(open(audioTrackCount: 0), isFalse,
          reason: 'la réserve sur le son serait aveugle : tout le détour par '
              'le lecteur ne servirait plus à rien');
    });

    test('⛔ jamais tant que le moteur ne rend pas', () {
      expect(open(playing: false), isFalse);
      expect(
        open(playing: false, waited: const Duration(seconds: 30)),
        isFalse,
        reason: 'le délai de grâce ne remplace pas la lecture : sans moteur, '
            'ni pistes ni codec en cours',
      );
    });

    test('⛔ jamais deux fois pour un même chargement', () {
      expect(open(alreadyOpened: true), isFalse);
    });

    test('un flux qui n\'énumère rien finit par ouvrir quand même', () {
      // Direct, ou moteur qui tarde : la feuille doit rester ATTEIGNABLE.
      // `_checkCastable` se rabat alors sur le codec en cours de décodage.
      expect(open(audioTrackCount: 0, waited: kCastAutostartGrace), isTrue);
      expect(
        open(
          audioTrackCount: 0,
          waited: kCastAutostartGrace - const Duration(milliseconds: 1),
        ),
        isFalse,
      );
    });

    test('sincérité : le délai de grâce n\'ouvre rien si c\'est déjà ouvert', () {
      expect(
        open(
          alreadyOpened: true,
          audioTrackCount: 0,
          waited: const Duration(minutes: 5),
        ),
        isFalse,
      );
    });
  });
}
