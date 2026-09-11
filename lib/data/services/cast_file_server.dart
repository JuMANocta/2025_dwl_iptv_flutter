import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/utils/lan_address.dart';
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
/// adresse LAN PRIVÉE (données mobiles), `start` rend `null` et la politique
/// refuse AVANT d'envoyer, avec la raison (`lanIpv4`, RFC 1918 stricte).
///
/// Revue 2026-09-11 — **Durcissement (D2A-12, D2A-02, D2A-03, D2A-07).**
///   - Le serveur écoutait sur `0.0.0.0` une route FIXE et devinable
///     (`/local/media.mkv`) : sur un Wi-Fi partagé, tout poste pouvait
///     télécharger le film servi en connaissant le seul port. Désormais lié à
///     l'adresse choisie, et chaque fichier a SON jeton aléatoire dans la
///     route (`/local/<jeton>/media.<ext>`, extension finale conservée : le
///     récepteur choisit son lecteur avec) — la console web exigeait déjà un
///     jeton pour la même exposition.
///   - Une simple SONDE (choix d'un appareil, puis annulation, ou appareil
///     muet) démarrait le serveur, qui restait ouvert jusqu'à la mort du
///     processus : il ne se fermait que sur un CHANGEMENT d'état Cast. Il se
///     ferme maintenant seul après [idleTimeout] sans diffusion d'un de SES
///     fichiers.
///   - La route était la même pour deux fichiers de même extension : « Diffuser
///     B » depuis le panneau renvoyait au téléviseur l'URL qui servait A. Le
///     jeton est propre à chaque chemin, donc chaque fichier a son URL, et un
///     repointage ne détourne plus une diffusion en cours.
///   - `_serve` n'attrapait rien : chaque requête `Range` interrompue par le
///     récepteur (saut de ±30 s) remontait en erreur non gérée (« 💀 (async) »
///     dans §tvLogs), et un fichier disparu laissait la réponse jamais fermée.
abstract final class CastFileServer {
  static HttpServer? _server;
  static String? _ip;
  static String? _path;
  static String? _url;

  /// Jeton → chemin servi. Un jeton par fichier, pour la vie du serveur.
  static final Map<String, String> _pathOfToken = <String, String>{};

  /// Chemin → jeton (le même fichier redemandé garde la même URL).
  static final Map<String, String> _tokenOfPath = <String, String>{};

  /// Arrêt faute de diffusion (D2A-02).
  static Timer? _idleTimer;

  /// Vrai dès qu'une diffusion d'UN de nos fichiers a été vue : à partir de
  /// là, la fin de la diffusion (ou le passage à un autre contenu) ferme le
  /// serveur. Avant, un état Cast étranger (une chaîne en cours de diffusion
  /// pendant qu'on sonde un fichier) ne doit RIEN fermer : c'est la minuterie
  /// d'inactivité qui tranche.
  static bool _castSeen = false;

  /// Délai sans diffusion au-delà duquel le serveur se ferme seul (D2A-02).
  @visibleForTesting
  static Duration idleTimeout = const Duration(seconds: 60);

  /// Source de l'adresse LAN — remplaçable par les tests (boucle locale).
  @visibleForTesting
  static Future<String?> Function() lanAddress = lanIpv4;

  /// Adresse d'écoute réelle (tests : lié à l'adresse choisie, pas 0.0.0.0).
  @visibleForTesting
  static InternetAddress? get boundAddress => _server?.address;

  /// L'adresse servie en dernier, ou `null`.
  static String? get url => _url;

  /// Le fichier servi en dernier, ou `null`.
  static String? get path => _path;

  /// D2A-04 — L'URL sous laquelle [path] est servi EN CE MOMENT, ou `null`
  /// s'il ne l'est pas. Sert au lecteur à reconnaître « la télé lit CE
  /// fichier » quand il a été rouvert pendant la diffusion.
  static String? urlFor(String path) {
    final HttpServer? s = _server;
    final String? token = _tokenOfPath[path];
    if (s == null || token == null || _ip == null) return null;
    return 'http://$_ip:${s.port}${routeFor(path, token)}';
  }

  /// La route d'un fichier : son jeton, puis `media.<ext>` — assez pour que le
  /// récepteur devine le conteneur à l'extension, sans exposer le chemin réel.
  static String routeFor(String path, String token) {
    final String name = path.split(RegExp(r'[\\/]')).last;
    final int dot = name.lastIndexOf('.');
    final String ext = dot < 0 ? 'mp4' : name.substring(dot + 1).toLowerCase();
    return '/local/$token/media.$ext';
  }

  /// Démarre (ou réutilise) le serveur et y publie [path]. Rend l'URL LAN du
  /// fichier, ou `null` si le téléphone n'a pas d'adresse LAN privée ou si le
  /// fichier n'existe pas. Idempotent : le même fichier garde la même URL.
  static Future<String?> start(String path) async {
    final File f = File(path);
    if (!await f.exists()) {
      debugPrint('❌ §castLocal : fichier introuvable');
      return null;
    }
    final String? ip = await lanAddress();
    if (ip == null) {
      debugPrint('❌ §castLocal : aucune adresse LAN privée (données mobiles ?)');
      return null;
    }
    // L'adresse a changé (autre Wi-Fi) : l'ancien serveur n'est plus joignable.
    if (_server != null && _ip != ip) await stop();
    if (_server == null) {
      try {
        _server = await HttpServer.bind(InternetAddress(ip), 0);
      } catch (e) {
        debugPrint('❌ §castLocal : bind impossible — $e');
        return null;
      }
      _ip = ip;
      _castSeen = false;
      _server!.listen(_handle, onError: (Object e) {
        debugPrint('⚠️ §castLocal : $e');
      });
      // Le serveur n'existe QUE pour servir une diffusion : dès qu'elle
      // s'arrête, il se ferme (même patron que le relais).
      CastService.state.addListener(_onCastStateChanged);
    }
    final String token = _tokenOfPath.putIfAbsent(path, _newToken);
    _pathOfToken[token] = path;
    _path = path;
    _url = urlFor(path);
    _armIdle();
    // ⚠️ L'URL porte le jeton : on ne journalise que le port.
    debugPrint('📡 §castLocal : fichier servi (port ${_server!.port})');
    return _url;
  }

  static Future<void> stop() async {
    CastService.state.removeListener(_onCastStateChanged);
    _idleTimer?.cancel();
    _idleTimer = null;
    final HttpServer? s = _server;
    _server = null;
    _ip = null;
    _path = null;
    _url = null;
    _castSeen = false;
    _pathOfToken.clear();
    _tokenOfPath.clear();
    if (s != null) {
      try {
        await s.close(force: true);
      } catch (_) {}
      debugPrint('📡 §castLocal : serveur fermé');
    }
  }

  /// `true` si [url] désigne un de NOS fichiers, sur NOTRE serveur.
  static bool _isOurs(String? url) {
    final HttpServer? s = _server;
    if (url == null || s == null) return false;
    final Uri? u = Uri.tryParse(url);
    if (u == null || u.host != _ip || u.port != s.port) return false;
    final List<String> segs = u.pathSegments;
    return segs.length == 3 &&
        segs[0] == 'local' &&
        _pathOfToken.containsKey(segs[1]);
  }

  /// D2A-02 — Ferme le serveur si aucune diffusion d'un de ses fichiers n'a
  /// commencé dans [idleTimeout]. Réarmée à chaque `start`.
  static void _armIdle() {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (_isOurs(CastService.state.value?.url)) return;
    _idleTimer = Timer(idleTimeout, () {
      _idleTimer = null;
      if (_isOurs(CastService.state.value?.url)) return;
      debugPrint('⏱️ §castLocal : aucune diffusion depuis ${idleTimeout.inSeconds} s, serveur fermé');
      unawaited(stop());
    });
  }

  static void _onCastStateChanged() {
    final CastState? s = CastService.state.value;
    if (_isOurs(s?.url)) {
      _castSeen = true;
      _idleTimer?.cancel();
      _idleTimer = null;
      return;
    }
    // Plus de diffusion, ou une diffusion d'autre chose APRÈS la nôtre : on
    // n'a plus rien à servir. Avant toute diffusion de nos fichiers (sonde en
    // cours pendant qu'une chaîne passe sur la télé), on laisse la minuterie
    // trancher — fermer ici couperait le fichier qu'on s'apprête à envoyer.
    if (_castSeen) unawaited(stop());
  }

  static String _newToken() {
    final Random rnd = Random.secure();
    return List<String>.generate(
            16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Point d'entrée de TEST : sert [path] à [req] sans passer par `start`
  /// (qui exige une adresse LAN et écoute `CastService`).
  @visibleForTesting
  static Future<void> serveForTest(HttpRequest req, String path) =>
      _serve(req, path);

  /// Le fichier désigné par le jeton de la route, ou `null` (→ 404).
  static Future<void> _handle(HttpRequest req) {
    final List<String> segs = req.uri.pathSegments;
    final String? path = (segs.length == 3 && segs[0] == 'local')
        ? _pathOfToken[segs[1]]
        : null;
    return _serve(req, path);
  }

  static Future<void> _serve(HttpRequest req, String? path) async {
    final HttpResponse res = req.response;
    // D2A-07 — Tout le corps est gardé, sur le modèle du relais : le
    // récepteur coupe une requête `Range` à chaque saut, et un fichier peut
    // disparaître (suppression depuis Téléchargements) pendant la diffusion.
    try {
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
      if (req.method != 'GET' && req.method != 'HEAD') {
        res.statusCode = HttpStatus.methodNotAllowed;
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
    } catch (e) {
      // Le récepteur a coupé (saut, arrêt) ou le fichier a disparu : normal,
      // pas une erreur de l'app. Réponse fermée proprement dans tous les cas.
      // Revue 2026-09-11, lot 9 — pas de `runtimeType` : illisible une fois
      // l'APK obfusqué (`obfuscation_guard_test`). Des libellés fixes.
      final String kind = e is SocketException
          ? 'socket'
          : e is FileSystemException
              ? 'fichier'
              : e is HttpException
                  ? 'http'
                  : 'autre';
      debugPrint('ℹ️ §castLocal — requête interrompue ($kind)');
      try {
        // En-têtes pas encore partis (fichier introuvable) : on le dit.
        res.statusCode = HttpStatus.notFound;
      } catch (_) {/* en-têtes déjà envoyés */}
      try {
        await res.close();
      } catch (_) {}
    }
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
