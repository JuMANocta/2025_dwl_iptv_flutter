import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/feature/player/player_media.dart';
import 'package:aetherStream/feature/player/player_page.dart';

/// §episodeMeta — Le contenu lu par le player était décrit par une douzaine de
/// champs `final` de `PlayerPage` : figés pour toute la durée de la route. Un
/// changement d'épisode ne pouvait donc pas rafraîchir le titre ni le synopsis,
/// d'où le symptôme « les infos de l'ancien épisode restent ».
///
/// [PlayerMedia] porte désormais ces informations côté State. Ces tests
/// verrouillent les règles qui en dépendent.
void main() {
  PlayerMedia episode({
    int? season,
    String title = 'Épisode',
    String path = 'http://h.tv/1.mkv',
    String? progressKey,
    PlayerBadgeType badge = PlayerBadgeType.series,
    VideoSourceType source = VideoSourceType.network,
  }) =>
      PlayerMedia(
        path: path,
        title: title,
        badgeType: badge,
        sourceType: source,
        seasonNumber: season,
        progressKey: progressKey,
      );

  group('resumeKey', () {
    test('sans clé explicite → le chemin fait office de clé', () {
      expect(episode(path: 'http://h.tv/ep1.mkv').resumeKey,
          'http://h.tv/ep1.mkv');
    });

    test('clé explicite → partagée entre variantes de qualité', () {
      // §resumeUnify : FHD et HD du même contenu partagent une clé canonique.
      final fhd = episode(path: 'http://h.tv/fhd.mkv', progressKey: 'canon');
      final hd = episode(path: 'http://h.tv/hd.mkv', progressKey: 'canon');
      expect(fhd.resumeKey, hd.resumeKey);
    });
  });

  group('skipProgress', () {
    test('chaîne live → pas de suivi de progression', () {
      expect(episode(badge: PlayerBadgeType.live).skipProgress, isTrue);
    });

    test('replay timeshift → pas de suivi de progression', () {
      expect(episode(source: VideoSourceType.networkReplay).skipProgress,
          isTrue);
    });

    test('épisode de série → suivi actif', () {
      expect(episode().skipProgress, isFalse);
    });

    test('fichier local → suivi actif', () {
      expect(
        episode(source: VideoSourceType.file, badge: PlayerBadgeType.movie)
            .skipProgress,
        isFalse,
      );
    });
  });

  group('crossesSeasonTo — décide décompte vs confirmation', () {
    test('même saison → enchaînement normal', () {
      expect(episode(season: 1).crossesSeasonTo(episode(season: 1)), isFalse);
    });

    test('saison différente → confirmation demandée', () {
      expect(episode(season: 1).crossesSeasonTo(episode(season: 2)), isTrue);
    });

    test('saison inconnue d\'un côté → on n\'interrompt pas à tort', () {
      // Dans le doute on enchaîne : mieux vaut ne pas couper la lecture sur une
      // information manquante que d'afficher une confirmation injustifiée.
      expect(episode(season: null).crossesSeasonTo(episode(season: 2)), isFalse);
      expect(episode(season: 1).crossesSeasonTo(episode(season: null)), isFalse);
    });

    test('les deux inconnues → enchaînement normal', () {
      expect(
          episode(season: null).crossesSeasonTo(episode(season: null)), isFalse);
    });
  });

  group('copyWith — utilisé par le retry .ts ↔ .m3u8', () {
    test('change le chemin sans toucher aux métadonnées', () {
      final base = episode(title: 'Le Bal', season: 3, path: 'a.m3u8');
      final alt = base.copyWith(path: 'a.ts');
      expect(alt.path, 'a.ts');
      expect(alt.title, 'Le Bal');
      expect(alt.seasonNumber, 3);
      expect(alt.badgeType, base.badgeType);
    });
  });
}
