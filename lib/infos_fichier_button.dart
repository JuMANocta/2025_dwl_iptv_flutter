import 'package:flutter/material.dart';
import 'screens/accounts_screen.dart';

class InfosFichierButton extends StatelessWidget {
  /// Optionnel : texte du bouton (pour compat)
  final String label;
  /// Optionnel : padding autour du bouton (pour compat)
  final EdgeInsetsGeometry padding;

  const InfosFichierButton({
    super.key,
    this.label = "Infos playlist",
    this.padding = const EdgeInsets.all(8),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: OutlinedButton.icon(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AccountsScreen()),
          );
        },
        icon: const Icon(Icons.info_outline),
        label: Text(label),
      ),
    );
  }
}
