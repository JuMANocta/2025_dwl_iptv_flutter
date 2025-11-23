import 'package:flutter/material.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'data/services/download_manager_service.dart';
import 'data/services/stream_account_service.dart';
import 'feature/search/recherche_page.dart';
import 'feature/accounts/accounts_page.dart';
import 'data/services/playlist_service.dart';
import 'core/themes/themes.dart';
import 'core/themes/colors.dart';

/// Clé globale pour le Navigator, permettant une navigation programmatique sans `BuildContext`.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Point d'entrée de l'application.
void main() async {
  // Séquence d'initialisation critique avant le lancement de l'UI.
  WidgetsFlutterBinding.ensureInitialized();
  await MediaStore.ensureInitialized();
  MediaStore.appFolder = 'AetherStream';
  await StreamAccountService.migrateFromLegacyIfNeeded();
  await DownloadManagerService().init();

  runApp(const MyApp());
}

/// Widget racine de l'application.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'AetherStream',
      themeMode: ThemeMode.system,
      theme: lightTheme(),
      darkTheme: darkTheme(),
      debugShowCheckedModeBanner: false,

      localizationsDelegates: const [
        AppLocalizations.delegate, // Notre delegate généré
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'), // Anglais
        Locale('fr'), // Français
      ],

      // Le `builder` est utilisé ici pour superposer un bandeau "BETA"
      // uniquement en mode debug, sans interférer avec le widget `home`.
      builder: (context, child) {
        bool isDebug = false;
        assert(isDebug = true); // Astuce pour n'être `true` qu'en mode debug.

        if (isDebug) {
          return Banner(
            message: "BETA",
            location: BannerLocation.topEnd,
            color: kAetherPrimaryPurple,
            child: child,
          );
        }
        return child!;
      },
      home: const _LaunchDecider(),
    );
  }
}

/// Ce widget agit comme un "aiguilleur" au démarrage.
/// Il affiche un écran de chargement, puis décide de la page à afficher
/// en fonction de l'état de l'initialisation (comptes, playlist).
class _LaunchDecider extends StatefulWidget {
  const _LaunchDecider();
  @override
  State<_LaunchDecider> createState() => _LaunchDeciderState();
}

class _LaunchDeciderState extends State<_LaunchDecider> {
  late Future<bool> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _initializeApp();
  }

  /// Valide la configuration initiale (comptes + playlist).
  Future<bool> _initializeApp() async {
    final accounts = await StreamAccountService.listAccounts();
    if (accounts.isEmpty) return false;

    // Propage l'erreur au FutureBuilder si la playlist échoue.
    await PlaylistService.getOrDownloadPlaylist();
    return true;
  }

  /// Permet de relancer la validation, typiquement après une action de l'utilisateur.
  void _retryInitialization() {
    setState(() {
      _initFuture = _initializeApp();
    });
  }

  /// Navigue vers les paramètres et force une réinitialisation au retour.
  Future<void> _recheckAfterSettings() async {
    await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const AccountsPage()));
    _retryInitialization();
  }

  @override
  Widget build(BuildContext context) {
    // Le FutureBuilder gère nativement les différents états (chargement, erreur, succès)
    // de notre logique d'initialisation asynchrone.
    return FutureBuilder<bool>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(height: 16), Text("Initialisation...")])));
        }
        if (snapshot.hasError) {
          return Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24.0), child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            const Text('Erreur au Démarrage', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(snapshot.error.toString(), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(onPressed: _retryInitialization, icon: const Icon(Icons.refresh), label: const Text("Réessayer")),
            const SizedBox(height: 8),
            TextButton(onPressed: _recheckAfterSettings, child: const Text("Vérifier les comptes"))
          ]))));
        }
        final hasAccountAndPlaylistIsReady = snapshot.data ?? false;
        if (hasAccountAndPlaylistIsReady) {
          return const RecherchePage();
        }
        return Scaffold(appBar: AppBar(title: const Text('AetherStream')), body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.settings, size: 64),
          const SizedBox(height: 16),
          const Text('Aucun compte configuré', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('Ajoutez un compte via la roue crantée pour commencer.', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: _recheckAfterSettings, icon: const Icon(Icons.settings), label: const Text('Configurer les comptes')),
        ]))));
      },
    );
  }
}