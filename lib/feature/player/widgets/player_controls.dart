import 'dart:async';
import 'package:flutter/material.dart';
import '../playback_engine.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/feature/player/player_page.dart';
import 'player_options_sheet.dart' show kPlaybackSpeeds;

/// Overlay de contrôles du player.
///
/// - Barre du haut : bouton retour + titre + spinner buffering
/// - Barre du bas  : seek bar + temps + play/pause + vitesse + lock
/// - Mode lock     : masque tout sauf un bouton cadenas pour déverrouiller
class PlayerControls extends StatefulWidget {
  final AetherPlaybackEngine player;
  final String title;
  /// §watchContext a — Qualité du flux en cours (4K/FHD/HD/SD), affichée en
  /// badge sous le titre. Null = pas de badge qualité.
  final String? qualityTag;
  /// §watchContext b — Numéro saison/épisode (« S01 E04 ») affiché sous le
  /// titre quand on lit une série. Null = pas de badge épisode.
  final String? episodeTag;
  /// §watchContext — Nom de la série (breadcrumb au-dessus du titre). Null = rien.
  final String? seriesName;
  /// §watchContext — Synopsis (épisode/film) affiché sous les badges, tronqué.
  final String? synopsis;
  final bool visible;
  final bool isFullScreen;
  final PlayerBadgeType badgeType;
  final VoidCallback onBack;
  final VoidCallback onInteraction;
  final VoidCallback? onToggleFullScreen;
  /// §1i — Notifie le parent quand l'utilisateur (dé)verrouille.
  /// Le parent ([PlayerPage]) propage l'état aux [PlayerGestures] pour
  /// désactiver les gestes en mode lock.
  final ValueChanged<bool>? onLockChanged;
  /// §1i — Si non-null, affiche un bouton "épisode suivant" qui appelle ce
  /// callback (utilisé pour les séries depuis [DetailsPage]).
  final VoidCallback? onNextEpisode;
  /// §5 — Si non-null, affiche un bouton CC qui ouvre le sélecteur de pistes
  /// audio / sous-titres (géré par [PlayerPage] pour suspendre l'auto-hide).
  final VoidCallback? onShowTracks;

  /// §pipPhone — Si non-null, affiche un bouton « Réduire en fenêtre »
  /// (téléphone seulement — `PlayerPage` passe `null` sur TV, en verrou, en
  /// erreur ou si le système ne sait pas faire de PiP).
  final VoidCallback? onEnterPip;

  /// §castSend — Si non-null, affiche le bouton « Diffuser » (téléphone
  /// seulement : sur TV, on EST le téléviseur). [castActive] change l'icône
  /// pour dire qu'une diffusion est en cours.
  final VoidCallback? onCast;
  final bool castActive;

  /// §playerOptionsTouch — Ouvre le panneau d'options du lecteur (format
  /// d'image, infos vidéo, pistes, vitesse…).
  ///
  /// ⚠️ Ce panneau n'avait qu'une porte D-pad (↑ / appui long sur la vidéo) :
  /// au tactile, il était **inatteignable**, et avec lui tout ce qui n'a pas
  /// de bouton inline — dont « Infos vidéo » (§videoStats). D'où ce bouton,
  /// posé côté mobile uniquement : sur TV les boutons inline sont des
  /// `GestureDetector` non focusables, un icône de plus ne ferait qu'encombrer
  /// une barre qu'on ne peut pas atteindre.
  final VoidCallback? onShowOptions;

  /// §tourFix — Vitesse courante, possédée par [PlayerPage]. Ce widget avait
  /// SA copie, jamais synchronisée avec celle du sous-menu Vitesse : le badge
  /// restait figé à 1.0× quand on changeait la vitesse depuis le panneau TV.
  final double speed;

  /// §tourFix — Le badge inline demande le changement au propriétaire au lieu
  /// d'appeler `setRate` lui-même : une seule voie, un seul état.
  final ValueChanged<double> onSpeedChanged;

  const PlayerControls({
    super.key,
    required this.player,
    required this.title,
    this.qualityTag,
    this.episodeTag,
    this.seriesName,
    this.synopsis,
    required this.visible,
    this.isFullScreen = false,
    this.badgeType = PlayerBadgeType.none,
    required this.onBack,
    required this.onInteraction,
    this.onToggleFullScreen,
    required this.speed,
    required this.onSpeedChanged,
    this.onLockChanged,
    this.onNextEpisode,
    this.onShowTracks,
    this.onShowOptions,
    this.onEnterPip,
    this.onCast,
    this.castActive = false,
  });

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  bool _locked = false;

  // État du player.
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;
  bool _buffering = true;

  // Seek bar.
  bool _draggingSeek = false;
  double _seekValue = 0.0;

  final List<StreamSubscription> _subs = [];

  /// §tourFix — Mémorise sans repeindre quand les contrôles sont cachés.
  ///
  /// Ils ne sont jamais démontés (AnimatedOpacity + IgnorePointer) : chaque
  /// tick de position déclenchait donc un rebuild de l'overlay invisible —
  /// un rebuild PERMANENT pendant toute la lecture, mesuré sur Fire Stick.
  /// Les champs restent à jour, donc à la réapparition (rebuild déclenché par
  /// le parent via `visible`) la seek bar repart des valeurs courantes.
  void _update(VoidCallback apply) {
    apply();
    if (widget.visible) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _subs.addAll([
      widget.player.playingStream.listen((v) => _update(() => _playing = v)),
      widget.player.positionStream.listen((v) {
        if (!_draggingSeek) _update(() => _position = v);
      }),
      widget.player.durationStream.listen((v) => _update(() => _duration = v)),
      widget.player.bufferStream.listen((v) => _update(() => _buffer = v)),
      widget.player.bufferingStream
          .listen((v) => _update(() => _buffering = v)),
    ]);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  void _togglePlayPause() {
    widget.player.playOrPause();
    widget.onInteraction();
  }

  void _seekTo(double ratio) {
    if (_duration == Duration.zero) return;
    widget.player
        .seek(Duration(milliseconds: (ratio * _duration.inMilliseconds).round()));
    widget.onInteraction();
  }

  void _cycleSpeed() {
    // `indexOf` renvoie -1 si la vitesse courante n'est pas dans la liste
    // (impossible en pratique) : (-1 + 1) % n = 0 → on repart du début.
    final idx = kPlaybackSpeeds.indexOf(widget.speed);
    final next = kPlaybackSpeeds[(idx + 1) % kPlaybackSpeeds.length];
    widget.onSpeedChanged(next);
    widget.onInteraction();
  }

  double get _progress =>
      _duration.inMilliseconds > 0
          ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
          : 0.0;

  double get _bufferRatio =>
      _duration.inMilliseconds > 0
          ? (_buffer.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
          : 0.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: widget.visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 250),
      child: IgnorePointer(
        ignoring: !widget.visible,
        child: _locked ? _buildLockOverlay() : _buildFullControls(),
      ),
    );
  }

  /// Mode lock : seul le bouton cadenas est affiché.
  Widget _buildLockOverlay() {
    return Align(
      alignment: Alignment.topRight,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: _LockButton(
            locked: true,
            onTap: () {
              setState(() => _locked = false);
              widget.onLockChanged?.call(false);
              widget.onInteraction();
            },
          ),
        ),
      ),
    );
  }

  /// Contrôles complets : dégradés + barre haute + barre basse.
  Widget _buildFullControls() {
    final displayPosition =
        _draggingSeek
            ? Duration(
                milliseconds:
                    (_seekValue * _duration.inMilliseconds).round())
            : _position;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Dégradé haut.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            // §watchContext — scrim haut allongé : couvre le bloc d'infos
            // enrichi (série + titre + badges + synopsis) → texte lisible.
            height: 160,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
          ),
        ),
        // Dégradé bas.
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 130,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
          ),
        ),

        // Barre haute : retour + titre + buffering.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Row(
              // §watchContext — bloc d'infos potentiellement multi-lignes
              // (série + titre + badges + synopsis) → on aligne en haut pour
              // que la flèche retour et le badge droite restent en tête.
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: widget.onBack,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // §watchContext — Nom de la série au-dessus du titre.
                      if (widget.seriesName != null &&
                          widget.seriesName != widget.title)
                        Text(
                          widget.seriesName!,
                          style: TextStyle(
                            color: Colors.white.withAlpha(180),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      // Titre (nom d'épisode pour une série, sinon film/chaîne).
                      Text(
                        widget.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // §watchContext a/b — Badges contextuels : saison/épisode
                      // puis qualité du flux en cours.
                      if (widget.episodeTag != null || widget.qualityTag != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Wrap(
                            spacing: 6,
                            children: [
                              if (widget.episodeTag != null)
                                _PlayerTag(
                                    text: widget.episodeTag!,
                                    color: kAccentSecondary),
                              if (widget.qualityTag != null)
                                _PlayerTag(
                                    text: widget.qualityTag!,
                                    color: _qualityTagColor(widget.qualityTag!)),
                            ],
                          ),
                        ),
                      // §watchContext — Synopsis tronqué (si TMDB/provider dispo).
                      // Largeur bornée à l'Expanded + 2 lignes max → ne déborde
                      // jamais sur les badges droite ni sur les contrôles bas.
                      if (widget.synopsis != null &&
                          widget.synopsis!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 5, right: 8),
                          child: Text(
                            widget.synopsis!,
                            style: TextStyle(
                              color: Colors.white.withAlpha(190),
                              fontSize: 11,
                              height: 1.35,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                // §castSend — Diffuser sur un Chromecast. Même logique de
                // placement que le PiP : envoyer l'image ailleurs est un geste
                // de sortie, il vit dans la barre du haut.
                if (widget.onCast != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _TapTarget(
                      tooltip: widget.castActive
                          ? 'Diffusion en cours'
                          : 'Diffuser sur un Chromecast',
                      onTap: widget.onCast!,
                      child: Icon(
                        widget.castActive
                            ? Icons.cast_connected_rounded
                            : Icons.cast_rounded,
                        color: widget.castActive ? kAccentPrimary : Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                // §pipPhone — Réduire en fenêtre. Placé ICI (barre du haut,
                // comme ⚙) plutôt que dans le panneau d'options : c'est un
                // geste de sortie, on ne va pas le chercher à deux niveaux.
                if (widget.onEnterPip != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _TapTarget(
                      tooltip: 'Réduire en fenêtre',
                      onTap: widget.onEnterPip!,
                      child: const Icon(
                        Icons.picture_in_picture_alt_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                // Badge contextuel (live / film / série).
                if (widget.badgeType != PlayerBadgeType.none)
                  _ContentBadge(type: widget.badgeType),
                if (_buffering)
                  const Padding(
                    padding: EdgeInsets.only(right: 16),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Barre basse : seek + boutons.
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Seek bar avec buffer visible.
                  Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      // Barre buffer (fond).
                      LinearProgressIndicator(
                        value: _bufferRatio,
                        backgroundColor: Colors.white24,
                        color: Colors.white38,
                        minHeight: 3,
                      ),
                      // Slider de progression.
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: kAccentPrimary,
                          inactiveTrackColor: Colors.transparent,
                          thumbColor: Colors.white,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 14),
                          trackHeight: 3,
                        ),
                        child: Slider(
                          value: _draggingSeek
                              ? _seekValue
                              : _progress,
                          min: 0,
                          max: 1,
                          onChangeStart: (v) => setState(() {
                            _draggingSeek = true;
                            _seekValue = v;
                          }),
                          onChanged: (v) =>
                              setState(() => _seekValue = v),
                          onChangeEnd: (v) {
                            setState(() => _draggingSeek = false);
                            _seekTo(v);
                          },
                        ),
                      ),
                    ],
                  ),

                  // Boutons + temps.
                  Row(
                    children: [
                      // Temps courant / total.
                      Text(
                        _fmt(displayPosition),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                      const Text(
                        ' / ',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                      Text(
                        _fmt(_duration),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                      const Spacer(),
                      // §playerOptionsTouch — Accès tactile au panneau
                      // d'options (format d'image, infos vidéo…).
                      if (widget.onShowOptions != null) ...[
                        _TapTarget(
                          tooltip: 'Options de lecture',
                          onTap: () {
                            widget.onShowOptions?.call();
                            widget.onInteraction();
                          },
                          child: const Icon(
                            Icons.tune_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      // §5 — Bouton CC : ouvre le sélecteur de pistes audio /
                      // sous-titres (PlayerPage suspend l'auto-hide pendant).
                      if (widget.onShowTracks != null) ...[
                        _TapTarget(
                          tooltip: 'Pistes audio et sous-titres',
                          onTap: () {
                            widget.onShowTracks?.call();
                            widget.onInteraction();
                          },
                          child: const Icon(
                            Icons.closed_caption_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      // Sélecteur de vitesse.
                      _TapTarget(
                        tooltip: 'Vitesse de lecture',
                        onTap: _cycleSpeed,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white54),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${widget.speed}x',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Play / Pause.
                      GestureDetector(
                        onTap: _togglePlayPause,
                        child: Icon(
                          _playing
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                      // §1i — Bouton épisode suivant (séries uniquement).
                      if (widget.onNextEpisode != null) ...[
                        const SizedBox(width: 4),
                        _TapTarget(
                          tooltip: 'Episode suivant',
                          onTap: () {
                            widget.onNextEpisode?.call();
                            widget.onInteraction();
                          },
                          child: const Icon(
                            Icons.skip_next,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      // Bouton Fullscreen (Windows/Desktop).
                      if (widget.onToggleFullScreen != null)
                        IconButton(
                          icon: Icon(
                            widget.isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                            color: Colors.white70,
                            size: 26,
                          ),
                          tooltip: widget.isFullScreen ? 'Exit fullscreen' : 'Fullscreen',
                          onPressed: widget.onToggleFullScreen,
                        ),
                      const SizedBox(width: 8),
                      // Bouton lock.
                      _LockButton(
                        locked: false,
                        onTap: () {
                          setState(() => _locked = true);
                          widget.onLockChanged?.call(true);
                          widget.onInteraction();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// §watchContext — Couleur du badge qualité (réutilise le code couleur
/// sémantique). Insensible à la casse.
Color _qualityTagColor(String q) {
  switch (q.toUpperCase()) {
    case '4K':
      return kQuality4K;
    case 'FHD':
      return kQualityFHD;
    case 'HD':
      return kQualityHD;
    case 'SD':
      return kQualitySD;
    default:
      return kQualityUnknown;
  }
}

/// §watchContext a/b — Petite pastille contextuelle (qualité / saison-épisode)
/// affichée sous le titre du player. Contour teinté, lisible sur la vidéo.
class _PlayerTag extends StatelessWidget {
  final String text;
  final Color color;
  const _PlayerTag({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(38),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(140)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Badge contextuel affiché en haut à droite du player.
class _ContentBadge extends StatelessWidget {
  final PlayerBadgeType type;
  const _ContentBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final (Color color, String label, bool showDot) = switch (type) {
      PlayerBadgeType.live   => (kBadgeLive,        'DIRECT', true),
      PlayerBadgeType.replay => (kBadgeReplay,      'REPLAY', false),
      PlayerBadgeType.movie  => (kBadgeMovie,       'FILM',   false),
      PlayerBadgeType.series => (kBadgeSeries,      'SÉRIE',  false),
      PlayerBadgeType.none   => (Colors.transparent, '',      false),
    };

    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            const Icon(Icons.circle, color: Colors.white, size: 7),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bouton cadenas (verrouille / déverrouille les contrôles).
/// §touchTarget — Une cible tactile d'au moins 48 dp autour d'une icône, sans
/// changer sa taille visuelle.
///
/// **Le défaut corrigé** (§audit0903 n° 15) : quatre boutons sur six de la
/// barre du lecteur étaient sous 48 dp — les options ⚙ à **24×24**, et c'est
/// le SEUL accès tactile au panneau — sous une barre qui se cache en 3 s.
/// Play/Pause (48) et le cadenas (`IconButton`, 48) étaient corrects : la
/// rangée était donc incohérente avec elle-même.
///
/// ⚠️ `HitTestBehavior.opaque` est indispensable : sans lui, la zone
/// transparente autour de l'icône ne reçoit aucun tap et l'élargissement ne
/// sert à rien.
class _TapTarget extends StatelessWidget {
  const _TapTarget({
    required this.onTap,
    required this.child,
    this.tooltip,
  });

  /// La regle Material : 48 dp. Pas un reglage — une borne.
  static const double size = 48;

  final VoidCallback onTap;
  final Widget child;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final Widget target = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Center(child: child),
      ),
    );
    if (tooltip == null) return target;
    return Tooltip(message: tooltip!, child: target);
  }
}

class _LockButton extends StatelessWidget {
  final bool locked;
  final VoidCallback onTap;

  const _LockButton({required this.locked, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        locked ? Icons.lock : Icons.lock_open,
        color: Colors.white70,
        size: 22,
      ),
      tooltip: locked ? 'Déverrouiller' : 'Verrouiller',
      onPressed: onTap,
    );
  }
}
