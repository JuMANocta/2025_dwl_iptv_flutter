import 'package:flutter/services.dart' show LogicalKeyboardKey;

import 'playback_engine.dart'
    show AetherNowPlayingActions, AetherNowPlayingCommand;
import 'player_page.dart' show PlayerBadgeType, VideoSourceType;

/// §notifAudit P8 — Ce que la notification de lecture (et l'écran verrouillé)
/// propose EN PLUS de lecture/pause. Décisions PURES : c'est ce qui se teste
/// sans appareil ; l'affichage réel se vérifie par `dumpsys` (patch 29 du
/// paquet vendoré, cf. `packages/aether_video/VENDORING.md`).

/// Pas des sauts de la notification. ⚠️ L'icône native est celle des 30 s
/// (`CommandButton.ICON_SKIP_BACK_30`) : changer l'un sans l'autre ferait
/// mentir le bouton.
const Duration kNowPlayingSeekStep = Duration(seconds: 30);

/// Les boutons à proposer pour le contenu courant.
///
/// - **Diffusion Cast en cours** : aucun bouton. Le téléviseur a sa propre
///   notification (Pause / Arrêter) ; le lecteur local est en pause. Les
///   TOUCHES ±30 s restent ([AetherNowPlayingActions.seekKeys]) : elles
///   commandent le téléviseur, comme les gestes du lecteur.
/// - **Direct** : rien — pas de saut dans un flux sans fin, pas d'épisode, et
///   les touches suivant/précédent gardent leur comportement d'avant.
/// - **Replay** : les sauts (le rattrapage se parcourt), jamais l'épisode
///   suivant (§autoNextEp : jamais en direct ni en replay).
/// - **Épisode suivant** : seulement si la fiche en fournit un
///   ([canRequestNext]) ET qu'on ne le sait pas épuisé :
///   - [nextExists] — la réponse de la fiche pour le contenu COURANT, sans
///     rien faire avancer (`PlayerPage.hasNextEpisode`) ; `null` = la fiche
///     ne sait pas répondre ;
///   - [nextExhausted] — la fiche a déjà répondu « plus rien » pour ce
///     contenu (appui précédent).
///
/// ⚠️ Les sauts ne sont qu'une DEMANDE : le natif ne les montre que si le
/// flux se laisse parcourir (`COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM`).
AetherNowPlayingActions nowPlayingActionsFor({
  required PlayerBadgeType badge,
  required VideoSourceType source,
  required bool casting,
  required bool canRequestNext,
  bool? nextExists,
  bool nextExhausted = false,
}) {
  if (badge == PlayerBadgeType.live) return AetherNowPlayingActions.none;
  // Patch 31 — décision utilisateur (2026-09-25) : « suivant » = +30 s,
  // « précédent » = −30 s, partout sauf en direct (films, séries, replay,
  // fichier local), diffusion comprise.
  if (casting) return const AetherNowPlayingActions(seekKeys: true);
  final bool replay = badge == PlayerBadgeType.replay ||
      source == VideoSourceType.networkReplay;
  final bool next =
      !replay && canRequestNext && !nextExhausted && (nextExists ?? true);
  return AetherNowPlayingActions(seek: true, next: next, seekKeys: true);
}

/// Patch 31 — Une touche « piste suivante / précédente » reçue par l'app
/// elle-même (casque ou clavier, app au premier plan au TÉLÉPHONE) : le saut
/// à faire, ou `null` pour la laisser au reste de l'app.
///
/// ⚠️ **Téléviseur exclu** : la touche ⏭ de la télécommande reste « épisode
/// suivant » (§mediaKeys). La décision utilisateur vise le casque et la
/// montre — sur TV il n'y a ni l'un ni l'autre, et aucune session média.
///
/// Même règle que la notification ([AetherNowPlayingActions.seekKeys]) : app
/// au premier plan ou en arrière-plan, la même touche fait la même chose.
Duration? mediaTrackKeySeek(
  LogicalKeyboardKey key, {
  required bool isTv,
  required AetherNowPlayingActions actions,
}) {
  if (isTv || !actions.seekKeys) return null;
  if (key == LogicalKeyboardKey.mediaTrackNext) return kNowPlayingSeekStep;
  if (key == LogicalKeyboardKey.mediaTrackPrevious) return -kNowPlayingSeekStep;
  return null;
}

/// Nom d'un bouton tel que le natif l'envoie (événement `mediaAction`,
/// constantes `ACTION_*` de `VideoPlayerNotificationHandler.kt`). Un nom
/// inconnu (version du natif plus récente) est ignoré, jamais deviné.
AetherNowPlayingCommand? nowPlayingCommandFromWire(String? action) =>
    switch (action) {
      'seekBack' => AetherNowPlayingCommand.seekBack,
      'seekForward' => AetherNowPlayingCommand.seekForward,
      'playPause' => AetherNowPlayingCommand.playPause,
      'next' => AetherNowPlayingCommand.next,
      _ => null,
    };
