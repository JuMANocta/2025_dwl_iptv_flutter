import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/models/media_model.dart';
import 'package:aetherStream/feature/search/details_page.dart';

/// §tmdbOnlyDetails — Verrouille l'entrée SYNTHÉTIQUE qui alimente la fiche
/// d'un titre absent des listes.
///
/// Deux invariants critiques :
///   - `url` VIDE : c'est le marqueur lu par `_isTmdbOnly` pour retirer
///     « Lire » et « Télécharger ». Une URL non vide ferait ouvrir le player
///     sur un chemin bidon et créerait une tâche de téléchargement fantôme.
///   - `tmdbId` RENSEIGNÉ : `_providerTmdbId()` le lit pour appeler
///     `getFullDetailsById` — donc zéro recherche floue, zéro homonyme.
void main() {
  group('DetailsPage.buildTmdbOnlyEntry', () {
    test('aucune source jouable : url vide, accountId vide', () {
      final e = DetailsPage.buildTmdbOnlyEntry(
        tmdbId: 27205,
        title: 'Inception',
        type: M3uContentType.movie,
      );
      expect(e.url, isEmpty);
      expect(e.accountId, isEmpty);
    });

    test('tmdbId conservé en chaîne → fetch par ID, pas par titre', () {
      final e = DetailsPage.buildTmdbOnlyEntry(
        tmdbId: 27205,
        title: 'Inception',
        type: M3uContentType.movie,
      );
      expect(e.tmdbId, '27205');
      expect(int.tryParse(e.tmdbId!), 27205);
    });

    test('le titre passe par le VRAI parseur (année extraite)', () {
      final e = DetailsPage.buildTmdbOnlyEntry(
        tmdbId: 1,
        title: 'Dune (2021)',
        type: M3uContentType.movie,
      );
      expect(e.displayName, 'Dune');
      expect(e.title.year, '2021');
    });

    test('le type demandé est respecté (série)', () {
      final e = DetailsPage.buildTmdbOnlyEntry(
        tmdbId: 1396,
        title: 'Breaking Bad',
        type: M3uContentType.series,
      );
      expect(e.type, M3uContentType.series);
      expect(e.isSerie, isTrue);
    });
  });

  group('Media.originalTitle — bascule VO de la recherche manuelle', () {
    test('film : original_title retenu quand il diffère du titre localisé', () {
      final m = Media.fromJson({
        'id': 1,
        'title': 'Le Parrain',
        'original_title': 'The Godfather',
        'overview': '…',
      });
      expect(m.originalTitle, 'The Godfather');
    });

    test('identique au titre localisé → null (rien à proposer)', () {
      final m = Media.fromJson({
        'id': 2,
        'title': 'Inception',
        'original_title': 'Inception',
        'overview': '…',
      });
      expect(m.originalTitle, isNull);
    });

    test('série : lit original_name, pas original_title', () {
      final m = Media.fromJson({
        'id': 3,
        'name': 'Chapeau melon et bottes de cuir',
        'original_name': 'The Avengers',
        'overview': '…',
      });
      expect(m.originalTitle, 'The Avengers');
    });

    test('absent ou vide → null', () {
      final m = Media.fromJson({
        'id': 4,
        'title': 'Sans VO',
        'original_title': '   ',
        'overview': '…',
      });
      expect(m.originalTitle, isNull);
    });
  });
}
