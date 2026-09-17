import 'package:aetherStream/data/services/cast_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// R39 / §heroSeriesResume — Un épisode suivi sur le TÉLÉVISEUR doit écrire la
/// progression de la SÉRIE comme le lecteur local, sinon la série n'entre
/// jamais au hero. Le service passe par une seule fonction pure pour ses trois
/// écritures : c'est elle qu'on tient ici.
void main() {
  const tv = CastDevice(
    id: 'tv1',
    name: 'tv1',
    host: '127.0.0.1',
    port: 8009,
    friendlyName: 'Salon',
  );
  const String episodeKey = 'http://panel.test/series/u/p/501.mkv';
  const String seriesKey = 'http://panel.test/series/u/p/42';

  CastState episode({bool live = false, String? series = seriesKey}) =>
      CastState(
        device: tv,
        url: 'http://192.168.1.2:8080/relay.m3u8',
        title: 'Heroes S03E01',
        live: live,
        progressKey: episodeKey,
        seriesProgressKey: series,
        status: const CastSessionStatus(
          playerState: 'PLAYING',
          position: Duration(minutes: 30),
          duration: Duration(minutes: 42),
        ),
      );

  group('R39 — la clé de série suit la diffusion', () {
    test('sauvegarde périodique : clé de l\'épisode ET clé de la série', () {
      final w = CastService.progressWriteFor(episode(), finished: false);
      expect(w, isNotNull);
      expect(w!.key, episodeKey);
      expect(w.position, const Duration(minutes: 30));
      expect(w.duration, const Duration(minutes: 42));
      expect(w.seriesKey, seriesKey);
    });

    test('fin naturelle (IDLE FINISHED) : position = durée, clé de série gardée', () {
      final w = CastService.progressWriteFor(episode(), finished: true);
      expect(w, isNotNull);
      expect(w!.position, w.duration);
      expect(w.seriesKey, seriesKey,
          reason: 'c\'est exactement le cas où le plafond seriesPositionFor '
              'doit s\'appliquer côté WatchProgressService');
    });

    test('un film n\'a pas de clé de série', () {
      final w = CastService.progressWriteFor(episode(series: null), finished: false);
      expect(w, isNotNull);
      expect(w!.seriesKey, isNull);
    });

    test('copyWith garde la clé de série (elle survit à chaque statut reçu)', () {
      final s = episode().copyWith(
        status: const CastSessionStatus(
          playerState: 'PLAYING',
          position: Duration(minutes: 31),
          duration: Duration(minutes: 42),
        ),
      );
      expect(s.seriesProgressKey, seriesKey);
      expect(s.progressKey, episodeKey);
    });

    test('rien à écrire sans durée connue', () {
      final s = CastState(
        device: tv,
        url: 'x',
        title: 'x',
        live: false,
        progressKey: episodeKey,
        seriesProgressKey: seriesKey,
        status: const CastSessionStatus(playerState: 'BUFFERING'),
      );
      expect(CastService.progressWriteFor(s, finished: false), isNull);
      expect(CastService.progressWriteFor(s, finished: true), isNull);
    });
  });
}
