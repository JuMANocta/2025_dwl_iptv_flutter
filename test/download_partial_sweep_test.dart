import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/feature/downloads/logic/partial_sweep.dart';

/// §dlPartSweep — Verrous du ménage des fichiers partiels.
///
/// Ce que ces tests protègent, par ordre d'importance :
///
///   1. **Un partiel VIVANT ne se supprime jamais.** Un `.part` est la seule
///      chose qui rend une reprise possible : le supprimer jette plusieurs
///      gigaoctets déjà téléchargés. Une tâche en échec est reprenable.
///   2. **Le dossier public appartient à l'utilisateur.** On n'y touche que ce
///      que l'app a écrit elle-même — jamais un film.
///   3. **Le repli ne suffixe pas `.part`.** Dans le cache privé, le partiel
///      porte le nom du fichier FINAL : un balayage qui chercherait `*.part`
///      raterait toute cette famille.
void main() {
  final DateTime now = DateTime(2026, 9, 10, 12, 0);
  final DateTime old = now.subtract(const Duration(hours: 3));
  final DateTime justNow = now.subtract(const Duration(seconds: 30));

  PartialFile f(String path, {int bytes = 1024, DateTime? at}) =>
      PartialFile(path: path, bytes: bytes, modified: at ?? old);

  List<String> sweep({
    List<PartialFile> cache = const <PartialFile>[],
    List<PartialFile> public = const <PartialFile>[],
    Set<String> live = const <String>{},
  }) =>
      orphanPartials(
        inPrivateCache: cache,
        inPublicFolder: public,
        liveTempPaths: live,
        now: now,
      ).map((PartialFile p) => p.path).toList();

  group('⚠️ Le garde-fou — un partiel reprenable est INTOUCHABLE', () {
    test('le partiel d\'une tâche connue est épargné', () {
      final res = sweep(
        cache: <PartialFile>[f('/cache/dl_tmp/Film.mkv')],
        live: <String>{'/cache/dl_tmp/Film.mkv'},
      );
      expect(res, isEmpty);
    });

    test('celui d\'une tâche INCONNUE part', () {
      final res = sweep(
        cache: <PartialFile>[f('/cache/dl_tmp/Film.mkv')],
        live: <String>{'/cache/dl_tmp/Autre.mkv'},
      );
      expect(res, <String>['/cache/dl_tmp/Film.mkv']);
    });

    test('un fichier RÉCENT n\'est pas abandonné, seulement jeune', () {
      // Une tâche naît en deux temps : le fichier peut exister avant que la
      // tâche soit inscrite.
      final res = sweep(cache: <PartialFile>[f('/cache/dl_tmp/A.mkv', at: justNow)]);
      expect(res, isEmpty);
    });

    test('le délai est réglable, et il compte depuis la DERNIÈRE écriture', () {
      final res = orphanPartials(
        inPrivateCache: <PartialFile>[f('/cache/dl_tmp/A.mkv', at: justNow)],
        inPublicFolder: const <PartialFile>[],
        liveTempPaths: const <String>{},
        now: now,
        minimumAge: const Duration(seconds: 5),
      );
      expect(res, hasLength(1));
    });
  });

  group('⚠️ Le dossier public appartient à l\'utilisateur', () {
    test('un FILM n\'est jamais touché, même inconnu de toute tâche', () {
      final res = sweep(public: <PartialFile>[
        f('/Movies/AetherStream/Heroes S03 E01.mkv', bytes: 900000000),
      ]);
      expect(res, isEmpty);
    });

    test('notre partiel caché, lui, part', () {
      final res = sweep(public: <PartialFile>[
        f('/Movies/AetherStream/.Heroes S03 E01.aetherpart.mkv'),
      ]);
      expect(res, <String>['/Movies/AetherStream/.Heroes S03 E01.aetherpart.mkv']);
    });

    test('un résidu de sonde d\'écriture part aussi', () {
      final res = sweep(public: <PartialFile>[
        f('/Movies/AetherStream/.aether_probe.mkv.part', bytes: 1),
        f('/Movies/AetherStream/.aether_write_probe', bytes: 1),
      ]);
      expect(res, hasLength(2));
    });

    test('un fichier caché de l\'utilisateur n\'est pas notre affaire', () {
      final res = sweep(public: <PartialFile>[
        f('/Movies/AetherStream/.nomedia'),
        f('/Movies/AetherStream/.trashed-1234-Film.mkv'),
      ]);
      expect(res, isEmpty);
    });

    test('même caché et en .part, un partiel VIVANT est épargné', () {
      const String p = '/Movies/AetherStream/.Film.mkv.part';
      expect(sweep(public: <PartialFile>[f(p)], live: <String>{p}), isEmpty);
    });
  });

  group('⚠️ Le cache privé : tout lui appartient, quel que soit le nom', () {
    test('le repli ne suffixe PAS .part — il garde le nom final', () {
      // C'est le piège : chercher `*.part` raterait toute cette famille.
      final res = sweep(cache: <PartialFile>[f('/cache/dl_tmp/Le rêve américain.mp4')]);
      expect(res, hasLength(1));
    });

    test('les deux dossiers se cumulent dans un seul bilan', () {
      final res = sweep(
        cache: <PartialFile>[f('/cache/dl_tmp/A.mp4')],
        public: <PartialFile>[f('/Movies/AetherStream/.B.mkv.part')],
      );
      expect(res, hasLength(2));
    });
  });

  group('isOwnPartialName — ce que l\'app reconnaît comme sien', () {
    test('les formes réelles', () {
      expect(isOwnPartialName('.Film (2024).mp4.part'), isTrue);
      expect(isOwnPartialName('.aether_probe.mkv.part'), isTrue);
      expect(isOwnPartialName('.aether_write_probe'), isTrue);
    });

    test('ce qui appartient à l\'utilisateur', () {
      expect(isOwnPartialName('Film.mkv'), isFalse);
      expect(isOwnPartialName('Film.mkv.part'), isFalse); // pas caché
      expect(isOwnPartialName('.nomedia'), isFalse);
      expect(isOwnPartialName('.part'), isFalse); // rien devant
    });
  });
}
