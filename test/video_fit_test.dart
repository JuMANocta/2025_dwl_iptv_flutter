import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/feature/player/video_fit.dart';

void main() {
  group('§videoFit — VideoFitMode', () {
    test('chaque mode est câblé sur le bon BoxFit', () {
      // C'est l'invariante qui porte tout le ticket : « effacer les bandes
      // noires » = cover (rogne), « remplir » = fill (déforme). Les inverser
      // donnerait deux modes qui ont l'air de marcher mais rendent le
      // contraire de ce que leur libellé promet.
      expect(VideoFitMode.original.boxFit, BoxFit.contain);
      expect(VideoFitMode.zoom.boxFit, BoxFit.cover);
      expect(VideoFitMode.stretch.boxFit, BoxFit.fill);
    });

    test('ordre du moins au plus destructif', () {
      // L'ordre de déclaration EST l'ordre du menu et du cycle : on propose
      // d'abord ce qui ne perd rien, puis le rognage, puis la déformation.
      expect(
        VideoFitMode.values,
        [VideoFitMode.original, VideoFitMode.zoom, VideoFitMode.stretch],
      );
    });

    test('next boucle sur les trois modes', () {
      expect(VideoFitMode.original.next, VideoFitMode.zoom);
      expect(VideoFitMode.zoom.next, VideoFitMode.stretch);
      expect(VideoFitMode.stretch.next, VideoFitMode.original);
    });

    test('tout mode a un libellé et une description non vides', () {
      // Le menu NOMME les modes (sur une source déjà plein cadre, les trois
      // rendus sont identiques — sans libellé le bouton paraîtrait cassé).
      for (final mode in VideoFitMode.values) {
        expect(mode.label, isNotEmpty, reason: mode.name);
        expect(mode.description, isNotEmpty, reason: mode.name);
      }
    });

    test('sans préférence chargée, on démarre sur le mode qui ne dénature rien',
        () {
      expect(VideoFitPreference.current, VideoFitMode.original);
    });
  });
}
