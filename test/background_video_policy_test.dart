import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/feature/player/background_video_policy.dart';

void main() {
  group('§bgAudio — couper la piste vidéo en arrière-plan', () {
    test('téléphone, lecteur seul : on coupe', () {
      expect(
        shouldDropVideoInBackground(isTv: false, inPip: false, casting: false),
        isTrue,
      );
    });

    test('téléviseur : jamais', () {
      expect(
        shouldDropVideoInBackground(isTv: true, inPip: false, casting: false),
        isFalse,
      );
    });

    test('fenêtre PiP visible : jamais (l\'image doit continuer)', () {
      expect(
        shouldDropVideoInBackground(isTv: false, inPip: true, casting: false),
        isFalse,
      );
    });

    test('diffusion Cast en cours : jamais (le lecteur local est déjà en pause)', () {
      expect(
        shouldDropVideoInBackground(isTv: false, inPip: false, casting: true),
        isFalse,
      );
    });
  });
}
