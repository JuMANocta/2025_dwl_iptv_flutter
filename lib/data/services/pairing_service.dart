import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/themes/app_theme_config.dart';
import '../models/stream_account.dart';
import '../../feature/pairing/pairing_html.dart';

/// Type de saisie demandée par le pairing (§3c-8).
///
/// Le `kind` est encodé dans le QR et lu par le serveur pour rendre le bon
/// formulaire HTML côté mobile, et pour typer le `PairingResult` côté TV.
enum PairingKind {
  /// Form complet : ajout / édition d'un compte IPTV (URL complète OU Xtream).
  account,

  /// Form 1 textarea : Bearer Token TMDB v4.
  tmdb,
}

/// Résultat envoyé via le `Stream<PairingResult>` quand le mobile valide le form.
sealed class PairingResult {
  const PairingResult();
}

class PairingAccountResult extends PairingResult {
  final StreamAccount account;

  /// Token TMDB optionnel saisi en même temps que le compte côté mobile.
  /// Permet de finir l'onboarding en un seul scan QR au lieu de deux.
  final String? tmdbToken;

  const PairingAccountResult(this.account, {this.tmdbToken});
}

class PairingTmdbResult extends PairingResult {
  final String token;
  const PairingTmdbResult(this.token);
}

/// Mini-serveur HTTP local pour la saisie depuis mobile (§3c-8).
///
/// Architecture :
///   - `bind(InternetAddress.anyIPv4, 0)` → l'OS attribue un port libre.
///   - Token aléatoire 8 chars dans l'URL pour empêcher un autre device du LAN
///     de deviner l'endpoint pendant la fenêtre d'activité.
///   - Auto-stop : timeout 10 min, ou stop manuel.
///   - L'IP exposée au QR est récupérée via `NetworkInterface.list()` (Wi-Fi
///     OU Ethernet — solution 2b retenue par l'utilisateur).
///
/// **Sécurité** : HTTP en clair (pas HTTPS — éviterait un warning navigateur
/// avec certif self-signed et casserait l'UX). C'est OK car :
///   - Trafic strictement LAN
///   - Token aléatoire dans l'URL = anti-snooping LAN basique
///   - Serveur fermé immédiatement après réception ou timeout
///
/// Cycle de vie :
/// ```dart
/// final stream = await PairingService.instance.start(PairingKind.account);
/// final result = await stream.first; // ou listen(...)
/// await PairingService.instance.stop();
/// ```
class PairingService {
  PairingService._();
  static final PairingService instance = PairingService._();

  HttpServer? _server;
  String? _token;
  PairingKind? _kind;
  StreamController<PairingResult>? _controller;
  Timer? _timeout;
  String? _localIp;
  AppThemeConfig? _theme;

  /// Durée max d'attente avant fermeture automatique (économise batterie + libère le port).
  static const Duration _autoStopDuration = Duration(minutes: 10);

  bool get isRunning => _server != null;

  /// URL complète à encoder dans le QR, ou `null` si pas démarré.
  String? get pairingUrl {
    if (_server == null || _localIp == null || _token == null) return null;
    final k = _kind == PairingKind.tmdb ? 'tmdb' : 'account';
    return 'http://$_localIp:${_server!.port}/?t=$_token&k=$k';
  }

  String? get localIp => _localIp;
  int? get port => _server?.port;

  /// Démarre le serveur et retourne un stream émettant le résultat quand le
  /// mobile soumet le form. Le stream se ferme :
  ///   - à la réception du premier résultat valide
  ///   - au timeout 10 min
  ///   - sur appel manuel à `stop()`
  Future<Stream<PairingResult>> start({
    required PairingKind kind,
    required AppThemeConfig theme,
  }) async {
    if (_server != null) await stop();

    _kind = kind;
    _theme = theme;
    _token = _generateToken();
    _localIp = await _detectLocalIp();
    _controller = StreamController<PairingResult>.broadcast();

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    } catch (e) {
      debugPrint('❌ PairingService: bind impossible : $e');
      _controller?.addError('Impossible de démarrer le serveur local : $e');
      await stop();
      rethrow;
    }

    debugPrint('🚀 PairingService: listening on ${_server!.address.address}:${_server!.port} (kind=$kind, ip=$_localIp)');

    _server!.listen(_handleRequest, onError: (e) {
      debugPrint('❌ PairingService: $e');
    });

    _timeout = Timer(_autoStopDuration, () {
      debugPrint('⏱️ PairingService: timeout 10 min, fermeture');
      stop();
    });

    return _controller!.stream;
  }

  Future<void> stop() async {
    _timeout?.cancel();
    _timeout = null;
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
    await _controller?.close();
    _controller = null;
    _token = null;
    _kind = null;
    _localIp = null;
    _theme = null;
    debugPrint('🛑 PairingService: arrêté');
  }

  // ── Handlers HTTP ──────────────────────────────────────────────────────────

  Future<void> _handleRequest(HttpRequest req) async {
    try {
      // Sécurise CORS (le mobile et la TV sont sur le même LAN, mais on reste
      // permissif pour les navigateurs paranoïaques).
      req.response.headers.set('Access-Control-Allow-Origin', '*');
      req.response.headers.set('Cache-Control', 'no-store');

      // Vérification token (sauf pour /favicon.ico).
      final uri = req.uri;
      if (uri.path == '/favicon.ico') {
        req.response.statusCode = 204;
        await req.response.close();
        return;
      }

      final providedToken = uri.queryParameters['t'];
      if (providedToken != _token) {
        // Page d'erreur friendly (pas un 404 sec).
        req.response.statusCode = 403;
        req.response.headers.contentType = ContentType.html;
        req.response.write(buildErrorPage(
          theme: _theme ?? AppThemeConfig.defaults,
          message: 'Lien invalide ou expiré. Régénère le QR sur ta TV.',
        ));
        await req.response.close();
        return;
      }

      if (req.method == 'GET' && uri.path == '/') {
        await _serveForm(req);
        return;
      }

      if (req.method == 'POST' && uri.path == '/submit') {
        await _handleSubmit(req);
        return;
      }

      req.response.statusCode = 404;
      await req.response.close();
    } catch (e, st) {
      debugPrint('❌ PairingService._handleRequest: $e\n$st');
      try {
        req.response.statusCode = 500;
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> _serveForm(HttpRequest req) async {
    final theme = _theme ?? AppThemeConfig.defaults;
    final html = _kind == PairingKind.tmdb
        ? buildTmdbForm(theme: theme, token: _token!)
        : buildAccountForm(theme: theme, token: _token!);
    req.response.headers.contentType = ContentType.html;
    req.response.write(html);
    await req.response.close();
  }

  Future<void> _handleSubmit(HttpRequest req) async {
    final theme = _theme ?? AppThemeConfig.defaults;
    Map<String, dynamic> payload;
    try {
      final body = await utf8.decoder.bind(req).join();
      payload = jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      _replyJson(req, 400, {'ok': false, 'error': 'Payload invalide.'});
      return;
    }

    if (_kind == PairingKind.tmdb) {
      final token = (payload['token'] as String?)?.trim() ?? '';
      if (token.isEmpty || token.length < 20) {
        _replyJson(req, 400, {'ok': false, 'error': 'Token trop court.'});
        return;
      }
      _controller?.add(PairingTmdbResult(token));
      _serveSuccess(req, theme);
      return;
    }

    // PairingKind.account
    final modeStr = (payload['mode'] as String?) ?? 'complete';
    final label = (payload['label'] as String?)?.trim();
    // TMDB token optionnel saisi en même temps que le compte (§3c-8b).
    final tmdbRaw = (payload['tmdb'] as String?)?.trim();
    final tmdb = (tmdbRaw != null && tmdbRaw.length >= 20) ? tmdbRaw : null;

    if (modeStr == 'complete') {
      final url = (payload['url'] as String?)?.trim() ?? '';
      if (url.isEmpty || Uri.tryParse(url) == null || !Uri.parse(url).isAbsolute) {
        _replyJson(req, 400, {'ok': false, 'error': 'URL invalide.'});
        return;
      }
      final acc = StreamAccount(
        id: 'acc_${DateTime.now().millisecondsSinceEpoch}',
        label: (label == null || label.isEmpty) ? 'Compte IPTV' : label,
        mode: StreamAuthMode.completeUrl,
        completeUrl: url,
      );
      _controller?.add(PairingAccountResult(acc, tmdbToken: tmdb));
      _serveSuccess(req, theme);
      return;
    }

    // separate (Xtream)
    final base = (payload['base'] as String?)?.trim() ?? '';
    final user = (payload['user'] as String?)?.trim() ?? '';
    final pass = (payload['pass'] as String?)?.trim() ?? '';
    if (base.isEmpty || user.isEmpty || pass.isEmpty) {
      _replyJson(req, 400, {'ok': false, 'error': 'Tous les champs sont requis.'});
      return;
    }
    if (Uri.tryParse(base) == null || !Uri.parse(base).isAbsolute) {
      _replyJson(req, 400, {'ok': false, 'error': 'URL serveur invalide.'});
      return;
    }
    final acc = StreamAccount(
      id: 'acc_${DateTime.now().millisecondsSinceEpoch}',
      label: (label == null || label.isEmpty) ? 'Compte IPTV' : label,
      mode: StreamAuthMode.separate,
      baseUrl: base,
      username: user,
      password: pass,
    );
    _controller?.add(PairingAccountResult(acc, tmdbToken: tmdb));
    _serveSuccess(req, theme);
  }

  void _serveSuccess(HttpRequest req, AppThemeConfig theme) {
    req.response.statusCode = 200;
    req.response.headers.contentType = ContentType.html;
    req.response.write(buildSuccessPage(theme: theme));
    req.response.close();
  }

  void _replyJson(HttpRequest req, int code, Map<String, dynamic> body) {
    req.response.statusCode = code;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(body));
    req.response.close();
  }

  // ── Utilitaires ────────────────────────────────────────────────────────────

  static String _generateToken() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // sans 0/O, I/1 confusables
    final rnd = Random.secure();
    return List.generate(8, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  /// Détecte une IP locale (Wi-Fi ou Ethernet — solution 2b).
  ///
  /// Préfère par ordre : Wi-Fi (wlan*), Ethernet (eth*), puis tout IPv4 non
  /// loopback. Retourne `null` si aucune interface utilisable — la PairingPage
  /// affichera alors un fallback "Wi-Fi requis".
  static Future<String?> _detectLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      if (interfaces.isEmpty) return null;

      // Tri préférentiel : wlan > eth > rest.
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
          // Filtre les IP privées habituelles ; on accepte aussi quand on
          // ne peut pas catégoriser (mieux que rien).
          if (ip.startsWith('192.168.') ||
              ip.startsWith('10.') ||
              ip.startsWith('172.')) {
            return ip;
          }
        }
      }
      // Fallback : première IP IPv4 non-loopback trouvée.
      return interfaces.first.addresses.first.address;
    } catch (e) {
      debugPrint('❌ PairingService._detectLocalIp: $e');
      return null;
    }
  }
}
