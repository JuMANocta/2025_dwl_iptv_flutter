import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/diagnostics/log_buffer.dart';
import '../../core/themes/app_theme_config.dart';
import '../../core/themes/theme_service.dart';
import '../models/stream_account.dart';
import 'backup_service.dart';
import 'favorites_service.dart';
import 'hidden_regions_service.dart';
import 'last_watched_channel_service.dart';
import 'parsed_playlist_service.dart';
import 'playlist_service.dart';
import 'remote_control_service.dart';
import 'search_history_service.dart';
import 'stream_account_service.dart';
import 'tmdb_api_service.dart';
import 'tmdb_service.dart';
import 'watch_progress_service.dart';
import 'xmltv_service.dart';
import '../../feature/search/m3u_filter.dart';
import '../../feature/settings/web_console/web_console_html.dart' as html;

/// §webConsole (Phase 1) — Console web embarquée pour gérer la configuration
/// depuis un navigateur PC/téléphone sur le même réseau local.
///
/// Reprend le modèle de sécurité de `PairingService` (LAN-only, token aléatoire
/// dans l'URL, fermeture à la sortie de l'écran) mais en **persistant** et
/// **multi-routes** : tant que l'écran "Console web" de la TV est ouvert, le
/// serveur répond aux actions (comptes, TMDB, XMLTV, thème, sauvegarde).
///
/// Sécurité : HTTP clair LAN uniquement, token 8 chars requis sur toute requête,
/// serveur fermé sur `stop()` (dispose de l'écran) ou timeout 30 min. Le `.aether`
/// reste chiffré — le mot de passe est exigé côté navigateur pour appliquer.
///
/// §webConsoleOnly (2026-08-05) — La Console web est devenue le **seul** canal
/// QR de l'app (l'ancien `PairingService` mono-formulaire a été supprimé : sur
/// TV, les entrées les plus visibles y menaient, et l'utilisateur se retrouvait
/// avec un formulaire de saisie de playlist au lieu du panneau complet). Deux
/// ajouts rendent ce remplacement possible :
///   - [start] accepte un `initialView` → le QR pointe directement sur la bonne
///     page (comptes, TMDB…), donc scanner depuis « Ajouter une playlist » reste
///     aussi direct qu'avant tout en gardant le reste du panneau accessible ;
///   - [lastEvent] notifie l'app native de chaque action appliquée depuis le
///     navigateur, ce qui permet à l'onboarding TV d'avancer tout seul et aux
///     écrans natifs de se rafraîchir.
/// §webConsoleOnly — Action appliquée depuis le navigateur, poussée vers l'app
/// native via [WebConsoleService.lastEvent].
///
/// [seq] s'incrémente à chaque événement : il garantit que le `ValueNotifier`
/// notifie même quand la **même** action est répétée (deux comptes ajoutés à la
/// suite, par exemple), ce qu'une simple `String` ne ferait pas.
class WebConsoleEvent {
  /// Route API appelée, ex. `/api/account/save`.
  final String path;
  final int seq;
  const WebConsoleEvent(this.seq, this.path);

  bool get isAccountChange => path.startsWith('/api/account/');
  bool get isTmdbChange => path == '/api/tmdb/save';
}

class WebConsoleService {
  WebConsoleService._();
  static final WebConsoleService instance = WebConsoleService._();

  HttpServer? _server;
  String? _token;
  String? _localIp;
  AppThemeConfig _theme = AppThemeConfig.defaults;
  Timer? _timeout;

  /// §webConsoleOnly — Vue sur laquelle le QR ouvre le navigateur (`accounts`,
  /// `tmdb`…). `null` = tableau de bord complet.
  String? _initialView;

  /// §webConsoleOnly — Dernière action appliquée depuis le navigateur.
  /// Jamais remis à `null` après coup : les écrans s'abonnent et filtrent sur
  /// le type d'événement qui les concerne.
  final ValueNotifier<WebConsoleEvent?> lastEvent =
      ValueNotifier<WebConsoleEvent?>(null);
  int _eventSeq = 0;

  static const Duration _autoStopDuration = Duration(minutes: 30);

  bool get isRunning => _server != null;
  String? get localIp => _localIp;
  int? get port => _server?.port;

  /// URL à afficher / encoder en QR, ou null si non démarré.
  String? get consoleUrl {
    if (_server == null || _localIp == null || _token == null) return null;
    final view = _initialView;
    final suffix = (view == null || view.isEmpty) ? '' : '&view=$view';
    return 'http://$_localIp:${_server!.port}/?t=$_token$suffix';
  }

  String? get token => _token;

  /// §webConsoleOnly — Change la vue cible **sans** redémarrer une session déjà
  /// active. Indispensable : redémarrer régénérerait le token et invaliderait
  /// l'onglet déjà ouvert sur le téléphone (cas de la télécommande en cours).
  void setInitialView(String? view) {
    _initialView = view;
  }

  Future<void> start({
    required AppThemeConfig theme,
    String? initialView,
  }) async {
    if (_server != null) await stop();
    _theme = theme;
    _initialView = initialView;
    _token = _generateToken();
    _localIp = await _detectLocalIp();

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    } catch (e) {
      debugPrint('❌ WebConsoleService: bind impossible : $e');
      rethrow;
    }
    debugPrint('🚀 WebConsoleService: ${_server!.address.address}:${_server!.port} (ip=$_localIp)');

    _server!.listen(_handleRequest, onError: (e) {
      debugPrint('❌ WebConsoleService: $e');
    });

    _timeout = Timer(_autoStopDuration, () {
      debugPrint('⏱️ WebConsoleService: timeout 30 min, fermeture');
      stop();
    });
  }

  Future<void> stop() async {
    _timeout?.cancel();
    _timeout = null;
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
    _token = null;
    _localIp = null;
    _initialView = null;
    debugPrint('🛑 WebConsoleService: arrêté');
  }

  /// §webConsoleOnly — Pousse l'action appliquée vers les écrans natifs abonnés.
  void _emit(String path) {
    lastEvent.value = WebConsoleEvent(++_eventSeq, path);
  }

  // ── Routage ────────────────────────────────────────────────────────────────

  Future<void> _handleRequest(HttpRequest req) async {
    final res = req.response;
    try {
      res.headers.set('Access-Control-Allow-Origin', '*');
      res.headers.set('Cache-Control', 'no-store');

      final uri = req.uri;
      if (uri.path == '/favicon.ico') {
        res.statusCode = 204;
        await res.close();
        return;
      }

      // Token obligatoire partout.
      if (uri.queryParameters['t'] != _token) {
        res.statusCode = 403;
        res.headers.contentType = ContentType.html;
        res.write(html.buildErrorPage(_theme, 'Lien invalide ou expiré. Rouvre la Console web sur ta TV.'));
        await res.close();
        return;
      }

      if (req.method == 'GET' && uri.path == '/') {
        await _serveView(req, uri.queryParameters['view']);
        return;
      }

      // §tvLogs — Export texte du journal (téléchargeable, et rechargé toutes
      // les 2 s par la vue « Journal » pour un suivi en direct).
      if (req.method == 'GET' && uri.path == '/logs.txt') {
        res.headers.contentType = ContentType.text;
        res.write(DiagnosticLog.dump());
        await res.close();
        return;
      }

      if (req.method == 'POST' && uri.path.startsWith('/api/')) {
        await _handleApi(req, uri.path);
        return;
      }

      res.statusCode = 404;
      await res.close();
    } catch (e, st) {
      debugPrint('❌ WebConsoleService._handleRequest: $e\n$st');
      try {
        res.statusCode = 500;
        await res.close();
      } catch (_) {}
    }
  }

  Future<void> _serveView(HttpRequest req, String? view) async {
    final tk = _token ?? '';
    String page;
    switch (view) {
      case 'accounts':
        final accounts = await StreamAccountService.listAccounts();
        final cur = await StreamAccountService.getCurrentAccount();
        page = html.buildAccounts(_theme, tk, accounts, cur?.id);
        break;
      case 'tmdb':
        page = html.buildTmdb(_theme, tk, await TmdbApiService.hasApiKey());
        break;
      case 'xmltv':
        page = html.buildXmltv(_theme, tk, XmltvService.loadedAt, XmltvService.channelCount);
        break;
      case 'langregion':
        page = html.buildRegions(
            _theme, tk, kHideableRegionLabels, HiddenRegionsService.hidden);
        break;
      case 'theme':
        final names = AppThemeConfig.presets.map((p) => p.name).toList();
        final current = _currentPresetName();
        page = html.buildTheme(_theme, tk, names, current);
        break;
      case 'backup':
        page = html.buildBackup(_theme, tk);
        break;
      case 'reset':
        page = html.buildReset(_theme, tk);
        break;
      case 'remote':
        page = html.buildRemote(_theme, tk);
        break;
      case 'about':
        final info = await PackageInfo.fromPlatform();
        page = html.buildAbout(_theme, tk, '${info.version}+${info.buildNumber}');
        break;
      case 'logs':
        page = html.buildLogs(_theme, tk, DiagnosticLog.dump(),
            DiagnosticLog.keyTrace, DiagnosticLog.lineCount);
        break;
      default:
        page = html.buildDashboard(_theme, tk);
    }
    req.response.headers.contentType = ContentType.html;
    req.response.write(page);
    await req.response.close();
  }

  Future<Map<String, dynamic>> _readJson(HttpRequest req) async {
    final body = await utf8.decoder.bind(req).join();
    if (body.isEmpty) return {};
    return jsonDecode(body) as Map<String, dynamic>;
  }

  void _json(HttpRequest req, int code, Map<String, dynamic> body) {
    req.response.statusCode = code;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(body));
    req.response.close();
  }

  Future<void> _handleApi(HttpRequest req, String path) async {
    Map<String, dynamic> payload;
    try {
      payload = await _readJson(req);
    } catch (_) {
      _json(req, 400, {'ok': false, 'error': 'Payload invalide.'});
      return;
    }

    try {
      switch (path) {
        case '/api/account/save':
          await _saveAccount(payload);
          _json(req, 200, {'ok': true});
          break;
        case '/api/account/delete':
          await _deleteAccount(payload['id'] as String?);
          _json(req, 200, {'ok': true});
          break;
        case '/api/account/primary':
          final id = payload['id'] as String?;
          if (id == null) throw 'ID manquant';
          await StreamAccountService.setCurrentAccount(id);
          // §secondaryRefresh — Même traitement que la bascule côté TV : si la
          // playlist du nouveau principal est périmée, on la rafraîchit en
          // arrière-plan (la réponse HTTP ne l'attend pas).
          final newPrimary = await StreamAccountService.getAccount(id);
          if (newPrimary != null) {
            unawaited(PlaylistService.refreshIfStale(newPrimary));
          }
          _json(req, 200, {'ok': true});
          break;
        case '/api/account/reload':
          await _reloadAccount(payload['id'] as String?);
          _json(req, 200, {'ok': true});
          break;
        // §tvLogs — Traceur de touches : montre ce que la télécommande émet
        // réellement (indispensable pour les touches média, invisibles sans
        // logcat sur TV).
        case '/api/logs/keytrace':
          DiagnosticLog.keyTrace = payload['on'] == true;
          _json(req, 200, {'ok': true});
          break;
        case '/api/logs/clear':
          DiagnosticLog.clear();
          _json(req, 200, {'ok': true});
          break;
        case '/api/tmdb/save':
          await _saveTmdb((payload['token'] as String?) ?? '');
          _json(req, 200, {'ok': true});
          break;
        case '/api/xmltv/refresh':
          XmltvService.invalidate();
          await XmltvService.ensureLoaded();
          _json(req, 200, {'ok': true});
          break;
        case '/api/regions/save':
          await _saveRegions(payload);
          _json(req, 200, {'ok': true});
          break;
        case '/api/theme/save':
          _saveTheme(payload['preset'] as String?);
          _json(req, 200, {'ok': true});
          break;
        case '/api/backup/import':
          await _importBackup(payload);
          _json(req, 200, {'ok': true});
          break;
        case '/api/backup/export':
          final out = await _exportBackup((payload['password'] as String?) ?? '');
          _json(req, 200, {'ok': true, 'filename': out.fileName, 'data': out.b64});
          break;
        case '/api/reset':
          await _resetUsage();
          _json(req, 200, {'ok': true});
          break;
        case '/api/remote':
          final key = (payload['key'] as String?) ?? '';
          if (key.isNotEmpty) RemoteControlService.instance.dispatch(key);
          _json(req, 200, {'ok': true});
          break;
        default:
          _json(req, 404, {'ok': false, 'error': 'Route inconnue.'});
          return; // Route inconnue : rien à notifier.
      }
      // §webConsoleOnly — On n'arrive ici que si l'action a réussi (toute erreur
      // est levée et interceptée ci-dessous). `/api/remote` est exclu : il part
      // à CHAQUE appui de touche de la télécommande et noierait les abonnés.
      // §tvLogs — `/api/logs/*` est exclu pour la même raison : consulter le
      // journal est une action de diagnostic, elle ne change pas la config.
      if (path != '/api/remote' && !path.startsWith('/api/logs/')) _emit(path);
    } catch (e) {
      debugPrint('❌ WebConsoleService API $path: $e');
      _json(req, 400, {'ok': false, 'error': e.toString()});
    }
  }

  // ── Actions ──────────────────────────────────────────────────────────────────

  Future<void> _saveAccount(Map<String, dynamic> p) async {
    final id = (p['id'] as String?)?.trim();
    final label = (p['label'] as String?)?.trim();
    final mode = (p['mode'] as String?) ?? 'complete';
    if (label == null || label.isEmpty) throw 'Le nom est requis.';

    final accId = (id == null || id.isEmpty)
        ? 'acc_${DateTime.now().millisecondsSinceEpoch}'
        : id;
    final isNew = id == null || id.isEmpty;

    final StreamAccount acc;
    if (mode == 'separate') {
      final base = (p['base'] as String?)?.trim() ?? '';
      final user = (p['user'] as String?)?.trim() ?? '';
      final pass = (p['pass'] as String?)?.trim() ?? '';
      if (base.isEmpty || user.isEmpty || pass.isEmpty) {
        throw 'Serveur, identifiant et mot de passe requis.';
      }
      if (Uri.tryParse(base)?.isAbsolute != true) throw 'URL serveur invalide.';
      acc = StreamAccount(
        id: accId, label: label, mode: StreamAuthMode.separate,
        baseUrl: base, username: user, password: pass,
      );
    } else {
      final url = (p['url'] as String?)?.trim() ?? '';
      if (Uri.tryParse(url)?.isAbsolute != true) throw 'URL M3U invalide.';
      acc = StreamAccount(
        id: accId, label: label, mode: StreamAuthMode.completeUrl,
        completeUrl: url,
      );
    }

    await StreamAccountService.saveAccount(acc);
    // Si c'est le tout premier compte, le définir comme principal.
    final all = await StreamAccountService.listAccounts();
    final cur = await StreamAccountService.getCurrentAccount();
    if (cur == null && all.isNotEmpty) {
      await StreamAccountService.setCurrentAccount(all.first.id);
    }

    // Le contenu change → invalider le cache parsé et re-hydrater en arrière-plan.
    ParsedPlaylistService.invalidate(accId);
    if (!isNew) await PlaylistService.deleteForAccountId(accId);
    _hydrate(acc); // fire & forget
  }

  Future<void> _deleteAccount(String? id) async {
    if (id == null) throw 'ID manquant';
    await StreamAccountService.deleteAccount(id);
    await PlaylistService.deleteForAccountId(id);
    ParsedPlaylistService.invalidate(id);
  }

  Future<void> _reloadAccount(String? id) async {
    if (id == null) throw 'ID manquant';
    final acc = await StreamAccountService.getAccount(id);
    if (acc == null) throw 'Compte introuvable.';
    await PlaylistService.deleteForAccountId(id);
    final cur = await StreamAccountService.getCurrentAccount();
    String? path;
    if (cur?.id == id) {
      path = await PlaylistService.downloadCurrentM3U();
    } else {
      path = (await PlaylistService.ensureDownloadedForAccount(acc)).path;
    }
    if (path == null) throw 'Téléchargement impossible (URL/connexion ?).';
    await ParsedPlaylistService.reloadFromDisk(acc.id, acc.label, path);
  }

  Future<void> _saveTmdb(String token) async {
    final t = token.trim();
    if (t.isEmpty) {
      await TmdbApiService.deleteApiKey();
    } else {
      if (t.length < 20) throw 'Token trop court.';
      await TmdbApiService.saveApiKey(t);
    }
    TmdbService.resetInstance();
  }

  /// §webConsoleLangFilter — Applique le set de régions masquées (miroir de
  /// `RegionFilterPage._apply`) : `setHidden` puis, si ça a changé, re-parse du
  /// compte actif (filtre appliqué immédiatement) + invalidation des secondaires.
  Future<void> _saveRegions(Map<String, dynamic> p) async {
    final list = (p['hidden'] as List?)?.cast<String>() ?? const <String>[];
    // Anti-injection : on ne retient que des labels connus.
    final set = list.where(kHideableRegionLabels.contains).toSet();
    final changed = await HiddenRegionsService.setHidden(set);
    if (!changed) return;
    final accounts = await StreamAccountService.listAccounts();
    final active = await StreamAccountService.getCurrentAccount();
    if (active != null) {
      final path = await PlaylistService.pathForAccountId(active.id);
      await ParsedPlaylistService.reloadFromDisk(active.id, active.label, path);
    }
    for (final a in accounts) {
      if (a.id != active?.id) ParsedPlaylistService.invalidate(a.id);
    }
  }

  /// §webConsoleReset — Remet à zéro les données d'usage (miroir de
  /// `SettingsPage._resetUsageData`) : favoris + reprises + historique de
  /// recherche + dernière chaîne. Conserve comptes/TMDB/thème/filtres. Chaque
  /// service bumpe son ValueNotifier → la TV se rafraîchit en direct.
  Future<void> _resetUsage() async {
    await Future.wait([
      FavoritesService.clear(),
      WatchProgressService.clearAll(),
      SearchHistoryService.clear(),
      LastWatchedChannelService.clear(),
    ]);
  }

  void _saveTheme(String? presetName) {
    if (presetName == null) throw 'Preset manquant.';
    final preset = AppThemeConfig.presets
        .where((p) => p.name == presetName)
        .map((p) => p.config)
        .firstOrNull;
    if (preset == null) throw 'Preset inconnu.';
    ThemeService.save(preset);
    _theme = preset; // les pages suivantes reprennent le nouveau thème
  }

  Future<void> _importBackup(Map<String, dynamic> p) async {
    final pw = (p['password'] as String?) ?? '';
    final b64 = (p['data'] as String?) ?? '';
    if (pw.isEmpty) throw 'Mot de passe requis.';
    if (b64.isEmpty) throw 'Fichier manquant.';
    final Uint8List bytes;
    try {
      bytes = base64Decode(b64);
    } catch (_) {
      throw 'Fichier illisible.';
    }
    final content = await BackupService.readBackupBytes(bytes, pw);
    await BackupService.applyBackup(content);
  }

  Future<({String fileName, String b64})> _exportBackup(String password) async {
    if (password.isEmpty) throw 'Mot de passe requis.';
    final out = await BackupService.exportToBytes(password);
    return (fileName: out.fileName, b64: base64Encode(out.bytes));
  }

  // ── Utilitaires ────────────────────────────────────────────────────────────

  String _currentPresetName() {
    final c = ThemeService.config.value;
    for (final p in AppThemeConfig.presets) {
      if (p.config.primaryColor == c.primaryColor &&
          p.config.accentColor == c.accentColor &&
          p.config.tertiaryColor == c.tertiaryColor) {
        return p.name;
      }
    }
    return AppThemeConfig.presets.first.name;
  }

  /// Télécharge + parse un compte en arrière-plan (silencieux).
  Future<void> _hydrate(StreamAccount acc) async {
    try {
      final path = (await PlaylistService.ensureDownloadedForAccount(acc)).path;
      if (path != null) {
        await ParsedPlaylistService.loadSecondary(acc.id, acc.label, path);
      }
    } catch (e) {
      debugPrint('⚠️ WebConsoleService._hydrate(${acc.label}): $e');
    }
  }

  static String _generateToken() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(8, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  static Future<String?> _detectLocalIp() async {
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
          if (ip.startsWith('192.168.') || ip.startsWith('10.') || ip.startsWith('172.')) {
            return ip;
          }
        }
      }
      return interfaces.first.addresses.first.address;
    } catch (e) {
      debugPrint('❌ WebConsoleService._detectLocalIp: $e');
      return null;
    }
  }
}
