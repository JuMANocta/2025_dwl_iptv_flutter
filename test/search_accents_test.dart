import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/data/models/m3u_entry.dart';

void main() {
  group('§searchAccents — repli des accents', () {
    test('les accents français disparaissent de la clé', () {
      // 18 % des titres des listes réelles portent un accent : sans ce repli,
      // « piece montee » ne trouvait pas « Pièce Montée ».
      expect(TitleMetadata.computeGroupKey('Pièce Montée'), 'piece montee');
      expect(TitleMetadata.computeGroupKey('L\'Âme Idéale'), 'l ame ideale');
      expect(TitleMetadata.computeGroupKey('Où êtes-vous ?'), 'ou etes vous');
    });

    test('les autres langues des catalogues sont couvertes', () {
      expect(TitleMetadata.foldAccents('ailecek şaşkınız'), 'ailecek saskiniz');
      expect(TitleMetadata.foldAccents('Björk'), 'Bjork');
      expect(TitleMetadata.foldAccents('mañana'), 'manana');
      expect(TitleMetadata.foldAccents('coração'), 'coracao');
    });

    test('les ligatures se déplient', () {
      expect(TitleMetadata.foldAccents('cœur'), 'coeur');
      expect(TitleMetadata.foldAccents('æon'), 'aeon');
      expect(TitleMetadata.foldAccents('straße'), 'strasse');
    });

    test('un titre sans accent est rendu à l\'identique', () {
      // Court-circuit : la grande majorité des titres ne contient aucun accent,
      // on ne doit pas reconstruire la chaîne pour rien.
      const plain = 'The Whisper Man';
      expect(identical(TitleMetadata.foldAccents(plain), plain), isTrue);
    });

    test('les alphabets non latins traversent sans dommage', () {
      // Les catalogues contiennent de l'arabe et du cyrillique : le repli ne
      // doit ni les altérer ni les faire disparaître.
      expect(TitleMetadata.foldAccents('ميد تيرم'), 'ميد تيرم');
      expect(TitleMetadata.foldAccents('Москва'), 'Москва');
    });

    test('deux écritures du même titre donnent la MÊME clé', () {
      // C'est ce qui fait fusionner deux listes qui n'écrivent pas pareil.
      expect(
        TitleMetadata.computeGroupKey('Le Voyage de Chihiro'),
        TitleMetadata.computeGroupKey('Le Voyagé de Chihiró'),
      );
    });
  });
}
