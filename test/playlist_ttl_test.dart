import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/services/playlist_service.dart';

/// §secondaryRefresh — Le TTL de 24 h n'était appliqué qu'au compte ACTIF
/// (`getOrDownloadPlaylist`). Les comptes secondaires passaient par
/// `ensureDownloadedForAccount`, dont la seule condition était l'existence
/// physique du fichier : une liste secondaire téléchargée une fois restait
/// figée indéfiniment.
///
/// La décision est désormais isolée dans [PlaylistService.needsDownload], qui
/// se teste sans système de fichiers.
void main() {
  const ttl = PlaylistService.playlistCacheDuration;

  group('needsDownload — comptes secondaires soumis au TTL', () {
    test('fichier absent → télécharger', () {
      expect(
        PlaylistService.needsDownload(
            exists: false, lengthBytes: 0, age: null),
        isTrue,
      );
    });

    test('fichier vide (téléchargement interrompu) → retélécharger', () {
      expect(
        PlaylistService.needsDownload(
            exists: true, lengthBytes: 0, age: Duration.zero),
        isTrue,
      );
    });

    test('cache frais → ne rien faire', () {
      expect(
        PlaylistService.needsDownload(
          exists: true,
          lengthBytes: 4096,
          age: ttl - const Duration(minutes: 1),
        ),
        isFalse,
      );
    });

    test('cache périmé → retélécharger (LE bug corrigé)', () {
      expect(
        PlaylistService.needsDownload(
          exists: true,
          lengthBytes: 4096,
          age: ttl + const Duration(minutes: 1),
        ),
        isTrue,
      );
    });

    test('pile sur le TTL → retélécharger (borne inclusive)', () {
      expect(
        PlaylistService.needsDownload(
            exists: true, lengthBytes: 4096, age: ttl),
        isTrue,
      );
    });

    test('cache vieux de plusieurs mois → retélécharger', () {
      expect(
        PlaylistService.needsDownload(
          exists: true,
          lengthBytes: 4096,
          age: const Duration(days: 180),
        ),
        isTrue,
      );
    });
  });

  group('needsDownload — mode « peupler seulement » (respectTtl: false)', () {
    test('cache périmé mais présent → conservé', () {
      expect(
        PlaylistService.needsDownload(
          exists: true,
          lengthBytes: 4096,
          age: const Duration(days: 30),
          respectTtl: false,
        ),
        isFalse,
      );
    });

    test('fichier absent → télécharger quand même', () {
      expect(
        PlaylistService.needsDownload(
          exists: false,
          lengthBytes: 0,
          age: null,
          respectTtl: false,
        ),
        isTrue,
      );
    });
  });
}
