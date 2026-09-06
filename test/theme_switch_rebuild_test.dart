import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/core/themes/app_theme_config.dart';
import 'package:aetherStream/core/themes/themes.dart';
import 'package:aetherStream/l10n/app_localizations.dart';

/// §themeReboot — Défaut constaté sur appareil réel le 2026-09-04, puis
/// reproduit ICI, sans appareil.
///
/// **Le symptôme** : changer une couleur de thème faisait apparaître un écran
/// rouge « Null check operator used on a null value » pendant une fraction de
/// seconde, **remontait tout le sous-arbre** de l'application et relançait le
/// démarrage complet.
///
/// **Ce que ça cassait vraiment** : une restauration `.aether` écrit le thème.
/// L'app repartait donc sur « Bienvenue » au milieu de la restauration (le
/// nouvel aiguilleur redemandait « faut-il montrer l'onboarding ? » avant que
/// la restauration ait pu répondre non), retéléchargeait les catalogues
/// (33 s mesurées), puis en relançait un second quand l'utilisateur terminait
/// l'onboarding. Le dialogue « Restauration réussie » était sauté en silence,
/// son contexte étant mort avec l'ancien aiguilleur.
///
/// **La cause** : `_chipFocusTheme` rendait `null` pour la bordure d'une puce
/// non focalisée. `ChipThemeData._lerpSides` (Flutter) résout les deux
/// bordures avec un ensemble d'états **vide**, puis fait `b!` — deux `null`,
/// une exception, à chaque interpolation de thème. Voir `themes.dart`.
void main() {
  const delegates = <LocalizationsDelegate<dynamic>>[
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];
  const locales = <Locale>[Locale('fr'), Locale('en')];

  final configA = AppThemeConfig.defaults;
  final configB = AppThemeConfig.defaults.copyWith(
    primaryColor: const Color(0xFFFF6D00),
  );

  group('§themeReboot — un changement de thème ne doit rien détruire', () {
    test('interpoler deux thèmes ne lève pas d\'exception', () {
      // C'est exactement ce que fait `AnimatedTheme` quand la couleur change.
      // ⚠️ Le garde-fou vaut pour les DEUX thèmes.
      expect(
        () => ThemeData.lerp(lightTheme(configA), lightTheme(configB), 0.5),
        returnsNormally,
      );
      expect(
        () => ThemeData.lerp(darkTheme(configA), darkTheme(configB), 0.5),
        returnsNormally,
      );
    });

    test('la bordure de puce n\'est JAMAIS nulle, focalisée ou non', () {
      for (final theme in [lightTheme(configA), darkTheme(configA)]) {
        final side = theme.chipTheme.side;
        expect(side, isNotNull, reason: 'le thème doit poser une bordure');
        final resolved =
            (side! as WidgetStateBorderSide).resolve(const <WidgetState>{});
        expect(
          resolved,
          isNotNull,
          reason: 'null ici casse ChipThemeData._lerpSides à chaque '
              'changement de thème (écran rouge + remontage complet)',
        );
      }
    });

    testWidgets(
      'changer le thème ne remonte pas la page et ne lève rien',
      (tester) async {
        int mountCount = 0;
        final notifier = ValueNotifier<AppThemeConfig>(configA);
        final navKey = GlobalKey<NavigatorState>();
        final observers = <NavigatorObserver>[
          RouteObserver<ModalRoute<void>>(),
        ];

        await tester.pumpWidget(
          ValueListenableBuilder<AppThemeConfig>(
            valueListenable: notifier,
            builder: (context, config, _) => MaterialApp(
              navigatorKey: navKey,
              navigatorObservers: observers,
              themeMode: config.themeMode,
              theme: lightTheme(config),
              darkTheme: darkTheme(config),
              localizationsDelegates: delegates,
              locale: const Locale('fr'),
              supportedLocales: locales,
              home: _Witness(onMount: () => mountCount++),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(mountCount, 1, reason: 'un seul montage au démarrage');
        expect(tester.takeException(), isNull);

        // Le geste fautif : une simple couleur qui change.
        notifier.value = configB;
        await tester.pump();
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'un changement de thème ne doit rien faire remonter',
        );
        expect(
          mountCount,
          1,
          reason: 'la page ne doit PAS être remontée : un remontage détruit '
              'l\'état du sous-arbre — dans l\'app, TOUT le démarrage',
        );
      },
    );
  });
}

/// Page témoin : elle fait ce que font les 23 pages de l'app
/// (`AppLocalizations.of(context)!`) et compte ses montages.
class _Witness extends StatefulWidget {
  const _Witness({required this.onMount});
  final VoidCallback onMount;

  @override
  State<_Witness> createState() => _WitnessState();
}

class _WitnessState extends State<_Witness> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(body: Center(child: Text(l10n.settingsTitle)));
  }
}
