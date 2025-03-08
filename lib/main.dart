import 'package:flutter/material.dart';
import 'secure_storage_service.dart';
import 'credential_form.dart';
import 'recherche.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IPTV App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SecureStorageService _storageService = SecureStorageService();
  bool _credentialsExist = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkCredentials();
  }

  Future<void> _checkCredentials() async {
    final creds = await _storageService.getCredentials();
    setState(() {
      _credentialsExist = _areCredentialsValid(creds);
      _isLoading = false;
    });
  }

  bool _areCredentialsValid(Map<String, String?> creds) {
    if (creds.isEmpty || creds['mode'] == null) return false;

    if (creds['mode'] == 'complete') {
      return creds['completeUrl'] != null && creds['completeUrl']!.isNotEmpty;
    }

    if (creds['mode'] == 'separate') {
      return (creds['baseUrl'] != null && creds['baseUrl']!.isNotEmpty) &&
          (creds['login'] != null && creds['login']!.isNotEmpty) &&
          (creds['password'] != null && creds['password']!.isNotEmpty);
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return _credentialsExist ? const Recherche() : const CredentialForm();
  }
}