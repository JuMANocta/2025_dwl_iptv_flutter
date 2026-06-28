import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/platform_tv.dart';

// ─── Intents ────────────────────────────────────────────────────────────────

/// Intent émis à chaque action télécommande mappée. Les implémentations sont
/// fournies par [PlayerActionHandlers] côté `PlayerPage`.
class _TogglePlayPauseIntent extends Intent {
  const _TogglePlayPauseIntent();
}

class _SeekForwardIntent extends Intent {
  const _SeekForwardIntent();
}

class _SeekBackwardIntent extends Intent {
  const _SeekBackwardIntent();
}

class _ToggleControlsIntent extends Intent {
  const _ToggleControlsIntent();
}

class _ShowControlsIntent extends Intent {
  const _ShowControlsIntent();
}

class _ShowOptionsIntent extends Intent {
  const _ShowOptionsIntent();
}

class _ToggleFullscreenIntent extends Intent {
  const _ToggleFullscreenIntent();
}

class _ExitPlayerIntent extends Intent {
  const _ExitPlayerIntent();
}

/// Callbacks fournis par [PlayerPage] pour réaliser les actions.
class PlayerActionHandlers {
  final VoidCallback togglePlayPause;

  /// Avance / recule la lecture de [delta] (négatif = recul).
  final void Function(Duration delta) seek;

  /// Modifie le volume de [delta] (échelle 0→200 en valeur absolue).
  final void Function(double delta) changeVolume;

  /// Bascule la visibilité des contrôles overlay.
  final VoidCallback toggleControls;

  /// Affiche (sans masquer) les contrôles du lecteur (révèle la barre de seek).
  final VoidCallback showControls;

  /// §tvPlayerNav — Ouvre le panneau d'options focusable (pistes audio/sous-
  /// titres, vitesse, épisode suivant) — le « centre de contrôle » TV.
  final VoidCallback showOptions;

  /// Bascule le mode plein écran (Windows).
  final VoidCallback? toggleFullscreen;

  /// Quitte le player (typiquement `Navigator.pop`).
  final VoidCallback exitPlayer;

  const PlayerActionHandlers({
    required this.togglePlayPause,
    required this.seek,
    required this.changeVolume,
    required this.toggleControls,
    required this.showControls,
    required this.showOptions,
    this.toggleFullscreen,
    required this.exitPlayer,
  });
}

/// Wrapper Shortcuts + Actions + Focus pour la navigation télécommande du
/// player (§3c-5). N'est actif QUE si `PlatformTv.isTv` ; sinon il rend
/// son [child] tel quel (pas d'interception clavier sur mobile).
///
/// Mapping (Android TV / Fire TV / Windows) :
/// | Touche                                       | Action                |
/// |----------------------------------------------|-----------------------|
/// | OK / Center / Enter / Space / GameButtonA    | Play / Pause          |
/// | MediaPlayPause / MediaPlay / MediaPause      | Play / Pause          |
/// | ←  (arrowLeft) / MediaRewind                 | Recul −10 s (scrub)   |
/// | →  (arrowRight) / MediaFastForward / MediaTrackNext / MediaTrackPrevious | Avance +10 s (scrub) |
/// | ↑  (arrowUp)                                 | Panneau d'OPTIONS     |
/// | ↓  (arrowDown)                               | Afficher la barre     |
/// | Menu / Info / ContextMenu                    | Toggle overlay        |
/// | F / F11                                      | Toggle plein écran    |
/// | Escape / Back / GameButtonB                  | Quitter le player     |
///
/// §tvPlayerNav — Les boutons inline (CC/vitesse/lock) sont des GestureDetector
/// NON focusables au D-pad : sur TV on passe par le **panneau d'options** (↑)
/// dont les items sont des FocusableCard. Le focus du player est ré-acquis après
/// chaque sheet (cf. PlayerPage `_restoreTvFocus`) pour ne pas « tuer » le D-pad.
class TvPlayerShortcuts extends StatelessWidget {
  final Widget child;
  final PlayerActionHandlers handlers;
  final Duration seekStep;
  final double volumeStep;

  /// §tvPlayerNav — Nœud de focus du player. Exposé pour que [PlayerPage] puisse
  /// RE-demander le focus après la fermeture d'un sheet/dialog (sinon le D-pad
  /// reste « mort » : `autofocus` ne se redéclenche pas au retour du dialog).
  final FocusNode? focusNode;

  const TvPlayerShortcuts({
    super.key,
    required this.child,
    required this.handlers,
    this.focusNode,
    this.seekStep = const Duration(seconds: 10),
    this.volumeStep = 5.0,
  });

  static final Map<ShortcutActivator, Intent> _shortcuts = {
    // Play / Pause
    const SingleActivator(LogicalKeyboardKey.select):
        const _TogglePlayPauseIntent(),
    const SingleActivator(LogicalKeyboardKey.enter):
        const _TogglePlayPauseIntent(),
    const SingleActivator(LogicalKeyboardKey.numpadEnter):
        const _TogglePlayPauseIntent(),
    const SingleActivator(LogicalKeyboardKey.space):
        const _TogglePlayPauseIntent(),
    const SingleActivator(LogicalKeyboardKey.gameButtonA):
        const _TogglePlayPauseIntent(),
    const SingleActivator(LogicalKeyboardKey.mediaPlayPause):
        const _TogglePlayPauseIntent(),
    const SingleActivator(LogicalKeyboardKey.mediaPlay):
        const _TogglePlayPauseIntent(),
    const SingleActivator(LogicalKeyboardKey.mediaPause):
        const _TogglePlayPauseIntent(),

    // Seek
    const SingleActivator(LogicalKeyboardKey.arrowLeft):
        const _SeekBackwardIntent(),
    const SingleActivator(LogicalKeyboardKey.arrowRight):
        const _SeekForwardIntent(),
    const SingleActivator(LogicalKeyboardKey.mediaRewind):
        const _SeekBackwardIntent(),
    const SingleActivator(LogicalKeyboardKey.mediaFastForward):
        const _SeekForwardIntent(),
    const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious):
        const _SeekBackwardIntent(),
    const SingleActivator(LogicalKeyboardKey.mediaTrackNext):
        const _SeekForwardIntent(),

    // §tvPlayerNav — ↑ ouvre le PANNEAU D'OPTIONS focusable (pistes audio/sous-
    // titres, vitesse, épisode suivant) = le centre de contrôle TV. ↓ révèle la
    // barre de seek (pour suivre la position pendant un scrub ←→). Le volume
    // reste géré par les touches volume natives de la télécommande.
    const SingleActivator(LogicalKeyboardKey.arrowUp):
        const _ShowOptionsIntent(),
    const SingleActivator(LogicalKeyboardKey.arrowDown):
        const _ShowControlsIntent(),

    // Overlay toggle
    const SingleActivator(LogicalKeyboardKey.contextMenu):
        const _ToggleControlsIntent(),
    const SingleActivator(LogicalKeyboardKey.info):
        const _ToggleControlsIntent(),

    // Fullscreen
    const SingleActivator(LogicalKeyboardKey.keyF):
        const _ToggleFullscreenIntent(),
    const SingleActivator(LogicalKeyboardKey.f11):
        const _ToggleFullscreenIntent(),

    // Quitter
    const SingleActivator(LogicalKeyboardKey.escape): const _ExitPlayerIntent(),
    const SingleActivator(LogicalKeyboardKey.gameButtonB):
        const _ExitPlayerIntent(),
  };

  @override
  Widget build(BuildContext context) {
    // Actif sur TV ET sur Windows/Desktop.
    final bool enableShortcuts = PlatformTv.isTv || Platform.isWindows;

    if (!enableShortcuts) return child;

    return Shortcuts(
      shortcuts: _shortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          _TogglePlayPauseIntent: CallbackAction<_TogglePlayPauseIntent>(
            onInvoke: (_) {
              handlers.togglePlayPause();
              return null;
            },
          ),
          _SeekForwardIntent: CallbackAction<_SeekForwardIntent>(
            onInvoke: (_) {
              handlers.seek(seekStep);
              return null;
            },
          ),
          _SeekBackwardIntent: CallbackAction<_SeekBackwardIntent>(
            onInvoke: (_) {
              handlers.seek(-seekStep);
              return null;
            },
          ),
          _ShowControlsIntent: CallbackAction<_ShowControlsIntent>(
            onInvoke: (_) {
              handlers.showControls();
              return null;
            },
          ),
          _ShowOptionsIntent: CallbackAction<_ShowOptionsIntent>(
            onInvoke: (_) {
              handlers.showOptions();
              return null;
            },
          ),
          _ToggleControlsIntent: CallbackAction<_ToggleControlsIntent>(
            onInvoke: (_) {
              handlers.toggleControls();
              return null;
            },
          ),
          _ToggleFullscreenIntent: CallbackAction<_ToggleFullscreenIntent>(
            onInvoke: (_) {
              handlers.toggleFullscreen?.call();
              return null;
            },
          ),
          _ExitPlayerIntent: CallbackAction<_ExitPlayerIntent>(
            onInvoke: (_) {
              handlers.exitPlayer();
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: focusNode,
          autofocus: true,
          child: child,
        ),
      ),
    );
  }
}
