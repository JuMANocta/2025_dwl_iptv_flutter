import 'package:flutter/material.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'services/download_manager_service.dart';
import 'services/iptv_account_service.dart';
import 'recherche_page.dart';
import 'screens/accounts_screen.dart';
import 'services/playlist_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MediaStore.ensureInitialized();
  MediaStore.appFolder = 'IPtvFlux';
  await IptvAccountService.migrateFromLegacyIfNeeded();
  await DownloadManagerService().init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  ThemeData _theme(Brightness b) {
    final base = ThemeData(useMaterial3: true, colorSchemeSeed: Colors.greenAccent, brightness: b);
    return base.copyWith(appBarTheme: base.appBarTheme.copyWith(centerTitle: true));
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
  late Future<bool> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _initializeApp();
  }

  Future<bool> _initializeApp() async {
    final accounts = await IptvAccountService.listAccounts();
    if (accounts.isEmpty) return false;
    await PlaylistService.getOrDownloadPlaylist();
    return true;
  }

  void _retryInitialization() {
    setState(() => _initFuture = _initializeApp());
  }

  Future<void> _recheckAfterSettings() async {
    await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const AccountsScreen()));
    _retryInitialization();
  }

  @override
  Widget build(BuildContext context) {
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
          // L'appel à RecherchePage est maintenant correct car il vient du bon fichier
          return const RecherchePage();
        }
        return Scaffold(appBar: AppBar(title: const Text('IPtvFlux')), body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.settings, size: 64),
          const SizedBox(height: 16),
          const Text('Aucun compte IPTV configuré', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('Ajoutez un compte via la roue crantée pour commencer.', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: _recheckAfterSettings, icon: const Icon(Icons.settings), label: const Text('Configurer les comptes')),
        ]))));
      },
    );
  }
}
