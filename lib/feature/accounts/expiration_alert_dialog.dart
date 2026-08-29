import 'package:flutter/material.dart';

import '../../core/themes/colors.dart';
import '../../data/models/account_info.dart';
import '../../data/models/stream_account.dart';
import '../../data/services/expiration_alert_service.dart';
import 'accounts_page.dart';
import 'package:aetherStream/widgets/tv/tv_adaptive_modal.dart';

/// AlertDialog §17b — popup au démarrage si au moins un compte expire <30j.
///
/// Liste les comptes concernés avec leurs dates + bouton "Voir détails"
/// (push `AccountsPage` — stats + expiration intégrées) + bouton "Plus tard".
/// Si au moins un compte
/// est **déjà expiré** (`daysLeft < 0`), le dialog devient non-dismissible
/// (l'app ne sert plus à rien sans playlist active).
///
/// Acquittement : le bouton "Plus tard" marque les alertes ack via
/// [ExpirationAlertService.ack], ce qui empêche la re-popup tant que la date
/// d'expiration ne change pas (renouvellement détecté).
class ExpirationAlertDialog extends StatelessWidget {
  final List<({StreamAccount account, AccountInfo info, int daysLeft})> alerts;

  const ExpirationAlertDialog({super.key, required this.alerts});

  static Future<void> show(
    BuildContext context,
    List<({StreamAccount account, AccountInfo info, int daysLeft})> alerts,
  ) async {
    if (alerts.isEmpty) return;
    final blocking = alerts.any((a) => a.daysLeft < 0);
    await showAppDialog<void>(
      context: context,
      barrierDismissible: !blocking,
      builder: (_) => ExpirationAlertDialog(alerts: alerts),
    );
  }

  String _formatLine(int daysLeft, DateTime expDate) {
    final d = '${expDate.day.toString().padLeft(2, '0')}/'
        '${expDate.month.toString().padLeft(2, '0')}/${expDate.year}';
    if (daysLeft < 0) return 'Expirée depuis ${-daysLeft} jours ($d)';
    if (daysLeft == 0) return 'Expire aujourd\'hui ($d)';
    if (daysLeft == 1) return 'Expire demain ($d)';
    return 'Expire dans $daysLeft jours ($d)';
  }

  Color _lineColor(int daysLeft) {
    if (daysLeft < 0 || daysLeft <= 7) return kError;
    return kWarning;
  }

  Future<void> _ackAll() async {
    for (final a in alerts) {
      if (a.info.expirationDate != null && a.daysLeft >= 0) {
        await ExpirationAlertService.ack(a.account.id, a.info.expirationDate!);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final blocking = alerts.any((a) => a.daysLeft < 0);
    return AlertDialog(
      icon: Icon(
        Icons.warning_amber_rounded,
        size: 40,
        color: blocking ? kError : kWarning,
      ),
      title: Text(
        blocking
            ? 'Playlist expirée'
            : 'Playlist bientôt expirée',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final a in alerts) ...[
            Text(
              a.account.label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _formatLine(a.daysLeft, a.info.expirationDate!),
              style: TextStyle(
                fontSize: 13,
                color: _lineColor(a.daysLeft),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 4),
          Text(
            blocking
                ? 'Cette playlist n\'est plus utilisable. Renouvelle auprès de ton provider pour reprendre l\'accès.'
                : 'Renouvelle auprès de ton provider pour ne pas perdre l\'accès.',
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
      actions: [
        if (!blocking)
          TextButton(
            onPressed: () async {
              await _ackAll();
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Plus tard'),
          ),
        FilledButton.icon(
          onPressed: () async {
            await _ackAll();
            if (!context.mounted) return;
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const AccountsPage(),
              ),
            );
          },
          icon: const Icon(Icons.open_in_new, size: 18),
          label: const Text('Voir détails'),
          style: FilledButton.styleFrom(
            backgroundColor: kAccentPrimary,
            foregroundColor: Colors.black,
          ),
        ),
      ],
    );
  }
}
