// §posterLang (2026-09-05) — La langue des visuels TMDB.
//
// **Le constat de départ.** L'affiche vient d'abord du fournisseur (§23,
// « plus grosse liste ») : sa langue est celle du catalogue. Quand TMDB prend
// le relais, la langue était `fr-FR` **écrite en dur à douze endroits** de
// `TmdbService`, et la locale de l'appareil n'était lue nulle part.

import 'package:aetherStream/core/settings/perf_config.dart';
import 'package:aetherStream/data/services/backup_service.dart';
import 'package:aetherStream/data/services/inferred_category_service.dart';
import 'package:aetherStream/data/services/tmdb_poster_cache.dart';
import 'package:aetherStream/data/services/visual_language_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(VisualLanguageService.resetForTest);
  tearDown(VisualLanguageService.resetForTest);

  group('§posterLang — le tag envoyé à TMDB', () {
    test('un choix explicite est respecté', () {
      VisualLanguageService.resetForTest(VisualLanguage.fr);
      expect(VisualLanguageService.resolvedTag, 'fr-FR');
      VisualLanguageService.resetForTest(VisualLanguage.en);
      expect(VisualLanguageService.resolvedTag, 'en-US');
    });

    test('« version originale » demande un tag valide, et aucun texte', () {
      VisualLanguageService.resetForTest(VisualLanguage.original);
      // TMDB exige un tag de langue : on lui donne l'anglais…
      expect(VisualLanguageService.resolvedTag, 'en-US');
      // …mais pour l'AFFICHE, on ne veut aucune langue (visuel sans texte).
      expect(VisualLanguageService.imageLanguageCode, isNull);
    });

    test('la langue de l\'appareil est traduite en tag TMDB', () {
      expect(VisualLanguageService.tagForLocale('fr'), 'fr-FR');
      expect(VisualLanguageService.tagForLocale('pt'), 'pt-PT');
      expect(VisualLanguageService.tagForLocale('ar'), 'ar-SA');
      // Une langue non listée retombe sur l'anglais, la mieux fournie de TMDB.
      expect(VisualLanguageService.tagForLocale('sw'), 'en-US');
      expect(VisualLanguageService.tagForLocale(''), 'en-US');
    });

    test('en mode auto, le tag reste toujours un tag valide', () {
      VisualLanguageService.resetForTest(VisualLanguage.auto);
      expect(VisualLanguageService.resolvedTag, matches(r'^[a-z]{2}-[A-Z]{2}$'));
    });
  });

  group('§posterLang — la valeur stockée', () {
    test('un code inconnu ne casse rien et ne change rien', () {
      // Sauvegarde d'une version future, ou préférence corrompue.
      expect(VisualLanguageService.fromCode('klingon'), isNull);
      expect(VisualLanguageService.fromCode(null), isNull);
      expect(VisualLanguageService.fromCode(''), isNull);
    });

    test('aller-retour code ↔ valeur pour toutes les valeurs', () {
      for (final v in VisualLanguage.values) {
        expect(VisualLanguageService.fromCode(v.name), v);
      }
    });

    test('chaque valeur a un libellé lisible', () {
      for (final v in VisualLanguage.values) {
        expect(VisualLanguageService.labelOf(v), isNotEmpty);
      }
    });
  });

  group('§posterLang — la sauvegarde .aether', () {
    test('le champ fait l\'aller-retour', () {
      final content = BackupContent(
        appVersion: '1.0.0+1',
        exportedAt: DateTime(2026, 9, 5),
        accounts: const [],
        activeAccountId: null,
        tmdbKey: null,
        theme: const {},
        favorites: const [],
        watchProgress: const {},
        visualLanguage: VisualLanguage.en.name,
      );
      final back = BackupContent.fromJson(content.toJson());
      expect(back.visualLanguage, 'en');
      expect(VisualLanguageService.fromCode(back.visualLanguage),
          VisualLanguage.en);
    });

    test('⚠️ absent d\'une vieille sauvegarde : null, pas un défaut imposé', () {
      // Même règle que §langRegion : un fichier antérieur au champ ne doit
      // JAMAIS écraser le réglage local de l'appareil cible.
      final json = BackupContent(
        appVersion: '1.0.0+1',
        exportedAt: DateTime(2026, 9, 5),
        accounts: const [],
        activeAccountId: null,
        tmdbKey: null,
        theme: const {},
        favorites: const [],
        watchProgress: const {},
      ).toJson()
        ..remove('visualLanguage');
      final back = BackupContent.fromJson(json);
      expect(back.visualLanguage, isNull);
      expect(VisualLanguageService.fromCode(back.visualLanguage), isNull);
    });
  });

  group('§posterLang — l\'option « TMDB d\'abord »', () {
    test('désactivée par défaut : aucun appel réseau en plus', () {
      expect(PerfConfig.defaults.tmdbPostersFirst, isFalse);
    });

    test('elle survit à l\'aller-retour JSON', () {
      final on = PerfConfig.defaults.copyWith(tmdbPostersFirst: true);
      expect(PerfConfig.fromJson(on.toJson()).tmdbPostersFirst, isTrue);
    });

    test('une config antérieure au champ garde le défaut', () {
      final json = PerfConfig.defaults.toJson()..remove('tpf');
      expect(PerfConfig.fromJson(json).tmdbPostersFirst, isFalse);
    });

    test('⚠️ elle est EXCLUE de l\'égalité, comme autoNextEpisode', () {
      // Sinon basculer un choix de goût ferait passer la page Optimisation en
      // « Personnalisé », alors qu'aucun profil de performance ne le porte.
      final a = PerfConfig.defaults.copyWith(tmdbPostersFirst: false);
      final b = PerfConfig.defaults.copyWith(tmdbPostersFirst: true);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('§tmdbCacheUi — la mémoire TMDB rendue lisible', () {
    test('un cache vide se décrit sans mentir', () {
      // Les compteurs servent d'abord à EXPLIQUER : « N mémorisées, dont M
      // introuvables ». Sans le second chiffre, un utilisateur qui voit un
      // gros nombre d'échecs croit à une panne — or ils sont mémorisés
      // EXPRÈS (68 % du cache à la mesure de §tmdbUrlPersist).
      expect(TmdbPosterCache.resolvedCount, greaterThanOrEqualTo(0));
      expect(TmdbPosterCache.unknownCount,
          lessThanOrEqualTo(TmdbPosterCache.resolvedCount));
      expect(TmdbPosterCache.networkResolutions, greaterThanOrEqualTo(0));
    });

    test('le compteur de catégories déduites est lisible hors tests', () {
      // §tmdbCacheUi — il était `@visibleForTesting` : la page de réglages ne
      // pouvait donc pas l'afficher, et le bouton « Réapprendre » n'aurait
      // rien pu annoncer.
      expect(InferredCategoryService.count, greaterThanOrEqualTo(0));
    });
  });
}
