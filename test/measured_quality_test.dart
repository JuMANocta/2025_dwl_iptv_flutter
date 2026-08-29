import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/data/models/quality_scale.dart';
import 'package:aetherStream/data/services/measured_quality_service.dart';

void main() {
  group('§qualityTruth — barème partagé', () {
    test('les seuils sont ceux de l\'encart du lecteur', () {
      // Ce barème vit dans UN seul endroit précisément pour que la fiche et le
      // lecteur ne puissent pas se contredire : c'est tout l'intérêt d'un outil
      // qui confronte deux affirmations.
      expect(QualityScale.labelForHeight(2160), '4K');
      expect(QualityScale.labelForHeight(1600), '4K');
      expect(QualityScale.labelForHeight(1080), 'FHD');
      expect(QualityScale.labelForHeight(720), 'HD');
      expect(QualityScale.labelForHeight(576), 'SD');
    });

    test('CAM n\'a pas de rang : ce n\'est pas une définition', () {
      // §camQuality désigne le TYPE de source. Un rip de salle peut être encodé
      // en 1080p : lui donner un rang produirait un faux « survendu » sur
      // chaque CAM.
      expect(QualityScale.rankOf('CAM'), isNull);
      expect(QualityScale.rankOf('MULTI'), isNull);
      expect(QualityScale.rankOf(null), isNull);
      expect(QualityScale.rankOf('4K'), 3);
    });
  });

  group('§qualityTruth — sérialisation d\'une mesure', () {
    test('aller-retour sans perte', () {
      final at = DateTime.fromMillisecondsSinceEpoch(1756400000 * 1000);
      final source =
          MeasuredQuality(width: 1920, height: 1080, measuredAt: at);
      final back = MeasuredQuality.decode(source.encode());
      expect(back, isNotNull);
      expect(back!.width, 1920);
      expect(back.height, 1080);
      expect(back.measuredAt.millisecondsSinceEpoch,
          at.millisecondsSinceEpoch);
    });

    test('une entrée corrompue est ignorée, pas fatale', () {
      // Le stockage est un simple champ texte : une version antérieure, une
      // troncature ou une écriture partielle ne doit pas empêcher les AUTRES
      // mesures de se recharger.
      expect(MeasuredQuality.decode(''), isNull);
      expect(MeasuredQuality.decode('1920x1080'), isNull);
      expect(MeasuredQuality.decode('1920@123'), isNull);
      expect(MeasuredQuality.decode('axb@123'), isNull);
      expect(MeasuredQuality.decode('1920x0@123'), isNull);
    });
  });

  group('§qualityTruth — verdict d\'une mesure', () {
    MeasuredQuality m(int h) =>
        MeasuredQuality(width: h * 16 ~/ 9, height: h, measuredAt: DateTime(2026));

    test('4K annoncé, 1080p servi → la liste survend', () {
      expect(m(1080).verdictFor('4K'), QualityVerdict.survendu);
    });

    test('annonce tenue', () {
      expect(m(2160).verdictFor('4K'), QualityVerdict.conforme);
    });

    test('annonce dépassée', () {
      expect(m(1080).verdictFor('HD'), QualityVerdict.sousEstime);
    });

    test('CAM : aucun verdict, seule la résolution est affichable', () {
      expect(m(1080).verdictFor('CAM'), QualityVerdict.unknown);
    });
  });
}
