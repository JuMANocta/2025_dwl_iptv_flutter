// §l10nAll (2026-09-05) — L'infrastructure de traduction, tranche 0.
//
// Deux accès, un par situation :
//   • `context.l10n` dans les widgets ;
//   • `L10n.current` pour tout ce qui n'a pas de `BuildContext` — les
//     services, `describeError()`, les ponts natifs.
//
// ⚠️ **La propriété qui rend le second sûr est son REPLI.** Un message d'erreur
// peut naître avant la première frame (échec au démarrage), ou dans un test
// sans arbre de widgets. Lever à ce moment-là remplacerait une erreur
// explicable par une erreur incompréhensible — précisément dans le chemin où
// l'utilisateur a le plus besoin d'une phrase claire.

import 'package:aetherStream/core/utils/user_error.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:aetherStream/l10n/l10n_ext.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(L10n.resetForTest);
  tearDown(L10n.resetForTest);

  group('§l10nAll — accès hors widget', () {
    test('sans binding, repli sur le français plutôt qu\'une exception', () {
      expect(L10n.current, isA<AppLocalizations>());
      expect(L10n.current.localeName, 'fr');
    });

    test('après binding, c\'est la locale liée qui parle', () {
      L10n.bind(lookupAppLocalizations(const Locale('en')));
      expect(L10n.current.localeName, 'en');
      L10n.resetForTest();
      expect(L10n.current.localeName, 'fr');
    });

    test('les messages d\'erreur passent par la traduction', () {
      // Le chemin service de bout en bout : `describeError` n'a aucun
      // `BuildContext` et rend pourtant un texte issu des `.arb`.
      final String fr = describeError(const FormatException('boom'));
      expect(fr, lookupAppLocalizations(const Locale('fr')).errBadFormat);

      L10n.bind(lookupAppLocalizations(const Locale('en')));
      final String en = describeError(const FormatException('boom'));
      expect(en, lookupAppLocalizations(const Locale('en')).errBadFormat);
      expect(en, isNot(fr), reason: 'les deux langues doivent différer');
    });

    test('⚠️ un message déjà écrit pour l\'utilisateur n\'est pas retraduit', () {
      // §userErrorOwn — `UserFacingException` porte un texte déjà destiné à
      // l'écran : le repasser dans la moulinette réseau le remplacerait par
      // « Connexion impossible… », ce qui serait faux.
      const custom = 'Le mot de passe de la sauvegarde est incorrect.';
      expect(describeError(const UserFacingException(custom)), custom);
    });
  });

  group('§l10nAll — accès dans un widget', () {
    testWidgets('context.l10n rend les textes de la locale courante',
        (tester) async {
      late String seen;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (context) {
          seen = context.l10n.errCancelled;
          return const SizedBox.shrink();
        }),
      ));
      expect(seen, lookupAppLocalizations(const Locale('en')).errCancelled);
    });
  });

  group('§l10nAll — les deux catalogues restent alignés', () {
    test('aucune clé française sans équivalent anglais', () {
      // Une clé ajoutée dans un seul `.arb` compile quand même : le générateur
      // retombe sur le template. Le défaut ne se verrait qu'à l'écran, dans la
      // langue qu'on ne regarde jamais pendant le développement.
      final fr = lookupAppLocalizations(const Locale('fr'));
      final en = lookupAppLocalizations(const Locale('en'));
      // Échantillon des clés ajoutées par les tranches 1 et 2.
      for (final pair in <List<String>>[
        [fr.settingsSectionSources, en.settingsSectionSources],
        [fr.settingsResetTitle, en.settingsResetTitle],
        [fr.errNetworkUnreachable, en.errNetworkUnreachable],
        [fr.errTls, en.errTls],
        [fr.errCancelled, en.errCancelled],
      ]) {
        expect(pair[0], isNotEmpty);
        expect(pair[1], isNotEmpty);
        expect(pair[0], isNot(pair[1]),
            reason: 'traduction manquante (les deux langues sont identiques)');
      }
      // Les messages à paramètre gardent leur paramètre dans les deux langues.
      expect(fr.errForbidden(403), contains('403'));
      expect(en.errForbidden(403), contains('403'));
    });
  });
}
