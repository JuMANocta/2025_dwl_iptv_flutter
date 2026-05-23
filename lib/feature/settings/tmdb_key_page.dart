import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/core/utils/platform_tv.dart';
import 'package:aetherStream/data/services/pairing_service.dart';
import 'package:aetherStream/data/services/tmdb_api_service.dart';
import 'package:aetherStream/data/services/tmdb_service.dart';
import 'package:aetherStream/feature/pairing/pairing_page.dart';

/// Sous-page Settings (§1g) : gestion de la clé API TMDB.
///
/// Extrait du card "API TheMovieDB" d'`AccountsPage` pour aligner avec le
/// hub `SettingsPage`. La clé est stockée dans `flutter_secure_storage` via
/// [TmdbApiService]. Une fois sauvée, le `TmdbService` singleton est réinitialisé
/// pour prendre en compte la nouvelle clé.
class TmdbKeyPage extends StatefulWidget {
  const TmdbKeyPage({super.key});

  @override
  State<TmdbKeyPage> createState() => _TmdbKeyPageState();
}

class _TmdbKeyPageState extends State<TmdbKeyPage> {
  final _keyController = TextEditingController();
  bool _isKeyVisible = false;
  bool _hasSavedKey = false;
  bool _loading = true;
  // §3c-8 — Sur TV, le TextField est replié derrière un bouton "avancé"
  // pour éviter le piège de saisie au D-pad d'un Bearer JWT de 220 chars.
  bool _showAdvancedManual = false;

  @override
  void initState() {
    super.initState();
    _loadKey();
    // §19 — Auto-focus initial sur TV (CTA pairing en tête).
    if (PlatformTv.isTv) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) FocusScope.of(context).nextFocus();
      });
    }
  }

  /// §3c-8 — Pairing QR mobile→TV pour coller la clé TMDB depuis le téléphone.
  Future<void> _openPairing() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await Navigator.of(context).push<PairingResult>(
      MaterialPageRoute(
        builder: (_) => PairingPage(
          kind: PairingKind.tmdb,
          onManualFallback: () {
            Navigator.of(context).pop();
            setState(() => _showAdvancedManual = true);
          },
        ),
      ),
    );
    if (result is PairingTmdbResult) {
      await TmdbApiService.saveApiKey(result.token);
      TmdbService.resetInstance();
      if (!mounted) return;
      setState(() {
        _keyController.text = result.token;
        _hasSavedKey = true;
      });
      messenger.clearSnackBars();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('✅ TMDb connecté'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _loadKey() async {
    final key = await TmdbApiService.getApiKey();
    if (!mounted) return;
    setState(() {
      _keyController.text = key ?? '';
      _hasSavedKey = key != null && key.isNotEmpty;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    await TmdbApiService.saveApiKey(key);
    TmdbService.resetInstance();
    if (!mounted) return;
    setState(() => _hasSavedKey = true);
    FocusScope.of(context).unfocus();
    messenger.clearSnackBars();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('✅ TMDb connecté'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _delete() async {
    final messenger = ScaffoldMessenger.of(context);
    await TmdbApiService.deleteApiKey();
    TmdbService.resetInstance();
    if (!mounted) return;
    setState(() {
      _keyController.clear();
      _hasSavedKey = false;
    });
    messenger.clearSnackBars();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('🗑️ Clé TMDB supprimée'),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _openTmdbSignup() async {
    final uri = Uri.parse('https://www.themoviedb.org/settings/api');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isTv = PlatformTv.isTv;
    // §3c-8 — Sur TV, on cache le TextField par défaut (le coller au D-pad
    // d'un Bearer JWT 220 chars = ~8 minutes pour rien). Affiché seulement
    // si l'utilisateur choisit explicitement "Saisir manuellement".
    final showManualField = !isTv || _showAdvancedManual || _hasSavedKey;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clé API TMDB'),
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
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StatusBanner(active: _hasSavedKey),
                    if (isTv) ...[
                      const SizedBox(height: 20),
                      _TvPairingCta(
                        hasKey: _hasSavedKey,
                        onTap: _openPairing,
                      ),
                    ],
                    if (showManualField) ...[
                      const SizedBox(height: 20),
                      Text(
                        isTv && !_hasSavedKey
                            ? 'Saisie manuelle (avancée)'
                            : 'Bearer Token (v4 API)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _keyController,
                        obscureText: !_isKeyVisible,
                        readOnly: _hasSavedKey,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _save(),
                        style: TextStyle(
                          color: _hasSavedKey ? kAccentSecondary : cs.onSurface,
                          fontWeight: _hasSavedKey
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Coller ici votre token v4…',
                          filled: true,
                          fillColor: cs.surfaceContainerHighest,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(_isKeyVisible
                                ? Icons.visibility_off
                                : Icons.visibility),
                            onPressed: () => setState(
                                () => _isKeyVisible = !_isKeyVisible),
                            tooltip: _isKeyVisible
                                ? 'Masquer'
                                : 'Afficher',
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          if (_hasSavedKey)
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _delete,
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Supprimer'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 14),
                                ),
                              ),
                            )
                          else
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _save,
                                icon: const Icon(Icons.save),
                                label: const Text('Sauvegarder'),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 14),
                                  backgroundColor: kAccentPrimary,
                                  foregroundColor: Colors.black,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ] else if (isTv && !_hasSavedKey) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton.icon(
                          onPressed: () =>
                              setState(() => _showAdvancedManual = true),
                          icon: const Icon(Icons.keyboard_alt_outlined, size: 18),
                          label: const Text(
                              'Saisir manuellement à la télécommande'),
                          style: TextButton.styleFrom(
                              foregroundColor: cs.onSurfaceVariant),
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                    _InfoBlock(onOpenTmdb: _openTmdbSignup),
                  ],
                ),
              ),
      ),
    );
  }
}

/// §3c-8 — Card "Configurer depuis mobile" affichée en tête sur TV.
class _TvPairingCta extends StatelessWidget {
  final bool hasKey;
  final VoidCallback onTap;
  const _TvPairingCta({required this.hasKey, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kAccentPrimary.withAlpha(140), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: kAccentPrimary.withAlpha(50),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: kAccentPrimary.withAlpha(40),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: kAccentPrimary.withAlpha(150), width: 1),
                ),
                child:
                    Icon(Icons.phone_iphone, color: kAccentPrimary, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasKey
                          ? 'Remplacer depuis mon téléphone'
                          : 'Configurer depuis mon téléphone',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Scanne un QR et colle le Bearer Token côté mobile',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final bool active;
  const _StatusBanner({required this.active});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = active ? kAccentPrimary : cs.outlineVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: active ? kAccentPrimary.withAlpha(20) : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color, width: active ? 1.5 : 1),
      ),
      child: Row(
        children: [
          Icon(
            active ? Icons.check_circle : Icons.info_outline,
            color: active ? kAccentPrimary : cs.onSurfaceVariant,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              active
                  ? 'TMDb connecté — affiches et synopsis disponibles'
                  : 'Aucune clé enregistrée — fonctionne sans, mais sans enrichissement visuel',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: active ? kAccentPrimary : cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  final VoidCallback onOpenTmdb;
  const _InfoBlock({required this.onOpenTmdb});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.help_outline, size: 18, color: kAccentSecondary),
              const SizedBox(width: 8),
              Text(
                'Comment obtenir un token ?',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '1. Crée un compte gratuit sur themoviedb.org\n'
            '2. Va dans Paramètres → API\n'
            '3. Demande une clé v4 (Read Access Token)\n'
            '4. Colle le token ici',
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onOpenTmdb,
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Ouvrir themoviedb.org'),
            style: OutlinedButton.styleFrom(
              foregroundColor: kAccentSecondary,
              side: BorderSide(color: kAccentSecondary.withAlpha(120)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}
