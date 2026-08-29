import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dpad/dpad.dart';

import '../../core/navigation/focus_route_memory.dart';
import '../../feature/player/player_action_handlers.dart';
import '../../main.dart' show navigatorKey;

/// §mediaKeys — Touches média des télécommandes TV → actions [RemoteControlService].
///
/// Aucune de ces touches n'était captée nulle part dans l'application (ni Dart,
/// ni Android natif) : PLAY, PAUSE, STOP et l'avance rapide ne faisaient
/// strictement rien. On les branche sur le vocabulaire d'actions qui existe
/// déjà pour la télécommande web, plutôt que de créer un second chemin.
///
/// Table pure (donc testable sans widget) consommée par le `Dpad` racine.
/// Non `const` : `LogicalKeyboardKey` redéfinit `==`, ce qu'une map constante
/// n'accepte pas comme clé.
final Map<LogicalKeyboardKey, String> kMediaKeyActions =
    <LogicalKeyboardKey, String>{
  LogicalKeyboardKey.mediaPlayPause: 'playpause',
  LogicalKeyboardKey.mediaPlay: 'play',
  LogicalKeyboardKey.mediaPause: 'pause',
  LogicalKeyboardKey.mediaStop: 'stop',
  LogicalKeyboardKey.mediaFastForward: 'seekfwd',
  LogicalKeyboardKey.mediaRewind: 'seekback',
  LogicalKeyboardKey.mediaTrackNext: 'next',
  LogicalKeyboardKey.mediaTrackPrevious: 'prev',
};

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

  /// §dpadNav — Bouton MENU de la télécommande (physique ou web) : pendant la
  /// lecture → bascule les contrôles ; sinon → ouvre le menu contextuel de
  /// l'élément focusé (favoris/reprise), s'il en a un.
  void invokeMenu() {
    final player = _player;
    if (player != null) {
      player.toggleControls();
      return;
    }
    _longPress?.call();
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
      // §mediaKeys — PLAY et PAUSE séparés : état explicite, pas une bascule.
      case 'play':
        p.setPlaying(true);
        break;
      case 'pause':
        p.setPlaying(false);
        break;
      case 'stop':
        p.exitPlayer();
        break;
      case 'next':
        p.nextEpisode?.call();
        break;
      case 'prev':
        // Pas d'« épisode précédent » dans l'app : on n'invente pas de
        // comportement surprenant, la touche reste sans effet.
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
      case 'down':
        // Haut / Bas → révèle les options du lecteur (cohérent avec la
        // télécommande TV physique). Le volume reste sur volup/voldown.
        p.showControls();
        break;
      case 'volup':
        p.changeVolume(5);
        break;
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
        // §dpadBack — Même chemin (et même debounce) que la touche physique.
        AppBack.popFromUi();
        break;
    }
  }

  void _move(TraversalDirection dir) {
    // §dpadNav — On délègue le déplacement au moteur `dpad` (nav par régions),
    // exactement comme une vraie touche télécommande → un déplacement = un item,
    // mémoire de région, auto-scroll. Fallback géométrique si Dpad absent.
    final ctx = FocusManager.instance.primaryFocus?.context ??
        navigatorKey.currentContext;
    if (ctx == null) return;
    final dpad = Dpad.maybeOf(ctx);
    if (dpad != null) {
      dpad.move(dir);
      return;
    }
    FocusManager.instance.primaryFocus?.focusInDirection(dir);
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
