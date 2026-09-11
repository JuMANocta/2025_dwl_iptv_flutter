import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../playback_engine.dart';
import 'player_seek_overlay.dart';

/// Couche transparente de gestion des gestures du player.
///
/// - Tap simple        → afficher/masquer les contrôles
/// - Double-tap gauche → reculer 10s (Mobile)
/// - Double-tap droite → avancer 10s (Mobile)
/// - Double-tap        → Fullscreen (Windows)
/// - Drag horizontal   → seek rapide (±60s par largeur d'écran)
/// - Drag vertical gauche → luminosité
/// - Drag vertical droite → volume
class PlayerGestures extends StatefulWidget {
  final AetherPlaybackEngine player;
  final VoidCallback onTap;
  final void Function(Duration delta) onSeek;
  final void Function(double delta) onVolumeChange;
  final void Function(double delta) onBrightnessChange;
  final VoidCallback? onDoubleTap;
  /// Lecteur de volume courant — utilisé pour afficher l'état (% boost compris).
  final double Function()? readVolume;
  /// §1i — Quand `true`, tous les gestes (sauf tap simple pour révéler le
  /// bouton de déverrouillage) sont ignorés. Pilote par [PlayerControls].
  final bool locked;

  /// §3c-5 — Quand `true`, AUCUN geste n'est traité (cas Android TV : toutes
  /// les interactions passent par la télécommande via [TvPlayerShortcuts]).
  final bool disabled;

  const PlayerGestures({
    super.key,
    required this.player,
    required this.onTap,
    required this.onSeek,
    required this.onVolumeChange,
    required this.onBrightnessChange,
    this.onDoubleTap,
    this.readVolume,
    this.locked = false,
    this.disabled = false,
  });

  @override
  State<PlayerGestures> createState() => _PlayerGesturesState();
}

/// §playerReach — Gabarit de l'encart de retour visuel (seek, volume,
/// luminosité). ⚠️ Les QUATRE types partagent ces bornes : un demi-disque plus
/// large d'un côté que de l'autre se lirait comme deux composants différents.
const double _kOverlayWidth = 104;
const double _kOverlayHeight = 116;

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

  /// §ctrlBlink (2026-09-09) — La disparition de l'encart, ANNULABLE.
  ///
  /// **Le défaut corrigé** (signalé pendant la recette : « si on laisse le
  /// doigt appuyé, au bout d'un temps ça clignote ») : chaque mise à jour du
  /// geste appelait `Future.delayed(900 ms)` — un `Future` **qu'on ne peut pas
  /// annuler**. Un glissement continu en programmait donc des dizaines, et la
  /// PREMIÈRE masquait l'encart alors que le doigt bougeait encore ; le
  /// mouvement suivant le rallumait. D'où un clignotement qui n'apparaissait
  /// qu'au bout d'un moment — le temps que la première échéance tombe.
  ///
  /// ⚠️ Un `Timer` annulable, pas un `Future.delayed` : le délai doit repartir
  /// à CHAQUE mouvement, donc compter depuis le DERNIER, pas depuis le premier.
  Timer? _overlayTimer;

  void _showOverlay(SeekOverlayType type, String label) {
    _overlayTimer?.cancel();
    setState(() {
      _overlayType = type;
      _overlayLabel = label;
      _overlayVisible = true;
    });
    _overlayTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _overlayVisible = false);
    });
  }

  @override
  void dispose() {
    _overlayTimer?.cancel();
    super.dispose();
  }

  void _handleDoubleTap() {
    if (_doubleTapPos == null) return;

    // Sur Desktop/Windows : le double tap (double clic) toggle le plein écran.
    if (Platform.isWindows && widget.onDoubleTap != null) {
      widget.onDoubleTap!();
      return;
    }

    // Sur Mobile : le double tap seek de ±10s.
    final sw = MediaQuery.of(context).size.width;
    final isLeft = _doubleTapPos!.dx < sw / 2;
    // §seekAccum — Le saut + l'overlay cumulé (« +30s ») sont gérés en amont
    // par PlayerPage._handleSeek (commun mobile/TV). On ne montre donc plus
    // d'overlay local ici pour éviter un doublon.
    widget.onSeek(Duration(seconds: isLeft ? -10 : 10));
  }

  void _onHorizontalDragStart(DragStartDetails d) {
    _dragStart = d.localPosition;
    _seekBase = widget.player.position;
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
      // Affiche le % courant ; au-delà de 100 = boost (amplification mpv).
      final v = widget.readVolume?.call();
      _showOverlay(
        SeekOverlayType.volume,
        v != null ? '${v.round()}%' : '',
      );
    }
  }

  void _onVerticalDragEnd(DragEndDetails _) => _dragStart = null;

  @override
  Widget build(BuildContext context) {
    // §3c-5 — Sur Android TV, on n'attache AUCUN handler : les actions
    // viennent toutes du clavier/D-pad via TvPlayerShortcuts.
    if (widget.disabled) {
      return const SizedBox.shrink();
    }
    // §1i — En mode lock, seul le tap reste actif (pour révéler le cadenas).
    final locked = widget.locked;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTapDown: locked ? null : (d) => _doubleTapPos = d.localPosition,
      onDoubleTap: locked ? null : _handleDoubleTap,
      onHorizontalDragStart: locked ? null : _onHorizontalDragStart,
      onHorizontalDragUpdate: locked ? null : _onHorizontalDragUpdate,
      onHorizontalDragEnd: locked ? null : _onHorizontalDragEnd,
      onVerticalDragStart: locked ? null : _onVerticalDragStart,
      onVerticalDragUpdate: locked ? null : _onVerticalDragUpdate,
      onVerticalDragEnd: locked ? null : _onVerticalDragEnd,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Surface transparente pour capturer les events.
          const ColoredBox(color: Colors.transparent),
          // Feedback seek / volume / luminosité.
          //
          // §playerReach — ⚠️ Cet encart occupait **35 % de la largeur sur
          // TOUTE la hauteur** (`width: size.width * 0.35`, `top: 0` +
          // `bottom: 0`). En paysage sur téléphone, cela faisait une dalle
          // sombre sur plus d'un tiers de l'écran pour une icône et deux
          // chiffres — signalement du 2026-09-08, « leurs largeurs est a
          // réduire ». Largeur FIXE et hauteur bornée au contenu : le repère
          // reste du bon côté de l'écran (c'est lui qui dit quel geste est en
          // cours) sans masquer l'image qu'on est justement en train de régler.
          if (_overlayVisible && _overlayType != null)
            Align(
              alignment: (_overlayType == SeekOverlayType.seekLeft ||
                      _overlayType == SeekOverlayType.brightness)
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: AnimatedOpacity(
                opacity: _overlayVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: SizedBox(
                  width: _kOverlayWidth,
                  height: _kOverlayHeight,
                  child: PlayerSeekOverlay(
                    type: _overlayType!,
                    label: _overlayLabel,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
