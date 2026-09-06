import 'dart:async';

import 'package:better_native_video_player/better_native_video_player.dart';
import 'package:flutter/widgets.dart';

import '../../core/diagnostics/log_buffer.dart' show sanitizeForLog;
import '../../core/settings/performance_settings_service.dart';
import 'playback_engine.dart';
import 'playback_error_message.dart';
import 'video_stats.dart';

/// §engineVendor étape 4 — Implémentation **Media3/ExoPlayer** de
/// [AetherPlaybackEngine], sur le paquet vendoré `packages/aether_video/`.
///
/// ## Ce qu'elle apporte, et pourquoi elle existe
///
/// Elle rend dans une **SurfaceView** au lieu d'une texture Flutter. C'est
/// toute la migration : la doc Android est explicite, « pour du HDR 10 bits, il
/// faut une SurfaceView », dont la Surface reçoit un overlay matériel et part
/// au contrôleur d'affichage **sans copie dans l'UI**. Le HDR natif a été
/// vérifié sur le téléviseur (tags HDR et Dolby).
///
/// ## Les quatre patchs du paquet sont exercés ICI pour la première fois
///
/// `setVolume` au-delà de 100 % (patch 1), bypass SSL scopé (patch 2),
/// `getVideoStats()` (patch 3) et `setResizeMode` (patch 4) étaient compilés
/// depuis l'étape 2 sans que rien ne les appelle. **C'est cette classe qui les
/// met à l'épreuve.**
///
/// ## Ce qui n'a PAS d'équivalent, et qu'on n'émule pas
///
/// ⚠️ Les réglages mpv de §audio/§avSync — `video-sync`, `correct-pts`,
/// `video-latency-hacks` — n'existent pas côté ExoPlayer. **On ne les imite
/// pas** : un réglage émulé approximativement est pire que son absence, parce
/// qu'il fait croire que le problème est traité.
///
/// ✅ **§playerBuffer (2026-09-02) — la dette de tampon est refermée.** Ce
/// commentaire annonçait que « la réponse est le `LoadControl` d'ExoPlayer ou
/// les profils de tampon du paquet ». C'est fait : [_applyBufferProfile] pose
/// `NativeVideoPlayerConfig.global` avant chaque création de lecteur, à partir
/// de `PerfConfig.bufferSeconds`. Sans ça on tournait sur les défauts du paquet
/// (50 s), que personne n'avait choisis.
class Media3Engine implements AetherPlaybackEngine {
  /// ⚠️ **UN SEUL contrôleur, réutilisé, avec des `loadUrl` enchaînés.**
  /// Jamais un contrôleur par média : chacun ouvre une vue native **et une
  /// instance MediaCodec**, or un SoC n'en autorise qu'une poignée. Le balayage
  /// du 2026-08-30 s'était arrêté au premier flux pour cette raison exacte.
  /// C'est aussi ce qui permet de passer d'un épisode au suivant sans
  /// reconstruire la vue (l'équivalent de §episodeMeta côté media_kit).
  late final NativeVideoPlayerController _c;

  final _playing = StreamController<bool>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _error = StreamController<String>.broadcast();
  final _videoParams = StreamController<AetherVideoSize>.broadcast();
  final _subs = <StreamSubscription<dynamic>>[];

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  /// §videoStatsPlus — Dernière position mise en tampon, pour dire l'avance
  /// disponible sans repasser par le natif.
  Duration _buffered = Duration.zero;
  bool _isPlaying = false;

  List<AetherTrack> _audio = const [];
  List<AetherTrack> _subtitles = const [];
  AetherTrack? _curAudio;
  AetherTrack? _curSub;

  /// Dernière langue de sous-titres demandée : le paquet la pose à l'ouverture
  /// (§trackLangPref), il faut donc la connaître avant chaque `loadUrl`.
  String? _subLang;

  /// §stallCount — Dérive blocages / démarrage / temps vu des flux d'événements
  /// que le contrôleur émet déjà : aucun trafic supplémentaire vers le natif.
  late final PlaybackAnalytics _analytics;

  int _stalls = 0;
  Duration _stalled = Duration.zero;
  Duration? _startup;

  /// §stallCount — Instant du dernier `seek`, pour ne pas compter la mise en
  /// tampon qu'il provoque.
  DateTime? _lastSeekAt;

  /// §liveRecover — Message et code de la dernière erreur du moteur.
  String _lastError = '';
  int _lastErrorCode = 0;

  /// Fenêtre d'amnistie après un `seek`.
  ///
  /// ⚠️ **Sans elle, le compteur mentirait**, et un compteur qui ment est pire
  /// que pas de compteur (leçon §qualityTruth). `PlaybackAnalytics` incrémente
  /// dès que l'état passe en `buffering` après avoir lu — or un déplacement dans
  /// la barre provoque exactement ça. Scruter un film aurait donc accusé le
  /// fournisseur d'une dizaine de blocages qu'il n'a pas causés.
  static const Duration _seekAmnesty = Duration(seconds: 4);

  Media3Engine() {
    _applyBufferProfile();
    _c = NativeVideoPlayerController(
      id: 7000,
      autoPlay: true,
      // Les contrôles natifs captureraient le D-pad et empileraient un second
      // spinner par-dessus les nôtres. L'app dessine tout elle-même.
      showNativeControls: false,
      // Le cœur de la migration.
      enableHDR: true,
      allowsPictureInPicture: false,
    );
    _analytics = PlaybackAnalytics(_c);
    _c.addActivityListener(_onActivity);
    _wire();
    // §audio — Même départ que media_kit : les flux IPTV sont souvent encodés
    // à faible niveau. Passe par le `LoudnessEnhancer` du patch 1, puisque
    // ExoPlayer plafonne à 100 %.
    setVolume(AetherVolume.initial);
  }

  /// §playerBuffer — Pose le `LoadControl` d'ExoPlayer depuis `PerfConfig`.
  ///
  /// ⚠️ **Le moment est imposé** : le paquet lit `NativeVideoPlayerConfig.global`
  /// au moment où le lecteur natif est créé (`initialize()`), pas après. On le
  /// pose donc AVANT de construire le contrôleur — et à chaque lecteur, pour que
  /// changer le réglage dans Optimisation prenne effet à la lecture suivante
  /// sans redémarrer l'app.
  ///
  /// Les deux constantes sont volontairement HORS du réglage utilisateur, parce
  /// qu'elles répondent à deux besoins opposés :
  ///   · `bufferForPlaybackMs` bas (1,5 s) = **zapping rapide**. C'est le seul
  ///     chiffre que l'on ressent au changement de chaîne.
  ///   · `bufferForPlaybackAfterRebufferMs` plus haut (5 s) = après un blocage,
  ///     on attend d'avoir un vrai coussin avant de repartir. Repartir trop tôt
  ///     produit la série de micro-coupures, bien plus pénible qu'une attente.
  static void _applyBufferProfile() {
    final seconds = PerformanceSettingsService.config.value.bufferSeconds;
    NativeVideoPlayerConfig.global = NativeVideoPlayerConfig(
      androidBufferConfig: NativeVideoPlayerAndroidBufferConfig(
        minBufferMs: seconds * 1000,
        maxBufferMs: seconds * 2 * 1000,
        bufferForPlaybackMs: 1500,
        bufferForPlaybackAfterRebufferMs: 5000,
      ),
    );
    debugPrint('🎚️ §playerBuffer — tampon ${seconds}s '
        '(min ${seconds}s / max ${seconds * 2}s, départ 1,5s, reprise 5s)');
  }

  /// ⚠️ Les abonnements se posent **avant** `initialize()` : le paquet le
  /// demande explicitement, sinon les premiers événements — dont l'erreur de
  /// chargement, la plus utile — sont perdus.
  void _wire() {
    _subs.add(_c.playerStateStream.listen((s) {
      final playing = s == PlayerActivityState.playing;
      if (playing != _isPlaying) {
        _isPlaying = playing;
        _playing.add(playing);
      }
      _buffering.add(s == PlayerActivityState.buffering ||
          s == PlayerActivityState.loading);
      if (s == PlayerActivityState.completed) _completed.add(true);
      // §liveRecover — L'erreur n'est PLUS émise ici.
      //
      // `playerStateStream` ne porte que l'énumération : le message et le code
      // de la `PlaybackException` n'y sont pas, et cette ligne posait donc
      // `'Lecture impossible'` en dur. Toutes les erreurs se ressemblaient en
      // aval, d'où l'unique réponse possible — tout recharger. C'est aussi ce
      // qui rendait §audioFallback inatteignable (constaté au §tourFix).
      //
      // L'émission se fait désormais dans `_onActivity`, le seul endroit où la
      // charge utile de l'événement est disponible.
      if (s == PlayerActivityState.loaded || s == PlayerActivityState.playing) {
        _refreshTracks();
      }
    }));
    // §stallCount — On ne relaie PAS le compteur du paquet tel quel : il compte
    // toute mise en tampon consécutive à une lecture, `seek` compris.
    _subs.add(_analytics.events.listen((e) {
      switch (e.type) {
        case PlaybackAnalyticsEventType.startup:
          _startup ??= Duration(milliseconds: e.value ?? 0);
        case PlaybackAnalyticsEventType.stallEnded:
          final since = _lastSeekAt == null
              ? null
              : DateTime.now().difference(_lastSeekAt!);
          if (since != null && since < _seekAmnesty) {
            // Mise en tampon due au déplacement demandé par l'utilisateur : ce
            // n'est pas un défaut du fournisseur.
            return;
          }
          _stalls++;
          _stalled += Duration(milliseconds: e.value ?? 0);
          debugPrint('⏸️ §stallCount — blocage n°$_stalls '
              '(${e.value} ms, cumul ${_stalled.inSeconds}s)');
        default:
          break;
      }
    }));
    _subs.add(_c.positionStream.listen((p) => _position = p));
    _subs.add(_c.durationStream.listen((d) => _duration = d));
    _subs.add(_c.bufferedPositionStream.listen((b) => _buffered = b));
    _subs.add(_c.videoSizeStream.listen((s) {
      // ⚠️ `0` signifie « pas encore décodé » → on publie `null`, jamais zéro :
      // §qualityTruth enregistrerait sinon une définition de 0×0 comme une
      // mesure (leçon §hwdecUnknown).
      final w = s.width.round();
      final h = s.height.round();
      _videoParams.add(AetherVideoSize(w > 0 ? w : null, h > 0 ? h : null));
    }));
  }

  /// §liveRecover — Capte le message ET le code de l'erreur, puis émet.
  void _onActivity(PlayerActivityEvent e) {
    if (e.state != PlayerActivityState.error) return;
    _lastError = (e.data?['message'] as String?)?.trim() ?? '';
    _lastErrorCode = (e.data?['errorCode'] as int?) ?? 0;
    final name = e.data?['errorCodeName'] as String?;
    debugPrint('❌ §liveRecover — erreur moteur : '
        '${name ?? 'inconnue'} ($_lastErrorCode) — ${sanitizeForLog(_lastError)}');
    // §userError — Ce qui part ici finit À L'ÉCRAN (`player_page` l'affiche
    // tel quel). Le message brut de Media3 est anglais et non filtré → on
    // parle à partir du code d'erreur, jamais du texte.
    _error.add(playbackErrorMessage(codeName: name, rawMessage: _lastError));
  }

  /// §liveRecover — cf. `AetherPlaybackEngine.recoverInPlace`.
  @override
  Future<bool> recoverInPlace() async {
    try {
      final ok = await _c.retryPlayback();
      if (ok) {
        debugPrint('🔁 §liveRecover — reprise en place (sans réouverture)');
        _lastError = '';
        _lastErrorCode = 0;
      }
      return ok;
    } catch (e) {
      debugPrint('⚠️ §liveRecover — reprise en place impossible : $e');
      return false;
    }
  }

  Future<void> _refreshTracks() async {
    try {
      final a = await _c.getAvailableAudioTracks();
      final t = await _c.getAvailableSubtitleTracks();
      _audio = a
          .map((e) => AetherTrack(
                id: '${e.index}',
                title: e.displayName,
                language: e.language,
                // §castAudio — §engineVendor patch 11 : le codec de la piste,
                // pour décider ce qu'un récepteur Chromecast saura décoder.
                codec: e.codec,
                channels: e.channelCount,
              ))
          .toList();
      _subtitles = t
          .map((e) => AetherTrack(
                id: '${e.index}',
                title: e.displayName,
                language: e.language,
              ))
          .toList();
      final selA = a.where((e) => e.isSelected);
      final selS = t.where((e) => e.isSelected);
      _curAudio = selA.isEmpty ? null : _audio[a.indexOf(selA.first)];
      _curSub = selS.isEmpty ? null : _subtitles[t.indexOf(selS.first)];
    } catch (e) {
      debugPrint('⚠️ Media3Engine — pistes illisibles : $e');
    }
  }

  // ── Ouverture ──────────────────────────────────────────────────────────────

  /// §nowPlaying — Traduit le descriptif neutre en modèle du paquet.
  ///
  /// ⚠️ `null` reste `null` : c'est l'ABSENCE de `mediaInfo` qui empêche le
  /// natif de créer la session et de démarrer le service de premier plan
  /// (`VideoPlayerObserver.onIsPlayingChanged`). Traduire `null` en objet vide
  /// ferait apparaître une notification « Video » sans titre sur téléviseur.
  static NativeVideoPlayerMediaInfo? _mediaInfoFor(AetherNowPlaying? n) {
    if (n == null) return null;
    return NativeVideoPlayerMediaInfo(
      title: n.title,
      subtitle: n.subtitle,
      artworkUrl: n.artworkUrl,
    );
  }

  @override
  Future<void> open(String url,
      {Duration? start,
      String? audioLang,
      String? subLang,
      AetherNowPlaying? nowPlaying}) async {
    _subLang = subLang;
    await _c.initialize();
    // §trackLangPref — Posée AVANT l'ouverture : changer de piste après coup
    // re-demuxe le flux ~3 s plus tard (« le film se relance »).
    await _applyLangPrefs(audioLang);
    await _c.loadUrl(
      url: url,
      // §nowPlaying — par chargement, pas par contrôleur (§engineVendor patch 9).
      mediaInfo: _mediaInfoFor(nowPlaying),
      // §iptvUaCompat — Les panels Xtream rejettent les UA navigateur par un
      // 500 muet : le profil de requête doit être identique à celui de Dio.
      headers: const {'User-Agent': 'IPTVSmartersPro'},
      // §resumeStart — Position passée NATIVEMENT : un `seek` après ouverture
      // est parfois avalé pendant le buffering initial.
      startAt: start,
      // §engineVendor patch 2 — Les panels servent souvent en HTTPS avec un
      // certificat auto-signé, et media_kit posait `tls-verify=no` : ne pas le
      // reproduire casserait des flux qui marchent aujourd'hui.
      allowInvalidCertificate: true,
    );
    await _applySubPreference();
  }

  @override
  Future<void> openFile(String path,
      {Duration? start,
      String? audioLang,
      String? subLang,
      AetherNowPlaying? nowPlaying}) async {
    _subLang = subLang;
    await _c.initialize();
    await _applyLangPrefs(audioLang);
    await _c.load(
      url: 'file://$path',
      startAt: start,
      mediaInfo: _mediaInfoFor(nowPlaying),
    );
    await _applySubPreference();
  }

  /// §trackLangPref — Préférence de langue audio.
  ///
  /// ⚠️ Le paquet amont ne gérait QUE les sous-titres : la préférence audio
  /// était silencieusement perdue et un film multi-langue repartait sur la
  /// piste par défaut du fichier (§engineVendor patch 8).
  Future<void> _applyLangPrefs(String? audioLang) async {
    if (audioLang == null || audioLang.isEmpty) return;
    await _c.setPreferredAudioLanguage(audioLang);
  }

  /// §trackLangPref — `subLang == 'no'` signifie « sous-titres désactivés ».
  Future<void> _applySubPreference() async {
    if (_subLang == 'no') {
      try {
        await _c.setSubtitleTrack(NativeVideoPlayerSubtitleTrack.off());
      } catch (_) {}
    }
  }

  // ── Commandes ──────────────────────────────────────────────────────────────

  @override
  Future<void> play() => _c.play();

  @override
  Future<void> pause() => _c.pause();

  @override
  Future<void> playOrPause() => _isPlaying ? _c.pause() : _c.play();

  @override
  Future<void> seek(Duration position) {
    // §stallCount — Marqué AVANT l'appel : la mise en tampon suit de quelques
    // millisecondes, et c'est elle qu'il faut amnistier.
    _lastSeekAt = DateTime.now();
    return _c.seekTo(position);
  }

  @override
  Future<void> setRate(double rate) => _c.setSpeed(rate);

  /// §engineVendor patch 1 — L'app parle en **0→200**, le paquet en **0→2.0**.
  /// Au-delà de 1.0 le natif bascule sur un `LoudnessEnhancer`, seul capable
  /// d'amplifier (ExoPlayer atténue, il n'amplifie pas).
  @override
  Future<void> setVolume(double volume) => _c.setVolume(volume / 100.0);

  @override
  Future<void> setAudioTrack(AetherTrack track) async {
    final i = int.tryParse(track.id);
    if (i == null) return;
    final all = await _c.getAvailableAudioTracks();
    final match = all.where((e) => e.index == i);
    if (match.isEmpty) return;
    await _c.setAudioTrack(match.first);
    await _refreshTracks();
  }

  @override
  Future<void> setSubtitleTrack(AetherTrack track) async {
    final i = int.tryParse(track.id);
    if (i == null) return;
    final all = await _c.getAvailableSubtitleTracks();
    final match = all.where((e) => e.index == i);
    if (match.isEmpty) return;
    await _c.setSubtitleTrack(match.first);
    await _refreshTracks();
  }

  /// §audioFallback — Lire **sans son** plutôt qu'abandonner.
  /// ⚠️ Sans objet ici en pratique : ExoPlayer ne remonte pas d'erreur de piste
  /// audio isolée comme mpv. Implémenté pour respecter le contrat.
  @override
  Future<void> disableAudio() async {}

  // ── État ───────────────────────────────────────────────────────────────────

  @override
  Duration get position => _position;

  @override
  Duration get duration => _duration;

  @override
  bool get playing => _isPlaying;

  @override
  List<AetherTrack> get audioTracks => _audio;

  @override
  List<AetherTrack> get subtitleTracks => _subtitles;

  @override
  AetherTrack? get currentAudioTrack => _curAudio;

  @override
  AetherTrack? get currentSubtitleTrack => _curSub;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Stream<bool> get bufferingStream => _buffering.stream;

  @override
  Stream<bool> get completedStream => _completed.stream;

  @override
  Stream<String> get errorStream => _error.stream;

  @override
  Stream<Duration> get positionStream => _c.positionStream;

  @override
  Stream<Duration> get durationStream => _c.durationStream;

  @override
  Stream<Duration> get bufferStream => _c.bufferedPositionStream;

  @override
  Stream<AetherVideoSize> get videoParamsStream => _videoParams.stream;

  // ── Rendu ──────────────────────────────────────────────────────────────────

  /// §engineVendor patch 4 — §videoFit passe par `setResizeMode` : le paquet
  /// amont figeait `RESIZE_MODE_FIT`, le menu « format d'image » aurait été
  /// sans effet.
  @override
  Widget buildSurface(BoxFit fit) {
    final mode = switch (fit) {
      BoxFit.cover => AetherResizeMode.zoom,
      BoxFit.fill => AetherResizeMode.fill,
      _ => AetherResizeMode.fit,
    };
    if (mode != _c.resizeMode) {
      // Après le frame : la vue native doit exister pour recevoir l'ordre.
      WidgetsBinding.instance.addPostFrameCallback((_) => _c.setResizeMode(mode));
    }
    return NativeVideoPlayer(controller: _c);
  }

  // ── Diagnostic ─────────────────────────────────────────────────────────────

  @override
  AetherPlaybackHealth get health => AetherPlaybackHealth(
        stalls: _stalls,
        stalled: _stalled,
        startup: _startup,
        watched: _analytics.watchedDuration,
      );

  /// §engineVendor patch 3 — §videoStats depuis l'`AnalyticsListener`.
  ///
  /// ⚠️ **Un champ que le natif ne renseigne pas reste `null`**, jamais zéro :
  /// un zéro se lirait comme une mesure et ferait conclure de travers — c'est
  /// exactement la leçon §hwdecUnknown. (Les champs que seul mpv savait
  /// remplir ont été retirés du modèle au §tourFix, cf. `video_stats.dart`.)
  @override
  Future<VideoStatsSnapshot> readStats() async {
    final m = await _c.getVideoStats();
    if (m == null) return const VideoStatsSnapshot();
    final hw = m['hardware'] as bool?;
    final transfer = m['colorTransfer'] as int? ?? -1;
    return VideoStatsSnapshot(
      width: _positive(m['width']),
      height: _positive(m['height']),
      // `hwdec` est un mot mpv. On y remet une valeur LISIBLE plutôt que rien,
      // pour que l'encart continue de dire « matériel · <décodeur> ».
      hwdec: hw == null ? null : (hw ? (m['decoder'] as String? ?? 'matériel') : 'no'),
      codec: m['codec'] as String?,
      decoder: m['decoder'] as String?,
      containerFps: _positiveDouble(m['frameRate']),
      videoBitrate: _positive(m['bitrate']),
      droppedFrames: m['droppedFrames'] as int?,
      // §tourFix — 6 = ST2084 (HDR10), 7 = HLG (`C.COLOR_TRANSFER_*`) : c'est
      // ce qui dit que le flux est HDR, au lieu de le supposer. Les deux sont
      // acceptés ici, mais l'ordre compte le jour où l'encart distinguera
      // « HDR10 » de « HLG » — une première rédaction les avait inversés.
      // -1 = `colorInfo` absent → Media3 ne
      // SAIT pas → `null`, jamais un faux « non » (leçon §hwdecUnknown).
      // Remplace l'astuce `signalPeak: 2.0` posée en dur, qui figeait la
      // ligne HDR de l'encart à « oui ».
      hdr: transfer < 0 ? null : (transfer == 6 || transfer == 7),
      vo: 'SurfaceView',
      // §stallCount — Ce que mpv ne savait pas dire : combien de fois la
      // lecture s'est réellement arrêtée pour attendre le réseau.
      stalls: _stalls,
      stalledMs: _stalled.inMilliseconds,
      startupMs: _startup?.inMilliseconds,
      // §videoStatsPlus — Les MESURES, à distinguer des déclarations du flux.
      renderedFps: _positiveDouble(m['renderedFps']),
      skippedFrames: _positive(m['skippedFrames']),
      networkBitrate: _positive(m['networkBitrate']),
      bytesTransferred: _positive(m['bytesTransferred']),
      // Gratuit et directement parlant : le tampon se remplit-il vraiment ?
      bufferAhead: _buffered > _position ? _buffered - _position : Duration.zero,
      audioCodec: m['audioCodec'] as String?,
      audioDecoder: m['audioDecoder'] as String?,
      audioBitrate: _positive(m['audioBitrate']),
      audioChannels: _positive(m['audioChannels']),
      audioSampleRate: _positive(m['audioSampleRate']),
    );
  }

  static int? _positive(Object? v) {
    final n = (v is num) ? v.toInt() : null;
    return (n != null && n > 0) ? n : null;
  }

  static double? _positiveDouble(Object? v) {
    final n = (v is num) ? v.toDouble() : null;
    return (n != null && n > 0) ? n : null;
  }

  /// ⚠️ **Ordre imposé par la vue native.** À la fermeture du lecteur, Flutter
  /// démonte le widget AVANT que `dispose()` ne s'exécute : la vue de plateforme
  /// n'existe déjà plus, et tout appel qui la vise échoue en
  /// `PlatformException(NO_VIEW)`. Ce n'est pas une panne — la lecture s'arrête
  /// bien — mais ça pollue le journal §tvLogs, seul canal de diagnostic sur
  /// téléviseur, et un bruit récurrent finit par masquer une vraie erreur.
  ///
  /// On coupe donc les abonnements en premier, et on laisse `dispose()` du
  /// contrôleur faire l'arrêt : c'est lui qui appelle `player.stop()` côté natif
  /// sans passer par la vue.
  @override
  void dispose() {
    // §engineVendor patch 7 — Couper la lecture AVANT tout le reste.
    //
    // Mesuré sur téléviseur : la sortie du lecteur prenait 1,5 s, interface
    // figée. `dispose()` du paquet est asynchrone et n'est pas attendu ici
    // (l'interface impose une signature synchrone) : la surface, le décodeur
    // Dolby Vision et la connexion réseau restaient donc tenus pendant que
    // Flutter reconstruisait la fiche.
    //
    // ⚠️ Volontairement NON attendu : `dispose()` doit rendre la main tout de
    // suite. L'ordre part au natif avant la destruction de la vue, c'est ce qui
    // compte.
    _c.stopNow();
    for (final s in _subs) {
      s.cancel();
    }
    _c.removeActivityListener(_onActivity);
    _analytics.dispose();
    _playing.close();
    _buffering.close();
    _completed.close();
    _error.close();
    _videoParams.close();
    _c.dispose();
  }
}
