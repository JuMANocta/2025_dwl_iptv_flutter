import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/data/models/m3u_entry.dart';

/// §searchTmdb — Verrouille la règle de rapprochement « ce titre est-il déjà
/// dans mes listes ? ».
///
/// Le filtrage lui-même vit dans un widget privé ; ce qui est testable — et
/// c'est le seul endroit où une erreur coûte cher — c'est la CLÉ utilisée pour
/// comparer un titre TMDB à un titre de playlist.
void main() {
  String key(String title) => TitleMetadata.computeGroupKey(title);

  group('§searchTmdb — un titre TMDB se rapproche par la clé de groupe', () {
    test('la variante fournisseur donne la MÊME clé que le titre TMDB', () {
      // C'est LE piège : comparer les chaînes brutes présenterait ce titre
      // comme absent alors qu'il est bien dans la liste.
      final tmdb = key('Le Voyage de Chihiro');
      final local = TitleMetadata.parse(
              '|FR| Le Voyage de Chihiro (2001) MULTI FHD')
          .groupKey;
      expect(local, tmdb);
    });

    test('les accents ne créent pas de faux « absent »', () {
      expect(key('La Servante Écarlate'), key('La Servante Ecarlate'));
    });

    test('le préfixe à pipe fermant seul ne crée pas de faux « absent »', () {
      expect(TitleMetadata.parse('FR| Spider-Man - 2002').groupKey,
          key('Spider-Man'));
    });

    test('deux titres réellement différents gardent des clés différentes', () {
      // Le rapprochement doit rester STRICT : rapprocher trop ferait
      // disparaître de vrais manquants, ce qui viderait la fonctionnalité.
      expect(key('Dune'), isNot(key('Dune : Deuxième partie')));
      expect(key('Alien'), isNot(key('Aliens')));
    });
  });
}
