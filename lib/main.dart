// lib/main.dart
import 'package:flutter/material.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'services/iptv_account_service.dart';
import 'recherche.dart';
import 'screens/settings/accounts_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Dossier "app" utilisé par media_store_plus (obligatoire)
  // -> évite AppFolderNotSetException lors des saveFile(...)
  MediaStore.appFolder = 'IPtvFlux';

  // Migration éventuelle de l'ancien stockage mono-compte vers multi-comptes
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

/// Décide quoi afficher au lancement :
/// - S’il existe au moins un compte → page Recherche
/// - Sinon → écran d’accueil avec bouton pour ouvrir la roue crantée (comptes)
class _LaunchDecider extends StatefulWidget {
  const _LaunchDecider();

  @override
  State<_LaunchDecider> createState() => _LaunchDeciderState();
}

class _LaunchDeciderState extends State<_LaunchDecider> {
  bool _loading = true;
  bool _hasAccount = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final list = await IptvAccountService.listAccounts();
    setState(() {
      _hasAccount = list.isNotEmpty;
      _loading = false;
    });
  }

  Future<void> _openAccountsThenRecheck() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AccountsScreen()),
    );
    // Re-vérifie après retour (création/sélection éventuelle)
    await _check();
    if ((_hasAccount || changed == true) && mounted) {
      // On remplace par la page de recherche pour éviter retour sur l'onboarding
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const RecherchePage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_hasAccount) {
      return const RecherchePage();
    }

    // Onboarding simple si aucun compte
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
                onPressed: _openAccountsThenRecheck,
                icon: const Icon(Icons.settings),
                label: const Text('Configurer les comptes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
