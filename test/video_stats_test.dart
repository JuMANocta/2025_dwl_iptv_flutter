import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/data/models/quality_scale.dart';
import 'package:aetherStream/feature/player/video_stats.dart';

void main() {
  group('§videoStats — décodage matériel ou logiciel', () {
    test('mpv répond littéralement « no » quand il retombe en logiciel', () {
      // C'est LE piège du ticket : un simple test de nullité verrait une
      // chaîne non vide et conclurait « matériel » — soit exactement
      // l'inverse de ce qu'on cherche à détecter pour §video4k.
      expect(
        const VideoStatsSnapshot(hwdec: 'no').hardwareDecoding,
        isFalse,
      );
      expect(
        const VideoStatsSnapshot(hwdec: 'No').hardwareDecoding,
        isFalse,
        reason: 'la casse ne doit pas changer le verdict',
      );
    });

    test('absence de valeur = pas de preuve de décodage matériel', () {
      expect(const VideoStatsSnapshot().hardwareDecoding, isFalse);
      expect(const VideoStatsSnapshot(hwdec: '').hardwareDecoding, isFalse);
    });

    test('un décodeur nommé = matériel', () {
      expect(
        const VideoStatsSnapshot(hwdec: 'mediacodec').hardwareDecoding,
        isTrue,
      );
    });
  });

  group('§videoStats — fluidité', () {
    test('décrochage signalé quand le rendu tombe sous 90 % de la cible', () {
      const s = VideoStatsSnapshot(containerFps: 25.0, renderedFps: 18.0);
      expect(s.isDroppingRate, isTrue);
    });

    test('les micro-oscillations ne déclenchent pas d\'alerte', () {
      // `estimated-vf-fps` est une moyenne glissante : sans marge, l'encart
      // crierait au loup en permanence sur une lecture parfaitement fluide.
      const s = VideoStatsSnapshot(containerFps: 25.0, renderedFps: 24.6);
      expect(s.isDroppingRate, isFalse);
    });

    test('sans cible connue, aucun verdict', () {
      expect(
        const VideoStatsSnapshot(renderedFps: 12.0).isDroppingRate,
        isFalse,
      );
      expect(
        const VideoStatsSnapshot(containerFps: 0.0, renderedFps: 0.0)
            .isDroppingRate,
        isFalse,
      );
    });

    test('pertes détectées côté affichage OU côté décodeur', () {
      expect(const VideoStatsSnapshot(droppedFrames: 3).hasDroppedFrames,
          isTrue);
      expect(
          const VideoStatsSnapshot(decoderDroppedFrames: 2).hasDroppedFrames,
          isTrue);
      expect(
          const VideoStatsSnapshot(droppedFrames: 0, decoderDroppedFrames: 0)
              .hasDroppedFrames,
          isFalse);
    });
  });

  group('§videoStats — image', () {
    test('pixels non carrés = source anamorphique, pas un downscale', () {
      expect(const VideoStatsSnapshot(pixelAspectRatio: 1.33).isAnamorphic,
          isTrue);
      expect(
          const VideoStatsSnapshot(pixelAspectRatio: 1.0).isAnamorphic, isFalse);
      expect(const VideoStatsSnapshot().isAnamorphic, isFalse);
    });

    test('définition déduite de la hauteur décodée', () {
      String? def(int h) => VideoStatsSnapshot(height: h).definitionLabel;
      expect(def(2160), '4K');
      expect(def(1080), 'FHD');
      expect(def(720), 'HD');
      expect(def(480), 'SD');
      expect(const VideoStatsSnapshot().definitionLabel, isNull);
    });

    test('résolution nulle tant que les deux dimensions ne sont pas connues',
        () {
      expect(const VideoStatsSnapshot(width: 1920).resolutionLabel, isNull);
      expect(const VideoStatsSnapshot(width: 1920, height: 1080)
          .resolutionLabel, '1920×1080');
    });
  });

  group('§videoStats — journal §tvLogs', () {
    test('la signature dit tout de suite si le décodage est logiciel', () {
      const s = VideoStatsSnapshot(
        hwdec: 'no',
        codec: 'hevc',
        width: 3840,
        height: 2160,
        containerFps: 23.976,
      );
      expect(s.diagnosticSignature, contains('hw=NON (logiciel)'));
      expect(s.diagnosticSignature, contains('res=3840×2160'));
      expect(s.diagnosticSignature, contains('codec=hevc'));
    });

    test('elle ignore débit et compteurs de pertes', () {
      // Ils changent à chaque seconde : les inclure noierait le journal sous
      // une ligne par tic, alors qu'on ne veut écrire que sur changement réel.
      const a = VideoStatsSnapshot(
        hwdec: 'mediacodec',
        codec: 'h264',
        width: 1920,
        height: 1080,
        containerFps: 25.0,
        videoBitrate: 4000000,
        droppedFrames: 0,
      );
      const b = VideoStatsSnapshot(
        hwdec: 'mediacodec',
        codec: 'h264',
        width: 1920,
        height: 1080,
        containerFps: 25.0,
        videoBitrate: 9500000,
        droppedFrames: 42,
      );
      expect(a.diagnosticSignature, b.diagnosticSignature);
    });
  });

  group('§qualityTruth — annoncé contre réel', () {
    VideoStatsSnapshot decoded(int height) =>
        VideoStatsSnapshot(width: height * 16 ~/ 9, height: height);

    test('la liste survend : 4K annonce, 1080p servi', () {
      // Le cas qui justifie tout le dispositif.
      expect(decoded(1080).verdictFor('4K'), QualityVerdict.survendu);
      expect(decoded(576).verdictFor('FHD'), QualityVerdict.survendu);
    });

    test('la liste dit vrai', () {
      expect(decoded(2160).verdictFor('4K'), QualityVerdict.conforme);
      expect(decoded(1080).verdictFor('FHD'), QualityVerdict.conforme);
      expect(decoded(720).verdictFor('HD'), QualityVerdict.conforme);
    });

    test('la liste sous-estime : annoncé HD, servi en FHD', () {
      // Pas un mensonge qui lèse : signalé, mais sans alarme.
      expect(decoded(1080).verdictFor('HD'), QualityVerdict.sousEstime);
    });

    test('CAM ne se confronte PAS à une résolution', () {
      // §camQuality : « CAM » dit le TYPE de source, pas la définition — un rip
      // de salle peut être encodé en 1080p. Le comparer produirait un faux
      // « survendu » sur chaque CAM, et l'outil perdrait sa crédibilité sur les
      // vrais cas.
      expect(decoded(1080).verdictFor('CAM'), QualityVerdict.unknown);
      expect(decoded(480).verdictFor('CAM'), QualityVerdict.unknown);
    });

    test('sans annonce ou sans résolution, aucun verdict', () {
      expect(decoded(1080).verdictFor(null), QualityVerdict.unknown);
      expect(decoded(1080).verdictFor(''), QualityVerdict.unknown);
      expect(const VideoStatsSnapshot().verdictFor('4K'),
          QualityVerdict.unknown);
    });

    test('la casse et les espaces de l\'annonce sont tolérés', () {
      // La qualité vient du parsing des titres : elle arrive telle quelle.
      expect(decoded(2160).verdictFor(' 4k '), QualityVerdict.conforme);
      expect(decoded(1080).verdictFor('fhd'), QualityVerdict.conforme);
    });
  });
}
