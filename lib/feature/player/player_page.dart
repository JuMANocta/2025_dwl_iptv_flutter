import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:aetherStream/data/services/playback_health_service.dart';
import 'package:aetherStream/data/services/watch_progress_service.dart';
import 'package:aetherStream/data/services/track_preferences_service.dart';
import 'package:aetherStream/data/services/remote_control_service.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/core/utils/app_snackbar.dart';
import 'package:aetherStream/core/settings/performance_settings_service.dart';
import 'media3_engine.dart';
import 'playback_engine.dart';
import 'widgets/player_controls.dart';
import 'widgets/player_gestures.dart';
import 'widgets/player_replay_bar.dart';
import 'widgets/track_selector_sheet.dart';
import '../../data/services/measured_quality_service.dart';
import 'player_error.dart';
import 'video_fit.dart';
import 'video_stats.dart';
import 'widgets/player_options_sheet.dart';
import 'widgets/video_stats_overlay.dart';
import 'widgets/next_episode_overlay.dart';
import 'player_media.dart';
import 'player_action_handlers.dart';
import 'package:dpad/dpad.dart';
import '../../core/navigation/focus_route_memory.dart';
import '../../core/utils/platform_tv.dart';

enum VideoSourceType {
  network, // live / VOD réseau (et timeshift simple)
  networkReplay, // timeshift avec barre replay + bouton "Retour au direct"
  file, // fichier local
  // networkWithCache supprimé : le moteur vidéo gère le cache nativement
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
  /// §nextEpPortrait — Vestige de l'ancien enchaînement pop/push d'épisodes,
  /// devenu **inutile** depuis §episodeMeta : on ne démonte plus le player pour
  /// changer d'épisode, donc plus de `dispose()` qui restaurait le portrait par
  /// dessus l'`initState` landscape du suivant. Conservé (toujours `false`) le
  /// temps de valider sur appareil, à retirer ensuite.
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

  /// §episodeMeta — Fournit le contenu à lire ENSUITE (séries).
  ///
  /// Si défini, le bouton ▶▶ apparaît dans les contrôles et l'enchaînement
  /// automatique de fin d'épisode s'active. **Asynchrone à dessein** : l'appelant
  /// ([DetailsPage]) en profite pour aller chercher les métadonnées TMDB du
  /// prochain épisode — le player n'affiche donc jamais les infos du précédent.
  /// Retourne `null` quand il n'y a plus rien à lire (fin de série).
  ///
  /// ⚠️ Cet appel **fait avancer l'état de l'appelant**. Le player met le
  /// résultat en cache (`_pendingNext`) : si l'utilisateur annule
  /// l'enchaînement, un ⏭ ultérieur réutilise ce cache au lieu de rappeler la
  /// fonction, sinon on sauterait un épisode.
  final Future<PlayerMedia?> Function()? onRequestNext;

  /// §autoNextEp — Saison du contenu lancé (séries), pour détecter le
  /// franchissement de saison. `null` hors séries.
  final int? seasonNumber;

  /// §stallCount — Compte IPTV source, pour rattacher les blocages mesurés au
  /// fournisseur qui les a causés. Vide = fichier local ou source inconnue :
  /// on n'enregistre alors rien plutôt que d'attribuer au hasard.
  final String accountId;

  const PlayerPage({
    super.key,
    required this.path,
    required this.title,
    this.accountId = '',
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
    this.onRequestNext,
    this.seasonNumber,
  });

  /// §episodeMeta — Contenu initial, assemblé depuis les champs du widget.
  PlayerMedia get initialMedia => PlayerMedia(
        path: path,
        title: title,
        qualityTag: qualityTag,
        episodeTag: episodeTag,
        seriesName: seriesName,
        synopsis: synopsis,
        sourceType: sourceType,
        badgeType: badgeType,
        replayStart: replayStart,
        replayDuration: replayDuration,
        startPosition: startPosition,
        progressKey: progressKey,
        seasonNumber: seasonNumber,
        accountId: accountId,
      );

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
  /// §engineVendor étape 4 — Typé par l'INTERFACE, plus par une implémentation :
  /// c'est ce qui permet de choisir le moteur au lancement de la lecture.
  late final AetherPlaybackEngine _ctrl;

  /// §episodeMeta — Contenu courant. Remplacé par [_switchTo] sans démonter la
  /// page : c'est ce qui permet aux infos affichées de suivre l'épisode lu.
  late PlayerMedia _media;

  /// Prochain contenu déjà résolu (métadonnées comprises), mis en cache pour ne
  /// pas rappeler `onRequestNext` — qui fait avancer l'état de l'appelant — si
  /// l'utilisateur annule puis redemande l'épisode suivant.
  PlayerMedia? _pendingNext;

  /// Vrai pendant l'attente de `onRequestNext` (affiche « chargement… »).
  bool _loadingNext = false;

  bool _controlsVisible = true;
  Timer? _hideTimer;

  bool _hasError = false;
  String _errorMessage = '';
  int _retryCount = 0;
  static const _maxRetries = 3;

  /// §liveRecover — Reprises en place déjà tentées pour ce média.
  int _inPlaceRecoveries = 0;

  /// Au-delà, on considère que re-préparer ne suffit pas et on rouvre.
  ///
  /// **5 et non 3, et le chiffre vient de la mesure.** Sur appareil, le moteur
  /// ré-émet son erreur toutes les ~3 s : trois tentatives couvraient donc à
  /// peine **6 secondes** de coupure avant de retomber sur la réouverture — trop
  /// court pour la plupart des respirations réseau, c'est-à-dire précisément le
  /// cas que §liveRecover doit absorber. Cinq couvrent ~15 s.
  ///
  /// Le budget se reconstitue dès que la lecture repart, donc l'allonger ne
  /// coûte rien sur la durée ; et il reste borné pour qu'une source réellement
  /// morte finisse par emprunter le chemin de la réouverture — le seul qui
  /// tente aussi l'extension alternative (.m3u8 ↔ .ts).
  static const _maxInPlaceRecoveries = 5;

  /// Vrai pendant qu'une reprise en place est en vol : empêche qu'une rafale
  /// d'erreurs (§retryBurst) en déclenche plusieurs à la fois.
  bool _recovering = false;
  // Chemin courant utilisé pour le retry (peut alterner .m3u8 ↔ .ts).
  late String _currentPath;

  // ── §1e Continue Watching ────────────────────────────────────────────────
  /// Timer périodique 10s pour sauvegarder la progression pendant la lecture.
  Timer? _progressTimer;

  /// Vrai pour les sources qui ne doivent PAS sauvegarder de progression
  /// (chaînes TV live = durée infinie, replay timeshift = pas de reprise utile).
  bool get _skipProgress => _media.skipProgress;

  // ── §1h Wakelock + Lifecycle ─────────────────────────────────────────────
  /// Souscription à `stream.playing` pour activer/désactiver le wakelock.
  StreamSubscription<bool>? _playingSub;

  /// §qualityTruth — Écoute des paramètres vidéo, pour mesurer la définition
  /// RÉELLEMENT servie par le flux.
  StreamSubscription<AetherVideoSize>? _videoParamsSub;

  /// Clé du flux déjà mesuré pendant cette lecture. Remise à zéro par
  /// [_switchTo] : sans ça, l'épisode suivant hériterait de la mesure du
  /// précédent et ne serait jamais enregistré.
  String? _measuredKey;

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

  /// §videoFit — Format d'image courant. Initialisé sur le dernier choix de
  /// l'utilisateur (mémorisé d'une vidéo à l'autre) plutôt que remis à
  /// « Original » à chaque lecture.
  VideoFitMode _fit = VideoFitPreference.current;

  /// §videoStats — Encart de diagnostic vidéo. L'état est repris du dernier
  /// choix : un diagnostic se mène sur plusieurs films d'affilée.
  bool _statsEnabled = VideoStatsPreference.enabled;

  /// §audioFallback — Pistes audio déjà écartées parce qu'elles ont fait
  /// échouer le décodage, pour ne jamais y revenir en boucle sur ce média.
  final Set<String> _rejectedAudioIds = <String>{};

  /// Vrai quand on a dû se rabattre sur une lecture muette (aucune piste
  /// audio décodable). Sert à le DIRE à l'utilisateur : un film sans son sans
  /// explication passe pour une panne.
  bool _audioGaveUp = false;

  /// §tvPlayerNav + §tourFix — Vitesse courante, UNIQUE source de vérité.
  /// Alimentée par le sous-menu Vitesse ET par le badge inline des contrôles
  /// (via [_setSpeed]) : les deux voies convergent ici, le badge et la coche
  /// du menu ne peuvent plus se contredire.
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
  // Volume courant (0.0–200.0). Démarre boosté (125 % sur TV, 130 % ailleurs)
  // pour compenser les flux IPTV souvent encodés faibles — cf. [AetherVolume],
  // qui vit dans l'interface et NON dans une implémentation : ces valeurs
  // avaient été écrites côté mpv, et le moteur suivant ne les aurait jamais
  // appliquées (§engineVendor étape 5).
  double _volume = AetherVolume.initial;

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

    _media = widget.initialMedia;
    _currentPath = _media.path;
    // §engineVendor étape 6 — Il n'y a plus qu'un moteur : Media3/ExoPlayer.
    // Le sélecteur du banc d'essai et l'implémentation libmpv sont partis avec
    // libmpv lui-même. `_ctrl` reste typé [AetherPlaybackEngine] : l'interface
    // garde son intérêt (elle borne ce que le lecteur a le droit de demander au
    // moteur, et c'est elle qui a rendu la bascule possible sans réécrire le
    // lecteur), même avec une seule implémentation.
    _ctrl = Media3Engine();
    _listenErrors();
    _listenPlaybackForWakelock();
    _listenVideoParamsForQuality();
    _listenCompleted();
    WidgetsBinding.instance.addObserver(this);
    _openMedia();
    _startHideTimer();
    _initBrightness();
    _startProgressTracking();

    _remoteHandlers = PlayerActionHandlers(
      togglePlayPause: _togglePlayPause,
      setPlaying: _setPlaying,
      nextEpisode: widget.onRequestNext == null ? null : _requestNextEpisode,
      seek: _handleSeek,
      changeVolume: _handleVolumeChange,
      toggleControls: _toggleControls,
      showControls: _showControls,
      showOptions: _showPlayerOptionsPanel,
      exitPlayer: AppBack.popFromUi,
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
    _playingSub = _ctrl.playingStream.listen((playing) {
      if (playing) {
        _acquireWakelock();
        // §liveRecover — La lecture est repartie : les compteurs de secours
        // repartent avec elle.
        //
        // ⚠️ Défaut trouvé À LA VÉRIFICATION sur appareil : sans cette remise à
        // zéro, `_inPlaceRecoveries` ne redescendait jamais. Trois coupures
        // espacées d'une heure épuisaient le budget, et le reste de la séance
        // ne connaissait plus que la réouverture complète — exactement ce que
        // §liveRecover corrige. Même raisonnement pour `_retryCount` : trois
        // incidents distincts ne sont pas un incident qui s'aggrave.
        if (_inPlaceRecoveries != 0 || _retryCount != 0) {
          debugPrint('✅ §liveRecover — lecture rétablie, compteurs remis à zéro '
              '(reprises=$_inPlaceRecoveries, réouvertures=$_retryCount)');
        }
        _inPlaceRecoveries = 0;
        _retryCount = 0;
      } else {
        _releaseWakelock();
      }
    });
  }

  /// §qualityTruth — Enregistre la définition réellement décodée, à chaque
  /// lecture.
  ///
  /// ⚠️ Volontairement **indépendant de l'encart §videoStats** : celui-ci
  /// s'active à la demande, alors que la mesure n'a de valeur que si elle
  /// s'accumule toute seule, sur tous les flux lus. Elle ne coûte rien de plus
  /// — la taille vidéo est un flux que le moteur publie déjà.
  ///
  /// Une seule écriture par lecture (`_measuredKey`) : le moteur republie ces
  /// paramètres à chaque reconfiguration de la chaîne vidéo.
  void _listenVideoParamsForQuality() {
    _videoParamsSub = _ctrl.videoParamsStream.listen((params) {
      final h = params.h;
      final w = params.w;
      if (h == null || w == null || h <= 0 || w <= 0) return;
      final key = _media.resumeKey;
      if (key == _measuredKey) return;
      _measuredKey = key;
      MeasuredQualityService.record(key, width: w, height: h);
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
        } else if (_ctrl.playing) {
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
    final pos = _ctrl.position;
    final dur = _ctrl.duration;
    if (dur <= Duration.zero) return;
    // §episodeMeta — clé du contenu COURANT, pas celle du widget : après une
    // bascule d'épisode, écrire sur l'ancienne clé fausserait les reprises.
    // saveProgress applique ses propres règles (min duration, threshold 95%, etc.).
    WatchProgressService.saveProgress(_media.resumeKey, pos, dur);
  }

  // ── §episodeMeta / §autoNextEp — Enchaînement d'épisodes ─────────────────

  /// Souscription à la fin de lecture (déclenche l'enchaînement).
  StreamSubscription<bool>? _completedSub;

  /// Décompte avant bascule automatique ; `null` = aucun encart affiché.
  Timer? _autoNextTimer;
  int _autoNextRemaining = 0;

  /// État de l'encart de fin, `null` tant que la lecture est en cours.
  EndOfPlaybackKind? _endOfPlayback;

  static const int _autoNextCountdownSeconds = 8;

  /// Garde de ré-entrance : `completed` peut réémettre (notamment au moment où
  /// l'on ouvre le média suivant) et `_onPlaybackCompleted` est asynchrone.
  bool _handlingCompletion = false;

  void _listenCompleted() {
    _completedSub = _ctrl.completedStream.listen((done) {
      if (!done || !mounted) return;
      // Live et replay n'ont pas de « fin » exploitable.
      if (_skipProgress) return;
      if (_handlingCompletion || _endOfPlayback != null) return;
      // Une durée nulle = flux pas encore chargé : `completed` peut passer à
      // `true` transitoirement à l'ouverture, ce n'est pas une vraie fin.
      if (_ctrl.duration <= Duration.zero) return;
      _onPlaybackCompleted();
    });
  }

  /// Résout le prochain contenu (une seule fois — le résultat est mis en cache,
  /// cf. [PlayerPage.onRequestNext]).
  Future<PlayerMedia?> _resolveNext() async {
    if (_pendingNext != null) return _pendingNext;
    final request = widget.onRequestNext;
    if (request == null) return null;
    if (mounted) setState(() => _loadingNext = true);
    try {
      final next = await request();
      _pendingNext = next;
      return next;
    } catch (e) {
      debugPrint('⚠️ §episodeMeta onRequestNext : $e');
      return null;
    } finally {
      if (mounted) setState(() => _loadingNext = false);
    }
  }

  /// Bouton ⏭ / panneau d'options / touche média « piste suivante ».
  Future<void> _requestNextEpisode() async {
    if (_loadingNext) return;
    _cancelAutoNext();
    final next = await _resolveNext();
    if (!mounted) return;
    if (next == null) {
      AppSnackBar.show(context, 'Dernier épisode disponible.');
      return;
    }
    await _switchTo(next);
  }

  /// §episodeMeta — Change de contenu **sans changer de route**.
  ///
  /// L'ancien enchaînement démontait le player et en poussait un nouveau :
  /// contrôleur `media_kit` détruit puis recréé (écran noir + re-buffering
  /// complet, très visible sur box TV) et métadonnées figées à la construction.
  Future<void> _switchTo(PlayerMedia next) async {
    // Clore proprement le contenu courant avant d'écraser `_media`.
    _saveProgress();
    _progressTimer?.cancel();
    _pendingRetryTimer?.cancel();
    _cancelAutoNext();

    if (!mounted) return;
    setState(() {
      _media = next;
      _pendingNext = null;
      _endOfPlayback = null;
      _currentPath = next.path; // sinon un retry .ts/.m3u8 de l'épisode
      _retryCount = 0; //        précédent contaminerait le suivant
      _inPlaceRecoveries = 0; // §liveRecover — même raison
      _measuredKey = null; // §qualityTruth — le suivant doit être mesuré aussi
      _hasError = false;
      _errorMessage = '';
      _seekAccumSeconds = 0;
      _seekOverlayVisible = false;
    });

    // §audioFallback — Les pistes écartées valaient pour le média PRÉCÉDENT.
    _rejectedAudioIds.clear();
    _audioGaveUp = false;

    await _openMedia();
    if (!mounted) return;
    _startProgressTracking();
    _showControls();
    debugPrint('▶️ §episodeMeta : bascule sur « ${next.title} ».');
  }

  Future<void> _onPlaybackCompleted() async {
    if (widget.onRequestNext == null) return;
    _handlingCompletion = true;
    try {
      await _resolveAndShowEndOverlay();
    } finally {
      _handlingCompletion = false;
    }
  }

  Future<void> _resolveAndShowEndOverlay() async {
    final next = await _resolveNext();
    if (!mounted) return;

    if (next == null) {
      // Fin de série : rien à enchaîner.
      setState(() => _endOfPlayback = EndOfPlaybackKind.endOfSeries);
      return;
    }

    if (_media.crossesSeasonTo(next)) {
      // Changer de saison est une décision : on attend une action explicite,
      // pas de décompte.
      setState(() => _endOfPlayback = EndOfPlaybackKind.endOfSeason);
      return;
    }

    if (!PerformanceSettingsService.config.value.autoNextEpisode) {
      setState(() => _endOfPlayback = EndOfPlaybackKind.manual);
      return;
    }
    _startAutoNextCountdown(next);
  }

  void _startAutoNextCountdown(PlayerMedia next) {
    setState(() {
      _endOfPlayback = EndOfPlaybackKind.countdown;
      _autoNextRemaining = _autoNextCountdownSeconds;
    });
    _autoNextTimer?.cancel();
    _autoNextTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_autoNextRemaining <= 1) {
        t.cancel();
        _switchTo(next);
        return;
      }
      setState(() => _autoNextRemaining--);
    });
  }

  void _cancelAutoNext() {
    _autoNextTimer?.cancel();
    _autoNextTimer = null;
  }

  /// « Annuler » : on reste sur l'écran de fin sans enchaîner.
  void _dismissEndOverlay() {
    _cancelAutoNext();
    if (mounted) setState(() => _endOfPlayback = null);
  }

  Future<void> _initBrightness() async {
    try {
      _brightness = await ScreenBrightness().current;
    } catch (_) {}
  }

  Future<void> _openMedia() async {
    try {
      // §resumeStart — Position de reprise passée NATIVEMENT au moteur via
      // `loadUrl(startAt:)` (cf. Media3Engine.open) : même garantie qu'avant —
      // un seek post-open peut être avalé pendant le buffering initial, la
      // lecture repartirait alors à 0. Pas de reprise pour les sources
      // live/replay (`_skipProgress`).
      final start = (_skipProgress) ? null : _media.startPosition;
      // §trackLangPref — Préférence de langue posée AVANT l'open (le moteur
      // choisit la piste au chargement → plus de switch/re-demux ~3 s = « le
      // film se relance »). Pas pour live/replay.
      final audioLang = _skipProgress ? null : TrackPreferencesService.audio;
      final subLang = _skipProgress ? null : TrackPreferencesService.subtitle;
      if (_media.sourceType == VideoSourceType.file) {
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
    await showTrackSelector(context, _ctrl);
    if (mounted) _startHideTimer();
  }

  /// §tvPlayerNav + §playerOptionsTouch — Panneau d'options du lecteur :
  /// pistes audio/sous-titres, vitesse, format d'image, infos vidéo, épisode
  /// suivant. Tout focusable au D-pad.
  ///
  /// Ouvert par ↑ / appui long sur TV, et par le bouton ⚙ des contrôles au
  /// tactile — l'ancien nom `_showPlayerOptionsPanel` laissait croire à un chemin
  /// réservé à la télécommande, ce qui est précisément l'oubli qu'on corrige.
  Future<void> _showPlayerOptionsPanel() async {
    _hideTimer?.cancel();
    await showPlayerOptions(
      context,
      hasNext: widget.onRequestNext != null,
      speedLabel: _speed == 1.0 ? 'Normale (1.0×)' : '$_speed×',
      fitMode: _fit,
      statsEnabled: _statsEnabled,
      onToggleStats: () {
        Navigator.of(context).pop();
        _toggleStats();
      },
      onFit: () {
        Navigator.of(context).pop();
        _showFitMenu();
      },
      onTracks: () {
        Navigator.of(context).pop();
        _showTrackSelector();
      },
      onSpeed: () {
        Navigator.of(context).pop();
        _showSpeedMenu();
      },
      onNext: widget.onRequestNext == null
          ? null
          : () {
              Navigator.of(context).pop();
              _requestNextEpisode();
            },
    );
    if (mounted) _startHideTimer();
  }

  /// §videoStats — Bascule l'encart de diagnostic vidéo.
  void _toggleStats() {
    final next = !_statsEnabled;
    setState(() => _statsEnabled = next);
    VideoStatsPreference.set(next);
  }

  /// §videoFit — Sous-menu Format d'image (Original / Zoom / Plein écran).
  ///
  /// Même chemin sur mobile et sur TV : un menu qui NOMME les trois modes,
  /// plutôt qu'un bouton qui cycle en aveugle. Sur une image déjà plein cadre
  /// (source 16/9 sur écran 16/9), les trois rendus sont identiques — sans
  /// libellé, l'utilisateur croirait le bouton cassé.
  Future<void> _showFitMenu() async {
    _hideTimer?.cancel();
    await showVideoFitMenu(
      context,
      current: _fit,
      onSelect: (mode) {
        setState(() => _fit = mode);
        VideoFitPreference.set(mode);
        Navigator.of(context).pop();
      },
    );
    if (mounted) _startHideTimer();
  }

  /// §tourFix — Point de passage unique pour changer la vitesse (sous-menu et
  /// badge inline) : état + moteur mis à jour ensemble, aucune voie ne peut en
  /// oublier l'autre.
  void _setSpeed(double s) {
    setState(() => _speed = s);
    _ctrl.setRate(s);
  }

  /// §tvPlayerNav — Sous-menu Vitesse.
  Future<void> _showSpeedMenu() async {
    await showSpeedMenu(
      context,
      current: _speed,
      onSelect: (s) {
        _setSpeed(s);
        Navigator.of(context).pop();
      },
    );
  }

  /// §audioFallback — Bascule sur une autre piste audio, sinon coupe le son.
  ///
  /// ⚠️ §tourFix (2026-09-02) — Chemin actuellement INATTEIGNABLE : il n'est
  /// déclenché que par [isAudioDecodeError], qui reconnaît des libellés
  /// d'erreur **mpv**, alors que Media3Engine n'émet plus qu'une chaîne
  /// constante ('Lecture impossible'). Conservé tel quel : la logique de
  /// bascule reste juste, le rebranchement se fera sur les erreurs typées
  /// Media3 (§engineFeatures) — cf. l'en-tête de `player_error.dart`.
  ///
  /// Retourne `true` si on a pris la main (donc pas de retry réseau : le flux
  /// n'a rien fait de mal, c'est la piste choisie qui ne se décode pas).
  ///
  /// ⚠️ La piste fautive est mémorisée dans [_rejectedAudioIds] : sans ça, le
  /// moteur peut la re-sélectionner et on tournerait en rond entre deux pistes
  /// indécodables. ⚠️ En dernier recours on lit **sans son** plutôt que
  /// d'abandonner : une image sans audio reste regardable, un écran d'erreur
  /// non — mais on le DIT, sinon ça passe pour une panne.
  bool _recoverFromAudioError() {
    final current = _ctrl.currentAudioTrack;
    if (current == null) return false;
    _rejectedAudioIds.add(current.id);

    // §engineVendor étape 3 — `isSpecial` remplace le test en dur sur les
    // identifiants mpv « no »/« auto » : ces valeurs n'existent que pour ce
    // moteur, et le prochain n'aura pas les mêmes.
    final candidates = _ctrl.audioTracks.where((t) {
      if (t.isSpecial) return false;
      return !_rejectedAudioIds.contains(t.id);
    }).toList();

    if (candidates.isNotEmpty) {
      final next = candidates.first;
      debugPrint('🔈 §audioFallback — piste « ${current.id} » indécodable, '
          'bascule sur « ${next.id} » (${next.language ?? "langue inconnue"})');
      _ctrl.setAudioTrack(next);
      if (mounted) {
        AppSnackBar.show(
          context,
          'Piste audio incompatible — bascule sur '
          '${next.title ?? next.language ?? "une autre piste"}',
          duration: const Duration(seconds: 3),
        );
      }
      return true;
    }

    if (_audioGaveUp) return false; // déjà muet et ça échoue encore → vrai échec
    _audioGaveUp = true;
    debugPrint('🔇 §audioFallback — aucune piste audio décodable, '
        'lecture sans son');
    _ctrl.disableAudio();
    if (mounted) {
      AppSnackBar.show(
        context,
        'Aucune piste audio lisible sur ce fichier — lecture sans son',
        duration: const Duration(seconds: 4),
      );
    }
    return true;
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
    _errorSub = _ctrl.errorStream.listen((error) {
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
    // §retryBurst — mpv émet la MÊME erreur plusieurs fois d'affilée (mesuré
    // sur device : 4 événements dans la même milliseconde). Chaque événement
    // incrémentait `_retryCount` et ré-armait le timer, qui n'avait donc jamais
    // le temps de se déclencher : les 3 tentatives étaient brûlées d'un coup et
    // la reconnexion « ×3, délai 5 s » ne servait à RIEN — pas même pour les
    // coupures réseau pour lesquelles elle a été écrite.
    // Tant qu'un retry est armé, ou qu'on a déjà rendu les armes, on ignore.
    if (_pendingRetryTimer != null || _hasError || _recovering) return;

    // §audioFallback — Un échec de DÉCODAGE AUDIO ne doit pas tuer la lecture.
    // Mesuré sur device : sur un fichier 4K, mpv rendait déjà la vidéo
    // (`VideoOutput.Resize 3832x1604`) quand la piste TrueHD l'a fait échouer.
    // Ces fichiers embarquent presque toujours une piste de secours (AC3/EAC3).
    if (isAudioDecodeError(error) && _recoverFromAudioError()) return;

    // §liveRecover — REPRENDRE avant de RECHARGER.
    //
    // Le défaut mesuré sur une chaîne 4K : couper le réseau vidait le tampon,
    // le moteur émettait une erreur, et la seule réponse de l'app était
    // `_openMedia()` — une réouverture complète. Relevé au journal : un `load`
    // natif, toutes les statistiques remises à zéro, décodeur recréé, ~3,5 s
    // d'écran noir. Pour une simple respiration du réseau.
    //
    // `recoverInPlace()` re-prépare la source DÉJÀ chargée : même connexion
    // logique, même sélection de pistes, pas de nouvelle vue. C'est la reprise
    // que Media3 documente. On l'essaie EN PREMIER, et **sans le délai de 5 s** :
    // attendre n'a de sens que pour laisser un serveur se remettre, pas pour
    // relancer un tampon.
    //
    // ⚠️ Budget borné : si la reprise en place échoue à se stabiliser (erreur
    // qui revient aussitôt), on retombe sur la réouverture. Sans ce plafond,
    // une source réellement morte ferait boucler la reprise en silence.
    if (_inPlaceRecoveries < _maxInPlaceRecoveries) {
      _inPlaceRecoveries++;
      _recovering = true;
      debugPrint('🔁 §liveRecover — tentative de reprise en place '
          '$_inPlaceRecoveries/$_maxInPlaceRecoveries');
      _ctrl.recoverInPlace().then((ok) {
        _recovering = false;
        if (ok || !mounted) return;
        // Le moteur n'avait rien à reprendre → filet historique.
        _scheduleReload(error);
      });
      return;
    }

    _scheduleReload(error);
  }

  /// Réouverture complète — le filet, quand la reprise en place ne suffit pas.
  void _scheduleReload(String error) {
    if (_retryCount < _maxRetries) {
      _retryCount++;
      // Retry 2 : tente l'extension alternative
      if (_retryCount == 2) {
        final alt = _altExtUrl(_media.path);
        if (alt != null) {
          _currentPath = alt;
          debugPrint(
              '⚠️ PlayerPage: retry $_retryCount/$_maxRetries — extension alternative: $alt');
        }
      } else {
        _currentPath = _media.path; // retour à l'URL originale
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
    final pos = _ctrl.position + delta;
    _ctrl.seek(pos.isNegative ? Duration.zero : pos);
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
    _volume = (_volume + delta).clamp(0.0, AetherVolume.max);
    _ctrl.setVolume(_volume);
  }

  // §3c-5 — Helpers consommés par TvPlayerShortcuts pour la nav télécommande.
  void _togglePlayPause() {
    _ctrl.playOrPause();
    _showControls();
  }

  /// §mediaKeys — Lecture/pause explicite (touches PLAY et PAUSE séparées de la
  /// télécommande). Basculer serait faux : PAUSE sur une vidéo déjà en pause la
  /// relancerait.
  void _setPlaying(bool play) {
    if (play) {
      _ctrl.play();
    } else {
      _ctrl.pause();
    }
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
      _currentPath = _media.path;
    });
    _openMedia();
  }

  /// §stallCount — Verse le bilan de la session au compte source.
  ///
  /// ⚠️ **Lu ICI et pas ailleurs** : c'est le seul instant où la mesure est
  /// complète, et `AetherPlaybackHealth` est justement synchrone pour être
  /// lisible depuis un `dispose()`. Appelé AVANT `_ctrl.dispose()`, qui coupe
  /// les analytics.
  ///
  /// Rien n'est enregistré pour un fichier local (`accountId` vide) ni pour une
  /// session trop courte : le service refuse les deux, parce qu'ils ne disent
  /// rien du fournisseur et fausseraient la moyenne.
  void _recordPlaybackHealth() {
    final h = _ctrl.health;
    if (!h.isMeaningful) return;
    PlaybackHealthService.record(
      accountId: _media.accountId,
      stalls: h.stalls,
      stalled: h.stalled,
      watched: h.watched,
      startup: h.startup,
    );
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
    _recordPlaybackHealth();
    _playingSub?.cancel();
    _videoParamsSub?.cancel();
    _errorSub?.cancel();
    _completedSub?.cancel();
    _autoNextTimer?.cancel();
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
        // §tourFix — Le mode lock ignorait la télécommande : cadenas fermé,
        // OK faisait play/pause, ←/→ seekaient, ↑ ouvrait les options. Tout est
        // désormais court-circuité, mais JAMAIS en silence : ↓ et OK révèlent
        // les contrôles (donc le cadenas), exactement comme le tap simple resté
        // actif au tactile. Une commande verrouillée qui ne produit aucun
        // retour se lit comme une panne, pas comme un verrou.
        //
        // ⚠️ Le cadenas lui-même n'est atteignable qu'au pointeur (c'est un
        // `IconButton` hors traversée dpad, et cette racine consomme les
        // directions) : à la télécommande SEULE on ne peut ni verrouiller ni
        // déverrouiller — pas de piège, mais pas non plus un mode « TV ».
        // Le rendre focusable est un sujet §navBlind, pas §tourFix.
        onSelect: () {
          if (_isLocked) {
            _showControls();
            return;
          }
          _togglePlayPause();
        },
        onLongSelect: () {
          if (_isLocked) return;
          _showPlayerOptionsPanel();
        },
        onDirection: (dir) {
          // Verrouillé : les directions bloquées sont CONSOMMÉES (`true`) —
          // rendre `false` laisserait le focus s'échapper de la vidéo.
          if (_isLocked && dir != TraversalDirection.down) return true;
          if (dir == TraversalDirection.left) {
            _handleSeek(const Duration(seconds: -10));
            return true;
          }
          if (dir == TraversalDirection.right) {
            _handleSeek(const Duration(seconds: 10));
            return true;
          }
          if (dir == TraversalDirection.up) {
            _showPlayerOptionsPanel();
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
            //    §doubleLoader — L'UI intégrée du lecteur natif est coupée à
            //    la SOURCE (`showNativeControls: false`, cf. Media3Engine) :
            //    sans ça, ses contrôles s'empileraient sur nos
            //    `PlayerControls` + `_BufferingOverlay` → DEUX spinners de
            //    chargement au démarrage + captation des taps en double (effet
            //    de "double lancement"). On rend tout nous-mêmes.
            // §engineVendor étape 3 — Le MOTEUR produit sa surface. L'app ne
            // sait plus s'il rend dans une texture ou dans une SurfaceView, et
            // c'est précisément la différence qui motive la migration.
            //
            // §videoFit — `cover` rogne les bords pour effacer les bandes
            // noires, `fill` déforme pour remplir. Le rognage se fait à
            // l'affichage : l'image entière est toujours décodée, donc changer
            // de format est instantané et n'entraîne aucun re-décodage.
            _ctrl.buildSurface(_fit.boxFit),

            // 2. Couche gesture (transparente, capte tout sauf les contrôles).
            //    Désactivée sur TV — toutes les interactions passent par le
            //    D-pad via TvPlayerShortcuts.
            PlayerGestures(
              player: _ctrl,
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
              player: _ctrl,
              title: _media.title,
              qualityTag: _media.qualityTag,
              episodeTag: _media.episodeTag,
              seriesName: _media.seriesName,
              synopsis: _media.synopsis,
              visible: _controlsVisible,
              badgeType: _media.badgeType,
              // §dpadBack — Même chemin que la touche Retour physique (debounce
              // partagé) : un `pop()` direct doublonnait avec elle.
              onBack: AppBack.popFromUi,
              onInteraction: _showControls,
              speed: _speed,
              onSpeedChanged: _setSpeed,
              onLockChanged: (locked) => setState(() => _isLocked = locked),
              onNextEpisode:
                  widget.onRequestNext == null ? null : _requestNextEpisode,
              onShowTracks: _showTrackSelector,
              // §playerOptionsTouch — Sur TV, les boutons inline ne sont pas
              // focusables : le panneau s'ouvre déjà par ↑ / appui long, un
              // icône de plus n'y serait qu'un ornement inatteignable.
              onShowOptions: isTv ? null : _showPlayerOptionsPanel,
            ),

            // §autoNextEp — Encart de fin (décompte / fin de saison / fin de
            // série). Masqué en mode lock, comme le reste des overlays.
            if (_endOfPlayback != null && !_isLocked)
              NextEpisodeOverlay(
                kind: _endOfPlayback!,
                nextTitle: _pendingNext?.title,
                nextEpisodeTag: _pendingNext?.episodeTag,
                nextSeason: _pendingNext?.seasonNumber,
                remainingSeconds: _autoNextRemaining,
                loading: _loadingNext,
                onPlayNow: _pendingNext == null
                    ? null
                    : () => _switchTo(_pendingNext!),
                onDismiss: _dismissEndOverlay,
                onLeave: AppBack.popFromUi,
              ),

            // §1i — Overlay buffering central : visible quand le player charge
            // un nouveau segment HLS. Désactivé en mode lock pour ne pas troubler
            // la zone cliquable du cadenas.
            _BufferingOverlay(player: _ctrl, hidden: _isLocked),

            // §videoStats — Encart de diagnostic, au-dessus des contrôles pour
            // rester lisible quand ils apparaissent. Rien n'est construit tant
            // que l'utilisateur ne l'a pas activé.
            if (_statsEnabled)
              VideoStatsOverlay(
                player: _ctrl,
                hidden: _isLocked,
                // §qualityTruth — la qualité que la LISTE annonce, à confronter
                // à ce qui est réellement décodé.
                announcedQuality: _media.qualityTag,
              ),

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
            if (_media.sourceType == VideoSourceType.networkReplay)
              Positioned(
                left: 16,
                right: 16,
                bottom: 90,
                child: PlayerReplayBar(
                  player: _ctrl,
                  replayStart: _media.replayStart,
                  replayDuration: _media.replayDuration,
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
  final AetherPlaybackEngine player;
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
    _sub = widget.player.bufferingStream.listen((v) {
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
