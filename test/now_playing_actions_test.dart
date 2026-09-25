import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/feature/player/now_playing_actions.dart';
import 'package:aetherStream/feature/player/playback_engine.dart';
import 'package:aetherStream/feature/player/player_page.dart'
    show PlayerBadgeType, VideoSourceType;

/// §notifAudit P8 — Les boutons de la notification de lecture en plus de
/// lecture/pause (±30 s, épisode suivant) sont décidés par UNE fonction pure,
/// `nowPlayingActionsFor`. Ces tests en tiennent les règles ; l'affichage
/// réel (patch 29 du paquet vendoré) se vérifie par `dumpsys`.
void main() {
  AetherNowPlayingActions actions({
    PlayerBadgeType badge = PlayerBadgeType.series,
    VideoSourceType source = VideoSourceType.network,
    bool casting = false,
    bool canRequestNext = true,
    bool? nextExists,
    bool nextExhausted = false,
  }) =>
      nowPlayingActionsFor(
        badge: badge,
        source: source,
        casting: casting,
        canRequestNext: canRequestNext,
        nextExists: nextExists,
        nextExhausted: nextExhausted,
      );

  group('nowPlayingActionsFor', () {
    test('épisode avec une suite : ±30 s ET épisode suivant', () {
      expect(
        actions(),
        const AetherNowPlayingActions(seek: true, next: true, seekKeys: true),
      );
    });

    test('film (pas de fournisseur de suite) : ±30 s seulement', () {
      expect(
        actions(badge: PlayerBadgeType.movie, canRequestNext: false),
        const AetherNowPlayingActions(seek: true, next: false, seekKeys: true),
      );
    });

    test('fichier téléchargé : ±30 s (un fichier se parcourt)', () {
      final a = actions(
        badge: PlayerBadgeType.movie,
        source: VideoSourceType.file,
        canRequestNext: false,
      );
      expect(a.seek, isTrue);
      expect(a.next, isFalse);
    });

    test('direct : rien, même si une suite était proposée (§autoNextEp)', () {
      expect(actions(badge: PlayerBadgeType.live), AetherNowPlayingActions.none);
    });

    test('replay (badge) : ±30 s, jamais l\'épisode suivant', () {
      expect(
        actions(badge: PlayerBadgeType.replay),
        const AetherNowPlayingActions(seek: true, next: false, seekKeys: true),
      );
    });

    test('replay (source timeshift) : jamais l\'épisode suivant', () {
      expect(
        actions(source: VideoSourceType.networkReplay).next,
        isFalse,
      );
    });

    test('diffusion Cast : aucun bouton (le téléviseur a sa notification), '
        'mais les touches ±30 s commandent le téléviseur (patch 31)', () {
      expect(actions(casting: true),
          const AetherNowPlayingActions(seekKeys: true));
    });

    test('direct diffusé : toujours rien, touches comprises', () {
      expect(actions(badge: PlayerBadgeType.live, casting: true),
          AetherNowPlayingActions.none);
    });

    test('la fiche dit « pas d\'épisode après » : pas de bouton suivant', () {
      expect(actions(nextExists: false).next, isFalse);
      expect(actions(nextExists: false).seek, isTrue);
    });

    test('la fiche dit « il y en a un » : le bouton suit', () {
      expect(actions(nextExists: true).next, isTrue);
    });

    test('fiche muette (null) : le bouton suit le fournisseur', () {
      expect(actions(nextExists: null).next, isTrue);
      expect(actions(nextExists: null, canRequestNext: false).next, isFalse);
    });

    test('« plus rien après » déjà répondu : le bouton disparaît', () {
      expect(actions(nextExhausted: true).next, isFalse);
      // … même si la fiche (périmée) dit encore oui.
      expect(actions(nextExhausted: true, nextExists: true).next, isFalse);
    });
  });

  group('nowPlayingCommandFromWire', () {
    test('les quatre noms du natif (constantes ACTION_* du patch 29)', () {
      expect(nowPlayingCommandFromWire('seekBack'),
          AetherNowPlayingCommand.seekBack);
      expect(nowPlayingCommandFromWire('seekForward'),
          AetherNowPlayingCommand.seekForward);
      expect(nowPlayingCommandFromWire('playPause'),
          AetherNowPlayingCommand.playPause);
      expect(nowPlayingCommandFromWire('next'), AetherNowPlayingCommand.next);
    });

    test('un nom inconnu est ignoré, jamais deviné', () {
      expect(nowPlayingCommandFromWire('previous'), isNull);
      expect(nowPlayingCommandFromWire(''), isNull);
      expect(nowPlayingCommandFromWire(null), isNull);
    });
  });

  group('mediaTrackKeySeek (patch 31, décision utilisateur)', () {
    const AetherNowPlayingActions vod =
        AetherNowPlayingActions(seek: true, seekKeys: true);

    test('téléphone : suivant = +30 s, précédent = −30 s', () {
      expect(
          mediaTrackKeySeek(LogicalKeyboardKey.mediaTrackNext,
              isTv: false, actions: vod),
          const Duration(seconds: 30));
      expect(
          mediaTrackKeySeek(LogicalKeyboardKey.mediaTrackPrevious,
              isTv: false, actions: vod),
          const Duration(seconds: -30));
    });

    test('direct : la touche est laissée au reste de l\'app', () {
      expect(
          mediaTrackKeySeek(LogicalKeyboardKey.mediaTrackNext,
              isTv: false, actions: AetherNowPlayingActions.none),
          isNull);
    });

    test('téléviseur : ⏭ reste « épisode suivant » (§mediaKeys)', () {
      expect(
          mediaTrackKeySeek(LogicalKeyboardKey.mediaTrackNext,
              isTv: true, actions: vod),
          isNull);
    });

    test('les autres touches média ne sont pas concernées', () {
      for (final k in [
        LogicalKeyboardKey.mediaPlayPause,
        LogicalKeyboardKey.mediaFastForward,
        LogicalKeyboardKey.mediaRewind,
        LogicalKeyboardKey.arrowRight,
      ]) {
        expect(mediaTrackKeySeek(k, isTv: false, actions: vod), isNull,
            reason: k.debugName);
      }
    });

    test('pendant une diffusion : la touche commande le téléviseur', () {
      expect(
          mediaTrackKeySeek(LogicalKeyboardKey.mediaTrackNext,
              isTv: false,
              actions: nowPlayingActionsFor(
                badge: PlayerBadgeType.movie,
                source: VideoSourceType.network,
                casting: true,
                canRequestNext: false,
              )),
          const Duration(seconds: 30));
    });
  });

  test('le pas des sauts est celui de l\'icône native (30 s)', () {
    expect(kNowPlayingSeekStep, const Duration(seconds: 30));
  });

  test('égalité par valeur : pas de renvoi au natif d\'un état identique', () {
    expect(const AetherNowPlayingActions(seek: true, next: false),
        const AetherNowPlayingActions(seek: true));
    expect(const AetherNowPlayingActions(seek: true),
        isNot(const AetherNowPlayingActions(seek: true, next: true)));
  });
}
