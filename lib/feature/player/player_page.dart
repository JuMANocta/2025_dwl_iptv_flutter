import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:aetherStream/data/services/watch_progress_service.dart';
import 'player_controller.dart';
import 'widgets/player_controls.dart';
import 'widgets/player_gestures.dart';
import 'widgets/player_replay_bar.dart';
import 'widgets/tv_player_shortcuts.dart';
import '../../core/utils/platform_tv.dart';

enum VideoSourceType {
  network,       // live / VOD réseau (et timeshift simple)
  networkReplay, // timeshift avec barre replay + bouton "Retour au direct"
  file,          // fichier local
  // networkWithCache supprimé : media_kit gère le cache nativement
}

/// Badge affiché en haut à droite du player.
enum PlayerBadgeType {
  none,    // aucun badge (fichier local…)
  live,    // ● DIRECT rouge (flux TV en direct)
  replay,  // ↩ REPLAY violet (timeshift)
  movie,   // FILM bleu
  series,  // SÉRIE violet
}

class PlayerPage extends StatefulWidget {
  final String path;
  final String title;
  final VideoSourceType sourceType;
  /// Badge affiché en haut à droite.
  final PlayerBadgeType badgeType;
  /// Heure de début du replay — alimente la barre replay (optionnel).
  final DateTime? replayStart;
  /// Durée totale du replay — alimente la barre replay (optionnel).
  final Duration? replayDuration;
  /// §1e — Position de reprise. Si non-null, seek juste après l'open du flux.
  final Duration? startPosition;
  /// Clé URL utilisée pour la persistance de progression. Si nulle, on utilise
  /// `path`. Permet de partager une progression entre variantes (FHD/HD du
  /// même film) en passant une clé canonique commune.
  final String? progressKey;
  /// §1i — Callback "épisode suivant". Si défini, un bouton ▶▶ apparaît dans
  /// les contrôles du player. À utiliser pour les séries depuis [DetailsPage].
  final VoidCallback? onNextEpisode;
  const PlayerPage({
    super.key,
    required this.path,
    required this.title,
    this.sourceType = VideoSourceType.network,
    this.badgeType = PlayerBadgeType.none,
    this.replayStart,
    this.replayDuration,
    this.startPosition,
    this.progressKey,
    this.onNextEpisode,
  });

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
  late final AetherPlayerController _ctrl;

  bool _controlsVisible = true;
  Timer? _hideTimer;

  bool _hasError = false;
  String _errorMessage = '';
  int _retryCount = 0;
  static const _maxRetries = 3;
  // Chemin courant utilisé pour le retry (peut alterner .m3u8 ↔ .ts).
  late String _currentPath;

  // ── §1e Continue Watching ────────────────────────────────────────────────
  /// Timer périodique 10s pour sauvegarder la progression pendant la lecture.
  Timer? _progressTimer;
  /// Vrai si la position de reprise a déjà été appliquée (idempotent au retry).
  bool _resumeApplied = false;
  /// Vrai pour les sources qui ne doivent PAS sauvegarder de progression
  /// (chaînes TV live = durée infinie, replay timeshift = pas de reprise utile).
  bool get _skipProgress =>
      widget.badgeType == PlayerBadgeType.live ||
      widget.sourceType == VideoSourceType.networkReplay;

  // ── §1h Wakelock + Lifecycle ─────────────────────────────────────────────
  /// Souscription à `stream.playing` pour activer/désactiver le wakelock.
  StreamSubscription<bool>? _playingSub;
  /// Souscription au stream d'erreur, à canceller pour éviter une fuite.
  StreamSubscription<String>? _errorSub;
  /// Timer de reconnexion automatique en attente — annulable depuis le lifecycle
  /// observer pour ne pas continuer à retry quand l'app passe en arrière-plan.
  Timer? _pendingRetryTimer;
  /// Vrai si le wakelock est actuellement détenu — évite les appels redondants.
  bool _wakelockHeld = false;
  /// §1i — Mode lock partagé entre [PlayerControls] et [PlayerGestures].
  /// `true` → tous les gestes (sauf tap pour révéler le cadenas) sont ignorés.
  bool _isLocked = false;

  // Luminosité courante (0.0–1.0), initialisée à 0.5 par défaut.
  double _brightness = 0.5;
  // Volume courant (0.0–200.0). Démarre boosté à 130% pour compenser les flux
  // IPTV souvent encodés faibles — voir AetherPlayerController.initialVolume.
  double _volume = AetherPlayerController.initialVolume;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _currentPath = widget.path;
    _ctrl = AetherPlayerController();
    _listenErrors();
    _listenPlaybackForWakelock();
    WidgetsBinding.instance.addObserver(this);
    _openMedia();
    _startHideTimer();
    _initBrightness();
    _startProgressTracking();
  }

  // ── §1h Wakelock — actif uniquement quand le player joue ─────────────────

  /// Active le wakelock dès que la lecture démarre, le relâche en pause/erreur.
  /// Évite que l'écran s'éteigne pendant un long film, sans le maintenir allumé
  /// quand l'utilisateur a mis en pause ou que le flux est planté.
  void _listenPlaybackForWakelock() {
    _playingSub = _ctrl.player.stream.playing.listen((playing) {
      if (playing) {
        _acquireWakelock();
      } else {
        _releaseWakelock();
      }
    });
  }

  Future<void> _acquireWakelock() async {
    if (_wakelockHeld) return;
    try {
      await WakelockPlus.enable();
      _wakelockHeld = true;
    } catch (e) {
      debugPrint('⚠️ PlayerPage: wakelock enable failed — $e');
    }
  }

  Future<void> _releaseWakelock() async {
    if (!_wakelockHeld) return;
    try {
      await WakelockPlus.disable();
      _wakelockHeld = false;
    } catch (e) {
      debugPrint('⚠️ PlayerPage: wakelock disable failed — $e');
    }
  }

  // ── §1h Lifecycle ────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // App en arrière-plan : couper le retry programmé (évite drain batterie
        // si le serveur est down) + relâcher le wakelock (écran déjà off).
        _pendingRetryTimer?.cancel();
        _pendingRetryTimer = null;
        _releaseWakelock();
        // Sauvegarde immédiate de la progression (l'OS peut tuer l'app à tout moment).
        _saveProgress();
        break;
      case AppLifecycleState.resumed:
        // Retour au premier plan : si on était en erreur définitive → tenter un
        // nouveau cycle de retry. Sinon, re-armer le wakelock si on joue.
        if (_hasError) {
          _retry();
        } else if (_ctrl.player.state.playing) {
          _acquireWakelock();
        }
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.inactive:
        break;
    }
  }

  /// §1e — Sauvegarde la position toutes les 10s tant que la lecture n'est
  /// pas en pause. Ignoré pour les sources live/replay.
  void _startProgressTracking() {
    if (_skipProgress) return;
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _saveProgress();
    });
  }

  void _saveProgress() {
    if (_skipProgress) return;
    final pos = _ctrl.player.state.position;
    final dur = _ctrl.player.state.duration;
    if (dur <= Duration.zero) return;
    final key = widget.progressKey ?? widget.path;
    // saveProgress applique ses propres règles (min duration, threshold 95%, etc.).
    WatchProgressService.saveProgress(key, pos, dur);
  }

  Future<void> _initBrightness() async {
    try {
      _brightness = await ScreenBrightness().current;
    } catch (_) {}
  }

  Future<void> _openMedia() async {
    try {
      if (widget.sourceType == VideoSourceType.file) {
        await _ctrl.openFile(_currentPath);
      } else {
        await _ctrl.open(_currentPath);
      }
      await _applyResumeIfNeeded();
    } catch (e) {
      _handleError(e.toString());
    }
  }

  /// §1e — Applique le seek de reprise (`startPosition`) une fois la duration
  /// du flux disponible. Idempotent : ne s'exécute qu'une fois par instance.
  ///
  /// On souscrit à `stream.duration` jusqu'à recevoir une valeur > 0, puis on
  /// cancel immédiatement. Timeout 4s pour ne pas bloquer indéfiniment sur un
  /// flux live mal taggué (qui n'émet jamais de duration).
  Future<void> _applyResumeIfNeeded() async {
    if (_resumeApplied) return;
    final start = widget.startPosition;
    if (start == null || start <= Duration.zero) return;
    if (_skipProgress) return;

    final completer = Completer<void>();
    final sub = _ctrl.player.stream.duration.listen((d) {
      if (d > Duration.zero && !completer.isCompleted) completer.complete();
    });
    try {
      await completer.future.timeout(
        const Duration(seconds: 4),
        onTimeout: () {},
      );
    } finally {
      await sub.cancel();
    }
    if (!mounted) return;
    await _ctrl.player.seek(start);
    _resumeApplied = true;
  }

  /// Retourne l'URL avec l'extension alternative (.m3u8 ↔ .ts), ou null si non applicable.
  String? _altExtUrl(String url) {
    if (url.contains('.m3u8')) return url.replaceFirst(RegExp(r'\.m3u8$'), '.ts');
    if (url.contains('.ts')) return url.replaceFirst(RegExp(r'\.ts$'), '.m3u8');
    return null;
  }

  void _listenErrors() {
    _errorSub = _ctrl.player.stream.error.listen((error) {
      if (error.isNotEmpty && mounted) {
        _handleError(error);
      }
    });
  }

  /// Reconnexion automatique (×3, délai 5s).
  /// Retry 1 : même URL (serveur pas encore prêt).
  /// Retry 2 : extension alternative (.m3u8 ↔ .ts) — certains serveurs ne supportent qu'un format.
  /// Retry 3 : retour à l'URL originale.
  void _handleError(String error) {
    if (_retryCount < _maxRetries) {
      _retryCount++;
      // Retry 2 : tente l'extension alternative
      if (_retryCount == 2) {
        final alt = _altExtUrl(widget.path);
        if (alt != null) {
          _currentPath = alt;
          debugPrint('⚠️ PlayerPage: retry $_retryCount/$_maxRetries — extension alternative: $alt');
        }
      } else {
        _currentPath = widget.path; // retour à l'URL originale
      }
      debugPrint(
          '⚠️ PlayerPage: erreur stream — retry $_retryCount/$_maxRetries dans 5s\n$error');
      // Timer trackable → on peut l'annuler quand l'app passe en arrière-plan.
      _pendingRetryTimer?.cancel();
      _pendingRetryTimer = Timer(const Duration(seconds: 5), () {
        _pendingRetryTimer = null;
        if (mounted) _openMedia();
      });
    } else {
      debugPrint('❌ PlayerPage: échec définitif après $_maxRetries tentatives\n$error');
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = error;
        });
      }
    }
  }

  void _showControls() {
    if (!mounted) return;
    setState(() => _controlsVisible = true);
    _startHideTimer();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _handleSeek(Duration delta) {
    final pos = _ctrl.player.state.position + delta;
    _ctrl.player.seek(pos.isNegative ? Duration.zero : pos);
    _showControls();
  }

  void _handleVolumeChange(double delta) {
    _volume = (_volume + delta).clamp(0.0, AetherPlayerController.maxVolume);
    _ctrl.player.setVolume(_volume);
  }

  // §3c-5 — Helpers consommés par TvPlayerShortcuts pour la nav télécommande.
  void _togglePlayPause() {
    _ctrl.player.playOrPause();
    _showControls();
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _hideTimer?.cancel();
      if (mounted) setState(() => _controlsVisible = false);
    } else {
      _showControls();
    }
  }

  void _handleBrightnessChange(double delta) {
    _brightness = (_brightness + delta).clamp(0.0, 1.0);
    // fire-and-forget : dispose() restore de toute façon la luminosité d'origine.
    ScreenBrightness().setScreenBrightness(_brightness).catchError((_) {});
  }

  void _retry() {
    setState(() {
      _hasError = false;
      _retryCount = 0;
      _currentPath = widget.path;
    });
    _openMedia();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _progressTimer?.cancel();
    _pendingRetryTimer?.cancel();
    _saveProgress(); // dernière sauvegarde à la sortie du player
    _playingSub?.cancel();
    _errorSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _releaseWakelock();
    _ctrl.dispose();
    ScreenBrightness().resetScreenBrightness().catchError((_) {});
    // §3c-bis — Sur TV, la sortie du player NE DOIT PAS basculer en portrait
    // (la TV n'a pas de portrait, ça casserait toute l'UI). On reste en
    // landscape. Sur mobile, on restaure le comportement portrait par défaut.
    if (PlatformTv.isTv) {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) return _buildErrorScreen();

    // §3c-5 — Sur Android TV : wrap Shortcuts/Actions/Focus pour mapper le
    // D-pad sur les actions du player. Sur mobile : pass-through neutre.
    final isTv = PlatformTv.isTv;
    return Scaffold(
      backgroundColor: Colors.black,
      body: TvPlayerShortcuts(
        handlers: PlayerActionHandlers(
          togglePlayPause: _togglePlayPause,
          seek: _handleSeek,
          changeVolume: _handleVolumeChange,
          toggleControls: _toggleControls,
          exitPlayer: () => Navigator.of(context).pop(),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Rendu vidéo plein écran.
            Video(controller: _ctrl.videoController),

            // 2. Couche gesture (transparente, capte tout sauf les contrôles).
            //    Désactivée sur TV — toutes les interactions passent par le
            //    D-pad via TvPlayerShortcuts.
            PlayerGestures(
              player: _ctrl.player,
              onTap: _showControls,
              onSeek: _handleSeek,
              onVolumeChange: _handleVolumeChange,
              onBrightnessChange: _handleBrightnessChange,
              readVolume: () => _volume,
              locked: _isLocked,
              disabled: isTv,
            ),

            // 3. Overlay contrôles.
            PlayerControls(
              player: _ctrl.player,
              title: widget.title,
              visible: _controlsVisible,
              badgeType: widget.badgeType,
              onBack: () => Navigator.of(context).pop(),
              onInteraction: _showControls,
              onLockChanged: (locked) => setState(() => _isLocked = locked),
              onNextEpisode: widget.onNextEpisode,
            ),

            // §1i — Overlay buffering central : visible quand le player charge
            // un nouveau segment HLS. Désactivé en mode lock pour ne pas troubler
            // la zone cliquable du cadenas.
            _BufferingOverlay(player: _ctrl.player, hidden: _isLocked),

            // 4. Barre replay (uniquement en mode networkReplay).
            if (widget.sourceType == VideoSourceType.networkReplay)
              Positioned(
                left: 16,
                right: 16,
                bottom: 90,
                child: PlayerReplayBar(
                  player: _ctrl.player,
                  replayStart: widget.replayStart,
                  replayDuration: widget.replayDuration,
                  visible: _controlsVisible,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 56),
              const SizedBox(height: 16),
              Text(
                _errorMessage,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Réessayer'),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Quitter',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── §1i Overlay buffering central ──────────────────────────────────────────

/// Affiche un cercle de chargement au centre du player quand `state.buffering`
/// est vrai. Petit délai d apparition (300ms) pour éviter le clignotement sur
/// les micro-stalls. Caché quand le player est verrouillé pour ne pas masquer
/// le bouton cadenas.
class _BufferingOverlay extends StatefulWidget {
  final Player player;
  final bool hidden;
  const _BufferingOverlay({required this.player, required this.hidden});

  @override
  State<_BufferingOverlay> createState() => _BufferingOverlayState();
}

class _BufferingOverlayState extends State<_BufferingOverlay> {
  StreamSubscription<bool>? _sub;
  bool _buffering = false;
  Timer? _showTimer;

  @override
  void initState() {
    super.initState();
    _sub = widget.player.stream.buffering.listen((v) {
      _showTimer?.cancel();
      if (v) {
        // Évite le clignotement : on attend 300ms avant d afficher.
        _showTimer = Timer(const Duration(milliseconds: 300), () {
          if (mounted) setState(() => _buffering = true);
        });
      } else if (_buffering) {
        setState(() => _buffering = false);
      }
    });
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_buffering || widget.hidden) return const SizedBox.shrink();
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 10),
            Text(
              "Mise en mémoire tampon…",
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
