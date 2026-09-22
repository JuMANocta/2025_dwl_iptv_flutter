import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/models/download_task.dart';
import 'package:aetherStream/feature/player/launch_playback.dart';

/// R23 — « Déjà en lecture sur cette liste ».
///
/// Le piège que ces tests verrouillent : un téléchargement lancé par
/// l'utilisateur occupe une connexion du panel. Sans le compter comme NÔTRE,
/// l'app accuserait « un autre écran » alors que l'écran, c'est le sien — et
/// le geste utile (mettre le transfert en pause) resterait invisible.
void main() {
  group('alreadyStreamingVerdict', () {
    test('une place libre : rien à dire', () {
      expect(alreadyStreamingVerdict(active: 1, max: 2, own: 0),
          StreamingSlotVerdict.free);
    });

    test('🔴 limite inconnue (panel muet) : on ne devine JAMAIS un obstacle',
        () {
      expect(alreadyStreamingVerdict(active: 9, max: 0, own: 0),
          StreamingSlotVerdict.free);
      expect(alreadyStreamingVerdict(active: 9, max: -1, own: 0),
          StreamingSlotVerdict.free);
    });

    test('aucune connexion active : rien à dire', () {
      expect(alreadyStreamingVerdict(active: 0, max: 1, own: 0),
          StreamingSlotVerdict.free);
    });

    test('saturé par quelqu\'un d\'autre : on avertit', () {
      expect(alreadyStreamingVerdict(active: 1, max: 1, own: 0),
          StreamingSlotVerdict.busyElsewhere);
      expect(alreadyStreamingVerdict(active: 3, max: 2, own: 0),
          StreamingSlotVerdict.busyElsewhere);
    });

    test('🔴 saturé par NOS transferts : le message doit être le nôtre', () {
      expect(alreadyStreamingVerdict(active: 1, max: 1, own: 1),
          StreamingSlotVerdict.busyOurselves);
      expect(alreadyStreamingVerdict(active: 2, max: 2, own: 2),
          StreamingSlotVerdict.busyOurselves);
    });

    test('un des nôtres ET un autre écran : c\'est l\'autre écran qui prime',
        () {
      expect(alreadyStreamingVerdict(active: 2, max: 2, own: 1),
          StreamingSlotVerdict.busyElsewhere);
    });

    test('un `own` aberrant (plus que d\'actives) ne renverse pas le verdict',
        () {
      expect(alreadyStreamingVerdict(active: 1, max: 1, own: 5),
          StreamingSlotVerdict.busyOurselves);
      expect(alreadyStreamingVerdict(active: 1, max: 1, own: -3),
          StreamingSlotVerdict.busyElsewhere);
    });
  });

  group('nos propres lecteurs', () {
    setUp(resetOpenPlayersForTest);

    test('aucun lecteur ouvert au départ', () {
      expect(openPlayersOn('compte-1'), 0);
    });

    test(
        '🔴 un lecteur À NOUS ne doit pas se faire passer pour un autre écran',
        () {
      // Ce que `launchPlayback` fait autour du `push` : un lecteur ouvert en
      // PiP sur ce compte, puis on lance un second titre.
      expect(
        alreadyStreamingVerdict(active: 1, max: 1, own: 0),
        StreamingSlotVerdict.busyElsewhere,
        reason: 'sans le compteur, c\'est ce que l\'app disait',
      );
      expect(
        alreadyStreamingVerdict(active: 1, max: 1, own: 1),
        StreamingSlotVerdict.busyOurselves,
      );
    });
  });

  group('hostOfUrl', () {
    test('port explicite ou non, casse ignorée', () {
      expect(hostOfUrl('http://Panel.TV:8080/movie/u/p/1.mkv'),
          'panel.tv:8080');
      expect(hostOfUrl('http://panel.tv/movie/u/p/1.mkv'), 'panel.tv');
    });

    test('une URL illisible ne rapproche rien de rien', () {
      expect(hostOfUrl(''), '');
      expect(hostOfUrl('   '), '');
      expect(hostOfUrl('pas une url'), '');
    });
  });

  group('ownTransfersOn', () {
    DownloadTask t(String id, String url, DownloadStatus s) => DownloadTask(
          id: id,
          url: url,
          displayName: 'x',
          finalPath: '/m/$id.mkv',
          tempPath: '',
          createdAt: DateTime(2026, 9, 16),
          status: s,
        );

    test('🔴 seul un transfert EN COURS tient une connexion', () {
      final tasks = <DownloadTask>[
        for (final s in DownloadStatus.values)
          t(s.name, 'http://panel.tv/movie/u/p/${s.index}.mkv', s),
      ];
      expect(ownTransfersOn('panel.tv', tasks: tasks), 1);
    });

    test('un transfert sur un AUTRE abonnement ne compte pas', () {
      final tasks = [
        t('a', 'http://autre.tv/movie/u/p/1.mkv', DownloadStatus.downloading),
      ];
      expect(ownTransfersOn('panel.tv', tasks: tasks), 0);
      expect(ownTransfersOn('autre.tv', tasks: tasks), 1);
    });

    test('hôte inconnu : on ne compte rien plutôt que n\'importe quoi', () {
      final tasks = [
        t('a', 'http://panel.tv/movie/u/p/1.mkv', DownloadStatus.downloading),
      ];
      expect(ownTransfersOn('', tasks: tasks), 0);
    });
  });

  // §busyRelease (2026-09-21) — « si je sors d'une vidéo et que je reprends,
  // il me dit que cet abonnement est occupé » : le panel compte encore, 30 à
  // 60 s, la connexion que nous venons de fermer.
  group('§busyRelease — connexion que nous venons de fermer', () {
    setUp(resetOpenPlayersForTest);

    test('1/1 expliqué par notre lecteur fermé : on lance sans un mot', () {
      expect(
          alreadyStreamingVerdict(active: 1, max: 1, own: 0, releasing: 1),
          StreamingSlotVerdict.free);
    });

    test('un VRAI autre écran en plus reste signalé', () {
      expect(
          alreadyStreamingVerdict(active: 2, max: 2, own: 0, releasing: 1),
          StreamingSlotVerdict.busyElsewhere);
    });

    test('nos transferts gardent leur message à eux', () {
      expect(
          alreadyStreamingVerdict(active: 1, max: 1, own: 1, releasing: 1),
          StreamingSlotVerdict.busyOurselves);
    });

    test('une fermeture compte 6 min (panel mesuré : ~5 min 30), puis plus', () {
      final DateTime t0 = DateTime(2026, 9, 21, 20);
      notePlayerClosed('acc', at: t0);
      // Le cas mesuré : le panel disait encore 1/1 à 5 min 06.
      expect(releasingPlayersOn('acc', now: t0.add(const Duration(seconds: 306))), 1);
      expect(releasingPlayersOn('acc', now: t0.add(const Duration(seconds: 359))), 1);
      expect(releasingPlayersOn('acc', now: t0.add(const Duration(minutes: 6))), 0);
    });

    test('par abonnement : fermer sur A ne libère rien sur B', () {
      notePlayerClosed('A');
      expect(releasingPlayersOn('A'), 1);
      expect(releasingPlayersOn('B'), 0);
    });

    test("sans compte connu, rien n'est noté", () {
      notePlayerClosed('');
      expect(releasingPlayersOn(''), 0);
    });
  });
}
