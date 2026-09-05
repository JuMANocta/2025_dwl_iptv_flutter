import 'package:aetherStream/data/services/cast_relay_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/feature/player/cast_relay_policy.dart';

/// §castRelay — Ce qui se décide sans téléphone ni téléviseur : **quand** on
/// propose de convertir le son, et **ce qu'on dit** avant de le faire.
///
/// La conversion fait du téléphone le tuyau du film pendant deux heures. Elle
/// ne doit donc jamais partir toute seule, ni être proposée quand elle ne
/// servirait à rien.
void main() {
  const ac3 = (label: 'Français', codec: 'audio/ac3', channels: 6);
  const dts = (label: 'VO', codec: 'audio/vnd.dts', channels: 8);
  const aac = (label: 'English', codec: 'audio/mp4a-latm', channels: 2);
  const url = 'http://panel.example/movie/u/p/1.mkv';

  group('castRelayPlan — quand proposer', () {
    test('aucune piste lisible par le récepteur : proposé', () {
      final p = castRelayPlan(
        isLocalFile: false,
        isLive: false,
        url: url,
        tracks: const [ac3, dts],
      );
      expect(p.offered, isTrue);
      expect(p.blocker, isNull);
      expect(p.sourceAudio, 'AC3 (Dolby Digital)');
    });

    test('une piste lisible existe : inutile, on la demandera', () {
      final p = castRelayPlan(
        isLocalFile: false,
        isLive: false,
        url: url,
        tracks: const [ac3, aac],
      );
      expect(p.offered, isFalse);
      expect(p.blocker, CastRelayBlocker.notNeeded);
    });

    test('aucune piste connue : rien à convertir', () {
      final p = castRelayPlan(
        isLocalFile: false,
        isLive: false,
        url: url,
        tracks: const [],
      );
      expect(p.offered, isFalse);
      expect(p.blocker, CastRelayBlocker.notNeeded);
    });

    test('chaîne en direct : refusé, et le motif le dit', () {
      final p = castRelayPlan(
        isLocalFile: false,
        isLive: true,
        url: 'http://panel.example/live/u/p/1.m3u8',
        tracks: const [ac3],
      );
      expect(p.offered, isFalse);
      expect(p.blocker, CastRelayBlocker.liveStream);
      expect(castRelayBlockerMessage(p.blocker!), contains('direct'));
    });

    test('fichier local : hors périmètre de cette version', () {
      final p = castRelayPlan(
        isLocalFile: true,
        isLive: false,
        url: '/sdcard/Movies/AetherStream/film.mkv',
        tracks: const [ac3],
      );
      expect(p.offered, isFalse);
      expect(p.blocker, CastRelayBlocker.localFile);
      expect(castRelayBlockerMessage(p.blocker!), isNotNull);
    });

    test('adresse non http : refusée', () {
      final p = castRelayPlan(
        isLocalFile: false,
        isLive: false,
        url: 'rtsp://cam/live',
        tracks: const [ac3],
      );
      expect(p.offered, isFalse);
      expect(p.blocker, CastRelayBlocker.unsupportedSource);
    });

    test('« pas nécessaire » ne produit aucun message : il n\'y a rien à dire',
        () {
      expect(castRelayBlockerMessage(CastRelayBlocker.notNeeded), isNull);
    });
  });

  group('castRelayConsent — expliquer avant de demander', () {
    test('dit ce que ça fait, ce que ça coûte, ce que ça ne fera pas', () {
      final c = castRelayConsent(
        deviceName: 'télé',
        sourceAudio: 'AC3 (Dolby Digital)',
      );
      // Plus de titre : la phrase seule porte tout (décision 2026-09-05).
      expect(c.what, contains('télé'));
      // Une phrase, sans jargon (décision 2026-09-04 : ne pas faire peur).
      expect(c.what, isNot(contains('AC3')));
      expect(c.what, contains('téléphone'));
      // Une seule note, la batterie ; plus de liste des limites.
      expect(c.costs, hasLength(1));
      expect(c.costs.single, contains('batterie'));
      expect(c.limits, isEmpty);
      expect(c.confirmLabel, 'Adapter et diffuser');
      expect(c.cancelLabel, 'Annuler');
    });

    test('sans nom d\'appareil ni codec connu : reste lisible', () {
      final c = castRelayConsent(deviceName: '  ', sourceAudio: null);
      // Repli sans nom : « la télé » (mots de l'utilisateur), lisible.
      expect(c.what, contains('télé'));
      expect(c.what, contains('le son de ce film'.split(' ').first));
      expect(c.what, isNot(contains('null')));
    });
  });

  group('castRelayProgressLabel', () {
    test('sans durée totale : seulement l\'avance', () {
      final s = castRelayProgressLabel(
        ready: const Duration(minutes: 3, seconds: 5),
        total: null,
        playing: true,
      );
      expect(s, contains('03:05'));
      expect(s, isNot(contains('%')));
    });

    test('avec durée : pourcentage, et l\'état de lecture', () {
      final s = castRelayProgressLabel(
        ready: const Duration(minutes: 30),
        total: const Duration(minutes: 120),
        playing: true,
      );
      expect(s, contains('25 %'));
      final p = castRelayProgressLabel(
        ready: const Duration(minutes: 30),
        total: const Duration(minutes: 120),
        playing: false,
      );
      expect(p, contains('en pause'));
    });

    test('film long : l\'heure apparaît', () {
      final s = castRelayProgressLabel(
        ready: const Duration(hours: 1, minutes: 2, seconds: 3),
        total: const Duration(hours: 2),
        playing: true,
      );
      expect(s, contains('1:02:03'));
    });
  });

  group('§castBattery — la note et l\'alerte', () {
    test('branché : on rassure, quel que soit le niveau', () {
      expect(castRelayBatteryNote(percent: 9, charging: true),
          contains('branché'));
      expect(castBatteryWarning(percent: 9, charging: true), isNull);
    });

    // Demande utilisateur (2026-09-05) : « avertir le client que charger
    // c'est mieux » — le conseil est TOUJOURS là hors charge. Ce qui change
    // sous le seuil, c'est le registre : conseil (« si tu peux ») ou alerte
    // (« la diffusion en dépend »).
    test('inconnue : conseil de brancher, pas d\'alerte', () {
      final String n = castRelayBatteryNote();
      expect(n, contains('Branche le téléphone'));
      expect(n, contains('si tu peux'));
      expect(n, isNot(contains('dépend')));
      expect(castBatteryWarning(), isNull);
    });

    test('au seuil (15 %) : le chiffre + le conseil, sans alarme', () {
      final String n = castRelayBatteryNote(percent: 15, charging: false);
      expect(n, contains('15 %'));
      expect(n, contains('si tu peux'));
      expect(n, isNot(contains('dépend')));
      expect(castBatteryWarning(percent: 15, charging: false), isNull);
    });

    test('sous 15 % hors charge : brancher, note ET alerte', () {
      final String n = castRelayBatteryNote(percent: 14, charging: false);
      expect(n, contains('14 %'));
      expect(n, contains('branche'));
      expect(n, contains('dépend'));
      expect(n, isNot(contains('si tu peux')));
      final String? w = castBatteryWarning(percent: 14, charging: false);
      expect(w, isNotNull);
      expect(w, contains('14 %'));
    });

    test('le consentement porte la note batterie réelle', () {
      final c = castRelayConsent(deviceName: 'télé', batteryPercent: 42);
      expect(c.costs.single, contains('42 %'));
    });

    // §castAwake — la note « garde l'appli ouverte » a disparu : le service
    // tient un verrou CPU, l'écran peut s'éteindre. Le consentement doit le
    // dire, et ne plus jamais demander de garder l'écran allumé.
    test('§castAwake — le consentement dit que l\'écran peut s\'éteindre', () {
      final c = castRelayConsent(deviceName: 'télé', batteryPercent: 42);
      expect(c.awake, contains('éteindre l\'écran'));
      expect(c.awake, contains('continue'));
      for (final String line in [c.what, ...c.costs, c.awake]) {
        expect(line, isNot(contains('appli ouverte')));
      }
    });
  });

  group('§castResume — le décalage de conversion', () {
    setUp(CastRelayService.resetForTest);
    tearDown(CastRelayService.resetForTest);

    test('sans relais : une position de film reste elle-même', () {
      expect(CastRelayService.filmPosition(const Duration(minutes: 3)),
          const Duration(minutes: 3));
    });

    test("l'état porte son décalage et le garde à travers copyWith", () {
      const s = CastRelayState(
        url: 'http://x/relay.mp4',
        percent: 0,
        done: false,
        offset: Duration(minutes: 45),
      );
      expect(s.offset, const Duration(minutes: 45));
      // ⚠️ Le décalage ne doit JAMAIS être perdu par une mise à jour de
      // progression : c'est lui qui rend leur sens aux positions.
      expect(s.copyWith(percent: 30).offset, const Duration(minutes: 45));
      expect(s.copyWith(done: true).offset, const Duration(minutes: 45));
      expect(s.copyWith(error: 'bim').offset, const Duration(minutes: 45));
    });
  });
}
