import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/feature/player/video_stats.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:aetherStream/l10n/l10n_ext.dart';

/// §videoStatsTags (lot 12) — L'utilisateur choisit les lignes de l'encart de
/// diagnostic. Deux pièges tenus ici :
///
/// 1. La sélection est persistée par NOM de ligne, jamais par index : une
///    ligne ajoutée au milieu de l'énumération décalerait autrement tout ce
///    que l'utilisateur avait coché (c'est la leçon de `DownloadStatus`, dont
///    l'ordre est figé pour cette raison même).
/// 2. « Tout décoché » est un choix, pas une absence de choix : le remettre à
///    « tout coché » rendrait la case impossible à décocher durablement.
void main() {
  tearDown(L10n.resetForTest);

  group('§videoStatsTags — décodage de la sélection enregistrée', () {
    test('les noms connus redeviennent des lignes', () {
      expect(
        VideoStatsRowsPreference.decodeRows(['decoding', 'hdr', 'stalls']),
        {VideoStatKey.decoding, VideoStatKey.hdr, VideoStatKey.stalls},
      );
    });

    test('un nom inconnu (ligne retirée depuis) est ignoré, pas fatal', () {
      expect(
        VideoStatsRowsPreference.decodeRows(['decoding', 'aPluOuJamais']),
        {VideoStatKey.decoding},
      );
    });

    test('une liste vide reste vide : tout décoché est un CHOIX', () {
      expect(VideoStatsRowsPreference.decodeRows([]), isEmpty);
    });

    test('l\'ordre enregistré n\'a pas d\'importance', () {
      expect(
        VideoStatsRowsPreference.decodeRows(['stalls', 'decoding']),
        VideoStatsRowsPreference.decodeRows(['decoding', 'stalls']),
      );
    });

    test('un nom se décode vers SA ligne, pas vers son voisin', () {
      // Sincérité : c'est l'assertion qui tombe si la persistance repasse par
      // un index. `decoding` est le premier de l'énumération, `startup` le
      // dernier — un décalage de un les échangerait sans bruit.
      expect(
        VideoStatsRowsPreference.decodeRows(['startup']),
        {VideoStatKey.startup},
      );
      expect(
        VideoStatsRowsPreference.decodeRows(
            VideoStatKey.values.map((k) => k.name).toList()),
        VideoStatKey.values.toSet(),
      );
    });

    test('aucun nom de ligne n\'est un numéro', () {
      // Un `name` numérique voudrait dire que quelqu'un a enregistré un index.
      for (final k in VideoStatKey.values) {
        expect(int.tryParse(k.name), isNull, reason: 'ligne « ${k.name} »');
      }
    });
  });

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
