import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/platform_tv.dart';

// ─── Intents ────────────────────────────────────────────────────────────────

/// Intent émis à chaque action télécommande mappée. Les implémentations sont
/// fournies par [PlayerActionHandlers] côté `PlayerPage`.
class _TogglePlayPauseIntent extends Intent { const _TogglePlayPauseIntent(); }
class _SeekForwardIntent     extends Intent { const _SeekForwardIntent();     }
class _SeekBackwardIntent    extends Intent { const _SeekBackwardIntent();    }
class _ToggleControlsIntent  extends Intent { const _ToggleControlsIntent();  }
class _ShowControlsIntent    extends Intent { const _ShowControlsIntent();    }
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
  /// Affiche (sans masquer) les contrôles/options du lecteur.
  /// Sur TV, ↑/↓ révèlent les options plutôt que de modifier le volume.
  final VoidCallback showControls;
  /// Quitte le player (typiquement `Navigator.pop`).
  final VoidCallback exitPlayer;

  const PlayerActionHandlers({
    required this.togglePlayPause,
    required this.seek,
    required this.changeVolume,
    required this.toggleControls,
    required this.showControls,
    required this.exitPlayer,
  });
}

/// Wrapper Shortcuts + Actions + Focus pour la navigation télécommande du
/// player (§3c-5). N'est actif QUE si `PlatformTv.isTv` ; sinon il rend
/// son [child] tel quel (pas d'interception clavier sur mobile).
///
/// Mapping (Android TV / Fire TV) :
/// | Touche                                       | Action                |
/// |----------------------------------------------|-----------------------|
/// | OK / Center / Enter / Space / GameButtonA    | Play / Pause          |
/// | MediaPlayPause / MediaPlay / MediaPause      | Play / Pause          |
/// | ←  (arrowLeft) / MediaRewind                 | Recul −10 s           |
/// | →  (arrowRight) / MediaFastForward / MediaTrackNext / MediaTrackPrevious | Avance +10 s |
/// | ↑  (arrowUp) / ↓ (arrowDown)                 | Afficher les options  |
/// | Menu / Info / ContextMenu                    | Toggle overlay        |
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

    // Haut / Bas → révèle les options du lecteur (le volume reste géré par
    // les touches volume natives du téléviseur / de la télécommande).
    const SingleActivator(LogicalKeyboardKey.arrowUp):    const _ShowControlsIntent(),
    const SingleActivator(LogicalKeyboardKey.arrowDown):  const _ShowControlsIntent(),

    // Overlay toggle
    const SingleActivator(LogicalKeyboardKey.contextMenu):   const _ToggleControlsIntent(),
    const SingleActivator(LogicalKeyboardKey.info):          const _ToggleControlsIntent(),

    // Quitter
    const SingleActivator(LogicalKeyboardKey.escape):       const _ExitPlayerIntent(),
    const SingleActivator(LogicalKeyboardKey.gameButtonB):  const _ExitPlayerIntent(),
    // Note: la touche `Back` Android est interceptée AVANT Flutter par
    // `WillPopScope` / `PopScope`. Si on veut un comportement spécifique sur
    // Back, à gérer côté PlayerPage avec un PopScope.
  };

  @override
  Widget build(BuildContext context) {
    // Hors TV : passthrough complet. Aucun risque d'intercepter des touches
    // clavier sur mobile (clavier physique BT par exemple — laissé au système).
    if (!PlatformTv.isTv) return child;

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
          _ToggleControlsIntent: CallbackAction<_ToggleControlsIntent>(
            onInvoke: (_) {
              handlers.toggleControls();
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
