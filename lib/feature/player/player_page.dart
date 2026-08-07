import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:aetherStream/data/services/watch_progress_service.dart';
import 'package:aetherStream/data/services/track_preferences_service.dart';
import 'package:aetherStream/data/services/remote_control_service.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'player_controller.dart';
import 'widgets/player_controls.dart';
import 'widgets/player_gestures.dart';
import 'widgets/player_replay_bar.dart';
import 'widgets/track_selector_sheet.dart';
import 'widgets/player_options_sheet.dart';
import 'player_action_handlers.dart';
import 'package:dpad/dpad.dart';
import '../../core/utils/platform_tv.dart';

enum VideoSourceType {
  network, // live / VOD réseau (et timeshift simple)
  networkReplay, // timeshift avec barre replay + bouton "Retour au direct"
  file, // fichier local
  // networkWithCache supprimé : media_kit gère le cache nativement
}

/// Badge affiché en haut à droite du player.
enum PlayerBadgeType {
  none, // aucun badge (fichier local…)
  live, // ● DIRECT rouge (flux TV en direct)
  replay, // ↩ REPLAY violet (timeshift)
  movie, // FILM bleu
  series, // SÉRIE violet
}

class PlayerPage extends StatefulWidget {
  /// §nextEpPortrait — Quand on enchaîne sur l'épisode suivant, on POP le player
  /// courant puis on en PUSH un nouveau. Le `dispose()` du player poppé restaure
  /// le portrait (mobile) ~300 ms plus tard (fin d'anim de pop), donc APRÈS
  /// l'`initState` landscape du nouveau player → l'épisode suivant s'ouvrait en
  /// portrait. Ce flag, levé par l'appelant avant le pop, fait sauter la
  /// restauration portrait du dispose (puis se réarme tout seul).
  static bool suppressOrientationRestore = false;

  final String path;
  final String title;
  /// §watchContext a — Qualité du flux (4K/FHD/HD/SD) → badge sous le titre.
  final String? qualityTag;
  /// §watchContext b — Numéro saison/épisode (« S01 E04 ») → badge sous le titre.
  final String? episodeTag;
  /// §watchContext — Nom de la série (breadcrumb au-dessus du titre, séries).
  final String? seriesName;
  /// §watchContext — Synopsis (épisode ou film, si TMDB/provider dispo) affiché
  /// dans l'overlay sous les badges.
  final String? synopsis;
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
    this.qualityTag,
    this.episodeTag,
    this.seriesName,
    this.synopsis,
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

  /// §tvPlayerNav — Vitesse courante, pilotée par le sous-menu Vitesse du
  /// panneau d'options TV (reflète la coche du menu).
  double _speed = 1.0;

  // §seekAccum — Accumulation des sauts rapprochés (double-tap mobile + flèches
  // télécommande TV). Les sauts dans une même direction et un court intervalle
  // s'additionnent et l'overlay affiche le total cumulé (ex: 3 sauts → +30s).
  Timer? _seekAccumTimer; // reset de l'accumulateur après inactivité
  Timer? _seekOverlayTimer; // masquage de l'overlay
  int _seekAccumSeconds = 0; // signé : >0 avance, <0 recul
  bool _seekOverlayVisible = false;

  // Luminosité courante (0.0–1.0), initialisée à 0.5 par défaut.
  double _brightness = 0.5;
  // Volume courant (0.0–200.0). Démarre boosté à 130% pour compenser les flux
  // IPTV souvent encodés faibles — voir AetherPlayerController.initialVolume.
  double _volume = AetherPlayerController.initialVolume;

  /// §webConsole Phase 2 — handlers exposés à la télécommande web pendant que
  /// le player est ouvert (mêmes actions que le D-pad TV).
  late final PlayerActionHandlers _remoteHandlers;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _currentPath = widget.path;
    // §replayBuffer — profil mpv timeshift (buffering propre aux frontières
    // de segments HLS longs) quand on lit un replay.
    _ctrl = AetherPlayerController(
      timeshift: widget.sourceType == VideoSourceType.networkReplay,
    );
    _listenErrors();
    _listenPlaybackForWakelock();
    WidgetsBinding.instance.addObserver(this);
    _openMedia();
    _startHideTimer();
    _initBrightness();
    _startProgressTracking();

    _remoteHandlers = PlayerActionHandlers(
      togglePlayPause: _togglePlayPause,
      seek: _handleSeek,
      changeVolume: _handleVolumeChange,
      toggleControls: _toggleControls,
      showControls: _showControls,
      showOptions: _showTvOptions,
      exitPlayer: () {
        if (mounted) Navigator.of(context).maybePop();
      },
    );
    RemoteControlService.instance.registerPlayer(_remoteHandlers);
    _releaseImageCache();
  }

  /// §playerMem — Rend au décodeur vidéo la RAM immobilisée par les vignettes.
  ///
  /// L'accueil reste MONTÉ derrière le player (route conservée) : son arbre de
  /// widgets, et surtout les images déjà décodées, continuent d'occuper la
  /// mémoire pendant tout le film — jusqu'à ~120 Mo au profil Confort. Or
  /// aucune de ces vignettes n'est visible derrière une vidéo plein écran.
  ///
  /// `imageCache.clear()` ne vide que les entrées **conservées pour plus tard**
  /// : les images encore référencées par des widgets vivants sont suivies à
  /// part (`liveImages`) et ne sont pas jetées. Au retour, les vignettes
  /// évincées se relisent depuis le cache DISQUE (§imgDiskCache) — donc sans
  /// re-téléchargement.
  ///
  /// Particulièrement utile sur box TV, où cette RAM manque au décodage 4K.
  void _releaseImageCache() {
    try {
      PaintingBinding.instance.imageCache.clear();
      debugPrint('🖼️ §playerMem : cache image RAM libéré pour la lecture');
    } catch (_) {
      // Non critique : au pire on garde le comportement précédent.
    }
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
      // §resumeStart — Position de reprise passée NATIVEMENT à mpv via
      // `Media(start:)` (cf. AetherPlayerController.open) → fini la lecture qui
      // repart à 0 (le seek post-open était avalé par media_kit v2). Pas de
      // reprise pour les sources live/replay (`_skipProgress`).
      final start = (_skipProgress) ? null : widget.startPosition;
      // §trackLangPref — Préférence de langue posée AVANT l'open (mpv choisit la
      // piste au chargement → plus de switch/re-demux ~3 s = « le film se
      // relance »). Pas pour live/replay.
      final audioLang = _skipProgress ? null : TrackPreferencesService.audio;
      final subLang = _skipProgress ? null : TrackPreferencesService.subtitle;
      if (widget.sourceType == VideoSourceType.file) {
        await _ctrl.openFile(_currentPath,
            start: start, audioLang: audioLang, subLang: subLang);
      } else {
        await _ctrl.open(_currentPath,
            start: start, audioLang: audioLang, subLang: subLang);
      }
    } catch (e) {
      _handleError(e.toString());
    }
  }

  /// §5 — Applique la préférence de langue audio / sous-titre dès que les pistes
  /// réelles sont peuplées (libmpv les remplit après le début de lecture), puis
  /// se désabonne pour ne JAMAIS écraser un choix manuel fait ensuite.
  /// §5 — Ouvre le sélecteur de pistes audio/sous-titres. Suspend l'auto-hide
  /// le temps du sheet, puis le réarme. §dpadNav : le retour de focus sur la
  /// vidéo est géré nativement par `dpad` (`restoreFocus`).
  Future<void> _showTrackSelector() async {
    _hideTimer?.cancel();
    await showTrackSelector(context, _ctrl.player);
    if (mounted) _startHideTimer();
  }

  /// §tvPlayerNav — Panneau d'options (centre de contrôle TV, ouvert via ↑) :
  /// pistes audio/sous-titres, vitesse, épisode suivant. Tout focusable au D-pad.
  Future<void> _showTvOptions() async {
    _hideTimer?.cancel();
    await showPlayerOptions(
      context,
      hasNext: widget.onNextEpisode != null,
      speedLabel: _speed == 1.0 ? 'Normale (1.0×)' : '$_speed×',
      onTracks: () {
        Navigator.of(context).pop();
        _showTrackSelector();
      },
      onSpeed: () {
        Navigator.of(context).pop();
        _showSpeedMenu();
      },
      onNext: widget.onNextEpisode == null
          ? null
          : () {
              Navigator.of(context).pop();
              widget.onNextEpisode!.call();
            },
    );
    if (mounted) _startHideTimer();
  }

  /// §tvPlayerNav — Sous-menu Vitesse.
  Future<void> _showSpeedMenu() async {
    await showSpeedMenu(
      context,
      current: _speed,
      onSelect: (s) {
        setState(() => _speed = s);
        _ctrl.player.setRate(s);
        Navigator.of(context).pop();
      },
    );
  }

  /// Retourne l'URL avec l'extension alternative (.m3u8 ↔ .ts), ou null si non applicable.
  String? _altExtUrl(String url) {
    if (url.contains('.m3u8')) {
      return url.replaceFirst(RegExp(r'\.m3u8$'), '.ts');
    }
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
          debugPrint(
              '⚠️ PlayerPage: retry $_retryCount/$_maxRetries — extension alternative: $alt');
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
      debugPrint(
          '❌ PlayerPage: échec définitif après $_maxRetries tentatives\n$error');
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
    _accumulateSeek(delta);
  }

  /// §seekAccum — Met à jour le total cumulé affiché. Les sauts d'une même
  /// direction réalisés à moins de ~1,1s d'intervalle s'additionnent ; un
  /// changement de direction (ou l'expiration du délai) repart de zéro.
  void _accumulateSeek(Duration delta) {
    final secs = delta.inSeconds;
    if (secs == 0) return;
    // Changement de sens ou nouvelle salve → on réinitialise l'accumulateur.
    if (_seekAccumTimer == null || _seekAccumSeconds.sign != secs.sign) {
      _seekAccumSeconds = 0;
    }
    _seekAccumSeconds += secs;

    setState(() => _seekOverlayVisible = true);
    _seekOverlayTimer?.cancel();
    _seekOverlayTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _seekOverlayVisible = false);
    });

    _seekAccumTimer?.cancel();
    _seekAccumTimer = Timer(const Duration(milliseconds: 1100), () {
      _seekAccumSeconds = 0;
      _seekAccumTimer = null;
    });
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
    _seekAccumTimer?.cancel();
    _seekOverlayTimer?.cancel();
    RemoteControlService.instance.clearPlayer(_remoteHandlers);
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
    if (PlatformTv.isTv || PlayerPage.suppressOrientationRestore) {
      // TV : jamais de portrait. §nextEpPortrait : enchaînement épisode suivant
      // → on garde landscape pour ne pas écraser l'orientation du player qui suit.
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      PlayerPage.suppressOrientationRestore =
          false; // réarme pour la prochaine sortie
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
      // §dpadNav — La zone vidéo est un `DpadFocusable` (autofocus) qui capte la
      // télécommande pendant la lecture : OK=play/pause, long-OK=options,
      // ←/→=seek ±10 s, ↑=options, ↓=affiche la barre. `effects: []` → aucun
      // halo autour de la vidéo. Le retour de focus après un sheet est géré par
      // `dpad` (restoreFocus). Remplace l'ancien `TvPlayerShortcuts`.
      body: DpadFocusable(
        autofocus: true,
        tapToSelect: false,
        effects: const [],
        onSelect: _togglePlayPause,
        onLongSelect: _showTvOptions,
        onDirection: (dir) {
          if (dir == TraversalDirection.left) {
            _handleSeek(const Duration(seconds: -10));
            return true;
          }
          if (dir == TraversalDirection.right) {
            _handleSeek(const Duration(seconds: 10));
            return true;
          }
          if (dir == TraversalDirection.up) {
            _showTvOptions();
            return true;
          }
          if (dir == TraversalDirection.down) {
            _showControls();
            return true;
          }
          return false;
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Rendu vidéo plein écran.
            //    §doubleLoader — `controls: NoVideoControls` DÉSACTIVE l'UI
            //    intégrée de media_kit_video (`AdaptiveVideoControls` par
            //    défaut). Sans ça, ses contrôles natifs s'empilaient sur nos
            //    `PlayerControls` + `_BufferingOverlay` → DEUX spinners de
            //    chargement au démarrage + captation des taps en double (effet
            //    de "double lancement"). On rend tout nous-mêmes.
            Video(
              controller: _ctrl.videoController,
              controls: NoVideoControls,
            ),

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
              qualityTag: widget.qualityTag,
              episodeTag: widget.episodeTag,
              seriesName: widget.seriesName,
              synopsis: widget.synopsis,
              visible: _controlsVisible,
              badgeType: widget.badgeType,
              onBack: () => Navigator.of(context).pop(),
              onInteraction: _showControls,
              onLockChanged: (locked) => setState(() => _isLocked = locked),
              onNextEpisode: widget.onNextEpisode,
              onShowTracks: _showTrackSelector,
            ),

            // §1i — Overlay buffering central : visible quand le player charge
            // un nouveau segment HLS. Désactivé en mode lock pour ne pas troubler
            // la zone cliquable du cadenas.
            _BufferingOverlay(player: _ctrl.player, hidden: _isLocked),

            // §seekAccum — Badge central du saut cumulé (ex: « ⏩ +30s »).
            if (_seekOverlayVisible && _seekAccumSeconds != 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: _SeekAccumBadge(seconds: _seekAccumSeconds),
                  ),
                ),
              ),

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
              Icon(Icons.error_outline, color: kError, size: 56),
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

/// §seekAccum — Badge central affichant le saut cumulé (ex: « ⏩ +30s »).
/// Le signe pilote l'icône (avance/recul) et le texte du total.
class _SeekAccumBadge extends StatelessWidget {
  final int seconds;
  const _SeekAccumBadge({required this.seconds});

  @override
  Widget build(BuildContext context) {
    final forward = seconds >= 0;
    final abs = seconds.abs();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(150),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kAccentPrimary.withAlpha(120), width: 1),
        boxShadow: [
          BoxShadow(color: kAccentPrimary.withAlpha(70), blurRadius: 16),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            forward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
            color: kAccentPrimary,
            size: 30,
          ),
          const SizedBox(width: 10),
          Text(
            '${forward ? '+' : '-'}${abs}s',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
