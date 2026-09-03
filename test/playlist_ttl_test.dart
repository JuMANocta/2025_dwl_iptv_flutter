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

    test('page d\'erreur HTML de 2 Ko renommée en .m3u → retélécharger', () {
      // §cacheKeep — LE cas que `lengthBytes > 0` laissait passer : ce qu'un
      // panel en panne renvoie n'est pas un fichier vide, c'est une page
      // d'erreur de quelques kilo-octets. Elle était acceptée comme un cache
      // sain et faisait autorité pendant 24 h.
      expect(
        PlaylistService.needsDownload(
            exists: true, lengthBytes: 2000, age: Duration.zero),
        isTrue,
        reason: '2000 octets ne peuvent pas être un catalogue IPTV',
      );
    });

    test('pile sur le plancher → accepté (borne inclusive)', () {
      expect(
        PlaylistService.needsDownload(
          exists: true,
          lengthBytes: PlaylistService.minPlaylistBytes,
          age: Duration.zero,
        ),
        isFalse,
      );
    });

    test('un octet sous le plancher → refusé', () {
      expect(
        PlaylistService.needsDownload(
          exists: true,
          lengthBytes: PlaylistService.minPlaylistBytes - 1,
          age: Duration.zero,
        ),
        isTrue,
      );
    });

    test('le plancher est paramétrable', () {
      expect(
        PlaylistService.needsDownload(
          exists: true,
          lengthBytes: 500,
          age: Duration.zero,
          minBytes: 100,
        ),
        isFalse,
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

    test('§cacheKeep — le plancher s\'applique AUSSI ici', () {
      // Ignorer le TTL, oui ; accepter un cache empoisonné, non. « Peupler
      // seulement » ne doit pas vouloir dire « peupler avec n'importe quoi ».
      expect(
        PlaylistService.needsDownload(
          exists: true,
          lengthBytes: 800,
          age: const Duration(minutes: 1),
          respectTtl: false,
        ),
        isTrue,
      );
    });
  });
}
