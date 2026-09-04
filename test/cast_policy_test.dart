import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/feature/player/cast_policy.dart';

/// §castSend — Tout ce qui se décide SANS téléviseur : quelle adresse envoyer,
/// quel type annoncer, si le flux est diffusable et pourquoi, ce que dit la
/// notification. Le reste (mDNS, session CASTV2, le récepteur qui lit ou non)
/// ne se vérifie qu'avec un Chromecast réel — cf. `.claude/decisions.md`
/// §castSend.
void main() {
  group('castUrlFor — chaîne Xtream en direct → HLS', () {
    test('/live/u/p/id.ts → .m3u8', () {
      expect(
        castUrlFor('http://panel.example:8080/live/user1/pass1/12345.ts'),
        'http://panel.example:8080/live/user1/pass1/12345.m3u8',
      );
    });

    test('URL nue « Ultimate » /u/p/id (sans extension) → .m3u8', () {
      expect(
        castUrlFor('http://panel.example/user1/pass1/12345'),
        'http://panel.example/user1/pass1/12345.m3u8',
      );
    });

    test('déjà en .m3u8 : inchangée', () {
      const u = 'http://panel.example/live/user1/pass1/12345.m3u8';
      expect(castUrlFor(u), u);
    });

    test('film /movie/… .mkv : inchangée (conteneur progressif)', () {
      const u = 'http://panel.example/movie/user1/pass1/777.mkv';
      expect(castUrlFor(u), u);
    });

    test('série /series/… .mp4 : inchangée', () {
      const u = 'http://panel.example/series/user1/pass1/888.mp4';
      expect(castUrlFor(u), u);
    });

    test('timeshift : inchangée', () {
      const u =
          'http://panel.example/timeshift/user1/pass1/120/2026-09-04:20-00/5.ts';
      expect(castUrlFor(u), u);
    });

    test('forme query get.php : inchangée', () {
      const u = 'http://panel.example/get.php?username=u&password=p&type=m3u';
      expect(castUrlFor(u), u);
    });

    test('URL sans identifiants Xtream : inchangée', () {
      const u = 'https://cdn.example/stream/index.ts';
      expect(castUrlFor(u), u);
    });

    test('extension inattendue sous /live/ (.mp4) : on ne devine pas', () {
      const u = 'http://panel.example/live/user1/pass1/12345.mp4';
      expect(castUrlFor(u), u);
    });

    test('chemin de fichier local : inchangé', () {
      const u = '/storage/emulated/0/Movies/AetherStream/film.mkv';
      expect(castUrlFor(u), u);
    });
  });

  group('castContentType', () {
    test('HLS / DASH / conteneurs', () {
      expect(castContentType('http://x/a.m3u8'), 'application/x-mpegURL');
      expect(castContentType('http://x/a.mpd'), 'application/dash+xml');
      expect(castContentType('http://x/a.mp4'), 'video/mp4');
      expect(castContentType('http://x/a.mkv'), 'video/x-matroska');
      expect(castContentType('http://x/a.ts'), 'video/mp2t');
      expect(castContentType('http://x/a.webm'), 'video/webm');
    });

    test('inconnu ou sans extension : video/mp4 (le récepteur sniffe)', () {
      expect(castContentType('http://x/a'), 'video/mp4');
      expect(castContentType('http://x/a.xyz'), 'video/mp4');
    });

    test('la query ne compte pas comme extension', () {
      expect(castContentType('http://x/a.m3u8?token=1.mp4'),
          'application/x-mpegURL');
    });

    test('castNeedsCors : seulement HLS/DASH', () {
      expect(castNeedsCors('http://x/a.m3u8'), isTrue);
      expect(castNeedsCors('http://x/a.mpd'), isTrue);
      expect(castNeedsCors('http://x/a.mp4'), isFalse);
      expect(castNeedsCors('http://x/a.mkv'), isFalse);
    });
  });

  group('castEligibility', () {
    const okProbe = CastProbe(statusCode: 200, corsAllowed: true);

    test('fichier local : jamais, et le motif le dit', () {
      final v = castEligibility(
          isLocalFile: true, url: '/sdcard/x.mkv', probe: okProbe);
      expect(v.castable, isFalse);
      expect(v.reason, contains('fichier téléchargé'));
    });

    test('schéma non http(s) : non', () {
      final v = castEligibility(
          isLocalFile: false, url: 'rtsp://cam/live', probe: okProbe);
      expect(v.castable, isFalse);
    });

    test('sonde absente : non, « réessaie »', () {
      final v = castEligibility(
          isLocalFile: false, url: 'http://x/a.mp4', probe: null);
      expect(v.castable, isFalse);
      expect(v.reason, contains('vérifier'));
    });

    test('TLS refusé : non, motif certificat', () {
      final v = castEligibility(
        isLocalFile: false,
        url: 'https://x/a.mp4',
        probe: const CastProbe(tlsFailed: true),
      );
      expect(v.castable, isFalse);
      expect(v.reason, contains('certificat'));
    });

    test('injoignable : non', () {
      final v = castEligibility(
        isLocalFile: false,
        url: 'http://x/a.mp4',
        probe: const CastProbe(unreachable: true),
      );
      expect(v.castable, isFalse);
      expect(v.reason, contains('ne répond pas'));
    });

    test('401/403 : identification exigée', () {
      for (final code in [401, 403]) {
        final v = castEligibility(
          isLocalFile: false,
          url: 'http://x/a.mp4',
          probe: CastProbe(statusCode: code),
        );
        expect(v.castable, isFalse, reason: '$code');
        expect(v.reason, contains('identification'));
      }
    });

    test('404 sur la forme HLS : le panel ne sert pas ce format', () {
      final v = castEligibility(
        isLocalFile: false,
        url: 'http://x/live/u/p/1.m3u8',
        probe: const CastProbe(statusCode: 404),
      );
      expect(v.castable, isFalse);
      expect(v.reason, contains('HLS'));
    });

    test('500 muet (UA rejeté) : profil IPTV, code cité', () {
      final v = castEligibility(
        isLocalFile: false,
        url: 'http://x/a.mp4',
        probe: const CastProbe(statusCode: 500),
      );
      expect(v.castable, isFalse);
      expect(v.reason, contains('500'));
      expect(v.reason, contains('profil IPTV'));
    });

    test('HLS sans CORS : non, motif navigateur', () {
      final v = castEligibility(
        isLocalFile: false,
        url: 'http://x/live/u/p/1.m3u8',
        probe: const CastProbe(statusCode: 200, corsAllowed: false),
      );
      expect(v.castable, isFalse);
      expect(v.reason, contains('CORS'));
    });

    test('HLS avec CORS : oui', () {
      final v = castEligibility(
        isLocalFile: false,
        url: 'http://x/live/u/p/1.m3u8',
        probe: okProbe,
      );
      expect(v.castable, isTrue);
      expect(v.reason, isNull);
    });

    test('MP4 progressif sans CORS : oui (la balise vidéo s\'en passe)', () {
      final v = castEligibility(
        isLocalFile: false,
        url: 'http://x/movie/u/p/1.mp4',
        probe: const CastProbe(statusCode: 206, corsAllowed: false),
      );
      expect(v.castable, isTrue);
    });

    test('aucun motif ne contient une URL ni un identifiant', () {
      const url = 'http://panel.example/live/secretuser/secretpass/1.m3u8';
      final probes = [
        const CastProbe(tlsFailed: true),
        const CastProbe(unreachable: true),
        const CastProbe(statusCode: 403),
        const CastProbe(statusCode: 404),
        const CastProbe(statusCode: 500),
        const CastProbe(statusCode: 200, corsAllowed: false),
        null,
      ];
      for (final p in probes) {
        final v = castEligibility(isLocalFile: false, url: url, probe: p);
        expect(v.reason, isNot(contains('secretuser')));
        expect(v.reason, isNot(contains('panel.example')));
      }
    });
  });

  group('castNotice', () {
    test('lecture en cours', () {
      final n = castNotice(
        isTv: false,
        granted: true,
        deviceName: 'Salon',
        mediaTitle: 'Dune',
        playing: true,
      );
      expect(n, isNotNull);
      expect(n!.title, 'Dune');
      expect(n.text, 'Diffusion sur Salon');
      expect(n.playing, isTrue);
    });

    test('en pause', () {
      final n = castNotice(
        isTv: false,
        granted: true,
        deviceName: 'Salon',
        mediaTitle: 'Dune',
        playing: false,
      );
      expect(n!.text, 'En pause sur Salon');
    });

    test('TV ou permission refusée : null', () {
      expect(
        castNotice(
            isTv: true,
            granted: true,
            deviceName: 'S',
            mediaTitle: 'D',
            playing: true),
        isNull,
      );
      expect(
        castNotice(
            isTv: false,
            granted: false,
            deviceName: 'S',
            mediaTitle: 'D',
            playing: true),
        isNull,
      );
    });

    test('titres vides : replis lisibles', () {
      final n = castNotice(
        isTv: false,
        granted: true,
        deviceName: '  ',
        mediaTitle: '',
        playing: true,
      );
      expect(n!.title, 'AetherStream');
      expect(n.text, 'Diffusion sur Chromecast');
    });
  });

  group('castAudioWarning — constaté sur Philips Android TV : AC3 = muet', () {
    test('AC3 / E-AC3 / DTS / TrueHD : une réserve, nommée', () {
      expect(castAudioWarning('audio/ac3'), contains('AC3'));
      expect(castAudioWarning('audio/eac3'), contains('E-AC3'));
      expect(castAudioWarning('audio/vnd.dts'), contains('DTS'));
      expect(castAudioWarning('audio/true-hd'), contains('TrueHD'));
      expect(castAudioWarning('AC3'), contains('AC3'));
    });

    test('AAC / MP3 / Opus / inconnu : rien à dire', () {
      expect(castAudioWarning('audio/mp4a-latm'), isNull);
      expect(castAudioWarning('audio/mpeg'), isNull);
      expect(castAudioWarning('audio/opus'), isNull);
      expect(castAudioWarning(null), isNull);
    });

    test('la réserve ne bloque pas : castable reste vrai', () {
      final v = const CastEligibility.ok()
          .withWarning(castAudioWarning('audio/ac3'));
      expect(v.castable, isTrue);
      expect(v.warning, isNotNull);
      final w = const CastEligibility.ok().withWarning(null);
      expect(w.warning, isNull);
    });
  });

  group('castAudioSupport — la table Google, et ce que la Philips a démenti', () {
    test('lus par le récepteur générique', () {
      for (final c in [
        'audio/mp4a-latm',
        'audio/aac',
        'audio/mpeg',
        'audio/opus',
        'audio/vorbis',
        'audio/flac',
        'audio/raw',
      ]) {
        expect(castAudioSupport(c), CastAudioSupport.ok, reason: c);
      }
    });

    test('NON décodés (passthrough seul, ou absents de la doc)', () {
      for (final c in [
        'audio/ac3',
        'audio/eac3',
        'audio/true-hd',
        'audio/vnd.dts',
        'audio/vnd.dts.hd',
      ]) {
        expect(castAudioSupport(c), CastAudioSupport.no, reason: c);
      }
    });

    test('inconnu ou absent : on ne présume rien', () {
      expect(castAudioSupport(null), CastAudioSupport.unknown);
      expect(castAudioSupport('audio/exotique'), CastAudioSupport.unknown);
      expect(castAudioSupport(''), CastAudioSupport.unknown);
    });

    test('castAudioCodecName nomme, ou rend null', () {
      expect(castAudioCodecName('audio/ac3'), 'AC3 (Dolby Digital)');
      expect(castAudioCodecName('AUDIO/MP4A-LATM'), 'AAC');
      expect(castAudioCodecName('audio/zzz'), isNull);
      expect(castAudioCodecName(null), isNull);
    });
  });

  group('castAudioTrackLabel', () {
    test('langue · codec · canaux', () {
      expect(
        castAudioTrackLabel((label: 'Français', codec: 'audio/ac3', channels: 6)),
        'Français · AC3 (Dolby Digital) · 5.1',
      );
      expect(
        castAudioTrackLabel((label: 'English', codec: 'audio/aac', channels: 2)),
        'English · AAC · stéréo',
      );
    });

    test('sans rien de connu : jamais vide', () {
      expect(castAudioTrackLabel((label: '', codec: null, channels: null)),
          'Piste audio');
    });
  });

  group('castAudioWarningForTracks', () {
    const fr = (label: 'Français', codec: 'audio/ac3', channels: 6);
    const en = (label: 'English', codec: 'audio/mp4a-latm', channels: 2);
    const dts = (label: 'VO', codec: 'audio/vnd.dts', channels: 8);

    test('aucune piste connue comme problématique : rien à dire', () {
      expect(castAudioWarningForTracks([en]), isNull);
      expect(castAudioWarningForTracks([]), isNull);
      expect(
        castAudioWarningForTracks([(label: 'x', codec: null, channels: null)]),
        isNull,
      );
    });

    test('une seule piste, AC3 : image sans son, dit clairement', () {
      final w = castAudioWarningForTracks([fr]);
      expect(w, contains('AC3'));
      expect(w, contains('image sans son'));
    });

    test('plusieurs pistes, toutes indécodables : les nomme et propose une autre version', () {
      final w = castAudioWarningForTracks([fr, dts]);
      expect(w, contains('AC3'));
      expect(w, contains('DTS'));
      expect(w, contains('AAC'));
    });

    test('une piste lisible parmi les autres : on annonce laquelle sera demandée', () {
      final w = castAudioWarningForTracks([fr, en]);
      expect(w, contains('English'));
      expect(w, contains('AAC'));
      expect(w, isNot(contains('image sans son')));
    });

    test('castPreferredAudioIndex désigne la première piste lisible', () {
      expect(castPreferredAudioIndex([fr, en]), 1);
      expect(castPreferredAudioIndex([en, fr]), 0);
      expect(castPreferredAudioIndex([fr, dts]), isNull);
      expect(castPreferredAudioIndex([]), isNull);
    });

    test('aucun message ne contient une URL ni un identifiant', () {
      for (final w in [
        castAudioWarningForTracks([fr]),
        castAudioWarningForTracks([fr, dts]),
        castAudioWarningForTracks([fr, en]),
      ]) {
        expect(w, isNot(contains('http')));
      }
    });
  });

  group('castReceiverTracksSummary — ce que le RÉCEPTEUR annonce', () {
    test('rien annoncé : le dit, car c\'est le cas le plus fréquent', () {
      expect(castReceiverTracksSummary([]), 'aucune piste annoncée');
    });

    test('des pistes, mais aucune audio', () {
      expect(
        castReceiverTracksSummary([
          (type: 'TEXT', language: 'fr', codec: 'text/vtt'),
        ]),
        contains('aucune audio'),
      );
    });

    test('pistes audio : langue + codec nommé', () {
      final s = castReceiverTracksSummary([
        (type: 'AUDIO', language: 'fr', codec: 'audio/ac3'),
        (type: 'AUDIO', language: 'en', codec: 'audio/mp4a-latm'),
        (type: 'VIDEO', language: null, codec: 'video/avc'),
      ]);
      expect(s, contains('2 audio'));
      expect(s, contains('fr AC3'));
      expect(s, contains('en AAC'));
      expect(s, isNot(contains('video')));
    });
  });

  group('castIdleMessage', () {
    test('vocabulaire du récepteur → français, ou rien', () {
      expect(castIdleMessage('FINISHED'), contains('terminée'));
      expect(castIdleMessage('ERROR'), contains('pas pu lire'));
      expect(castIdleMessage('INTERRUPTED'), contains('interrompue'));
      expect(castIdleMessage('CANCELLED'), isNull);
      expect(castIdleMessage(null), isNull);
    });
  });
}
