import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/feature/player/video_stats.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:aetherStream/l10n/l10n_ext.dart';

/// §engineFeatures — Le débit d'une variante suit la langue de l'interface.
///
/// §tvPlayerPanel (2026-09-21) — Les tests de `VideoStatsRowsPreference`
/// (lignes choisies de l'encart, §videoStatsTags) sont partis avec elle :
/// l'encart affiche désormais toutes ses lignes, un seul interrupteur.
void main() {
  tearDown(L10n.resetForTest);

  group('§engineFeatures — le débit d\'une variante suit la langue', () {
    test('au-dessus du mégabit, une décimale et le séparateur de la langue',
        () {
      L10n.bind(lookupAppLocalizations(const Locale('fr')));
      expect(formatBitrate(4500000), '4,5 Mb/s');
      L10n.bind(lookupAppLocalizations(const Locale('en')));
      expect(formatBitrate(4500000), '4.5 Mb/s');
    });

    test('sous le mégabit, des kilobits entiers', () {
      L10n.bind(lookupAppLocalizations(const Locale('fr')));
      expect(formatBitrate(640000), '640 kb/s');
    });

    test('rien à dire d\'un débit nul, inconnu ou négatif', () {
      expect(formatBitrate(null), isNull);
      expect(formatBitrate(0), isNull);
      expect(formatBitrate(-1), isNull);
    });
  });
}
