// §castLocal (2026-09-06) — Le téléphone sert un fichier téléchargé au
// téléviseur. Ce qui se teste sans appareil : le découpage `Range`, le type
// MIME, la route, et un VRAI serveur HTTP sur un fichier temporaire — le
// récepteur Chromecast fait exactement ces requêtes-là.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/core/utils/lan_address.dart';
import 'package:aetherStream/data/services/cast_file_server.dart';
import 'package:aetherStream/feature/player/cast_policy.dart';
import 'package:aetherStream/feature/player/cast_relay_policy.dart';

void main() {
  group('parseRange — bornes inclusives, bornées au fichier', () {
    test('bytes=0-99 sur 1000 → 0..99, 100 octets', () {
      final r = CastFileServer.parseRange('bytes=0-99', 1000)!;
      expect((r.start, r.end, r.length), (0, 99, 100));
    });

    test('bytes=500- → jusqu à la fin', () {
      final r = CastFileServer.parseRange('bytes=500-', 1000)!;
      expect((r.start, r.end), (500, 999));
    });

    test('bytes=-100 → les 100 derniers', () {
      final r = CastFileServer.parseRange('bytes=-100', 1000)!;
      expect((r.start, r.end), (900, 999));
    });

    test('une fin au-delà du fichier est rognée, pas refusée', () {
      final r = CastFileServer.parseRange('bytes=900-5000', 1000)!;
      expect((r.start, r.end), (900, 999));
    });

    test('un début au-delà du fichier → invalide (416)', () {
      expect(CastFileServer.parseRange('bytes=1000-', 1000)!.valid, isFalse);
      expect(CastFileServer.parseRange('bytes=50-10', 1000)!.valid, isFalse);
    });

    test('sans en-tête → null (réponse complète)', () {
      expect(CastFileServer.parseRange(null, 1000), isNull);
      expect(CastFileServer.parseRange('items=0-1', 1000), isNull);
    });
  });

  group('MIME et route — le récepteur choisit son lecteur à l extension', () {
    test('mkv, mp4, ts', () {
      expect(CastFileServer.contentTypeFor('/a/b/film.mkv').toString(),
          'video/x-matroska');
      expect(CastFileServer.contentTypeFor('/a/b/film.MP4').toString(),
          'video/mp4');
      expect(CastFileServer.contentTypeFor('/a/b/ch.ts').toString(),
          'video/mp2t');
    });

    test('la route garde l extension et le jeton, jamais le chemin réel', () {
      expect(
          CastFileServer.routeFor(
              '/storage/emulated/0/Movies/AetherStream/Un film (2024).mkv', 'ab12'),
          '/local/ab12/media.mkv');
      expect(CastFileServer.routeFor('C:\\\\x\\\\film.mp4', 'ab12'),
          '/local/ab12/media.mp4');
      expect(CastFileServer.routeFor('/x/sansext', 'ab12'), '/local/ab12/media.mp4');
    });
  });

  group('castEligibility — le fichier local n est plus refusé', () {
    test('une adresse LAN servie + sonde OK → diffusable', () {
      final v = castEligibility(
        isLocalFile: true,
        url: 'http://192.168.1.10:41234/local/media.mkv',
        probe: const CastProbe(statusCode: 206, corsAllowed: true),
      );
      expect(v.castable, isTrue);
    });

    test('⚠️ sans adresse LAN (données mobiles) → refus AVANT d envoyer', () {
      final v = castEligibility(isLocalFile: true, url: '', probe: null);
      expect(v.castable, isFalse);
      expect(v.reason, contains('Wi-Fi'));
    });

    test('la conversion est proposée aussi pour un fichier local', () {
      final plan = castRelayPlan(
        isLocalFile: true,
        isLive: false,
        url: '/storage/emulated/0/Movies/AetherStream/film.mkv',
        tracks: const [(label: 'FR', codec: 'ac3', channels: 6)],
      );
      expect(plan.blocker, isNot(CastRelayBlocker.localFile));
    });
  });

  group('serveur HTTP réel sur un fichier temporaire', () {
    late Directory dir;
    late File file;
    late HttpServer server;
    final List<int> bytes = List<int>.generate(10000, (i) => i % 251);

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('castlocal');
      file = File('${dir.path}/media.mp4');
      await file.writeAsBytes(bytes);
      // On ne peut pas passer par `CastFileServer.start` (il cherche une
      // adresse LAN et écoute `CastService`) : on rejoue son `_handle` via
      // l'API publique de test.
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) => CastFileServer.serveForTest(req, file.path));
    });

    tearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });

    Future<HttpClientResponse> get(String path, {String? range}) async {
      final client = HttpClient();
      final req = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}$path'));
      if (range != null) req.headers.set('range', range);
      return req.close();
    }

    test('sans Range : 200, Content-Length total, Accept-Ranges', () async {
      final r = await get('/local/media.mp4');
      expect(r.statusCode, 200);
      expect(r.headers.contentLength, bytes.length);
      expect(r.headers.value('accept-ranges'), 'bytes');
      expect(r.headers.contentType.toString(), 'video/mp4');
      final body = await r.fold<List<int>>([], (a, b) => a..addAll(b));
      expect(body.length, bytes.length);
    });

    test('Range 1000-1999 : 206 + Content-Range + les bons octets', () async {
      final r = await get('/local/media.mp4', range: 'bytes=1000-1999');
      expect(r.statusCode, 206);
      expect(r.headers.value('content-range'), 'bytes 1000-1999/10000');
      expect(r.headers.contentLength, 1000);
      final body = await r.fold<List<int>>([], (a, b) => a..addAll(b));
      expect(body, bytes.sublist(1000, 2000));
    });

    test('Range hors fichier : 416', () async {
      final r = await get('/local/media.mp4', range: 'bytes=20000-');
      expect(r.statusCode, 416);
      await r.drain<void>();
    });

    test('une autre route : 404', () async {
      final r = await get('/relay.mp4');
      expect(r.statusCode, 404);
      await r.drain<void>();
    });
  });

  // Revue 2026-09-11, D2A-07 — `_serve` n'attrapait rien.
  group('robustesse du service (D2A-07)', () {
    late Directory dir;
    late HttpServer server;
    late String served;
    final List<Object> unhandled = <Object>[];

    setUp(() async {
      unhandled.clear();
      dir = await Directory.systemTemp.createTemp('castlocal_rob');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      // Une erreur du Future rendu par le gestionnaire est NON GÉRÉE : elle
      // remonte à la zone où l'écoute a été posée — on la capte ici.
      runZonedGuarded(() {
        server.listen((req) => CastFileServer.serveForTest(req, served));
      }, (Object e, StackTrace _) => unhandled.add(e));
    });

    tearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });

    Future<HttpClientResponse> send(String method, String path) async {
      final client = HttpClient();
      final req = await client.openUrl(
          method, Uri.parse('http://127.0.0.1:${server.port}$path'));
      return req.close();
    }

    test('⚠️ fichier disparu : réponse d erreur FERMÉE, pas un client pendu', () async {
      served = '${dir.path}/supprime.mp4'; // n'existe pas
      final r = await send('GET', '/local/x/media.mp4')
          .timeout(const Duration(seconds: 5));
      expect(r.statusCode, 404);
      await r.drain<void>().timeout(const Duration(seconds: 5));
      expect(unhandled, isEmpty);
    });

    test('méthode autre que GET/HEAD/OPTIONS : 405', () async {
      final f = File('${dir.path}/m.mp4')..writeAsBytesSync(List<int>.filled(10, 1));
      served = f.path;
      final r = await send('POST', '/local/x/media.mp4');
      expect(r.statusCode, 405);
      await r.drain<void>();
    });

    test('client qui coupe en pleine réponse : aucune erreur non gérée', () async {
      final f = File('${dir.path}/gros.mp4')
        ..writeAsBytesSync(List<int>.filled(8 * 1024 * 1024, 7));
      served = f.path;
      final client = HttpClient();
      final req = await client
          .getUrl(Uri.parse('http://127.0.0.1:${server.port}/local/x/media.mp4'));
      final r = await req.close();
      final sub = r.listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      client.close(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(unhandled, isEmpty);
    });
  });

  // Revue 2026-09-11, D2A-12 / D2A-02 / D2A-03 — le vrai `start()`, sur la
  // boucle locale.
  group('start() — jeton par fichier, adresse choisie, arrêt sans diffusion', () {
    late Directory dir;
    late File a;
    late File b;
    final List<int> bytesA = List<int>.generate(3000, (i) => i % 7);
    final List<int> bytesB = List<int>.generate(4000, (i) => 200 - i % 11);

    setUp(() async {
      CastFileServer.lanAddress = () async => '127.0.0.1';
      dir = await Directory.systemTemp.createTemp('castlocal_start');
      a = File('${dir.path}/Heat.mp4')..writeAsBytesSync(bytesA);
      b = File('${dir.path}/Ronin.mp4')..writeAsBytesSync(bytesB);
    });

    tearDown(() async {
      await CastFileServer.stop();
      CastFileServer.lanAddress = lanIpv4;
      CastFileServer.idleTimeout = const Duration(seconds: 60);
      await dir.delete(recursive: true);
    });

    Future<({int status, List<int> body})> fetch(String url) async {
      final client = HttpClient();
      final r = await (await client.getUrl(Uri.parse(url))).close();
      final body = await r.fold<List<int>>([], (acc, c) => acc..addAll(c));
      client.close();
      return (status: r.statusCode, body: body);
    }

    test('⚠️ deux fichiers de MÊME extension → deux URL, chacune sert SES octets', () async {
      final String? ua = await CastFileServer.start(a.path);
      final String? ub = await CastFileServer.start(b.path);
      expect(ua, isNotNull);
      expect(ub, isNotNull);
      expect(ua, isNot(ub));
      expect((await fetch(ua!)).body, bytesA);
      expect((await fetch(ub!)).body, bytesB);
      // Idempotent : le même fichier garde la même URL.
      expect(await CastFileServer.start(a.path), ua);
      expect(CastFileServer.urlFor(a.path), ua);
    });

    test('sans jeton, ou avec un faux, → 404', () async {
      final String? ua = await CastFileServer.start(a.path);
      final int port = Uri.parse(ua!).port;
      expect((await fetch('http://127.0.0.1:$port/local/media.mp4')).status, 404);
      expect(
          (await fetch('http://127.0.0.1:$port/local/00ff00ff/media.mp4')).status,
          404);
    });

    test('lié à l adresse choisie, pas à 0.0.0.0', () async {
      await CastFileServer.start(a.path);
      expect(CastFileServer.boundAddress?.address, '127.0.0.1');
    });

    test('⚠️ sonde sans diffusion : le serveur se ferme seul', () async {
      CastFileServer.idleTimeout = const Duration(milliseconds: 150);
      expect(await CastFileServer.start(a.path), isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(CastFileServer.url, isNull);
      expect(CastFileServer.urlFor(a.path), isNull);
    });

    test('sans adresse LAN privée → null (la politique dira « pas de Wi-Fi »)', () async {
      CastFileServer.lanAddress = () async => null;
      expect(await CastFileServer.start(a.path), isNull);
    });
  });
}
