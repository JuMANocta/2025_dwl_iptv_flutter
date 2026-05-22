import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/themes/colors.dart';
import '../../core/themes/theme_service.dart';
import '../../data/services/pairing_service.dart';

/// Page d'attente d'un pairing mobile→TV (§3c-8).
///
/// Affiche un QR code que l'utilisateur scanne depuis son téléphone. Au scan,
/// le navigateur du mobile ouvre un mini-serveur HTTP servi par la TV (cf.
/// [PairingService]) avec un formulaire HTML thémé. Une fois soumis, la TV
/// reçoit le [PairingResult] via le stream et la page se ferme avec ce
/// résultat (`Navigator.pop(result)`).
///
/// Utilisation :
/// ```dart
/// final result = await Navigator.push<PairingResult>(
///   context,
///   MaterialPageRoute(builder: (_) => const PairingPage(kind: PairingKind.account)),
/// );
/// ```
///
/// Mode embedded (pour `OnboardingPage` slide 2) : passer `embedded: true`
/// pour omettre le Scaffold et utiliser le widget comme un body inline.
class PairingPage extends StatefulWidget {
  final PairingKind kind;
  final bool embedded;

  /// Callback optionnel pour gérer le fallback manuel (édition à la
  /// télécommande). Si null, un bouton "Saisir manuellement" est affiché et
  /// retourne `null` via `Navigator.pop` — au caller de décider quoi faire.
  final VoidCallback? onManualFallback;

  /// Callback alternatif au `Navigator.pop(result)` par défaut. Utilisé quand
  /// la page est embarquée (mode `embedded: true`) et qu'il n'y a pas de route
  /// à fermer — le parent veut traiter le résultat in-situ (cf. onboarding TV).
  final void Function(PairingResult)? onResult;

  const PairingPage({
    super.key,
    required this.kind,
    this.embedded = false,
    this.onManualFallback,
    this.onResult,
  });

  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> {
  StreamSubscription<PairingResult>? _sub;
  String? _pairingUrl;
  String? _ip;
  int? _port;
  String? _error;
  bool _loading = true;
  bool _received = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final stream = await PairingService.instance.start(
        kind: widget.kind,
        theme: ThemeService.config.value,
      );
      _sub = stream.listen(_onResult, onError: (e) {
        if (mounted) setState(() => _error = '$e');
      });
      if (!mounted) return;
      setState(() {
        _pairingUrl = PairingService.instance.pairingUrl;
        _ip = PairingService.instance.localIp;
        _port = PairingService.instance.port;
        _loading = false;
        _error = _ip == null
            ? 'Impossible de détecter une adresse IP locale. Connecte la TV au Wi-Fi puis réessaie.'
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossible de démarrer le serveur de pairing : $e';
      });
    }
  }

  void _onResult(PairingResult result) {
    if (!mounted) return;
    setState(() => _received = true);
    // Laisse l'utilisateur voir la confirmation avant la propagation.
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      if (widget.onResult != null) {
        widget.onResult!(result);
      } else {
        Navigator.of(context).pop(result);
      }
    });
  }

  Future<void> _restart() async {
    setState(() {
      _loading = true;
      _error = null;
      _pairingUrl = null;
      _ip = null;
      _port = null;
    });
    await PairingService.instance.stop();
    await _start();
  }

  @override
  void dispose() {
    _sub?.cancel();
    PairingService.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final body = _buildBody(context);

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.kind == PairingKind.tmdb
              ? 'Configurer TMDB'
              : 'Ajouter une playlist',
        ),
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
                  center: const Alignment(0, -1.2),
                  radius: 1.4,
                  colors: [kAccentPrimary.withAlpha(25), cs.surface],
                )
              : null,
        ),
        child: SafeArea(child: body),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_received) return _buildReceivedState(context);
    if (_error != null) return _buildErrorState(context);
    return _buildQrState(context);
  }

  // ── États ───────────────────────────────────────────────────────────────

  Widget _buildReceivedState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [kAccentPrimary.withAlpha(80), Colors.transparent],
                ),
                border: Border.all(color: kAccentPrimary, width: 2),
                boxShadow: [
                  BoxShadow(color: kAccentPrimary.withAlpha(150), blurRadius: 30),
                ],
              ),
              child: Icon(Icons.check, color: kAccentPrimary, size: 56),
            ),
            const SizedBox(height: 20),
            Text(
              'Configuration reçue',
              style: GoogleFonts.vt323(
                color: kAccentPrimary,
                fontSize: 30,
                letterSpacing: 2.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Application en cours…',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, size: 64, color: kWarning),
            const SizedBox(height: 16),
            Text(
              'Pairing indisponible',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _restart,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
              style: FilledButton.styleFrom(
                backgroundColor: kAccentPrimary,
                foregroundColor: Colors.black,
              ),
            ),
            if (widget.onManualFallback != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: widget.onManualFallback,
                icon: const Icon(Icons.keyboard_alt_outlined),
                label: const Text('Saisir manuellement'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQrState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isTmdb = widget.kind == PairingKind.tmdb;

    return LayoutBuilder(
      builder: (context, constraints) {
        // QR adaptatif : 60% de la hauteur max ou 320 px, le plus petit.
        final qrSize = (constraints.maxHeight * 0.42).clamp(200.0, 320.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isTmdb
                    ? 'Colle ta clé TMDB depuis ton téléphone'
                    : 'Configure depuis ton téléphone',
                textAlign: TextAlign.center,
                style: GoogleFonts.vt323(
                  color: kAccentPrimary,
                  fontSize: 28,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Scanne le QR ci-dessous avec l\'appareil photo de ton téléphone',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: kAccentPrimary.withAlpha(100),
                        blurRadius: 30,
                        spreadRadius: 2,
                      ),
                    ],
                    border: Border.all(color: kAccentPrimary, width: 2),
                  ),
                  child: QrImageView(
                    data: _pairingUrl ?? '',
                    version: QrVersions.auto,
                    size: qrSize,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _WifiBanner(ip: _ip, port: _port),
              const SizedBox(height: 12),
              _StatusRow(),
              const SizedBox(height: 18),
              if (widget.onManualFallback != null)
                Center(
                  child: TextButton.icon(
                    onPressed: widget.onManualFallback,
                    icon: const Icon(Icons.keyboard_alt_outlined, size: 18),
                    label: const Text('Saisir manuellement à la télécommande'),
                    style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ── Sous-widgets privés ─────────────────────────────────────────────────────

class _WifiBanner extends StatelessWidget {
  final String? ip;
  final int? port;
  const _WifiBanner({this.ip, this.port});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kWarning.withAlpha(80), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi, color: kWarning, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Téléphone et TV doivent être sur le même Wi-Fi',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (ip != null && port != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Saisie manuelle : $ip:$port',
                    style: GoogleFonts.sourceCodePro(
                      color: cs.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatefulWidget {
  @override
  State<_StatusRow> createState() => _StatusRowState();
}

class _StatusRowState extends State<_StatusRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kAccentPrimary.withAlpha(
                  (255 * (0.3 + 0.7 * _ctrl.value)).round(),
                ),
                boxShadow: [
                  BoxShadow(
                    color: kAccentPrimary.withAlpha(
                      (180 * _ctrl.value).round(),
                    ),
                    blurRadius: 10,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'En attente du téléphone…',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
          ],
        );
      },
    );
  }
}
