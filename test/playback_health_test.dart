// §stallCount + §playerBuffer — Verrous de la santé de lecture.
//
// Ce que ces tests protègent :
//
//   1. **Les deux refus.** Une session sans compte source (fichier local) et une
//      session trop courte ne doivent RIEN enregistrer. Sans ça, le chiffre
//      censé désigner le mauvais fournisseur serait dilué par des lectures qui
//      ne disent rien de lui — et un compteur qui ment est pire que pas de
//      compteur (leçon §qualityTruth).
//   2. **La mesure comparable.** Un total brut de blocages favorise le compte
//      le moins regardé. C'est `stallsPerHour` qui permet de comparer deux
//      abonnements, et il doit se taire tant que l'échantillon est trop maigre.
//   3. **Le tampon dans les profils.** `bufferSeconds` participe à l'égalité de
//      `PerfConfig` (donc à la détection du preset actif) et se relit clampé.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aetherStream/core/settings/perf_config.dart';
import 'package:aetherStream/data/services/playback_health_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PlaybackHealthService.clear();
  });

  group('Les deux refus', () {
    test('une lecture de fichier local (compte vide) n\'est pas enregistrée',
        () async {
      await PlaybackHealthService.record(
        accountId: '',
        stalls: 5,
        stalled: const Duration(seconds: 30),
        watched: const Duration(minutes: 40),
      );
      expect(PlaybackHealthService.forAccount(''), isNull);
    });

    test('une session de moins de 10 s ne dit rien du fournisseur', () async {
      await PlaybackHealthService.record(
        accountId: 'acc1',
        stalls: 2,
        stalled: const Duration(seconds: 4),
        watched: const Duration(seconds: 9),
      );
      expect(PlaybackHealthService.forAccount('acc1'), isNull,
          reason: 'zapper deux secondes ne doit pas accuser le fournisseur');
    });

    test('à partir de 10 s, on compte', () async {
      await PlaybackHealthService.record(
        accountId: 'acc1',
        stalls: 1,
        stalled: const Duration(seconds: 2),
        watched: const Duration(seconds: 10),
      );
      expect(PlaybackHealthService.forAccount('acc1')?.sessions, 1);
    });
  });

  group('Cumul', () {
    test('deux sessions s\'additionnent, chaque compte reste séparé', () async {
      await PlaybackHealthService.record(
        accountId: 'platinium',
        stalls: 3,
        stalled: const Duration(seconds: 12),
        watched: const Duration(minutes: 30),
        startup: const Duration(milliseconds: 2000),
      );
      await PlaybackHealthService.record(
        accountId: 'platinium',
        stalls: 1,
        stalled: const Duration(seconds: 4),
        watched: const Duration(minutes: 30),
        startup: const Duration(milliseconds: 4000),
      );
      await PlaybackHealthService.record(
        accountId: 'vod',
        stalls: 0,
        stalled: Duration.zero,
        watched: const Duration(minutes: 60),
      );

      final p = PlaybackHealthService.forAccount('platinium')!;
      expect(p.sessions, 2);
      expect(p.stalls, 4);
      expect(p.stalled, const Duration(seconds: 16));
      expect(p.watched, const Duration(hours: 1));
      expect(p.stallsPerHour, closeTo(4.0, 0.001));
      expect(p.averageStartup, const Duration(milliseconds: 3000));

      final v = PlaybackHealthService.forAccount('vod')!;
      expect(v.stalls, 0);
      expect(v.stallsPerHour, 0.0);
    });

    test('le démarrage moyen ignore les sessions qui n\'en ont pas', () async {
      await PlaybackHealthService.record(
        accountId: 'a',
        stalls: 0,
        stalled: Duration.zero,
        watched: const Duration(minutes: 10),
        startup: const Duration(milliseconds: 1000),
      );
      await PlaybackHealthService.record(
        accountId: 'a',
        stalls: 0,
        stalled: Duration.zero,
        watched: const Duration(minutes: 10),
        // pas de startup : la première image n'a jamais été vue
      );
      final h = PlaybackHealthService.forAccount('a')!;
      expect(h.sessions, 2);
      expect(h.averageStartup, const Duration(milliseconds: 1000),
          reason: 'moyenne sur les sessions MESURÉES, pas sur toutes');
    });
  });

  group('La mesure comparable', () {
    test('stallsPerHour se tait sous 3 minutes de lecture', () {
      const h = AccountPlaybackHealth(
          sessions: 1, stalls: 2, watched: Duration(minutes: 2));
      expect(h.stallsPerHour, isNull,
          reason: 'deux blocages sur deux minutes ne permettent pas de '
              'conclure sur un abonnement');
    });

    test('un total brut favoriserait le compte le moins regardé', () {
      const peuVu = AccountPlaybackHealth(
          sessions: 1, stalls: 5, watched: Duration(minutes: 30));
      const beaucoupVu = AccountPlaybackHealth(
          sessions: 1, stalls: 8, watched: Duration(hours: 8));
      // 8 > 5 en brut, mais 1/h < 10/h : c'est le second qui est bon.
      expect(beaucoupVu.stalls, greaterThan(peuVu.stalls));
      expect(beaucoupVu.stallsPerHour, lessThan(peuVu.stallsPerHour!));
    });

    test('le résumé nomme l\'absence de blocage plutôt que « 0 »', () {
      const h = AccountPlaybackHealth(
          sessions: 1, stalls: 0, watched: Duration(hours: 2));
      expect(h.summary, contains('aucun blocage'));
      expect(h.summary, contains('2h00'));
    });
  });

  group('Persistance', () {
    test('un aller-retour disque conserve les totaux', () async {
      await PlaybackHealthService.record(
        accountId: 'acc1',
        stalls: 7,
        stalled: const Duration(seconds: 33),
        watched: const Duration(minutes: 90),
        startup: const Duration(milliseconds: 1800),
      );
      // Simule un redémarrage : on vide la mémoire et on relit.
      final before = PlaybackHealthService.forAccount('acc1')!;
      await PlaybackHealthService.init();
      final after = PlaybackHealthService.forAccount('acc1')!;
      expect(after.stalls, before.stalls);
      expect(after.watched, before.watched);
      expect(after.stalled, before.stalled);
      expect(after.averageStartup, before.averageStartup);
    });
  });

  group('§playerBuffer — le tampon dans les profils', () {
    test('le profil Fire Stick en tient le moins', () {
      expect(PerfConfig.performance.bufferSeconds,
          lessThan(PerfConfig.defaults.bufferSeconds),
          reason: 'le profil visant les box faibles doit immobiliser moins de '
              'mémoire, pas plus');
    });

    test('il participe à l\'égalité — donc à la détection du preset', () {
      final modifie =
          PerfConfig.defaults.copyWith(bufferSeconds: 90);
      expect(modifie == PerfConfig.defaults, isFalse,
          reason: 'toucher au tampon doit basculer la page en « Personnalisé »');
      expect(PerfConfig.defaults.copyWith(bufferSeconds: null) ==
          PerfConfig.defaults, isTrue);
    });

    test('une valeur absurde en cache est ramenée dans les bornes', () {
      expect(PerfConfig.fromJson({'bfs': 9999}).bufferSeconds,
          PerfConfig.maxBufferSeconds);
      expect(PerfConfig.fromJson({'bfs': 0}).bufferSeconds,
          PerfConfig.minBufferSeconds);
      expect(PerfConfig.fromJson(const {}).bufferSeconds,
          PerfConfig.defaults.bufferSeconds,
          reason: 'un cache antérieur à §playerBuffer doit prendre le défaut');
    });

    test('la sérialisation fait l\'aller-retour', () {
      final c = PerfConfig.defaults.copyWith(bufferSeconds: 60);
      expect(PerfConfig.fromJson(c.toJson()).bufferSeconds, 60);
    });
  });
}
