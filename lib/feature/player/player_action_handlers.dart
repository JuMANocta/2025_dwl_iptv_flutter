import 'package:flutter/foundation.dart';

/// §dpadNav — Callbacks d'actions du player, exposés à la **télécommande web**
/// ([RemoteControlService]) pendant qu'un player est ouvert. Auparavant défini
/// dans `tv_player_shortcuts.dart` (supprimé : le D-pad TV passe désormais par
/// le package `dpad` via un `DpadFocusable` qui enveloppe la vidéo).
class PlayerActionHandlers {
  final VoidCallback togglePlayPause;

  /// §mediaKeys — Lecture/pause **explicite**, pour les télécommandes qui ont
  /// des touches PLAY et PAUSE séparées (basculer serait faux : appuyer sur
  /// PAUSE alors que c'est déjà en pause relancerait la lecture).
  final void Function(bool play) setPlaying;

  /// §mediaKeys — Épisode suivant (touche ⏭), `null` si le contenu n'en a pas
  /// (film, chaîne live).
  final VoidCallback? nextEpisode;

  /// Avance / recule la lecture de [delta] (négatif = recul).
  final void Function(Duration delta) seek;

  /// Modifie le volume de [delta] (échelle 0→200 en valeur absolue).
  final void Function(double delta) changeVolume;

  /// Bascule la visibilité des contrôles overlay.
  final VoidCallback toggleControls;

  /// Affiche (sans masquer) la barre de lecture.
  final VoidCallback showControls;

  /// Ouvre le panneau d'options (pistes / vitesse / épisode suivant).
  final VoidCallback showOptions;

  /// Quitte le player (typiquement `Navigator.pop`).
  final VoidCallback exitPlayer;

  const PlayerActionHandlers({
    required this.togglePlayPause,
    required this.setPlaying,
    required this.seek,
    this.nextEpisode,
    required this.changeVolume,
    required this.toggleControls,
    required this.showControls,
    required this.showOptions,
    required this.exitPlayer,
  });
}
