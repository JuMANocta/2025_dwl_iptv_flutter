import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'player_seek_overlay.dart';

/// Couche transparente de gestion des gestures du player.
///
/// - Tap simple        → afficher/masquer les contrôles
/// - Double-tap gauche → reculer 10s
/// - Double-tap droite → avancer 10s
/// - Drag horizontal   → seek rapide (±60s par largeur d'écran)
/// - Drag vertical gauche → luminosité
/// - Drag vertical droite → volume
class PlayerGestures extends StatefulWidget {
  final Player player;
  final VoidCallback onTap;
  final void Function(Duration delta) onSeek;
  final void Function(double delta) onVolumeChange;
  final void Function(double delta) onBrightnessChange;

  const PlayerGestures({
    super.key,
    required this.player,
    required this.onTap,
    required this.onSeek,
    required this.onVolumeChange,
    required this.onBrightnessChange,
  });

  @override
  State<PlayerGestures> createState() => _PlayerGesturesState();
}

class _PlayerGesturesState extends State<PlayerGestures> {
  // Position du dernier double-tap (pour savoir gauche/droite).
  Offset? _doubleTapPos;

  // Feedback overlay.
  SeekOverlayType? _overlayType;
  String _overlayLabel = '';
  bool _overlayVisible = false;

  // Drag horizontal : seek.
  Offset? _dragStart;
  Duration _seekBase = Duration.zero;

  void _showOverlay(SeekOverlayType type, String label) {
    setState(() {
      _overlayType = type;
      _overlayLabel = label;
      _overlayVisible = true;
    });
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _overlayVisible = false);
    });
  }

  void _handleDoubleTap() {
    if (_doubleTapPos == null) return;
    final sw = MediaQuery.of(context).size.width;
    final isLeft = _doubleTapPos!.dx < sw / 2;
    final delta = Duration(seconds: isLeft ? -10 : 10);
    widget.onSeek(delta);
    _showOverlay(
      isLeft ? SeekOverlayType.seekLeft : SeekOverlayType.seekRight,
      isLeft ? '-10s' : '+10s',
    );
  }

  void _onHorizontalDragStart(DragStartDetails d) {
    _dragStart = d.localPosition;
    _seekBase = widget.player.state.position;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails d) {
    if (_dragStart == null) return;
    final sw = MediaQuery.of(context).size.width;
    final dx = d.localPosition.dx - _dragStart!.dx;
    // ±60s sur toute la largeur de l'écran.
    final seconds = (dx / sw * 60).round();
    final newPos = _seekBase + Duration(seconds: seconds);
    final clamped = newPos.isNegative ? Duration.zero : newPos;
    widget.player.seek(clamped);
    _showOverlay(
      seconds >= 0 ? SeekOverlayType.seekRight : SeekOverlayType.seekLeft,
      '${seconds >= 0 ? '+' : ''}${seconds}s',
    );
  }

  void _onHorizontalDragEnd(DragEndDetails _) => _dragStart = null;

  void _onVerticalDragStart(DragStartDetails d) {
    _dragStart = d.localPosition;
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    if (_dragStart == null) return;
    final sh = MediaQuery.of(context).size.height;
    final sw = MediaQuery.of(context).size.width;
    final isLeft = _dragStart!.dx < sw / 2;
    // Swipe vers le haut = positif.
    final delta = -d.delta.dy / sh;

    if (isLeft) {
      widget.onBrightnessChange(delta);
      _showOverlay(SeekOverlayType.brightness, '');
    } else {
      widget.onVolumeChange(delta * 100);
      _showOverlay(SeekOverlayType.volume, '');
    }
  }

  void _onVerticalDragEnd(DragEndDetails _) => _dragStart = null;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTapDown: (d) => _doubleTapPos = d.localPosition,
      onDoubleTap: _handleDoubleTap,
      onHorizontalDragStart: _onHorizontalDragStart,
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      onVerticalDragStart: _onVerticalDragStart,
      onVerticalDragUpdate: _onVerticalDragUpdate,
      onVerticalDragEnd: _onVerticalDragEnd,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Surface transparente pour capturer les events.
          const ColoredBox(color: Colors.transparent),
          // Feedback seek / volume / luminosité.
          if (_overlayVisible && _overlayType != null)
            AnimatedOpacity(
              opacity: _overlayVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              child: PlayerSeekOverlay(
                type: _overlayType!,
                label: _overlayLabel,
              ),
            ),
        ],
      ),
    );
  }
}
