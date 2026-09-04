import 'dart:async';
import 'dart:io';

import 'package:better_native_video_player/cast.dart' as nvp;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/utils/device_battery.dart';

import '../../core/utils/log_sanitizer.dart';
import '../../feature/player/cast_policy.dart';
import '../../feature/player/cast_relay_policy.dart';
import 'watch_progress_service.dart';

export 'package:better_native_video_player/cast.dart'
    show CastDevice, CastSessionStatus, CastMediaTrack;

/// §castSend — Erreur en clair, destinée à l'écran (§userError). Le message
/// ne contient jamais d'adresse ni d'identifiant.
class CastException implements Exception {
  const CastException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Ce qui est en train d'être diffusé, et sur quoi.
@immutable
class CastState {
  const CastState({
    required this.device,
    required this.url,
    required this.title,
    required this.live,
    required this.status,
    this.subtitle,
    this.imageUrl,
    this.progressKey,
    this.batteryWarning,
  });

  final nvp.CastDevice device;

  /// Adresse envoyée au récepteur (déjà réécrite par `castUrlFor`).
  final String url;
  final String title;
  final String? subtitle;
  final String? imageUrl;

  /// Chaîne en direct : pas de position utile, pas de reprise.
  final bool live;

  /// Clé de reprise (§1e, `PlayerMedia.resumeKey`) : la progression suit le
  /// TÉLÉVISEUR tant qu'il lit, même lecteur fermé. `null` = pas de suivi.
  final String? progressKey;

  /// Dernier statut poussé par le récepteur.
  final nvp.CastSessionStatus status;

  /// §castBattery — Alerte batterie basse (`castBatteryWarning`), `null`
  /// tant que tout va bien. Une seule vérité pour le panneau ET la notif.
  final String? batteryWarning;

  bool get playing => status.isPlaying;
  bool get buffering => status.playerState == 'BUFFERING';
  Duration get position => status.position;
  Duration? get duration => status.duration;

  CastState copyWith({
    nvp.CastSessionStatus? status,
    String? batteryWarning,
    bool clearBatteryWarning = false,
  }) =>
      CastState(
        device: device,
        url: url,
        title: title,
        subtitle: subtitle,
        imageUrl: imageUrl,
        live: live,
        progressKey: progressKey,
        status: status ?? this.status,
        batteryWarning: clearBatteryWarning
            ? null
            : (batteryWarning ?? this.batteryWarning),
      );
}

/// §castSend — Façade sur le Cast du paquet vendoré
/// (`package:better_native_video_player/cast.dart`, point d'entrée SÉPARÉ du
/// barrel : découverte mDNS + session CASTV2 en Dart pur, sans SDK Google).
///
/// **Un seul état, global** (`state`) : la diffusion survit à la fermeture du
/// lecteur — c'est tout l'intérêt d'envoyer l'image sur le téléviseur — et la
/// notification (`CastNotificationBridge`) comme le lecteur ne font que LIRE
/// ce notifier. Rien d'autre ne connaît la session.
///
/// ⚠️ **Le récepteur va chercher l'URL lui-même** : voir `cast_policy.dart`
/// pour ce que ça interdit (UA IPTV, cookies, certificats, CORS) et [probe],
/// qui le vérifie AVANT de proposer la diffusion.
///
/// ⚠️ **Le récepteur ne pousse son statut que sur CHANGEMENT d'état**
/// (constaté sur appareil : position figée à 02:28 pendant toute la
/// diffusion). La position, il faut la lui DEMANDER — d'où [_poll], une
/// requête `GET_STATUS` par seconde tant qu'une diffusion est active.
abstract final class CastService {
  static final ValueNotifier<CastState?> state =
      ValueNotifier<CastState?>(null);

  /// Messages destinés à l'utilisateur (fin de lecture sur le téléviseur,
  /// flux refusé par le récepteur, connexion perdue). Le lecteur les affiche
  /// en snackbar ; hors du lecteur, ils sont simplement perdus — la
  /// notification disparaît, ce qui en dit déjà assez.
  static Stream<String> get messages => _messages.stream;
  static final StreamController<String> _messages =
      StreamController<String>.broadcast();

  static nvp.CastSession? _session;
  static StreamSubscription<nvp.CastSessionStatus>? _statusSub;
  static Timer? _poll;

  /// Après un `loadMedia`, le récepteur passe par IDLE (ancien média annulé)
  /// avant BUFFERING : on ignore les IDLE jusqu'à ce qu'il ait vraiment
  /// commencé, sinon on prendrait notre propre chargement pour une fin.
  static bool _awaitingStart = false;

  /// Vrai entre le premier PLAYING/BUFFERING d'un chargement et son IDLE.
  static bool _started = false;

  /// §1e — Dernière sauvegarde de progression (une toutes les 10 s, comme le
  /// lecteur local), pour que « Reprendre » sache où le téléviseur en était.
  static DateTime _lastProgressSave = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _progressInterval = Duration(seconds: 10);

  /// §castAudio — Une seule tentative de choix de piste audio par chargement :
  /// si le récepteur ignore la demande, insister ne changerait rien et
  /// noierait le journal.
  static bool _triedAudioSelect = false;

  static bool get isActive => state.value != null;

  // ── Découverte ────────────────────────────────────────────────────────────

  /// Balayage mDNS `_googlecast._tcp` sur le réseau local. Lève une
  /// [CastException] en français si le réseau bloque la requête (téléphone en
  /// 4G, réseau invité avec isolation des clients).
  static Future<List<nvp.CastDevice>> discover({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    try {
      final devices = await nvp.CastDeviceDiscovery.discover(timeout: timeout);
      debugPrint('📡 CastService.discover : ${devices.length} appareil(s) — '
          '${devices.map((d) => d.displayName).join(', ')}');
      devices.sort((a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ));
      return devices;
    } on nvp.CastDiscoveryException catch (e) {
      debugPrint('❌ CastService.discover : ${e.message}');
      throw const CastException(
        'Recherche impossible sur ce réseau. Le téléphone doit être sur le '
        'même WiFi que le téléviseur, hors réseau invité.',
      );
    }
  }

  // ── Sonde ─────────────────────────────────────────────────────────────────

  /// UA d'un récepteur Cast : ce qui compte, c'est que ce n'est PAS
  /// `IPTVSmartersPro` — un panel qui rejette les UA navigateur rejettera le
  /// Chromecast exactement comme il rejette cette sonde (§iptvUaCompat).
  static const String _receiverUa =
      'Mozilla/5.0 (X11; Linux armv7l) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.0.0 Safari/537.36 CrKey/1.56.500000';

  /// Demande [url] **comme le récepteur le ferait** : sans UA IPTV, sans
  /// cookie, sans tolérance de certificat. Rend `null` seulement si la sonde
  /// elle-même n'a pas pu tourner (jamais pour une réponse, même 500).
  ///
  /// ⚠️ `ResponseType.stream` + fermeture forcée : un flux TS en direct ne
  /// finit jamais, on ne veut que les en-têtes.
  static Future<CastProbe?> probe(
    String url, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final dio = Dio(BaseOptions(
      connectTimeout: timeout,
      receiveTimeout: timeout,
      sendTimeout: timeout,
      followRedirects: true,
      maxRedirects: 5,
      validateStatus: (_) => true,
      responseType: ResponseType.stream,
      headers: {'User-Agent': _receiverUa, 'Accept': '*/*'},
    ));
    try {
      final r = await dio.get<ResponseBody>(
        url,
        options: Options(headers: {'Range': 'bytes=0-1'}),
      );
      final bool cors = r.headers.value('access-control-allow-origin') != null;
      debugPrint('🔍 CastService.probe ${redactUrl(url)} → HTTP '
          '${r.statusCode} cors=$cors');
      return CastProbe(statusCode: r.statusCode, corsAllowed: cors);
    } on DioException catch (e) {
      final Object? cause = e.error;
      final bool tls = e.type == DioExceptionType.badCertificate ||
          cause is HandshakeException ||
          cause is TlsException ||
          (cause is SocketException &&
              cause.message.toLowerCase().contains('handshake'));
      if (tls) {
        debugPrint('🔍 CastService.probe ${redactUrl(url)} → TLS refusé');
        return const CastProbe(tlsFailed: true);
      }
      if (e.response != null) {
        return CastProbe(statusCode: e.response!.statusCode);
      }
      debugPrint('🔍 CastService.probe ${redactUrl(url)} → injoignable '
          '(${e.type.name})');
      return const CastProbe(unreachable: true);
    } catch (e) {
      debugPrint('⚠️ CastService.probe : $e');
      return null;
    } finally {
      dio.close(force: true);
    }
  }

  // ── Session ───────────────────────────────────────────────────────────────

  /// Connecte [device] (ou réutilise la session ouverte sur le même appareil)
  /// et y charge [url]. Lève une [CastException] en clair en cas d'échec.
  ///
  /// [progressKey] — clé de reprise du contenu (`PlayerMedia.resumeKey`,
  /// donc l'adresse D'ORIGINE, pas celle réécrite pour le récepteur) : la
  /// progression est sauvée toutes les 10 s depuis la position du
  /// TÉLÉVISEUR, lecteur ouvert ou non. `null` pour le direct et le replay.
  static Future<void> start({
    required nvp.CastDevice device,
    required String url,
    required String contentType,
    required bool live,
    required String title,
    String? subtitle,
    String? imageUrl,
    String? progressKey,
    Duration startAt = Duration.zero,
    String? streamType,
  }) async {
    nvp.CastSession? session = _session;
    if (session == null ||
        !session.isConnected ||
        session.device.id != device.id) {
      await _closeSession();
      try {
        session = await nvp.CastSession.connect(device);
      } on TimeoutException {
        throw CastException(
          '${device.displayName} ne répond pas. Vérifie qu\'il est allumé et '
          'sur le même réseau.',
        );
      } catch (e) {
        debugPrint('❌ CastService.connect ${device.displayName} : $e');
        throw CastException(
          'Connexion à ${device.displayName} impossible.',
        );
      }
      _session = session;
      _statusSub = session.statusStream.listen(
        _onStatus,
        onDone: _onSessionClosed,
        onError: (Object e) {
          debugPrint('⚠️ CastService.status : $e');
          _onSessionClosed();
        },
      );
    } else {
      // Nouveau contenu sur la même session : clore proprement la
      // progression du précédent avant d'écraser l'état.
      _saveProgress(force: true);
    }

    _awaitingStart = true;
    _started = false;
    _triedAudioSelect = false;
    _lastProgressSave = DateTime.now();
    state.value = CastState(
      device: device,
      url: url,
      title: title,
      subtitle: subtitle,
      imageUrl: imageUrl,
      live: live,
      progressKey: live ? null : progressKey,
      status: const nvp.CastSessionStatus(playerState: 'BUFFERING'),
    );
    debugPrint('📡 CastService.start → ${device.displayName} '
        '(${streamType ?? (live ? 'LIVE' : 'BUFFERED')}, $contentType, '
        'depuis ${startAt.inSeconds}s) ${redactUrl(url)}');
    try {
      await session.loadMedia(
        contentUrl: url,
        contentType: contentType,
        // ⚠️ **Ce que le récepteur doit croire ≠ ce que l'app sait.** Un film
        // relayé est un film pour nous (reprise, position, pas de badge
        // DIRECT), mais son manifeste GRANDIT encore : annoncé « BUFFERED »,
        // le récepteur cherche une durée totale, n'en trouve pas et abandonne
        // — 400 ms, mesuré trois fois le 2026-09-04. D'où ce réglage séparé.
        streamType: streamType ?? (live ? 'LIVE' : 'BUFFERED'),
        title: title,
        subtitle: subtitle,
        imageUrl: imageUrl,
        startAt: live ? Duration.zero : startAt,
      );
    } catch (e) {
      debugPrint('❌ CastService.loadMedia : $e');
      // ⚠️ Sur une session RÉUTILISÉE (nouveau contenu, même téléviseur),
      // le poll et la veille batterie de la diffusion précédente tournent
      // déjà : sans ces deux lignes ils survivaient à l'échec et battaient
      // jusqu'à la fin du processus.
      _poll?.cancel();
      _poll = null;
      _stopBatteryWatch();
      state.value = null;
      throw const CastException(
        "Le téléviseur n'a pas accepté ce flux.",
      );
    }
    _startPolling();
    _startBatteryWatch();
  }

  /// §castBattery — Veille batterie pendant la diffusion : le téléphone porte
  /// la session (et tout le film en relais). Sous `kCastLowBatteryPercent`
  /// hors charge, `CastState.batteryWarning` porte l'alerte — lue par le
  /// panneau du lecteur ET par la notification (rouge). Toutes les 30 s : la
  /// batterie ne bouge pas plus vite, et on ne réveille pas le natif pour rien.
  static Timer? _batteryTimer;

  static void _startBatteryWatch() {
    _batteryTimer?.cancel();
    unawaited(_checkBattery());
    _batteryTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_checkBattery()),
    );
  }

  static void _stopBatteryWatch() {
    _batteryTimer?.cancel();
    _batteryTimer = null;
  }

  static Future<void> _checkBattery() async {
    if (state.value == null) return;
    final b = await DeviceBattery.read();
    final CastState? current = state.value;
    if (current == null) return;
    final String? warning =
        castBatteryWarning(percent: b.percent, charging: b.charging);
    if (warning == current.batteryWarning) return;
    if (warning != null) {
      debugPrint('🔋 §castBattery — $warning');
    } else if (current.batteryWarning != null) {
      debugPrint('🔋 §castBattery — alerte levée');
    }
    state.value = warning == null
        ? current.copyWith(clearBatteryWarning: true)
        : current.copyWith(batteryWarning: warning);
  }

  /// Le récepteur ne pousse `MEDIA_STATUS` que sur changement d'état : sans
  /// cette interrogation, position et durée resteraient celles du chargement.
  static void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) {
      final s = _session;
      if (s == null || !s.isConnected || state.value == null) return;
      s.requestStatus();
    });
  }

  static void _onStatus(nvp.CastSessionStatus s) {
    final current = state.value;
    if (current == null) return;

    if (s.playerState == 'PLAYING' || s.playerState == 'BUFFERING') {
      _awaitingStart = false;
      _started = true;
    }
    if (s.playerState == 'IDLE') {
      if (_awaitingStart) {
        // Ancien média annulé par NOTRE chargement : pas une fin.
        return;
      }
      if (_started) {
        final String? msg = castIdleMessage(s.idleReason);
        debugPrint(
            '📡 CastService : IDLE (${s.idleReason}) → fin de diffusion');
        // §1e — Fin naturelle : position = durée → le service efface la
        // reprise (règle des 95 %), le film n'apparaît plus dans « Reprendre ».
        if (s.idleReason == 'FINISHED') {
          final Duration? dur = current.duration;
          final String? key = current.progressKey;
          if (key != null && dur != null && dur > Duration.zero) {
            WatchProgressService.saveProgress(key, dur, dur);
          }
        } else {
          _saveProgress(force: true);
        }
        _poll?.cancel();
        _poll = null;
        _stopBatteryWatch();
        state.value = null;
        _started = false;
        if (msg != null) _messages.add(msg);
        return;
      }
    }
    state.value = current.copyWith(status: s);
    _maybeSelectAudioTrack(s);
    if (s.isPlaying) _saveProgress();
  }

  /// §castAudio — Le récepteur annonce-t-il des pistes audio, et si oui,
  /// peut-on lui demander celle qu'il sait décoder ?
  ///
  /// ⚠️ **C'est une TENTATIVE, pas une garantie.** Pour un fichier progressif
  /// (MKV/MP4 servi tel quel), le récepteur lit la piste par DÉFAUT du
  /// conteneur ; Google ne documente `EDIT_TRACKS_INFO` que pour HLS et DASH.
  /// D'où le journal : il dit ce que le récepteur a réellement annoncé, ce qui
  /// est la seule façon de savoir si cette voie existe sur un appareil donné.
  static void _maybeSelectAudioTrack(nvp.CastSessionStatus s) {
    if (_triedAudioSelect) return;
    final tracks = s.mediaTracks;
    if (tracks.isEmpty) return;
    _triedAudioSelect = true;

    debugPrint('🔊 CastService — pistes annoncées par le récepteur '
        '(${tracks.length}) : ${tracks.join(' | ')}');

    final audio = tracks.where((t) => t.isAudio).toList();
    if (audio.isEmpty) {
      debugPrint('🔊 CastService — aucune piste AUDIO annoncée : le récepteur '
          'lira la piste par défaut du conteneur, sans choix possible.');
      return;
    }
    final compatible = audio.where(
      (t) => castAudioSupport(t.contentType) == CastAudioSupport.ok,
    );
    if (compatible.isEmpty) {
      debugPrint('🔊 CastService — aucune des ${audio.length} pistes audio '
          "annoncées n'est décodable par le récepteur : rien à demander.");
      return;
    }
    final target = compatible.first;
    debugPrint('🔊 CastService — demande de la piste #${target.trackId} '
        '(${target.contentType ?? '?'} ${target.language ?? ''})');
    _session?.setActiveTracks([target.trackId]);
  }

  /// §1e — Sauvegarde la position du téléviseur sous la clé de reprise du
  /// contenu. Throttlée à une toutes les 10 s (comme le lecteur local), sauf
  /// [force] (arrêt, changement de contenu).
  static void _saveProgress({bool force = false}) {
    final s = state.value;
    if (s == null) return;
    final String? key = s.progressKey;
    final Duration? dur = s.duration;
    if (key == null || dur == null || dur <= Duration.zero) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastProgressSave) < _progressInterval) return;
    _lastProgressSave = now;
    WatchProgressService.saveProgress(key, s.position, dur);
  }

  static void _onSessionClosed() {
    final bool wasActive = state.value != null;
    debugPrint('📡 CastService : session fermée (active=$wasActive)');
    if (wasActive) _saveProgress(force: true);
    _poll?.cancel();
    _poll = null;
    _stopBatteryWatch();
    _statusSub?.cancel();
    _statusSub = null;
    _session = null;
    state.value = null;
    _started = false;
    _awaitingStart = false;
    if (wasActive) _messages.add('Connexion au téléviseur perdue.');
  }

  static Future<void> play() async => _session?.play();
  static Future<void> pause() async => _session?.pause();

  static Future<void> toggle() async {
    final s = state.value;
    if (s == null) return;
    if (s.playing) {
      await pause();
    } else {
      await play();
    }
  }

  static Future<void> seek(Duration position) async {
    final s = state.value;
    if (s == null || s.live) return;
    final Duration max = s.duration ?? position;
    final Duration target = position < Duration.zero
        ? Duration.zero
        : (position > max ? max : position);
    await _session?.seek(target);
  }

  static Future<void> seekBy(Duration delta) async {
    final s = state.value;
    if (s == null) return;
    await seek(s.position + delta);
  }

  /// Arrête la diffusion et ferme la session. Idempotent. La progression est
  /// sauvée AVANT : c'est elle que « Reprendre sur le téléphone » relit.
  static Future<void> stop() async {
    _saveProgress(force: true);
    _poll?.cancel();
    _poll = null;
    _stopBatteryWatch();
    final session = _session;
    if (session != null && session.isConnected && state.value != null) {
      try {
        await session.stop();
      } catch (_) {}
    }
    state.value = null;
    _started = false;
    _awaitingStart = false;
    await _closeSession();
    debugPrint('📡 CastService.stop');
  }

  static Future<void> _closeSession() async {
    _poll?.cancel();
    _poll = null;
    _stopBatteryWatch();
    await _statusSub?.cancel();
    _statusSub = null;
    final session = _session;
    _session = null;
    if (session != null) {
      try {
        await session.close();
      } catch (_) {}
    }
  }

  /// Tests uniquement.
  @visibleForTesting
  static void resetForTest() {
    _poll?.cancel();
    _poll = null;
    _stopBatteryWatch();
    _statusSub?.cancel();
    _statusSub = null;
    _session = null;
    state.value = null;
    _started = false;
    _awaitingStart = false;
    _lastProgressSave = DateTime.fromMillisecondsSinceEpoch(0);
  }
}
