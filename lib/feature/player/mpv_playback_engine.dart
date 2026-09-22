import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'playback_engine.dart';
import 'video_stats.dart';
import '../../data/services/track_preferences_service.dart';

/// §dualEngine — Implémentation **media_kit / libmpv** de [AetherPlaybackEngine]
/// pour Windows Desktop.
///
/// Permet à AetherStream sous Windows de conserver le décodage vidéo matériel
/// DirectX 11 (D3D11va / DXVA2) et l'intégralité des fonctionnalités IPTV (HLS,
/// MKV, TS, multi-pistes, sous-titres, amplification sonore 200%) pendant
/// qu'Android utilise Media3.
class MpvPlaybackEngine implements AetherPlaybackEngine {
  late final Player player;
  late final VideoController videoController;

  final _playing = StreamController<bool>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _error = StreamController<String>.broadcast();
  final _videoParams = StreamController<AetherVideoSize>.broadcast();
  final _qualitiesCtrl = StreamController<List<AetherQuality>>.broadcast();
  AetherQuality? _currentQuality;
  bool _lastErrorAudio = false;
  AetherTrack? _lastErrorAudioTrack;
  final _subs = <StreamSubscription<dynamic>>[];

  DateTime? _openTime;
  DateTime? _firstPlayTime;
  DateTime? _bufferingStartTime;
  DateTime? _lastSeekAt;

  int _stalls = 0;
  Duration _stalled = Duration.zero;
  Duration _watched = Duration.zero;
  DateTime? _lastWatchTick;
  Timer? _watchTimer;

  static const Duration _seekAmnesty = Duration(seconds: 4);

  MpvPlaybackEngine() {
    player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 64 * 1024 * 1024, // 64 Mo : marge anti-désync sur flux HLS
        logLevel: MPVLogLevel.warn,
      ),
    );

    videoController = VideoController(player);

    _applyMpvTuning();

    // Volume initial boosté (125-130 %)
    player.setVolume(AetherVolume.initial);

    // Relais des streams
    _subs.add(player.stream.playing.listen((p) {
      _playing.add(p);
      if (p) {
        if (_firstPlayTime == null && _openTime != null) {
          _firstPlayTime = DateTime.now();
        }
        _lastWatchTick = DateTime.now();
      } else {
        if (_lastWatchTick != null) {
          _watched += DateTime.now().difference(_lastWatchTick!);
          _lastWatchTick = null;
        }
      }
    }));

    _subs.add(player.stream.buffering.listen((b) {
      _buffering.add(b);
      final now = DateTime.now();
      if (b) {
        final recentSeek = _lastSeekAt != null &&
            now.difference(_lastSeekAt!) < _seekAmnesty;
        if (!recentSeek && _firstPlayTime != null) {
          _stalls++;
          _bufferingStartTime = now;
        }
      } else {
        if (_bufferingStartTime != null) {
          _stalled += now.difference(_bufferingStartTime!);
          _bufferingStartTime = null;
        }
      }
    }));

    _subs.add(player.stream.completed.listen(_completed.add));
    _subs.add(player.stream.error.listen((err) {
      _lastErrorAudio = err.toLowerCase().contains('audio');
      _lastErrorAudioTrack = _lastErrorAudio ? currentAudioTrack : null;
      _error.add(err);
    }));
    _subs.add(player.stream.videoParams.listen((p) {
      _videoParams.add(AetherVideoSize(p.w, p.h));
    }));

    _watchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (player.state.playing && _lastWatchTick != null) {
        final now = DateTime.now();
        _watched += now.difference(_lastWatchTick!);
        _lastWatchTick = now;
      }
    });
  }

  Future<void> _applyMpvTuning() async {
    try {
      if (player.platform is! NativePlayer) return;
      final np = player.platform as NativePlayer;
      await np.setProperty('volume-max', '200');
      await np.setProperty('audio-pitch-correction', 'yes');
      await np.setProperty('video-sync', 'display-resample');
      await np.setProperty('audio-buffer', '0.2');
      await np.setProperty('demuxer-mkv-probe-start-time', 'no');
      await np.setProperty('correct-pts', 'yes');
      await np.setProperty('demuxer-max-back-bytes', '${16 * 1024 * 1024}');
      await np.setProperty('cache-pause', 'no');
      await np.setProperty('video-latency-hacks', 'yes');
    } catch (e) {
      debugPrint('⚠️ MpvPlaybackEngine: mpv tuning échoué — $e');
    }
  }

  // ── Commandes ──────────────────────────────────────────────────────────────

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> playOrPause() => player.playOrPause();

  @override
  Future<void> seek(Duration position) {
    _lastSeekAt = DateTime.now();
    return player.seek(position);
  }

  @override
  Future<void> setRate(double rate) => player.setRate(rate);

  // ── Qualité HLS (§engineFeatures) ──────────────────────────────────────────

  @override
  List<AetherQuality> get qualities => const [];

  @override
  AetherQuality? get currentQuality => _currentQuality;

  @override
  Stream<List<AetherQuality>> get qualitiesStream => _qualitiesCtrl.stream;

  @override
  Future<bool> setQuality(AetherQuality quality) async {
    _currentQuality = quality;
    _qualitiesCtrl.add(qualities);
    return true;
  }

  // ── Sous-titres externes (lot 11) ─────────────────────────────────────────

  @override
  Future<bool> loadExternalSubtitle({
    required String filePath,
    required String language,
    required String label,
  }) async {
    try {
      final uri = Uri.file(filePath).toString();
      await player.setSubtitleTrack(
        SubtitleTrack.uri(uri, title: label, language: language),
      );
      return true;
    } catch (e) {
      debugPrint('⚠️ MpvPlaybackEngine: loadExternalSubtitle échoué: $e');
      return false;
    }
  }

  @override
  Future<void> setVolume(double volume) => player.setVolume(volume);

  @override
  Future<bool> setAudioTrack(AetherTrack track) async {
    final match = player.state.tracks.audio.where((t) => t.id == track.id);
    if (match.isEmpty) return false;
    if (player.state.track.audio.id == track.id) return true;
    await player.setAudioTrack(match.first);
    return true;
  }

  @override
  Future<bool> setSubtitleTrack(AetherTrack track) async {
    final match = player.state.tracks.subtitle.where((t) => t.id == track.id);
    if (match.isEmpty) return false;
    if (player.state.track.subtitle.id == track.id) return true;
    await player.setSubtitleTrack(match.first);
    return true;
  }

  @override
  Future<bool> resetSubtitlesToAuto() async {
    try {
      await player.setSubtitleTrack(SubtitleTrack.auto());
      await TrackPreferencesService.setSubtitle(null);
      return true;
    } catch (e) {
      debugPrint('⚠️ MpvPlaybackEngine: resetSubtitlesToAuto échoué: $e');
      return false;
    }
  }

  @override
  Future<bool> resetAudioToAuto() async {
    try {
      await player.setAudioTrack(AudioTrack.auto());
      await TrackPreferencesService.setAudio(null);
      return true;
    } catch (e) {
      debugPrint('⚠️ MpvPlaybackEngine: resetAudioToAuto échoué: $e');
      return false;
    }
  }

  @override
  Future<void> disableAudio() => player.setAudioTrack(AudioTrack.no());

  @override
  Future<bool> disableSubtitles() async {
    try {
      await player.setSubtitleTrack(SubtitleTrack.no());
      await TrackPreferencesService.setSubtitle(
          TrackPreferencesService.kSubtitlesOff);
      return true;
    } catch (e) {
      debugPrint('⚠️ MpvPlaybackEngine: disableSubtitles échoué: $e');
      return false;
    }
  }

  @override
  bool get lastErrorWasAudio => _lastErrorAudio;

  @override
  AetherTrack? get lastErrorAudioTrack => _lastErrorAudioTrack;

  @override
  Future<void> refreshTracks() async {
    // mpv / media_kit maintient player.state.tracks et player.state.track synchronisés en temps réel.
  }

  @override
  Future<bool> setVideoEnabled(bool enabled) async {
    try {
      await player.setVideoTrack(enabled ? VideoTrack.auto() : VideoTrack.no());
      return true;
    } catch (e) {
      debugPrint('⚠️ MpvPlaybackEngine: setVideoEnabled échoué: $e');
      return false;
    }
  }

  // ── Ouverture ──────────────────────────────────────────────────────────────

  @override
  Future<void> open(
    String url, {
    Duration? start,
    String? audioLang,
    String? subLang,
    AetherNowPlaying? nowPlaying,
  }) async {
    _openTime = DateTime.now();
    _firstPlayTime = null;
    _bufferingStartTime = null;
    _lastWatchTick = null;
    _stalls = 0;
    _stalled = Duration.zero;
    _watched = Duration.zero;
    _lastErrorAudio = false;
    _lastErrorAudioTrack = null;

    try {
      if (player.platform is NativePlayer) {
        final np = player.platform as NativePlayer;
        await np.setProperty('tls-verify', 'no');
        await np.setProperty('insecure', 'yes');
        await _applyLangPrefs(np, audioLang, subLang);
      }
    } catch (_) {}

    await player.open(Media(url, start: start), play: true);
  }

  @override
  Future<void> openFile(
    String path, {
    Duration? start,
    String? audioLang,
    String? subLang,
    AetherNowPlaying? nowPlaying,
  }) async {
    _openTime = DateTime.now();
    _firstPlayTime = null;
    _bufferingStartTime = null;
    _lastWatchTick = null;
    _stalls = 0;
    _stalled = Duration.zero;
    _watched = Duration.zero;
    _lastErrorAudio = false;
    _lastErrorAudioTrack = null;

    try {
      if (player.platform is NativePlayer) {
        final np = player.platform as NativePlayer;
        await _applyLangPrefs(np, audioLang, subLang);
      }
    } catch (_) {}

    await player.open(Media('file://$path', start: start), play: true);
  }

  Future<void> _applyLangPrefs(
    NativePlayer np,
    String? audioLang,
    String? subLang,
  ) async {
    if (audioLang != null && audioLang.isNotEmpty) {
      await np.setProperty('alang', audioLang);
    }
    if (subLang == 'no') {
      await np.setProperty('sid', 'no');
    } else if (subLang != null && subLang.isNotEmpty) {
      await np.setProperty('slang', subLang);
    }
  }

  // ── État instantané ────────────────────────────────────────────────────────

  @override
  Duration get position => player.state.position;

  @override
  Duration get duration => player.state.duration;

  @override
  bool get playing => player.state.playing;

  static AetherTrack _toTrack(dynamic t) => AetherTrack(
        id: t.id as String,
        title: t.title as String?,
        language: t.language as String?,
        isSpecial: t.id == 'auto' || t.id == 'no',
      );

  @override
  List<AetherTrack> get audioTracks =>
      player.state.tracks.audio.map(_toTrack).toList();

  @override
  List<AetherTrack> get subtitleTracks =>
      player.state.tracks.subtitle.map(_toTrack).toList();

  @override
  AetherTrack? get currentAudioTrack => _toTrack(player.state.track.audio);

  @override
  AetherTrack? get currentSubtitleTrack => _toTrack(player.state.track.subtitle);

  // ── Flux ───────────────────────────────────────────────────────────────────

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Stream<bool> get bufferingStream => _buffering.stream;

  @override
  Stream<bool> get completedStream => _completed.stream;

  @override
  Stream<String> get errorStream => _error.stream;

  @override
  Stream<Duration> get positionStream => player.stream.position;

  @override
  Stream<Duration> get durationStream => player.stream.duration;

  @override
  Stream<Duration> get bufferStream => player.stream.buffer;

  @override
  Stream<AetherVideoSize> get videoParamsStream => _videoParams.stream;

  // ── Rendu ──────────────────────────────────────────────────────────────────

  @override
  Widget buildSurface(BoxFit fit) {
    return Video(
      controller: videoController,
      controls: NoVideoControls,
      fit: fit,
    );
  }

  // ── Diagnostic ─────────────────────────────────────────────────────────────

  @override
  Future<VideoStatsSnapshot> readStats() async {
    int? width = player.state.width;
    int? height = player.state.height;
    String? hwdec;
    String? codec;
    double? containerFps;
    double? renderedFps;
    int? droppedFrames;
    int? videoBitrate;
    String? audioCodec;

    if (player.platform is NativePlayer) {
      try {
        final np = player.platform as NativePlayer;
        hwdec = await np.getProperty('hwdec-current');
        codec = await np.getProperty('video-codec');
        final wStr = await np.getProperty('video-params/w');
        final hStr = await np.getProperty('video-params/h');
        if (wStr.isNotEmpty) width = int.tryParse(wStr);
        if (hStr.isNotEmpty) height = int.tryParse(hStr);
        final fpsStr = await np.getProperty('container-fps');
        if (fpsStr.isNotEmpty) {
          containerFps = double.tryParse(fpsStr);
        }
        final rfpsStr = await np.getProperty('estimated-vf-fps');
        if (rfpsStr.isNotEmpty) {
          renderedFps = double.tryParse(rfpsStr);
        }
        final dropStr = await np.getProperty('drop-frame-count');
        if (dropStr.isNotEmpty) {
          droppedFrames = int.tryParse(dropStr);
        }
        final brStr = await np.getProperty('video-bitrate');
        if (brStr.isNotEmpty) {
          videoBitrate = int.tryParse(brStr);
        }
        audioCodec = await np.getProperty('audio-codec-name');
      } catch (_) {}
    }

    final Duration? bufferAhead = player.state.buffer > player.state.position
        ? player.state.buffer - player.state.position
        : null;

    final startupMs = (_firstPlayTime != null && _openTime != null)
        ? _firstPlayTime!.difference(_openTime!).inMilliseconds
        : null;

    return VideoStatsSnapshot(
      width: width,
      height: height,
      hwdec: hwdec,
      codec: codec,
      containerFps: containerFps,
      renderedFps: renderedFps,
      droppedFrames: droppedFrames,
      videoBitrate: videoBitrate,
      vo: 'd3d11va',
      stalls: _stalls,
      stalledMs: _stalled.inMilliseconds,
      startupMs: startupMs,
      bufferAhead: bufferAhead,
      audioCodec: audioCodec,
    );
  }

  @override
  AetherPlaybackHealth get health {
    final startup = (_firstPlayTime != null && _openTime != null)
        ? _firstPlayTime!.difference(_openTime!)
        : null;
    return AetherPlaybackHealth(
      stalls: _stalls,
      stalled: _stalled,
      startup: startup,
      watched: _watched,
    );
  }

  @override
  Future<bool> recoverInPlace() async => false;

  @override
  void dispose() {
    _watchTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _playing.close();
    _buffering.close();
    _completed.close();
    _error.close();
    _videoParams.close();
    _qualitiesCtrl.close();
    player.dispose();
  }
}
