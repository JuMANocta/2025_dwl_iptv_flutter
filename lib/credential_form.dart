import 'package:flutter/material.dart';
import 'screens/settings/accounts_screen.dart';

/// Ancien nom le plus probable (conservé pour compat)
class CredentialForm extends StatelessWidget {
  const CredentialForm({super.key});

  @override
  Widget build(BuildContext context) {
    // On renvoie directement l'écran de gestion des comptes
    return const AccountsScreen();
  }
}

/// Variante souvent utilisée dans certains projets (on garde aussi)
class CredentialFormPage extends StatelessWidget {
  const CredentialFormPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AccountsScreen();
  }
}
