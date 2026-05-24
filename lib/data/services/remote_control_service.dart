import 'package:flutter/material.dart';

import '../../main.dart' show navigatorKey;
import '../../feature/player/widgets/tv_player_shortcuts.dart';

/// §webConsole Phase 2 — Pont "téléphone = télécommande".
///
/// La page web "Télécommande" envoie des actions (`up/down/left/right/ok/back/
/// menu/playpause/seekfwd/seekback/volup/voldown`) en POST ; ce service les
/// exécute **au niveau applicatif** (Flutter ne permet pas d'injecter des
/// `KeyEvent` matériels proprement) :
///
///   - Navigation : `FocusScope.focusInDirection` + activation de l'élément
///     focusé (les `FocusableCard` s'enregistrent ici quand elles prennent le
///     focus → OK appelle leur `onTap`, Menu leur `onLongPress`).
///   - Lecture : quand un player est ouvert, [PlayerPage] enregistre ses
///     [PlayerActionHandlers] → les actions sont routées vers le player
///     (play/pause, seek, volume) exactement comme la télécommande TV.
class RemoteControlService {
  RemoteControlService._();
  static final RemoteControlService instance = RemoteControlService._();

  VoidCallback? _activate;
  VoidCallback? _longPress;
  Object? _activateOwner;

  PlayerActionHandlers? _player;

  /// Vrai si un player est actuellement ouvert (route player vs navigation).
  bool get playerActive => _player != null;

  // ── Enregistrement depuis l'UI ───────────────────────────────────────────

  /// Une [FocusableCard] focusée s'enregistre comme cible d'activation OK/Menu.
  void registerActivate(Object owner, VoidCallback? onTap, VoidCallback? onLongPress) {
    _activateOwner = owner;
    _activate = onTap;
    _longPress = onLongPress;
  }

  /// Libère l'enregistrement quand la card perd le focus (si c'est bien elle).
  void clearActivate(Object owner) {
    if (identical(_activateOwner, owner)) {
      _activateOwner = null;
      _activate = null;
      _longPress = null;
    }
  }

  void registerPlayer(PlayerActionHandlers handlers) => _player = handlers;
  void clearPlayer(PlayerActionHandlers handlers) {
    if (identical(_player, handlers)) _player = null;
  }

  // ── Dispatch ─────────────────────────────────────────────────────────────

  void dispatch(String action) {
    try {
      final player = _player;
      if (player != null) {
        _dispatchPlayer(player, action);
      } else {
        _dispatchNav(action);
      }
    } catch (e) {
      debugPrint('⚠️ RemoteControlService.dispatch($action): $e');
    }
  }

  void _dispatchPlayer(PlayerActionHandlers p, String action) {
    switch (action) {
      case 'ok':
      case 'playpause':
        p.togglePlayPause();
        break;
      case 'left':
      case 'seekback':
        p.seek(const Duration(seconds: -10));
        break;
      case 'right':
      case 'seekfwd':
        p.seek(const Duration(seconds: 10));
        break;
      case 'up':
      case 'volup':
        p.changeVolume(5);
        break;
      case 'down':
      case 'voldown':
        p.changeVolume(-5);
        break;
      case 'menu':
        p.toggleControls();
        break;
      case 'back':
        p.exitPlayer();
        break;
    }
  }

  void _dispatchNav(String action) {
    switch (action) {
      case 'up':
        _move(TraversalDirection.up);
        break;
      case 'down':
        _move(TraversalDirection.down);
        break;
      case 'left':
        _move(TraversalDirection.left);
        break;
      case 'right':
        _move(TraversalDirection.right);
        break;
      case 'ok':
        _activateFocused();
        break;
      case 'menu':
        _longPress?.call();
        break;
      case 'back':
        navigatorKey.currentState?.maybePop();
        break;
    }
  }

  void _move(TraversalDirection dir) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    FocusScope.of(ctx).focusInDirection(dir);
  }

  void _activateFocused() {
    if (_activate != null) {
      _activate!();
      return;
    }
    // Fallback : ActivateIntent sur l'élément focusé (boutons natifs, etc.).
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx != null) Actions.maybeInvoke(ctx, const ActivateIntent());
  }
}
