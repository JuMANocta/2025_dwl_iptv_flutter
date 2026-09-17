import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/widgets/matrix_decode_text.dart';

/// §matrixFx — Le brouillage du décodage « Matrix », extrait de
/// `VersionDiffLine` pour servir au dialogue de téléchargement.
///
/// Ce qui est tenu ici est ce qui casse à l'œil sans qu'on sache pourquoi :
/// un texte qui change de LONGUEUR pendant qu'il se décode (la carte saute),
/// des espaces brouillés (les mots ne se devinent plus), un séparateur de
/// version qui danse (« 1.19.3 » a l'air instable, pas en train d'arriver).
void main() {
  // Graine fixe : un test de brouillage aléatoire qui échoue une fois sur
  // vingt ne vaut rien.
  Random rng() => Random(42);

  group('§matrixFx — matrixScramble', () {
    test('la longueur ne bouge jamais, quel que soit l\'avancement', () {
      const target = 'Téléchargement en cours';
      for (var settled = 0; settled <= target.length; settled++) {
        expect(
          matrixScramble(target, settled, rng()).length,
          target.length,
          reason: 'à $settled caractères figés, la mise en page sauterait',
        );
      }
    });

    test('les caractères figés sont les VRAIS, de gauche à droite', () {
      const target = 'ABCDEFGH';
      final out = matrixScramble(target, 5, rng());
      expect(out.substring(0, 5), 'ABCDE');
    });

    test('à zéro figé, rien du texte ne doit fuiter', () {
      // Le point du brouillage : si les premiers caractères étaient déjà lisibles
      // au départ, il n'y aurait pas de décodage à regarder.
      const target = 'ZZZZZZZZZZZZZZZZ';
      final out = matrixScramble(target, 0, rng());
      expect(out, isNot(target));
    });

    test('tout figé = le texte final, à l\'identique', () {
      const target = 'v1.19.3+155';
      expect(matrixScramble(target, target.length, rng()), target);
    });

    test('les espaces et les sauts de ligne gardent la forme des mots', () {
      const target = 'deux mots';
      final out = matrixScramble(target, 0, rng());
      expect(out[4], ' ', reason: 'l\'espace doit rester un espace');
      const multi = 'a\nb';
      expect(matrixScramble(multi, 0, rng())[1], '\n');
    });

    test('les caractères de « keep » sont figés d\'emblée', () {
      // Le cas de VersionDiffLine : les séparateurs d\'un numéro de version.
      const target = '1.19.3+155';
      final out = matrixScramble(target, 0, rng(), keep: '.+');
      expect(out[1], '.');
      expect(out[4], '.');
      expect(out[6], '+');
    });

    test('« keep » ne fige QUE les caractères nommés', () {
      // Sincérité : sans cette assertion, un `keep` qui figerait tout
      // passerait le test précédent.
      const target = '1.19.3+155';
      final out = matrixScramble(target, 0, rng(), keep: '.+');
      final digits = <int>[0, 2, 3, 5, 7, 8, 9];
      expect(
        digits.any((i) => out[i] != target[i]),
        isTrue,
        reason: 'les chiffres doivent encore défiler',
      );
    });

    test('un texte vide ne lève pas', () {
      expect(matrixScramble('', 0, rng()), '');
    });

    test('les glyphes tirés viennent tous de l\'alphabet Matrix', () {
      const target = 'XXXXXXXXXXXXXXXXXXXX';
      final out = matrixScramble(target, 0, rng());
      for (final c in out.split('')) {
        expect(kMatrixGlyphs.contains(c), isTrue, reason: 'glyphe inattendu : $c');
      }
    });
  });
}
