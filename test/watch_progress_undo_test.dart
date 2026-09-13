// R46 (2026-09-13) — **« Annuler » après un oubli de reprise PERDAIT des
// données.**
//
// « Oublier la reprise » efface la progression de TOUTES les versions d'un
// groupe (qualités, comptes — §resumeUnify), mais l'annulation n'en restaurait
// qu'UNE : `versions.first` côté accueil, `snapshot.url` côté fiche. Mesuré sur
// appareil : une série présente sur deux comptes avait deux reprises (28,1 s et
// 186,9 s) ; l'oubli a effacé les deux, « Annuler » n'en a rendu qu'une, et
// l'autre était perdue pour de bon.
//
// ⚠️ **Pourquoi le défaut a survécu si longtemps** : il est INVISIBLE sur un
// titre à une seule version. Tous les tests existants en utilisaient une. Ces
// cas-ci portent donc sur un groupe MULTI-VERSIONS — c'est la seule forme qui
// puisse le tenir.

import 'package:aetherStream/data/services/watch_progress_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const Duration duree = Duration(minutes: 90);

  // Le groupe tel que l'app le manipule : le MÊME titre, deux comptes.
  const String vFhd = 'http://a.tv/movie/user/pass/100.mkv';
  const String v4k = 'http://b.tv/movie/user/pass/200.mkv';
  const String stub = 'http://a.tv/series/user/pass/42';

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    WatchProgressService.resetForTest();
  });

  group('R46 — l\'annulation rend TOUTES les versions', () {
    test('⚠️ deux versions oubliées : les DEUX reviennent, avec leur position '
        'propre', () async {
      await WatchProgressService.saveProgress(
          vFhd, const Duration(seconds: 28), duree);
      await WatchProgressService.saveProgress(
          v4k, const Duration(seconds: 187), duree);

      // Ce que fait la tuile : capturer AVANT, puis tout effacer.
      final avant = WatchProgressService.snapshotFor(<String>[vFhd, v4k]);
      expect(avant, hasLength(2), reason: 'la capture doit voir les DEUX');
      for (final u in <String>[vFhd, v4k]) {
        await WatchProgressService.clearProgress(u);
      }
      expect(WatchProgressService.getProgress(vFhd), isNull);
      expect(WatchProgressService.getProgress(v4k), isNull);

      // « Annuler ».
      await WatchProgressService.restoreAll(avant);

      // ⚠️ C'EST ICI que l'ancien code tombait : il ne rendait que la première.
      expect(WatchProgressService.getProgress(vFhd)?.position,
          const Duration(seconds: 28));
      expect(WatchProgressService.getProgress(v4k)?.position,
          const Duration(seconds: 187),
          reason: 'la seconde version était perdue pour de bon');
    });

    test('la capture ignore les URL sans reprise (aucune entrée fabriquée)',
        () async {
      await WatchProgressService.saveProgress(
          vFhd, const Duration(seconds: 30), duree);

      final avant =
          WatchProgressService.snapshotFor(<String>[vFhd, v4k, 'http://c/x']);

      expect(avant, hasLength(1));
      expect(avant.single.url, vFhd);
    });

    test('la clé de SÉRIE est rendue, et une seule fois pour tout le groupe',
        () async {
      await WatchProgressService.saveProgress(
          vFhd, const Duration(seconds: 28), duree);
      await WatchProgressService.saveProgress(
          v4k, const Duration(seconds: 187), duree);
      final avant = WatchProgressService.snapshotFor(<String>[vFhd, v4k]);
      for (final u in <String>[vFhd, v4k, stub]) {
        await WatchProgressService.clearProgress(u);
      }

      await WatchProgressService.restoreAll(avant, seriesKey: stub);

      expect(WatchProgressService.getProgress(vFhd), isNotNull);
      expect(WatchProgressService.getProgress(v4k), isNotNull);
      // La série revient au hero : c'est l'autre moitié de l'annulation.
      final serie = WatchProgressService.getProgress(stub);
      expect(serie, isNotNull, reason: 'sans elle, la série reste hors du hero');
      // ⚠️ Écrite d'après la PREMIÈRE version restaurée, jamais réécrite par
      // les suivantes (§perfBigList : une seule invalidation de l'accueil).
      expect(serie!.position, avant.first.position);
    });

    test('une annulation sur un groupe vide ne fabrique rien et ne lève pas',
        () async {
      await WatchProgressService.restoreAll(<WatchProgress>[]);
      expect(WatchProgressService.all, isEmpty);
    });

    test('⛔ ce qui n\'aurait jamais pu être écrit ne renaît pas par une '
        'annulation', () async {
      // Règle silencieuse de `saveProgress` : moins de 5 s ne s'écrit pas.
      final bidon = WatchProgress(
        url: vFhd,
        position: const Duration(seconds: 2),
        duration: duree,
        lastWatched: DateTime(2026, 9, 13),
      );

      await WatchProgressService.restoreAll(<WatchProgress>[bidon]);

      expect(WatchProgressService.getProgress(vFhd), isNull,
          reason: 'la restauration passe par les mêmes règles que l\'écriture');
    });
  });
}
