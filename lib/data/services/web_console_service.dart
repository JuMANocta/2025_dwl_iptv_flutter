import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/diagnostics/log_buffer.dart';
import '../../core/utils/lan_address.dart';
import '../../core/utils/user_error.dart';
import 'load_failure.dart';
import '../../core/themes/app_theme_config.dart';
import '../../core/themes/theme_service.dart';
import '../models/stream_account.dart';
import 'backup_service.dart';
import 'favorites_service.dart';
import 'hidden_regions_service.dart';
import 'last_watched_channel_service.dart';
import 'parsed_playlist_service.dart';
import 'playlist_reload_service.dart';
import 'playlist_service.dart';
import '../../core/boot/boot_status.dart';
import '../../feature/search/xtream_catalog_parser.dart';
import '../../feature/search/m3u_parser.dart';
import '../models/m3u_entry.dart';
import 'remote_control_service.dart';
import 'search_history_service.dart';
import 'stream_account_service.dart';
import 'tmdb_api_service.dart';
import 'tmdb_poster_cache.dart';
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
/// Sécurité — revue 2026-09-11, D1B-02 (décision utilisateur : la console
/// RESTE en release, mais verrouillée). L'en-tête d'origine promettait
/// « fermeture à la sortie de l'écran » alors que §webConsolePersist la garde
/// vivante hors écran : il décrit désormais ce qui est vrai.
///   - HTTP clair, **lié à l'adresse LAN** détectée (plus `0.0.0.0` : sur un
///     point d'accès ou un téléphone en données mobiles, elle écoutait sur
///     toutes les interfaces) ; repli `anyIPv4` seulement si la détection est
///     impossible. Un second écouteur sur la BOUCLE LOCALE, même port : c'est
///     par lui que passe `adb forward` (driver.sh `port`/`logs`/`api`) — il
///     n'est joignable que depuis l'appareil lui-même.
///   - Jeton de **16** caractères (80 bits, contre 40) sur TOUTE requête — il
///     ouvre `/api/backup/export`, donc tous les identifiants IPTV.
///   - Plus d'en-tête CORS `*` (la page est servie par ce même serveur, elle
///     n'en a jamais eu besoin) ; `Referrer-Policy: no-referrer` et plus de
///     police Google (l'URL de la page porte le jeton).
///   - Fermeture après 30 min **sans geste** (le délai repart à chaque
///     requête authentifiée : une télécommande en cours n'est plus coupée
///     net — sauf les lectures que la page relance seule, `/logs.txt` et
///     `/fleet.json`, sinon un onglet oublié la garderait ouverte à vie) ;
///     tant qu'elle tourne, un bandeau le dit hors de l'écran ([running]).
///   - `/api/dev/*` absentes du release (sauf `--dart-define=AS_DEV_ROUTES=true`),
///     corps de requête borné ([maxBodyBytes]), erreurs par `describeError`.
/// Le `.aether` reste chiffré — le mot de passe est exigé côté navigateur pour
/// appliquer.
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

  /// D1B-02 — Écouteur sur la boucle locale, même port que [_server] : le
  /// chemin d'`adb forward` (outillage de recette), injoignable du réseau.
  HttpServer? _loopback;
  String? _token;
  String? _localIp;
  AppThemeConfig _theme = AppThemeConfig.defaults;
  Timer? _timeout;
  DateTime? _autoStopAt;

  /// D1B-02 — Vrai tant que le serveur écoute. Le bandeau de l'app
  /// (`WebConsoleBanner`) s'y abonne : la console survit à son écran
  /// (§webConsolePersist), il faut que ça se VOIE.
  final ValueNotifier<bool> running = ValueNotifier<bool>(false);

  /// D1B-12 — Plafond d'un corps de requête. Le plus gros légitime est un
  /// `.aether` en base64 (quelques Mo) : 20 Mo laissent une marge large sans
  /// laisser un POST de plusieurs centaines de Mo se charger en mémoire.
  @visibleForTesting
  static int maxBodyBytes = 20 * 1024 * 1024;

  /// Source de l'adresse LAN — remplaçable par les tests (boucle locale).
  @visibleForTesting
  static Future<String?> Function() localAddress =
      () => lanIpv4(allowNonPrivate: true);

  /// D1B-11 / D5A-17 — `/api/dev/*` (le banc AOT §parseSpeed) re-parse une
  /// liste sur le thread principal : l'interface gèle le temps de l'analyse.
  /// Servies en debug et en profile (profile = AOT : la mesure reste
  /// possible), jamais dans un release — sauf build de recette compilé avec
  /// `--dart-define=AS_DEV_ROUTES=true`, comme `AS_KEYTRACE`.
  static const bool devRoutesEnabled =
      !kReleaseMode || bool.fromEnvironment('AS_DEV_ROUTES');

  /// D1B-02 — Lectures que la page relance d'elle-même (journal en suivi
  /// direct, état des listes) : elles ne prouvent pas qu'une personne est là,
  /// donc ne repoussent pas l'arrêt automatique.
  static bool _isPassivePoll(String method, String path) =>
      method == 'GET' && (path == '/logs.txt' || path == '/fleet.json');

  /// Échéance de l'arrêt automatique (tests / diagnostic).
  @visibleForTesting
  DateTime? get autoStopAt => _autoStopAt;

  /// Adresse d'écoute réelle du serveur LAN (tests).
  @visibleForTesting
  InternetAddress? get boundAddress => _server?.address;

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
    _localIp = await localAddress();

    // D1B-02 — Lié à l'adresse LAN ; `anyIPv4` seulement si la détection n'a
    // rien donné (comportement d'avant, faute de mieux).
    final String? ip = _localIp;
    final InternetAddress bindTo =
        ip == null ? InternetAddress.anyIPv4 : InternetAddress(ip);
    try {
      _server = await HttpServer.bind(bindTo, 0);
    } catch (e) {
      debugPrint('❌ WebConsoleService: bind impossible : $e');
      rethrow;
    }
    // ⚠️ Format lu par driver.sh (`WebConsoleService: <ip>:<port>`) : ne pas
    // le changer sans mettre l'outil à jour.
    debugPrint('🚀 WebConsoleService: ${_server!.address.address}:${_server!.port} (ip=$_localIp)');

    _server!.listen(_handleRequest, onError: (e) {
      debugPrint('❌ WebConsoleService: $e');
    });

    // Boucle locale, MÊME port (adb forward tcp:P → 127.0.0.1:P sur
    // l'appareil). Inutile si le serveur écoute déjà partout ou sur la boucle.
    if (!bindTo.isLoopback && bindTo != InternetAddress.anyIPv4) {
      try {
        _loopback =
            await HttpServer.bind(InternetAddress.loopbackIPv4, _server!.port);
        _loopback!.listen(_handleRequest, onError: (e) {
          debugPrint('❌ WebConsoleService (boucle locale): $e');
        });
      } catch (e) {
        // Port déjà pris sur la boucle : la console marche, seul l'outillage
        // adb est privé de ce chemin.
        debugPrint('⚠️ WebConsoleService: boucle locale indisponible : $e');
      }
    }

    running.value = true;
    _armAutoStop();
  }

  /// D1B-02 — (Ré)arme l'arrêt automatique : 30 min APRÈS la dernière
  /// requête authentifiée qui vient d'un GESTE, et non plus 30 min après
  /// l'ouverture — une télécommande en cours d'usage était coupée net.
  void _armAutoStop() {
    _timeout?.cancel();
    _autoStopAt = DateTime.now().add(_autoStopDuration);
    _timeout = Timer(_autoStopDuration, () {
      debugPrint('⏱️ WebConsoleService: 30 min sans requête, fermeture');
      stop();
    });
  }

  Future<void> stop() async {
    _timeout?.cancel();
    _timeout = null;
    _autoStopAt = null;
    try {
      await _server?.close(force: true);
    } catch (_) {}
    try {
      await _loopback?.close(force: true);
    } catch (_) {}
    _server = null;
    _loopback = null;
    _token = null;
    _localIp = null;
    _initialView = null;
    running.value = false;
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
      // D1B-02 — Plus de `Access-Control-Allow-Origin: *` : la page est
      // servie par ce serveur, et l'en-tête ouvrait les réponses à tout script
      // d'une autre origine. D1B-13 — l'URL porte le jeton : aucun Referer.
      res.headers.set('Cache-Control', 'no-store');
      res.headers.set('Referrer-Policy', 'no-referrer');

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
      // D1B-02 — Requête authentifiée : la session est utilisée, l'arrêt
      // automatique repart de maintenant. ⚠️ SAUF les deux lectures que la
      // page relance TOUTE SEULE (`/logs.txt` toutes les 2 s en suivi direct,
      // `/fleet.json` toutes les 5 s) : un onglet oublié sur le PC aurait
      // gardé la console ouverte sans fin — pire que les 30 min FIXES d'avant.
      // Seul un geste (page ouverte, télécommande, action) prolonge la session.
      if (!_isPassivePoll(req.method, uri.path)) _armAutoStop();

      if (req.method == 'GET' && uri.path == '/') {
        await _serveView(req, uri.queryParameters['view']);
        return;
      }

      // §tvLogs — Export texte du journal (téléchargeable, et rechargé toutes
      // les 2 s par la vue « Journal » pour un suivi en direct).
      //
      // §tvLogsPersist — `?session=previous` sert le journal de la session
      // D'AVANT ce lancement (survivant à un kill), lu depuis le fichier de
      // rotation plutôt que depuis le tampon mémoire courant. `await` reste
      // sûr même si la console s'ouvre très tôt après le boot : l'amorçage
      // disque (async) n'a peut-être pas encore fini.
      if (req.method == 'GET' && uri.path == '/logs.txt') {
        final bool wantPrevious = uri.queryParameters['session'] == 'previous';
        res.headers.contentType = ContentType.text;
        res.write(wantPrevious
            ? (await DiagnosticLog.awaitPreviousSession() ?? '')
            : DiagnosticLog.dump());
        await res.close();
        return;
      }

      // §fleetState — La SEULE route de lecture avec `/logs.txt`.
      //
      // ⚠️ Toutes les routes `/api/*` sont en POST **parce qu'elles mutent** :
      // aucune ne doit basculer en GET (un GET se pré-charge, se met en cache,
      // se rejoue depuis l'historique — une suppression de compte n'a rien à
      // faire là). Celle-ci ne fait que lire, d'où le GET, et elle vit à côté
      // de `/logs.txt` plutôt que sous `/api/`.
      //
      // ⚠️ Servie en HTTP CLAIR sur le réseau local : la sortie ne contient
      // donc **aucune URL et aucun identifiant** — que des libellés, des états,
      // des compteurs et des tailles.
      if (req.method == 'GET' && uri.path == '/fleet.json') {
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode(await _fleetSnapshot()));
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
        // §tvLogsPersist — `awaitPreviousSession` peut être en cours (console
        // ouverte très tôt après le boot) : on attend ici, une fois, pour que
        // le compteur affiché soit juste dès le premier rendu de la page.
        await DiagnosticLog.awaitPreviousSession();
        page = html.buildLogs(_theme, tk, DiagnosticLog.dump(),
            DiagnosticLog.keyTrace, DiagnosticLog.lineCount,
            DiagnosticLog.previousSessionLineCount);
        break;
      // §fleetState — Vue « État des listes » : le rendu lisible de
      // `/fleet.json`, rafraîchi côté navigateur. La page elle-même est vide de
      // données : tout arrive par la route JSON.
      case 'fleet':
        page = html.buildFleet(_theme, tk);
        break;
      default:
        page = html.buildDashboard(_theme, tk);
    }
    req.response.headers.contentType = ContentType.html;
    req.response.write(page);
    await req.response.close();
  }

  /// §fleetState — Photographie de l'état des listes, sans un seul identifiant.
  ///
  /// **Le problème résolu** : une liste peut être absente de la mémoire sans
  /// qu'aucune UI ne le dise, et la seule page qui rapportait cet état — la page
  /// Comptes — est aussi celle qui le détruisait (le déchargement paresseux
  /// tournait pendant qu'on la regardait). Une route de lecture consultée depuis
  /// un téléphone permet enfin d'observer sans perturber.
  ///
  /// ⚠️ Chaque valeur est prise **sans toucher `_lastAccess`** :
  /// `entriesCountOf` et `countsOf` sont sûrs, `getAccount()` ne l'est pas — il
  /// repousserait le déchargement des comptes qu'on observe.
  Future<Map<String, dynamic>> _fleetSnapshot() async {
    final accounts = await StreamAccountService.listAccounts();
    final current = await StreamAccountService.getCurrentAccount();
    final supportDir = await getApplicationSupportDirectory();
    final now = DateTime.now();

    final list = <Map<String, dynamic>>[];
    for (final a in accounts) {
      final state = ParsedPlaylistService.stateOf(a.id);
      final failure = ParsedPlaylistService.failureOf(a.id);
      final memoryEntries = ParsedPlaylistService.entriesCountOf(a.id);
      final counts = await ParsedPlaylistService.countsOf(a.id);

      // Fichier source (catalogue `.json` §23 ou `.m3u` legacy) : taille et
      // âge. L'âge est ce qui dit si le TTL de 24 h a expiré.
      int sourceBytes = 0;
      int? sourceAgeMinutes;
      String? sourceKind;
      try {
        final srcPath = await PlaylistService.pathForAccountId(a.id);
        final src = File(srcPath);
        if (await src.exists()) {
          final stat = await src.stat();
          sourceBytes = stat.size;
          sourceAgeMinutes = now.difference(stat.modified).inMinutes;
          sourceKind = srcPath.toLowerCase().endsWith('.json')
              ? 'catalogue JSON'
              : 'M3U';
        }
      } catch (_) {/* un fichier illisible se rapporte comme absent */}

      // Cache analysé (NDJSON gzippé) : sa présence dit si la liste peut
      // revenir en ~50 ms ou s'il faut re-télécharger et ré-analyser.
      int parsedBytes = 0;
      bool hasParsed = false;
      try {
        final f = File('${supportDir.path}/parsed_playlist_${a.id}.json.gz');
        if (await f.exists()) {
          hasParsed = true;
          parsedBytes = await f.length();
        }
      } catch (_) {/* idem */}

      list.add({
        'label': a.label, // ⚠️ le libellé, JAMAIS l'URL ni les identifiants
        'primary': a.id == current?.id,
        'state': state.name,
        'inMemory': memoryEntries > 0,
        'memoryEntries': memoryEntries,
        'cacheFilms': counts?.films,
        'cacheSeries': counts?.series,
        'cacheTv': counts?.tv,
        'cacheTotal': counts?.total,
        'sourceKind': sourceKind,
        'sourceBytes': sourceBytes,
        'sourceAgeMinutes': sourceAgeMinutes,
        'hasParsedCache': hasParsed,
        'parsedCacheBytes': parsedBytes,
        if (failure != null) ...{
          'failureKind': failure.kind.name,
          'failureLabel': labelForFailure(failure.kind),
          // `describeFailure` inclut le détail, qui vient parfois du réseau :
          // il repasse par `sanitizeForLog` en dernier filet (invariant
          // §tourFix — ce qu'on sait extraire, on doit savoir le masquer).
          'failureText': sanitizeForLog(describeFailure(failure)),
          'failureBenign': failure.isBenign,
          'failureAt': failure.at.toIso8601String(),
        },
      });
    }

    return {
      'at': now.toIso8601String(),
      'accounts': list,
    };
  }

  /// D1B-12 — Lecture BORNÉE : au-delà de [maxBodyBytes] (annoncé par
  /// `Content-Length` ou constaté en route pour un corps « chunked »), plus
  /// rien n'est GARDÉ en mémoire.
  ///
  /// ⚠️ Le reste du corps est quand même LU (et jeté) avant de répondre :
  /// abandonner le flux de la requête en cours de route fait fermer la
  /// connexion par `HttpServer`, et le navigateur ne reçoit jamais le 413 —
  /// seulement « connexion fermée ». Mémoire bornée à plafond + un bloc.
  Future<Map<String, dynamic>> _readJson(HttpRequest req) async {
    bool tooLarge = req.contentLength > maxBodyBytes;
    final BytesBuilder buf = BytesBuilder(copy: false);
    await for (final List<int> chunk in req) {
      if (tooLarge) continue; // on vide sans garder
      buf.add(chunk);
      if (buf.length > maxBodyBytes) {
        tooLarge = true;
        buf.clear();
      }
    }
    if (tooLarge) throw const _PayloadTooLarge();
    final String body = utf8.decode(buf.takeBytes());
    if (body.isEmpty) return {};
    return jsonDecode(body) as Map<String, dynamic>;
  }

  void _json(HttpRequest req, int code, Map<String, dynamic> body) {
    req.response.statusCode = code;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(body));
    // D1B-12 — `close()` n'était pas attendu NI gardé : un onglet fermé
    // pendant la réponse devenait une erreur asynchrone non gérée.
    unawaited(req.response.close().then<void>((_) {}, onError: (Object e) {
      // Revue 2026-09-11, lot 9 — pas de `runtimeType` (illisible une fois
      // l'APK obfusqué, `obfuscation_guard_test`).
      final String kind = e is SocketException
          ? 'socket'
          : e is HttpException
              ? 'http'
              : 'autre';
      debugPrint('ℹ️ WebConsoleService: réponse interrompue ($kind)');
    }));
  }

  Future<void> _handleApi(HttpRequest req, String path) async {
    Map<String, dynamic> payload;
    try {
      payload = await _readJson(req);
    } on _PayloadTooLarge {
      _json(req, 413, {'ok': false, 'error': 'Fichier trop volumineux.'});
      return;
    } catch (_) {
      _json(req, 400, {'ok': false, 'error': 'Payload invalide.'});
      return;
    }

    // D1B-11 / D5A-17 — Outils de mesure : absents d'un release.
    if (path.startsWith('/api/dev/') && !devRoutesEnabled) {
      _json(req, 404, {'ok': false, 'error': 'Route inconnue.'});
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
        // R41 — `clearAll` et non `clear` : le vidage doit emporter les DEUX
        // fichiers de session (§tvLogsPersist), et être ATTENDU avant de
        // répondre `ok`. La vue Journal relit `?session=previous` d'elle-même :
        // sans l'attente, elle pourrait réafficher ce qu'elle vient de faire
        // détruire.
        // F1 — On dit le RÉSULTAT. Afficher « Journal vidé » alors qu'un
        // fichier a résisté serait le pire résultat sur un ticket de sécurité :
        // plus rien n'est servi tout de suite, mais au prochain lancement la
        // rotation relit le survivant et la console le ressert. §clientText :
        // ce que la personne doit savoir, jamais la mécanique — §userError :
        // aucun `$e` à l'écran (le détail part au journal, pas au navigateur).
        case '/api/logs/clear':
          final bool disquePropre = await DiagnosticLog.clearAll();
          _json(
              req,
              200,
              disquePropre
                  ? {'ok': true}
                  : {
                      'ok': false,
                      'error': 'Journal vidé, mais un fichier n\'a pas pu être '
                          'supprimé. Réessayez.',
                    });
          break;
        case '/api/tmdb/save':
          await _saveTmdb((payload['token'] as String?) ?? '');
          _json(req, 200, {'ok': true});
          break;
        case '/api/xmltv/refresh':
          // Revue 2026-09-11, D1B-04 — `invalidate` + `ensureLoaded` relisait
          // le fichier de moins de 24 h sans rien télécharger. `refresh()`
          // télécharge vraiment, et dit si c'est fait.
          final bool xmltvFresh = await XmltvService.refresh();
          _json(req, 200, {'ok': true, 'fresh': xmltvFresh});
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
        case '/api/dev/parsebench':
          // §parseSpeed — Banc AOT sur l'appareil : ré-analyse le fichier en
          // cache d'un compte (payload {"id": …}) sur le thread principal,
          // exactement comme au démarrage, et rend le chrono. Le banc
          // `flutter test` est en JIT et a donné le résultat INVERSE du
          // release sur ce parseur : seul ceci fait foi.
          final String? benchId = payload['id'] as String?;
          if (benchId == null) {
            _json(req, 400, {'ok': false, 'error': 'id requis'});
            break;
          }
          final String benchPath = await PlaylistService.pathForAccountId(benchId);
          final films = <M3uEntry>[], series = <M3uEntry>[], tv = <M3uEntry>[];
          final Stopwatch swBench = Stopwatch()..start();
          // `mode` : 'nu' (rien d'autre), 'boot' (filtre régions + callbacks de
          // progression, comme au démarrage).
          final bool likeBoot = (payload['mode'] as String?) == 'boot';
          final Set<String> benchHidden = likeBoot ? HiddenRegionsService.hidden : const <String>{};
          int benchTicks = 0;
          void benchProgress(double v) { benchTicks++; if (likeBoot) BootStatus.report(v); }
          void benchDetail(String d) { if (likeBoot) BootStatus.setDetail(d); }
          if (benchPath.toLowerCase().endsWith('.json')) {
            await XtreamCatalogParser.parseFile(benchPath, films, series, tv, accountId: benchId,
                hidden: benchHidden, onProgress: likeBoot ? benchProgress : null, onDetail: likeBoot ? benchDetail : null);
          } else {
            await M3uParser.parseFile(benchPath, films, series, tv, accountId: benchId,
                hidden: benchHidden, onProgress: likeBoot ? benchProgress : null, onDetail: likeBoot ? benchDetail : null);
          }
          _json(req, 200, {
            'ok': true,
            'ms': swBench.elapsedMilliseconds,
            'entries': films.length + series.length + tv.length,
            'path': benchPath.split('/').last,
            'ticks': benchTicks,
            'hidden': benchHidden.length,
          });
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
      // D1B-12 / §userError — Jamais le `toString()` brut au navigateur
      // (`FileSystemException`, `TypeError`…) : `describeError` garde nos
      // phrases de validation, traduit le reste et repasse par sanitizeForLog.
      _json(req, 400, {'ok': false, 'error': describeError(e)});
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
    final cur = await StreamAccountService.getCurrentAccount();
    // §reloadKeep + §reloadNaming — revue 2026-09-11, D1L-01 — Ce chemin-ci
    // avait été OUBLIÉ par les deux correctifs : il supprimait la liste AVANT
    // de la retélécharger (une panne du panel laissait le compte sans rien au
    // redémarrage), ne forçait pas le téléchargement d'un secondaire, et
    // ignorait le `null` d'une analyse ratée — la route répondait `ok`. Le
    // chemin PARTAGÉ ne supprime rien, force, et lève sur tout échec : la
    // console affiche alors l'erreur au lieu d'un faux succès.
    await PlaylistReloadService.reloadAccount(acc, isPriority: cur?.id == id);
  }

  Future<void> _saveTmdb(String token) async {
    final t = token.trim();
    if (t.isEmpty) {
      await TmdbApiService.deleteApiKey();
    } else {
      if (t.length < 20) throw 'Token trop court.';
      // §tmdbKeyCheck — revue 2026-09-11, D1B-18 — Même contrôle que la page
      // native : une clé mal collée depuis le PC (le canal privilégié sur TV)
      // répondait « ok » et laissait une app sans affiche, sans un mot.
      // `null` (TMDB injoignable) : on enregistre quand même, comme la page.
      final bool? accepted = await TmdbService.probeKey(t);
      if (accepted == false) throw 'Clé refusée par TMDB.';
      final String? previous = await TmdbApiService.getApiKey();
      await TmdbApiService.saveApiKey(t);
      // Revue 2026-09-11, D1B-01 — clé NOUVELLE : les « introuvables »
      // mémorisés sans clé valide se recherchent à nouveau.
      if (previous != t) await TmdbPosterCache.forgetNegatives();
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

  /// D1B-02 — 16 caractères sur 32 symboles (80 bits ; 8 auparavant). Même
  /// alphabet sans caractères ambigus (ni 0/O ni 1/I) : il se recopie à la
  /// main depuis l'écran de la TV.
  static String _generateToken() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(16, (_) => chars[rnd.nextInt(chars.length)]).join();
  }
}

/// D1B-12 — Corps de requête au-delà de [WebConsoleService.maxBodyBytes].
class _PayloadTooLarge implements Exception {
  const _PayloadTooLarge();
}
