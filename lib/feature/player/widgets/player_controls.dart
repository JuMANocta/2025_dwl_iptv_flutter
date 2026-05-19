import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/feature/player/player_page.dart';

/// Overlay de contrôles du player.
///
/// - Barre du haut : bouton retour + titre + spinner buffering
/// - Barre du bas  : seek bar + temps + play/pause + vitesse + lock
/// - Mode lock     : masque tout sauf un bouton cadenas pour déverrouiller
class PlayerControls extends StatefulWidget {
  final Player player;
  final String title;
  final bool visible;
  final PlayerBadgeType badgeType;
  final VoidCallback onBack;
  final VoidCallback onInteraction;
  /// §1i — Notifie le parent quand l'utilisateur (dé)verrouille.
  /// Le parent ([PlayerPage]) propage l'état aux [PlayerGestures] pour
  /// désactiver les gestes en mode lock.
  final ValueChanged<bool>? onLockChanged;
  /// §1i — Si non-null, affiche un bouton "épisode suivant" qui appelle ce
  /// callback (utilisé pour les séries depuis [DetailsPage]).
  final VoidCallback? onNextEpisode;

  const PlayerControls({
    super.key,
    required this.player,
    required this.title,
    required this.visible,
    this.badgeType = PlayerBadgeType.none,
    required this.onBack,
    required this.onInteraction,
    this.onLockChanged,
    this.onNextEpisode,
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

  // Vitesse de lecture.
  double _speed = 1.0;
  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  // Seek bar.
  bool _draggingSeek = false;
  double _seekValue = 0.0;

  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _subs.addAll([
      widget.player.stream.playing
          .listen((v) => setState(() => _playing = v)),
      widget.player.stream.position.listen((v) {
        if (!_draggingSeek) setState(() => _position = v);
      }),
      widget.player.stream.duration
          .listen((v) => setState(() => _duration = v)),
      widget.player.stream.buffer
          .listen((v) => setState(() => _buffer = v)),
      widget.player.stream.buffering
          .listen((v) => setState(() => _buffering = v)),
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
    final idx = _speeds.indexOf(_speed);
    final next = _speeds[(idx + 1) % _speeds.length];
    setState(() => _speed = next);
    widget.player.setRate(next);
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
            height: 100,
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
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: widget.onBack,
                ),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
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
                      // Sélecteur de vitesse.
                      GestureDetector(
                        onTap: _cycleSpeed,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white54),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${_speed}x',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
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
                        const SizedBox(width: 12),
                        GestureDetector(
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
