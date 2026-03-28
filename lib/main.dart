import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'data/services/download_manager_service.dart';
import 'data/services/stream_account_service.dart';
import 'data/services/parsed_playlist_service.dart';
import 'feature/search/recherche_page.dart';
import 'feature/accounts/accounts_page.dart';
import 'data/services/playlist_service.dart';
import 'core/themes/themes.dart';
import 'core/themes/colors.dart';
import 'data/services/update_service.dart';
import 'feature/update/update_dialog.dart';

/// Clé globale pour le Navigator, permettant une navigation programmatique sans `BuildContext`.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Point d'entrée de l'application.
void main() async {
  // Séquence d'initialisation critique avant le lancement de l'UI.
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await MediaStore.ensureInitialized();
  MediaStore.appFolder = 'AetherStream';
  await StreamAccountService.migrateFromLegacyIfNeeded();
  await DownloadManagerService().init();

  runApp(const MyApp());

  // Vérification silencieuse des mises à jour après le démarrage (non-bloquant).
  // Délai court pour laisser l'UI s'afficher avant la requête réseau.
  Future.delayed(const Duration(seconds: 3), _checkForUpdate);
}

/// Vérifie silencieusement si une mise à jour est disponible.
/// Affiche le dialogue uniquement si une nouvelle version existe.
Future<void> _checkForUpdate() async {
  final info = await UpdateService.checkForUpdate();
  if (info == null) return;
  final context = navigatorKey.currentContext;
  if (context == null || !context.mounted) return;
  await UpdateDialog.show(context, info);
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
  late Future<({String path, String accountId, String accountName})?> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _initializeApp();
  }

  /// Valide la configuration initiale et retourne les données du compte actif (null = pas de compte).
  Future<({String path, String accountId, String accountName})?> _initializeApp() async {
    final accounts = await StreamAccountService.listAccounts();
    if (accounts.isEmpty) return null;

    // Téléchargement / vérification cache M3U du compte actif.
    final path = await PlaylistService.getOrDownloadPlaylist();
    final acc  = await StreamAccountService.getCurrentAccount();

    // Précharger silencieusement les autres comptes depuis le disque (background).
    if (accounts.length > 1) {
      final others = accounts.where((a) => a.id != acc?.id).toList();
      ParsedPlaylistService.preloadOthersFromDisk(others);  // fire & forget
    }

    return (
      path:        path,
      accountId:   acc?.id   ?? '',
      accountName: acc?.label ?? '',
    );
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
    return FutureBuilder<({String path, String accountId, String accountName})?>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          final cs = Theme.of(context).colorScheme;
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'AetherStream',
                    style: TextStyle(color: cs.onSurface, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 32),
                  CircularProgressIndicator(color: cs.primary),
                ],
              ),
            ),
          );
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
        final data = snapshot.data;
        if (data != null) {
          return RecherchePage(initialData: data);
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