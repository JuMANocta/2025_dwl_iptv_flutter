import 'package:flutter/material.dart';
import '../feature/accounts/accounts_page.dart';

/// Ancien nom le plus probable (conservé pour compat)
class CredentialForm extends StatelessWidget {
  const CredentialForm({super.key});

  @override
  Widget build(BuildContext context) {
    // On renvoie directement l'écran de gestion des comptes
    return const AccountsPage();
  }
}

/// Variante souvent utilisée dans certains projets (on garde aussi)
class CredentialFormPage extends StatelessWidget {
  const CredentialFormPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AccountsPage();
  }
}
