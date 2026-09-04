import 'playback_engine.dart' show AetherNowPlaying;
import 'player_page.dart' show PlayerBadgeType, VideoSourceType;

/// §episodeMeta — Tout ce qui décrit le contenu **actuellement lu**.
///
/// **Pourquoi ce modèle existe.** Avant, ces informations étaient une douzaine
/// de champs `final` de `PlayerPage` : figés pour toute la durée de la route.
/// Passer à l'épisode suivant obligeait donc à démonter le player et à en
/// pousser un nouveau — d'où deux défauts :
///
///   1. le titre et le synopsis affichés étaient ceux de l'épisode PRÉCÉDENT
///      (les métadonnées TMDB du suivant n'étaient pas encore chargées au
///      moment de la reconstruction, et plus rien ne pouvait les rafraîchir
///      ensuite puisque les champs étaient `final`) ;
///   2. le contrôleur du moteur vidéo était détruit et recréé à chaque épisode :
///      écran noir et re-buffering complet, très visible sur box TV.
///
/// Regrouper ces champs dans un objet porté par le State rend le player
/// capable de changer de contenu en place.
class PlayerMedia {
  /// URL réseau ou chemin de fichier local.
  final String path;

  final String title;

  /// §watchContext a — Qualité du flux (4K/FHD/HD/SD) → badge sous le titre.
  final String? qualityTag;

  /// §watchContext b — Numéro saison/épisode (« S01 E04 ») → badge sous le titre.
  final String? episodeTag;

  /// §watchContext — Nom de la série (breadcrumb au-dessus du titre).
  final String? seriesName;

  /// §watchContext — Synopsis (épisode ou film) affiché sous les badges.
  final String? synopsis;

  final VideoSourceType sourceType;
  final PlayerBadgeType badgeType;

  /// Heure de début du replay — alimente la barre replay (optionnel).
  final DateTime? replayStart;

  /// Durée totale du replay — alimente la barre replay (optionnel).
  final Duration? replayDuration;

  /// §1e — Position de reprise, passée nativement au moteur à l'ouverture
  /// (§resumeStart) : un seek post-open peut être avalé par le buffering.
  final Duration? startPosition;

  /// Clé de persistance de progression. Si nulle, [path] fait office de clé.
  /// Permet de partager une progression entre variantes (FHD/HD d'un même film).
  final String? progressKey;

  /// §autoNextEp — Saison du contenu (séries uniquement, `null` sinon).
  ///
  /// Sert à détecter un **franchissement de saison** : on enchaîne
  /// automatiquement d'un épisode au suivant, mais changer de saison demande
  /// une confirmation explicite.
  final int? seasonNumber;

  /// §stallCount — Compte IPTV d'où vient ce flux.
  ///
  /// Sert à rattacher les blocages mesurés au **fournisseur** qui les a causés :
  /// sans lui, on saurait que « ça a bloqué 4 fois » sans pouvoir dire lequel
  /// des trois abonnements accuser. Vide pour une lecture de fichier local, où
  /// la question n'a pas de sens.
  final String accountId;

  /// §nowPlaying — Image pour la notification et l'écran verrouillé : affiche
  /// TMDB quand la fiche l'a, sinon le `tvg-logo` de la liste. `null` = la
  /// notification s'affiche sans image, ce qui vaut mieux qu'un carré blanc.
  final String? posterUrl;

  const PlayerMedia({
    required this.path,
    required this.title,
    this.accountId = '',
    this.posterUrl,
    this.qualityTag,
    this.episodeTag,
    this.seriesName,
    this.synopsis,
    this.sourceType = VideoSourceType.network,
    this.badgeType = PlayerBadgeType.none,
    this.replayStart,
    this.replayDuration,
    this.startPosition,
    this.progressKey,
    this.seasonNumber,
  });

  /// Clé effective de sauvegarde de progression.
  String get resumeKey => progressKey ?? path;

  /// Vrai si le contenu ne doit pas être suivi en progression : une chaîne live
  /// n'a pas de fin, un replay n'a pas de reprise utile.
  bool get skipProgress =>
      badgeType == PlayerBadgeType.live ||
      sourceType == VideoSourceType.networkReplay;

  /// Vrai si [next] appartient à une autre saison que ce contenu.
  /// `false` dès qu'une des deux saisons est inconnue — dans le doute, on
  /// enchaîne normalement plutôt que d'interrompre l'utilisateur à tort.
  bool crossesSeasonTo(PlayerMedia next) {
    final a = seasonNumber, b = next.seasonNumber;
    if (a == null || b == null) return false;
    return a != b;
  }

  PlayerMedia copyWith({String? path, Duration? startPosition}) => PlayerMedia(
        path: path ?? this.path,
        title: title,
        qualityTag: qualityTag,
        episodeTag: episodeTag,
        seriesName: seriesName,
        synopsis: synopsis,
        sourceType: sourceType,
        badgeType: badgeType,
        replayStart: replayStart,
        replayDuration: replayDuration,
        startPosition: startPosition ?? this.startPosition,
        progressKey: progressKey,
        seasonNumber: seasonNumber,
        accountId: accountId,
        posterUrl: posterUrl,
      );
}

/// §nowPlaying — Ce que la notification de lecture doit afficher pour [m].
///
/// Fonction **pure**, donc testée : c'est elle qui décide de la ligne
/// secondaire. Règles :
///   · série → « Nom de la série · S01 E04 » (l'un ou l'autre s'il en manque) ;
///   · film → pas de ligne secondaire (le titre suffit, l'année est déjà dans
///     `title` quand elle est connue) ;
///   · chaîne en direct → « En direct », replay → « Replay » : sur l'écran
///     verrouillé, savoir qu'on est sur du direct explique l'absence de barre
///     de progression.
///
/// ⚠️ Ne décide PAS de la plateforme : c'est l'appelant qui rend `null` sur
/// téléviseur (`PlatformTv.isTv` est un cache natif, invisible en test).
AetherNowPlaying nowPlayingFor(PlayerMedia m) {
  final String title = m.title.trim().isEmpty ? 'AetherStream' : m.title.trim();

  String? subtitle;
  switch (m.badgeType) {
    case PlayerBadgeType.live:
      subtitle = 'En direct';
      break;
    case PlayerBadgeType.replay:
      subtitle = 'Replay';
      break;
    case PlayerBadgeType.series:
      final parts = <String>[
        if (m.seriesName != null &&
            m.seriesName!.trim().isNotEmpty &&
            m.seriesName!.trim() != title)
          m.seriesName!.trim(),
        if (m.episodeTag != null && m.episodeTag!.trim().isNotEmpty)
          m.episodeTag!.trim(),
      ];
      subtitle = parts.isEmpty ? null : parts.join(' · ');
      break;
    case PlayerBadgeType.movie:
    case PlayerBadgeType.none:
      subtitle = null;
      break;
  }

  final String? art =
      (m.posterUrl != null && m.posterUrl!.trim().isNotEmpty) ? m.posterUrl : null;

  return AetherNowPlaying(title: title, subtitle: subtitle, artworkUrl: art);
}
