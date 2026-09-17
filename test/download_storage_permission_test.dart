import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/core/utils/storage_file.dart';

/// R14 (D1B-22) — **Un téléchargement doit aboutir SANS la permission
/// « vidéos ».**
///
/// Le défaut payé : `getAppMoviesPath()` demandait `READ_MEDIA_VIDEO` d'entrée
/// de jeu et rendait `null` au moindre refus, ce qui annulait le
/// téléchargement. Or en stockage cloisonné (Android 10+, API 29) une
/// application écrit SES propres fichiers dans `Movies/` sans aucune
/// permission ; « vidéos » ne sert qu'à relire ceux d'une installation
/// précédente (§dlOrphans). Et Google Play refusera cette permission pour un
/// usage comme le nôtre : le dépôt en dépend.
void main() {
  test('🔴 Android 10 et au-delà : aucune permission pour écrire nos fichiers',
      () {
    // 29 = Android 10, la version qui a introduit le stockage cloisonné.
    for (final int sdk in [29, 30, 33, 34, 35, 36]) {
      expect(storagePermissionNeededToWrite(sdk), isFalse,
          reason: 'API $sdk : refuser « vidéos » ne doit plus coûter le '
              'téléchargement, seulement la relecture des fichiers d\'avant '
              'une réinstallation.');
    }
  });

  test('Android 9 et avant : la permission décide vraiment de l\'écriture', () {
    // minSdk 24. Avant le stockage cloisonné, écrire hors du bac à sable
    // exige bien WRITE_EXTERNAL_STORAGE : là, un refus est un vrai mur et
    // abandonner est honnête.
    for (final int sdk in [24, 26, 28]) {
      expect(storagePermissionNeededToWrite(sdk), isTrue,
          reason: 'API $sdk : sans permission, rien ne peut être écrit dans '
              'Movies — prétendre le contraire produirait un échec plus tard, '
              'sans explication.');
    }
  });

  test('la frontière est exactement API 29', () {
    expect(storagePermissionNeededToWrite(28), isTrue);
    expect(storagePermissionNeededToWrite(29), isFalse);
  });
}
