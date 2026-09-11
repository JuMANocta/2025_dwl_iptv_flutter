// §catalogTruth + §cacheKeep — revue 2026-09-11, D1A-01.
//
// Le repli `get.php` enchaînait QUEL QUE SOIT le motif du refus du catalogue
// JSON, et n'était validé que par « taille > 0 » : un panel saturé qui
// répondait `200 []` au catalogue puis une page d'erreur de 2 Ko à `get.php`
// voyait cette page publiée comme liste, et le `.json` SAIN supprimé. Ces
// tests verrouillent les deux règles pures qui l'empêchent.
import 'dart:convert';

import 'package:aetherStream/data/services/load_failure.dart';
import 'package:aetherStream/data/services/playlist_fallback_policy.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _bytes(String s) => utf8.encode(s);

void main() {
  group('shouldFallbackToGetPhp — un refus motivé ne détruit pas un catalogue sain',
      () {
    test('catalogue JSON présent : AUCUN motif de refus n\'autorise le repli '
        '(sauf l\'absence d\'identifiants Xtream)', () {
      for (final LoadFailureKind kind in LoadFailureKind.values) {
        if (kind == LoadFailureKind.badAccount) continue;
        expect(
          shouldFallbackToGetPhp(failure: kind, hasJsonSource: true),
          isFalse,
          reason: '« ${kind.name} » ne doit pas faire remplacer un catalogue '
              'sain par ce que get.php rendra d\'un panel qui va mal',
        );
      }
    });

    test('catalogue JSON présent + exception (motif inconnu) → pas de repli',
        () {
      expect(shouldFallbackToGetPhp(failure: null, hasJsonSource: true),
          isFalse);
    });

    test('compte sans identifiants Xtream (badAccount) → repli, même avec un '
        'JSON : get.php est son seul chemin', () {
      expect(
        shouldFallbackToGetPhp(
            failure: LoadFailureKind.badAccount, hasJsonSource: true),
        isTrue,
      );
    });

    test('rien à protéger (premier téléchargement, compte get.php) → repli', () {
      for (final LoadFailureKind? kind in <LoadFailureKind?>[
        null,
        LoadFailureKind.busy,
        LoadFailureKind.amputated,
        LoadFailureKind.noSource,
        LoadFailureKind.badAccount,
      ]) {
        expect(shouldFallbackToGetPhp(failure: kind, hasJsonSource: false),
            isTrue,
            reason: 'sans catalogue à protéger, get.php reste la seule issue');
      }
    });
  });

  group('isCredibleM3u — une liste se reconnaît à son contenu', () {
    bool credible(String s) {
      final List<int> b = _bytes(s);
      return isCredibleM3u(lengthBytes: b.length, head: b);
    }

    test('en-tête #EXTM3U', () {
      expect(credible('#EXTM3U\n#EXTINF:-1,TF1\nhttp://h/1.ts\n'), isTrue);
    });

    test('en-tête précédé d\'espaces ou d\'une marque d\'ordre des octets', () {
      expect(credible('\n  #EXTM3U\n#EXTINF:-1,TF1\nhttp://h/1.ts\n'), isTrue);
      // ⚠️ La marque est construite par son code : la couche d'édition
      // décode les échappements (§catWords).
      expect(
          credible('${String.fromCharCode(0xFEFF)}#EXTM3U\n#EXTINF:-1,TF1\n'),
          isTrue);
    });

    test('en-tête SEUL, sans aucun titre (panel qui n\'a rien à servir) → '
        'refusé', () {
      expect(credible('#EXTM3U\n'), isFalse,
          reason: 'le publier remplacerait la liste d\'hier par une liste vide');
      expect(credible('#EXTM3U url-tvg="http://epg.test/x.xml"\n\n'), isFalse);
    });

    test('directives avant la première adresse (liste « simple » avec en-tête)',
        () {
      expect(credible('#EXTM3U\nhttp://h/live/u/p/1.ts\n'), isTrue);
    });

    test('sans en-tête mais avec des lignes #EXTINF', () {
      expect(credible('#EXTINF:-1 group-title="X",France 2\nhttp://h/2.ts'),
          isTrue);
    });

    test('liste « simple » (une adresse par ligne) — le parseur la lit', () {
      expect(credible('http://h/live/u/p/1.ts\nhttp://h/live/u/p/2.ts'), isTrue);
    });

    test('page d\'erreur HTML (LE cas du défaut) → refusée', () {
      final String page = '<!DOCTYPE html>\n<html><body><h1>503</h1>'
          '${'x' * 2000}<a href="x">\nhttp://support.example</a></body></html>';
      expect(credible(page), isFalse,
          reason: 'une adresse plus bas dans la page ne fait pas une liste');
    });

    test('JSON d\'erreur Xtream → refusé', () {
      expect(credible('{"user_info":{"auth":0}}'), isFalse);
    });

    test('fichier vide → refusé', () {
      expect(isCredibleM3u(lengthBytes: 0, head: const <int>[]), isFalse);
    });

    test('liste en Latin-1 : les marqueurs ASCII restent reconnus', () {
      final List<int> latin1 = <int>[
        ..._bytes('#EXTM3U\n#EXTINF:-1,Th'),
        0xE9, // « é » en Latin-1 : invalide en UTF-8
        ..._bytes('atre\nhttp://h/3.ts\n'),
      ];
      expect(isCredibleM3u(lengthBytes: latin1.length, head: latin1), isTrue);
    });
  });
}
