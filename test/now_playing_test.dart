import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/feature/player/playback_engine.dart';
import 'package:aetherStream/feature/player/player_media.dart';
import 'package:aetherStream/feature/player/player_page.dart'
    show PlayerBadgeType, VideoSourceType;

/// §nowPlaying — Ce que la notification de lecture affiche est décidé par UNE
/// fonction pure, `nowPlayingFor`. Ces tests verrouillent ses règles.
void main() {
  PlayerMedia media({
    String title = 'Titre',
    PlayerBadgeType badge = PlayerBadgeType.movie,
    String? series,
    String? episode,
    String? poster,
    VideoSourceType source = VideoSourceType.network,
  }) =>
      PlayerMedia(
        path: 'http://x/y.mkv',
        title: title,
        badgeType: badge,
        seriesName: series,
        episodeTag: episode,
        posterUrl: poster,
        sourceType: source,
      );

  test('film : le titre seul, l\'image si elle existe', () {
    final n = nowPlayingFor(media(title: 'Dune (2021)', poster: 'http://p/1.jpg'));
    expect(n.title, 'Dune (2021)');
    expect(n.subtitle, isNull);
    expect(n.artworkUrl, 'http://p/1.jpg');
  });

  test('série : « Série · S01 E04 » en ligne secondaire', () {
    final n = nowPlayingFor(media(
      title: 'Pilot',
      badge: PlayerBadgeType.series,
      series: 'Breaking Bad',
      episode: 'S01 E01',
    ));
    expect(n.subtitle, 'Breaking Bad · S01 E01');
  });

  test('série sans numéro : le nom de la série seul', () {
    final n = nowPlayingFor(media(
        title: 'Pilot', badge: PlayerBadgeType.series, series: 'Breaking Bad'));
    expect(n.subtitle, 'Breaking Bad');
  });

  test('série dont le titre EST le nom de la série : pas de doublon', () {
    // Sans épisode identifié, la fiche envoie le nom de la série comme titre.
    // Le répéter en sous-titre ferait « Lost · Lost ».
    final n = nowPlayingFor(media(
        title: 'Lost', badge: PlayerBadgeType.series, series: 'Lost'));
    expect(n.subtitle, isNull);
  });

  test('chaîne en direct : « En direct » — explique l\'absence de barre', () {
    final n = nowPlayingFor(media(title: 'TF1', badge: PlayerBadgeType.live));
    expect(n.subtitle, 'En direct');
  });

  test('replay : « Replay »', () {
    final n = nowPlayingFor(media(
        title: 'Le 20h',
        badge: PlayerBadgeType.replay,
        source: VideoSourceType.networkReplay));
    expect(n.subtitle, 'Replay');
  });

  test('titre vide : jamais une notification sans titre', () {
    final n = nowPlayingFor(media(title: '   '));
    expect(n.title, 'AetherStream');
  });

  test('image vide : traitée comme absente (pas de carré blanc)', () {
    final n = nowPlayingFor(media(poster: '  '));
    expect(n.artworkUrl, isNull);
  });

  test('rien de l\'URL ne fuit vers l\'écran verrouillé', () {
    // ⚠️ L'écran verrouillé est lisible SANS déverrouiller. Une URL Xtream
    // porte l'identifiant et le mot de passe du compte : aucun champ de la
    // notification ne doit jamais en dériver (§logHygiene, côté écran).
    final n = nowPlayingFor(PlayerMedia(
      path: 'http://panel.example:8080/movie/jean/motdepasse42/123.mkv',
      title: 'Dune',
      badgeType: PlayerBadgeType.movie,
      accountId: 'acc_1',
    ));
    for (final s in [n.title, n.subtitle ?? '', n.artworkUrl ?? '']) {
      expect(s, isNot(contains('jean')));
      expect(s, isNot(contains('motdepasse42')));
      expect(s, isNot(contains('panel.example')));
    }
  });

  test('égalité par valeur : deux descriptifs identiques sont égaux', () {
    // Le moteur pourra comparer avant de re-pousser des métadonnées.
    const a = AetherNowPlaying(title: 'A', subtitle: 'B', artworkUrl: 'C');
    const b = AetherNowPlaying(title: 'A', subtitle: 'B', artworkUrl: 'C');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
