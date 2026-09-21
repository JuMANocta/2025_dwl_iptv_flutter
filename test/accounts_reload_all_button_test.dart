// §reloadAll — « Recharger toutes les listes » était un ↻ nu dans l'AppBar de
// la page Comptes : personne ne devinait ce qu'il rechargeait. C'est désormais
// un bouton LIBELLÉ en tête de la liste, présent à partir de deux comptes
// seulement (avec un seul, le bouton de sa carte suffit).
import 'dart:convert';

import 'package:aetherStream/data/models/stream_account.dart';
import 'package:aetherStream/feature/accounts/accounts_page.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

StreamAccount _account(String id) => StreamAccount(
      id: id,
      label: 'Liste $id',
      mode: StreamAuthMode.separate,
      baseUrl: 'http://panel.test',
      username: 'u',
      password: 'p',
    );

void _seed(List<StreamAccount> accounts) {
  FlutterSecureStorage.setMockInitialValues(<String, String>{
    'accounts_index': jsonEncode(<String>[for (final a in accounts) a.id]),
    for (final a in accounts) 'account:${a.id}': jsonEncode(a.toJson()),
    'current_account_id': accounts.first.id,
  });
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(
    locale: Locale('fr'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: AccountsPage(),
  ));
  // Lectures du stockage simulé : de vraies futures, hors horloge de test.
  await tester.runAsync(() => Future<void>.delayed(
      const Duration(milliseconds: 200)));
  await tester.pump();
  await tester.pump();
}

/// `ExpirationAlertService.fetchAll` interroge le panel (faux hôte) derrière
/// `HostGate` : sa minuterie d'attente doit s'écouler avant la fin du test.
Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 10));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('deux comptes : bouton libellé en tête, plus de ↻ dans l\'AppBar',
      (tester) async {
    _seed(<StreamAccount>[_account('a'), _account('b')]);
    await _pump(tester);

    final Finder button =
        find.widgetWithText(FilledButton, 'Recharger toutes les listes');
    expect(button, findsOneWidget);
    expect(
      find.descendant(
          of: find.byType(AppBar), matching: find.byIcon(Icons.refresh)),
      findsNothing,
      reason: 'pas de doublon : l\'icône de l\'AppBar est retirée',
    );
    await _drain(tester);
  });

  testWidgets('un seul compte : pas de bouton de page', (tester) async {
    _seed(<StreamAccount>[_account('a')]);
    await _pump(tester);

    expect(find.text('Recharger toutes les listes'), findsNothing);
    await _drain(tester);
  });
}
