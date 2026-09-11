import 'package:flutter_test/flutter_test.dart';
import 'package:aetherStream/feature/downloads/logic/direct_write_probe.dart';

/// §dlDirectWrite — Les parties PURES de la sonde d'écriture directe.
///
/// L'écriture réelle ne se teste pas ici : elle dépend du stockage cloisonné
/// d'Android, que ni la machine de développement ni `flutter test` ne simulent.
/// Ce qui se teste, c'est ce qui a fait la faute : **la sonde ne ressemblait
/// pas au fichier qu'elle prétendait tester**.
void main() {
  group('extensionChainOf — la sonde porte la MÊME extension que le vrai fichier', () {
    test('la forme réelle d\'un partiel garde ses deux extensions', () {
      expect(DirectWriteProbe.extensionChainOf('.Mon film.aetherpart.mkv'),
          '.aetherpart.mkv');
    });

    test('un titre à points ne rallonge pas la chaîne', () {
      // ⚠️ Le piège : prendre tout ce qui suit le PREMIER point ferait sonder
      // « .aether_probe.film.2024.mkv.part », un nom que rien ne produit.
      expect(DirectWriteProbe.extensionChainOf('Le.film.2024.aetherpart.mkv'),
          '.aetherpart.mkv');
    });

    test('un fichier simple garde son unique extension', () {
      expect(DirectWriteProbe.extensionChainOf('Film.mp4'), '.mp4');
    });

    test('le point de TÊTE n\'est pas une extension', () {
      expect(DirectWriteProbe.extensionChainOf('.nomedia'), '');
    });

    test('sans extension, rien', () {
      expect(DirectWriteProbe.extensionChainOf('truc'), '');
    });

    test('un point final ne fabrique pas une extension vide', () {
      expect(DirectWriteProbe.extensionChainOf('truc.'), '');
    });
  });

  group('probeNames — la batterie de diagnostic', () {
    test('la PREMIÈRE forme est exactement celle qu\'un téléchargement écrit', () {
      expect(DirectWriteProbe.probeNames('mkv').first,
          '.aether_probe.aetherpart.mkv');
    });

    test('⛔ les formes MESURÉES comme refusées restent dans la batterie', () {
      // Mesuré sur Android 16 : `.part` et l'absence d'extension sont refusés.
      // Les garder permet de voir tout de suite si un appareil se comporte
      // autrement — c'est un diagnostic, pas une liste de candidats.
      final names = DirectWriteProbe.probeNames('mkv');
      expect(names, contains('.aether_probe.mkv.part'));
      expect(names, contains('.aether_probe'));
    });

    test('la sonde HISTORIQUE (sans extension) est toujours essayée', () {
      // C'est elle qui est soupçonnée : si elle est la seule à échouer, la
      // cause est l'extension, pas le dossier.
      expect(DirectWriteProbe.probeNames('mkv'), contains('.aether_probe'));
    });

    test('le point de l\'extension est toléré à l\'entrée', () {
      expect(DirectWriteProbe.probeNames('.MKV'), DirectWriteProbe.probeNames('mkv'));
    });

    test('sans extension cible, aucun nom ne porte de double point', () {
      for (final String name in DirectWriteProbe.probeNames('')) {
        expect(name, isNot(contains('..')));
      }
    });

    test('toutes les formes sont distinctes', () {
      final List<String> names = DirectWriteProbe.probeNames('mp4');
      expect(names.toSet().length, names.length);
    });
  });

  group('verdict — ce que la table permet de conclure', () {
    test('aucune forme acceptée : le dossier est fermé, le repli est JUSTE', () {
      final v = DirectWriteProbe.verdict(<String, String?>{
        '.aether_probe.mkv.part': 'EACCES',
        '.aether_probe': 'EACCES',
      });
      expect(v, contains('aucune forme'));
      expect(v, contains('repli'));
    });

    test('tout accepté : le nom n\'est pas en cause', () {
      final v = DirectWriteProbe.verdict(<String, String?>{
        '.aether_probe.mkv.part': null,
        '.aether_probe': null,
      });
      expect(v, contains('toutes les formes'));
    });

    test('acceptation partielle : le verdict NOMME les formes qui passent', () {
      final v = DirectWriteProbe.verdict(<String, String?>{
        '.aether_probe.mkv.part': 'EPERM',
        '.aether_probe.mkv': null,
        '.aether_probe': 'EPERM',
      });
      expect(v, contains('.aether_probe.mkv'));
      expect(v, isNot(contains('EPERM')));
    });
  });
}
