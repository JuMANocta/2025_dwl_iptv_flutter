import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/platform_tv.dart';

// ─── Intents ────────────────────────────────────────────────────────────────

/// Intent émis à chaque action télécommande mappée. Les implémentations sont
/// fournies par [PlayerActionHandlers] côté `PlayerPage`.
class _TogglePlayPauseIntent extends Intent { const _TogglePlayPauseIntent(); }
class _SeekForwardIntent     extends Intent { const _SeekForwardIntent();     }
class _SeekBackwardIntent    extends Intent { const _SeekBackwardIntent();    }
class _VolumeUpIntent        extends Intent { const _VolumeUpIntent();        }
class _VolumeDownIntent      extends Intent { const _VolumeDownIntent();      }
class _ToggleControlsIntent  extends Intent { const _ToggleControlsIntent();  }
class _ToggleFullscreenIntent extends Intent { const _ToggleFullscreenIntent(); }
class _ExitPlayerIntent      extends Intent { const _ExitPlayerIntent();      }

/// Callbacks fournis par [PlayerPage] pour réaliser les actions.
class PlayerActionHandlers {
  final VoidCallback togglePlayPause;
  /// Avance / recule la lecture de [delta] (négatif = recul).
  final void Function(Duration delta) seek;
  /// Modifie le volume de [delta] (échelle 0→200 en valeur absolue).
  final void Function(double delta) changeVolume;
  /// Bascule la visibilité des contrôles overlay.
  final VoidCallback toggleControls;
  /// Bascule le mode plein écran (Windows).
  final VoidCallback? toggleFullscreen;
  /// Quitte le player (typiquement `Navigator.pop`).
  final VoidCallback exitPlayer;

  const PlayerActionHandlers({
    required this.togglePlayPause,
    required this.seek,
    required this.changeVolume,
    required this.toggleControls,
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
/// | ←  (arrowLeft) / MediaRewind                 | Recul −10 s           |
/// | →  (arrowRight) / MediaFastForward / MediaTrackNext / MediaTrackPrevious | Avance +10 s |
/// | ↑  (arrowUp)                                 | Volume +              |
/// | ↓  (arrowDown)                               | Volume −              |
/// | Menu / Info / ContextMenu                    | Toggle overlay        |
/// | F / F11                                      | Toggle plein écran    |
/// | Escape / Back / GameButtonB                  | Quitter le player     |
class TvPlayerShortcuts extends StatelessWidget {
  final Widget child;
  final PlayerActionHandlers handlers;
  final Duration seekStep;
  final double volumeStep;

  const TvPlayerShortcuts({
    super.key,
    required this.child,
    required this.handlers,
    this.seekStep = const Duration(seconds: 10),
    this.volumeStep = 5.0,
  });

  static final Map<ShortcutActivator, Intent> _shortcuts = {
    // Play / Pause
    const SingleActivator(LogicalKeyboardKey.select):         const _TogglePlayPauseIntent(),
    const SingleActivator(LogicalKeyboardKey.enter):          const _TogglePlayPauseIntent(),
    const SingleActivator(LogicalKeyboardKey.numpadEnter):    const _TogglePlayPauseIntent(),
    const SingleActivator(LogicalKeyboardKey.space):          const _TogglePlayPauseIntent(),
    const SingleActivator(LogicalKeyboardKey.gameButtonA):    const _TogglePlayPauseIntent(),
    const SingleActivator(LogicalKeyboardKey.mediaPlayPause): const _TogglePlayPauseIntent(),
    const SingleActivator(LogicalKeyboardKey.mediaPlay):      const _TogglePlayPauseIntent(),
    const SingleActivator(LogicalKeyboardKey.mediaPause):     const _TogglePlayPauseIntent(),

    // Seek
    const SingleActivator(LogicalKeyboardKey.arrowLeft):         const _SeekBackwardIntent(),
    const SingleActivator(LogicalKeyboardKey.arrowRight):        const _SeekForwardIntent(),
    const SingleActivator(LogicalKeyboardKey.mediaRewind):       const _SeekBackwardIntent(),
    const SingleActivator(LogicalKeyboardKey.mediaFastForward):  const _SeekForwardIntent(),
    const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious):const _SeekBackwardIntent(),
    const SingleActivator(LogicalKeyboardKey.mediaTrackNext):    const _SeekForwardIntent(),

    // Volume
    const SingleActivator(LogicalKeyboardKey.arrowUp):    const _VolumeUpIntent(),
    const SingleActivator(LogicalKeyboardKey.arrowDown):  const _VolumeDownIntent(),

    // Overlay toggle
    const SingleActivator(LogicalKeyboardKey.contextMenu):   const _ToggleControlsIntent(),
    const SingleActivator(LogicalKeyboardKey.info):          const _ToggleControlsIntent(),

    // Fullscreen
    const SingleActivator(LogicalKeyboardKey.keyF):          const _ToggleFullscreenIntent(),
    const SingleActivator(LogicalKeyboardKey.f11):           const _ToggleFullscreenIntent(),

    // Quitter
    const SingleActivator(LogicalKeyboardKey.escape):       const _ExitPlayerIntent(),
    const SingleActivator(LogicalKeyboardKey.gameButtonB):  const _ExitPlayerIntent(),
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
          _VolumeUpIntent: CallbackAction<_VolumeUpIntent>(
            onInvoke: (_) {
              handlers.changeVolume(volumeStep);
              return null;
            },
          ),
          _VolumeDownIntent: CallbackAction<_VolumeDownIntent>(
            onInvoke: (_) {
              handlers.changeVolume(-volumeStep);
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
          autofocus: true,
          child: child,
        ),
      ),
    );
  }
}
