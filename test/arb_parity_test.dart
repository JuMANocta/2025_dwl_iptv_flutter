// §l10nAll — **Les deux `.arb` ne doivent jamais diverger.**
//
// Le cliquet (`l10n_guard_test.dart`) empêche une chaîne française d'être
// écrite EN DUR. Il ne dit rien du cas symétrique, qui est tout aussi facile :
// ajouter la clé dans `app_fr.arb` et oublier `app_en.arb`. Le générateur
// laisse passer — il replie silencieusement sur le template — et la version
// anglaise se met à parler français, une clé à la fois.
//
// Ce test tient donc l'invariant : **même jeu de clés des deux côtés**, et
// aucune valeur vide. Il vérifie aussi que les métadonnées `@clé` ne survivent
// pas à la suppression de leur clé.
//
// ⚠️ `app_en.arb` est le TEMPLATE (`l10n.yaml`) : c'est lui qui définit les
// placeholders. Une clé présente en français seulement ne serait même pas
// générée.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _read(String path) {
  final file = File(path);
  if (!file.existsSync()) throw StateError('$path manquant');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

Set<String> _messageKeys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

void main() {
  final fr = _read('lib/l10n/app_fr.arb');
  final en = _read('lib/l10n/app_en.arb');

  test('§l10nAll — les deux .arb portent exactement les mêmes clés', () {
    final frKeys = _messageKeys(fr);
    final enKeys = _messageKeys(en);

    expect(frKeys.difference(enKeys), isEmpty,
        reason: 'Clé(s) en français mais PAS en anglais. `app_en.arb` est le '
            'template : une clé qui n\'y est pas n\'est pas générée du tout.');
    expect(enKeys.difference(frKeys), isEmpty,
        reason: 'Clé(s) en anglais mais PAS en français — l\'écran parlerait '
            'anglais sur un appareil français.');
  });

  test('§l10nAll — aucune traduction vide', () {
    for (final entry in [('fr', fr), ('en', en)]) {
      final (lang, arb) = entry;
      for (final key in _messageKeys(arb)) {
        expect((arb[key] as String).trim(), isNotEmpty,
            reason: '$lang : la clé « $key » est vide.');
      }
    }
  });

  test('§l10nAll — pas de métadonnée orpheline', () {
    for (final entry in [('fr', fr), ('en', en)]) {
      final (lang, arb) = entry;
      final orphans = arb.keys
          .where((k) => k.startsWith('@') && k != '@@locale')
          .where((k) => !arb.containsKey(k.substring(1)))
          .toList();
      expect(orphans, isEmpty,
          reason: '$lang : métadonnée(s) sans clé — ${orphans.join(', ')}');
    }
  });

  test('§l10nAll — les placeholders sont déclarés des deux côtés', () {
    final placeholder = RegExp(r'\{([A-Za-z][A-Za-z0-9_]*)\}');
    for (final key in _messageKeys(en)) {
      final inEn = placeholder
          .allMatches(en[key] as String)
          .map((m) => m.group(1)!)
          .toSet();
      final inFr = placeholder
          .allMatches(fr[key] as String)
          .map((m) => m.group(1)!)
          .toSet();
      // Un pluriel ICU (`{count, plural, …}`) n'est pas capté par la regex
      // simple ci-dessus des deux côtés de la même façon : on ne compare que
      // les messages SANS syntaxe ICU, où l'écart serait un vrai bug.
      final bool icu = (en[key] as String).contains(', plural,') ||
          (fr[key] as String).contains(', plural,');
      if (icu) continue;
      expect(inFr, inEn,
          reason: 'La clé « $key » n\'utilise pas les mêmes variables en '
              'français et en anglais : l\'une des deux affichera un trou.');
    }
  });
}
