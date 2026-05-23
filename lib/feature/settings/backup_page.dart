import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/core/utils/platform_tv.dart';
import 'package:aetherStream/data/services/backup_service.dart';

/// Page Sauvegarde / Restauration (§10).
///
/// 2 actions principales :
///   - **Exporter** : génère un fichier `.aether` chiffré (AES-256-GCM +
///     PBKDF2) dans `Download/AetherStream/` à partir de la config courante.
///   - **Restaurer** : sélectionne un fichier `.aether`, demande le mot de
///     passe, affiche un résumé pour confirmation, puis écrase l'état courant.
class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _exporting = false;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    // §19 — Auto-focus initial sur TV.
    if (PlatformTv.isTv) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) FocusScope.of(context).nextFocus();
      });
    }
  }

  // ── EXPORT ────────────────────────────────────────────────────────────────

  Future<void> _onExportTap() async {
    if (_exporting) return;

    final password = await _askExportPassword();
    if (password == null || password.isEmpty) return;

    if (!mounted) return;
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final fileName = await BackupService.exportAll(password);
      if (!mounted) return;
      _showExportSuccessDialog(fileName);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('❌ Échec : $e')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Dialog de saisie du mot de passe d'export (saisie + confirmation).
  Future<String?> _askExportPassword() async {
    final pwd1 = TextEditingController();
    final pwd2 = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        bool visible = false;
        String? error;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Mot de passe de chiffrement'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choisis un mot de passe — il sera demandé pour restaurer la sauvegarde.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: pwd1,
                    obscureText: !visible,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => FocusScope.of(ctx).nextFocus(),
                    decoration: InputDecoration(
                      labelText: 'Mot de passe',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(visible
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () => setLocal(() => visible = !visible),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: pwd2,
                    obscureText: !visible,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => FocusScope.of(ctx).unfocus(),
                    decoration: const InputDecoration(
                      labelText: 'Confirmer',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(error!,
                        style: TextStyle(color: kWarning, fontSize: 12)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () {
                    final a = pwd1.text;
                    final b = pwd2.text;
                    if (a.isEmpty) {
                      setLocal(() => error = 'Le mot de passe ne peut pas être vide.');
                      return;
                    }
                    if (a.length < 6) {
                      setLocal(() => error = 'Au moins 6 caractères.');
                      return;
                    }
                    if (a != b) {
                      setLocal(() => error = 'Les deux mots de passe ne correspondent pas.');
                      return;
                    }
                    Navigator.pop(ctx, a);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: kAccentPrimary,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Sauvegarder'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showExportSuccessDialog(String fileName) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: kAccentPrimary, size: 22),
            const SizedBox(width: 8),
            const Text('Sauvegarde créée'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fileName,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Disponible dans :\n/storage/emulated/0/Download/AetherStream/\n\n'
              'Copie ce fichier sur Drive, ton PC, ou un autre device pour le restaurer plus tard. '
              'N\'oublie pas le mot de passe — il n\'est nulle part stocké.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(
              backgroundColor: kAccentPrimary,
              foregroundColor: Colors.black,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ── IMPORT ────────────────────────────────────────────────────────────────

  Future<void> _onImportTap() async {
    if (_importing) return;

    // 1. Sélection du fichier.
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (picked == null || picked.files.single.path == null) return;
    final path = picked.files.single.path!;

    if (!mounted) return;

    // 2. Saisie du mot de passe.
    final password = await _askImportPassword();
    if (password == null || password.isEmpty) return;

    // 3. Lecture + décrypt en mémoire (sans appliquer).
    if (!mounted) return;
    setState(() => _importing = true);
    final messenger = ScaffoldMessenger.of(context);
    BackupContent? content;
    try {
      content = await BackupService.readBackup(path, password);
    } catch (e) {
      if (!mounted) return;
      setState(() => _importing = false);
      messenger.showSnackBar(SnackBar(content: Text('❌ $e')));
      return;
    }

    // 4. Confirmation avec résumé.
    if (!mounted) return;
    final ok = await _confirmApply(content);
    if (ok != true) {
      if (mounted) setState(() => _importing = false);
      return;
    }

    // 5. Application effective.
    try {
      await BackupService.applyBackup(content);
      if (!mounted) return;
      _showImportSuccessDialog(content);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('❌ Échec : $e')));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<String?> _askImportPassword() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        bool visible = false;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('Mot de passe de la sauvegarde'),
            content: TextField(
              controller: ctrl,
              obscureText: !visible,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Mot de passe',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                      visible ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setLocal(() => visible = !visible),
                ),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text),
                style: FilledButton.styleFrom(
                  backgroundColor: kAccentPrimary,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Déchiffrer'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool?> _confirmApply(BackupContent content) async {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: kWarning, size: 22),
            const SizedBox(width: 8),
            const Text('Confirmer la restauration'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sauvegarde du ${_fmtDate(content.exportedAt)} '
              '(v${content.appVersion}) :',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: kAccentPrimary.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: kAccentPrimary.withAlpha(80), width: 1),
              ),
              child: Text(
                content.summary(),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: kAccentPrimary),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Tout l\'état actuel (comptes, clé TMDB, thème, favoris, '
              'progression de lecture) sera ÉCRASÉ par cette sauvegarde.\n\n'
              'Action irréversible. Continuer ?',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: kWarning,
              foregroundColor: Colors.black,
            ),
            child: const Text('Restaurer'),
          ),
        ],
      ),
    );
  }

  void _showImportSuccessDialog(BackupContent content) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: kAccentPrimary, size: 22),
            const SizedBox(width: 8),
            const Text('Restauration réussie'),
          ],
        ),
        content: Text(
          '${content.summary()}\n\n'
          'Les playlists IPTV seront re-téléchargées au prochain démarrage.',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(
              backgroundColor: kAccentPrimary,
              foregroundColor: Colors.black,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${pad(d.day)}/${pad(d.month)}/${d.year} ${pad(d.hour)}h${pad(d.minute)}';
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final busy = _exporting || _importing;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sauvegarde'),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: isDark ? null : cs.surface,
          gradient: isDark
              ? RadialGradient(
                  center: const Alignment(0, -1.5),
                  radius: 1.4,
                  colors: [
                    kAccentPrimary.withAlpha(20),
                    cs.surface,
                  ],
                )
              : null,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ActionCard(
                icon: Icons.cloud_upload_outlined,
                color: kAccentPrimary,
                title: 'Créer une sauvegarde',
                subtitle:
                    'Chiffre tes comptes, clé TMDB, thème, favoris et progression dans un fichier .aether.',
                buttonLabel: _exporting
                    ? 'Chiffrement en cours…'
                    : 'Sauvegarder',
                busy: _exporting,
                disabled: busy,
                onPressed: _onExportTap,
              ),
              const SizedBox(height: 14),
              _ActionCard(
                icon: Icons.cloud_download_outlined,
                color: kAccentSecondary,
                title: 'Restaurer une sauvegarde',
                subtitle:
                    'Sélectionne un fichier .aether, saisis ton mot de passe, vérifie le résumé, applique.',
                buttonLabel: _importing
                    ? 'Restauration en cours…'
                    : 'Importer un fichier .aether',
                busy: _importing,
                disabled: busy,
                onPressed: _onImportTap,
              ),
              const SizedBox(height: 20),
              _InfoBlock(),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Sous-widgets ───────────────────────────────────────────────────────────

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final bool busy;
  final bool disabled;
  final VoidCallback onPressed;

  const _ActionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.busy,
    required this.disabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(80), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withAlpha(30),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withAlpha(120), width: 1),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: disabled ? null : onPressed,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : Icon(icon),
            label: Text(
              buttonLabel,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withAlpha(120),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline, size: 18, color: kAccentSecondary),
              const SizedBox(width: 8),
              Text(
                'Comment ça marche',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '• Fichier `.aether` chiffré AES-256-GCM + PBKDF2 (100k itérations).\n'
            '• Mot de passe choisi par toi — l\'app ne le stocke nulle part.\n'
            '• Stockage : Download/AetherStream/ (survit à un uninstall).\n'
            '• Contenu : comptes IPTV, clé TMDB, thème, favoris, progression.\n'
            '• Exclus : téléchargements (trop lourds), historique de recherche.\n'
            '• L\'import écrase entièrement la config actuelle (action irréversible).',
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }
}
