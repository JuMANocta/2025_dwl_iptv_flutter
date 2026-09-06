import 'dart:io';

import 'package:flutter/foundation.dart';

import 'cast_service.dart';

/// §castLocal (2026-09-06) — Sert UN fichier du téléphone au téléviseur.
///
/// **Le défaut réparé.** `castEligibility(isLocalFile: true)` refusait tout
/// fichier téléchargé : « le Chromecast va chercher l'adresse lui-même et n'a
/// pas accès au téléphone ». C'était vrai avant §castRelay. Depuis, le
/// téléphone SAIT servir un fichier au téléviseur (`CastRelayService` monte un
/// `HttpServer` sur le LAN et publie `/relay.mp4` avec les requêtes `Range`).
/// Il manquait le câblage, pas la brique.
///
/// Ce serveur-ci sert le fichier **tel quel** — pas la conversion, qui reste
/// l'affaire de `CastRelayService` quand le son n'est pas lisible.
///
/// ⚠️ **Jamais en mémoire** : 2,5 Go mesurés sur le S25 pour un seul film. Le
/// fichier est streamé par `openRead(start, end)` aux bornes du `Range`.
/// ⚠️ Même réseau LAN obligatoire : le récepteur va chercher l'adresse. Sans
/// adresse LAN (données mobiles), `start` rend `null` et la politique refuse
/// AVANT d'envoyer, avec la raison.
abstract final class CastFileServer {
  static HttpServer? _server;
  static String? _path;
  static String? _url;

  /// L'adresse servie en ce moment, ou `null`.
  static String? get url => _url;

  /// Le fichier servi en ce moment, ou `null`.
  static String? get path => _path;

  /// Le nom d'un chemin dans l'URL — assez pour que le récepteur devine le
  /// conteneur à l'extension (`/local/film.mkv`), sans exposer le chemin réel.
  static String routeFor(String path) {
    final String name = path.split(RegExp(r'[\\/]')).last;
    final int dot = name.lastIndexOf('.');
    final String ext = dot < 0 ? 'mp4' : name.substring(dot + 1).toLowerCase();
    return '/local/media.$ext';
  }

  /// Démarre (ou redirige) le serveur sur [path]. Rend l'URL LAN, ou `null`
  /// si le téléphone n'a pas d'adresse LAN ou si le fichier n'existe pas.
  static Future<String?> start(String path) async {
    final File f = File(path);
    if (!await f.exists()) {
      debugPrint('❌ §castLocal : fichier introuvable');
      return null;
    }
    final String? ip = await lanIpv4();
    if (ip == null) {
      debugPrint('❌ §castLocal : aucune adresse LAN (données mobiles ?)');
      return null;
    }
    if (_server == null) {
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      } catch (e) {
        debugPrint('❌ §castLocal : bind impossible — $e');
        return null;
      }
      _server!.listen(_handle, onError: (Object e) {
        debugPrint('⚠️ §castLocal : $e');
      });
      // Le serveur n'existe QUE pour servir une diffusion : dès qu'elle
      // s'arrête, il se ferme (même patron que le relais).
      CastService.state.addListener(_onCastStateChanged);
    }
    _path = path;
    _url = 'http://$ip:${_server!.port}${routeFor(path)}';
    debugPrint('📡 §castLocal : fichier servi sur $_url');
    return _url;
  }

  static Future<void> stop() async {
    CastService.state.removeListener(_onCastStateChanged);
    final HttpServer? s = _server;
    _server = null;
    _path = null;
    _url = null;
    if (s != null) {
      try {
        await s.close(force: true);
      } catch (_) {}
      debugPrint('📡 §castLocal : serveur fermé');
    }
  }

  static void _onCastStateChanged() {
    final CastState? s = CastService.state.value;
    if (s == null || s.url != _url) {
      // Plus de diffusion, ou une diffusion d'autre chose : on n'a plus rien
      // à servir.
      stop();
    }
  }

  /// Point d'entrée de TEST : sert [path] à [req] sans passer par `start`
  /// (qui exige une adresse LAN et écoute `CastService`).
  @visibleForTesting
  static Future<void> serveForTest(HttpRequest req, String path) =>
      _serve(req, path);

  static Future<void> _handle(HttpRequest req) => _serve(req, _path);

  static Future<void> _serve(HttpRequest req, String? path) async {
    final HttpResponse res = req.response;
    res.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Headers', 'Range, Content-Type')
      ..set('Access-Control-Expose-Headers',
          'Content-Length, Content-Range, Accept-Ranges');
    if (req.method == 'OPTIONS') {
      res.statusCode = HttpStatus.noContent;
      await res.close();
      return;
    }
    if (path == null || !req.uri.path.startsWith('/local/')) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    final File f = File(path);
    final int total = await f.length();
    final RangeSpec? range = parseRange(req.headers.value('range'), total);
    res.headers.contentType = contentTypeFor(path);
    res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    if (range == null) {
      res.statusCode = HttpStatus.ok;
      res.headers.contentLength = total;
      if (req.method == 'HEAD') {
        await res.close();
        return;
      }
      await res.addStream(f.openRead());
      await res.close();
      return;
    }
    if (!range.valid) {
      res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
      await res.close();
      return;
    }
    res.statusCode = HttpStatus.partialContent;
    res.headers.contentLength = range.length;
    res.headers.set(HttpHeaders.contentRangeHeader,
        'bytes ${range.start}-${range.end}/$total');
    if (req.method == 'HEAD') {
      await res.close();
      return;
    }
    await res.addStream(f.openRead(range.start, range.end + 1));
    await res.close();
  }

  /// Type MIME d'après l'extension — le récepteur s'en sert pour choisir son
  /// lecteur (`castContentType` fait le même choix côté message Cast).
  static ContentType contentTypeFor(String path) {
    final int dot = path.lastIndexOf('.');
    final String ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
    return switch (ext) {
      'mkv' => ContentType('video', 'x-matroska'),
      'webm' => ContentType('video', 'webm'),
      'ts' => ContentType('video', 'mp2t'),
      'avi' => ContentType('video', 'x-msvideo'),
      'mp3' => ContentType('audio', 'mpeg'),
      'aac' => ContentType('audio', 'aac'),
      _ => ContentType('video', 'mp4'),
    };
  }

  /// `bytes=a-b`, `bytes=a-`, `bytes=-n` → bornes INCLUSIVES bornées au
  /// fichier ; `null` = pas de Range (réponse complète).
  static RangeSpec? parseRange(String? header, int total) {
    if (header == null || !header.startsWith('bytes=')) return null;
    final String spec = header.substring(6).split(',').first.trim();
    final int dash = spec.indexOf('-');
    if (dash < 0) return const RangeSpec.invalid();
    final String a = spec.substring(0, dash).trim();
    final String b = spec.substring(dash + 1).trim();
    if (a.isEmpty) {
      // Suffixe : les n derniers octets.
      final int? n = int.tryParse(b);
      if (n == null || n <= 0) return const RangeSpec.invalid();
      final int start = n >= total ? 0 : total - n;
      return RangeSpec(start, total - 1);
    }
    final int? start = int.tryParse(a);
    if (start == null || start >= total) return const RangeSpec.invalid();
    int end = b.isEmpty ? total - 1 : (int.tryParse(b) ?? -1);
    if (end < 0) return const RangeSpec.invalid();
    if (end >= total) end = total - 1;
    if (end < start) return const RangeSpec.invalid();
    return RangeSpec(start, end);
  }

  /// Même détection que la Console web et le relais : WiFi d'abord, puis une
  /// adresse privée, sinon la première trouvée.
  static Future<String?> lanIpv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      if (interfaces.isEmpty) return null;
      String prioOf(String name) {
        final n = name.toLowerCase();
        if (n.startsWith('wlan') || n.contains('wifi')) return 'a';
        if (n.startsWith('eth')) return 'b';
        return 'c';
      }

      interfaces.sort((a, b) => prioOf(a.name).compareTo(prioOf(b.name)));
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('192.168.') ||
              ip.startsWith('10.') ||
              ip.startsWith('172.')) {
            return ip;
          }
        }
      }
      return interfaces.first.addresses.first.address;
    } catch (e) {
      debugPrint('❌ §castLocal lanIpv4 : $e');
      return null;
    }
  }
}

/// Une plage d'octets INCLUSIVE `[start, end]`.
class RangeSpec {
  final int start;
  final int end;
  final bool valid;
  const RangeSpec(this.start, this.end) : valid = true;
  const RangeSpec.invalid()
      : start = 0,
        end = -1,
        valid = false;
  int get length => end - start + 1;
}
