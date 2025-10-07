// lib/main.dart
import 'package:flutter/material.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'services/iptv_account_service.dart';
import 'recherche.dart';
import 'screens/settings/accounts_screen.dart';
import 'services/playlist_service.dart'; // <-- 1. AJOUTER CET IMPORT

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaStore.appFolder = 'IPtvFlux';
  await IptvAccountService.migrateFromLegacyIfNeeded();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  ThemeData _theme(Brightness b) {
    final base = ThemeData(
      useMaterial3: true,
      colorSchemeSeed: Colors.greenAccent,
      brightness: b,
    );
    return base.copyWith(
      appBarTheme: base.appBarTheme.copyWith(
        centerTitle: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IPtvFlux',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: const _LaunchDecider(),
    );
  }
}

class _LaunchDecider extends StatefulWidget {
  const _LaunchDecider();

  @override
  State<_LaunchDecider> createState() => _LaunchDeciderState();
}

class _LaunchDeciderState extends State<_LaunchDecider> {
  // 2. MODIFICATION : On utilise une seule variable d'état
  late Future<bool> _initFuture;

  @override
  void initState() {
    super.initState();
    // 3. On lance notre nouvelle fonction d'initialisation
    _initFuture = _initializeApp();
  }

  // 4. NOUVELLE FONCTION D'INITIALISATION
  Future<bool> _initializeApp() async {
    final accounts = await IptvAccountService.listAccounts();
    if (accounts.isEmpty) {
      return false; // Pas de compte, on va à l'onboarding
    }

    // S'il y a des comptes, on lance le chargement intelligent de la playlist.
    // L'écran de chargement attendra la fin de cette opération.
    try {
      await PlaylistService.getOrDownloadPlaylist();
      return true; // Playlist prête, on va à la recherche
    } catch (e) {
      // Si le chargement échoue, on peut décider d'aller à la page de recherche
      // qui affichera une erreur, ou aux paramètres.
      // Dans ce cas, aller à la recherche est cohérent.
      // ignore: avoid_print
      print("Erreur au chargement initial de la playlist: $e");
      // On peut choisir de continuer quand même vers la page de recherche
      // qui pourra gérer l'affichage d'une erreur.
      return true;
    }
  }

  Future<void> _recheckAfterSettings() async {
    // Navigue vers les paramètres
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AccountsScreen()),
    );

    // Après retour, on relance toute l'initialisation
    setState(() {
      _initFuture = _initializeApp();
    });
  }

  // 5. MODIFICATION DU BUILD POUR UTILISER FUTUREBUILDER
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _initFuture,
      builder: (context, snapshot) {
        // Pendant que l'on vérifie les comptes ET la playlist
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text("Initialisation..."),
                ],
              ),
            ),
          );
        }

        // Si une erreur survient dans _initializeApp (ne devrait pas arriver avec le try/catch)
        if (snapshot.hasError) {
          return Scaffold(body: Center(child: Text("Erreur critique: ${snapshot.error}")));
        }

        final hasAccountAndPlaylistIsReady = snapshot.data ?? false;

        // Si tout est prêt (compte trouvé ET playlist chargée) -> Page de recherche
        if (hasAccountAndPlaylistIsReady) {
          return const RecherchePage();
        }

        // Sinon (pas de compte) -> Onboarding
        return Scaffold(
          appBar: AppBar(title: const Text('IPtvFlux')),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.settings, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'Aucun compte IPTV configuré',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Ajoute un compte via la roue crantée pour télécharger la playlist et commencer la recherche.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _recheckAfterSettings, // On utilise la nouvelle fonction
                    icon: const Icon(Icons.settings),
                    label: const Text('Configurer les comptes'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
