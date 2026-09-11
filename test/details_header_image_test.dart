import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/feature/search/details_header_image.dart';

/// §posterFlash — La fiche montre ce que la vignette montrait.
///
/// Le défaut mesuré : sur « Heroes », le `backdrop` de la plus grosse liste
/// EST l'affiche de Speed 2. Ce champ passait devant, alors que la vignette
/// d'accueil ne le regarde jamais — donc personne ne pouvait voir qu'il était
/// faux, sauf pendant la seconde où la fiche l'affichait en grand.
void main() {
  String? header({
    String? groupLogo,
    String? episodeLogo,
    String? entryLogo,
    String? groupBackdrop,
    String? entryBackdrop,
  }) =>
      playlistHeaderImage(
        groupLogo: groupLogo,
        episodeLogo: episodeLogo,
        entryLogo: entryLogo,
        groupBackdrop: groupBackdrop,
        entryBackdrop: entryBackdrop,
      );

  group('⚠️ Le cas mesuré — Heroes', () {
    test("l'affiche du groupe passe devant le décor du fournisseur", () {
      expect(
        header(
          groupLogo: 'http://provider/heroes.png',
          groupBackdrop: 'http://provider/speed2.jpg', // la donnée FAUSSE
        ),
        'http://provider/heroes.png',
      );
    });

    test('le décor sert encore quand aucune affiche n\'existe', () {
      // ⛔ Il n'est pas banni : sans lui, une fiche sans affiche n'aurait plus
      // rien à montrer du tout en attendant TMDB.
      expect(
        header(groupBackdrop: 'http://provider/decor.jpg'),
        'http://provider/decor.jpg',
      );
    });
  });

  group("L'ordre des affiches", () {
    test('le groupe (politique « plus grosse liste ») en premier', () {
      expect(
        header(
          groupLogo: 'groupe',
          episodeLogo: 'episode',
          entryLogo: 'entree',
        ),
        'groupe',
      );
    });

    test("l'épisode courant vient après le groupe", () {
      expect(header(episodeLogo: 'episode', entryLogo: 'entree'), 'episode');
    });

    test('la version tapée ferme la marche des affiches', () {
      expect(header(entryLogo: 'entree', groupBackdrop: 'decor'), 'entree');
    });

    test('le décor du groupe avant celui de la version tapée', () {
      expect(
        header(groupBackdrop: 'decor groupe', entryBackdrop: 'decor entree'),
        'decor groupe',
      );
    });
  });

  group('Robustesse', () {
    test('une chaîne VIDE ne compte pas comme une image', () {
      // Le champ arrive vide du parsing plus souvent qu'absent.
      expect(header(groupLogo: '', entryLogo: 'entree'), 'entree');
    });

    test('sans aucune adresse, rien', () {
      expect(header(), isNull);
      expect(header(groupLogo: '', entryBackdrop: ''), isNull);
    });
  });
}
