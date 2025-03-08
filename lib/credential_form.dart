import 'package:flutter/material.dart';
import 'secure_storage_service.dart';
import 'recherche.dart';

class CredentialForm extends StatefulWidget {
  const CredentialForm({super.key});

  @override
  _CredentialFormState createState() => _CredentialFormState();
}

class _CredentialFormState extends State<CredentialForm> {
  final _formKey = GlobalKey<FormState>();
  final _completeUrlController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  final SecureStorageService _storageService = SecureStorageService();

  bool _isCompleteMode = true; // Mode par défaut : URL complète

  Future<void> _saveCredentials() async {
    if (_formKey.currentState!.validate()) {
      final credentials = _isCompleteMode
          ? {
        "mode": "complete",
        "completeUrl": _completeUrlController.text,
      }
          : {
        "mode": "separate",
        "baseUrl": _baseUrlController.text,
        "login": _loginController.text,
        "password": _passwordController.text,
      };

      await _storageService.saveCredentials(credentials);

      if (context.mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const Recherche()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Configuration IPTV")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  title: const Text('Utiliser URL complète'),
                  value: _isCompleteMode,
                  onChanged: (value) => setState(() => _isCompleteMode = value),
                ),
                const SizedBox(height: 20),
                if (_isCompleteMode)
                  TextFormField(
                    controller: _completeUrlController,
                    decoration: const InputDecoration(
                      labelText: "URL complète",
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.isEmpty
                        ? "Veuillez entrer l'URL complète"
                        : null,
                  ),
                if (!_isCompleteMode) ...[
                  TextFormField(
                    controller: _baseUrlController,
                    decoration: const InputDecoration(
                      labelText: "URL de base",
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.isEmpty
                        ? "Veuillez entrer l'URL de base"
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _loginController,
                    decoration: const InputDecoration(
                      labelText: "Login",
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.isEmpty
                        ? "Veuillez entrer votre login"
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: "Mot de passe",
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    validator: (value) => value == null || value.isEmpty
                        ? "Veuillez entrer votre mot de passe"
                        : null,
                  ),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _saveCredentials,
                  child: const Text("Sauvegarder"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _completeUrlController.dispose();
    _baseUrlController.dispose();
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}