import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/themes/colors.dart';
import '../../../core/themes/theme_service.dart';
import '../../../data/services/web_console_service.dart';

/// §webConsole (Phase 1) — Écran "Console web".
///
/// Démarre [WebConsoleService] au mount (ou réutilise la session en cours),
/// affiche le QR + l'URL + le token à ouvrir depuis un navigateur du même
/// réseau. L'écran garde l'allumage (wakelock) pour laisser le temps de scanner.
///
/// §webConsolePersist — Le serveur **ne s'arrête PLUS au dispose** : il reste
/// actif en arrière-plan pour que la **télécommande téléphone** continue de
/// piloter la TV après qu'on a quitté cet écran. L'arrêt se fait explicitement
/// via le bouton "Arrêter le serveur" (ou le timeout de sécurité 30 min du
/// service).
class WebConsolePage extends StatefulWidget {
  const WebConsolePage({super.key});

  @override
  State<WebConsolePage> createState() => _WebConsolePageState();
}

class _WebConsolePageState extends State<WebConsolePage> {
  bool _starting = true;
  String? _error;
  String? _url;
  String? _ip;
  int? _port;
  String? _token;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _start();
  }

  Future<void> _start() async {
    try {
      // §webConsolePersist — Si une session tourne déjà (on revient sur l'écran
      // pendant que la télécommande téléphone est active), on la réutilise au
      // lieu de la redémarrer : sinon un nouveau token invaliderait la session
      // ouverte sur le téléphone.
      if (!WebConsoleService.instance.isRunning) {
        await WebConsoleService.instance.start(theme: ThemeService.config.value);
      }
      if (!mounted) return;
      setState(() {
        _starting = false;
        _url = WebConsoleService.instance.consoleUrl;
        _ip = WebConsoleService.instance.localIp;
        _port = WebConsoleService.instance.port;
        _token = WebConsoleService.instance.token;
        if (_url == null) {
          _error = 'Réseau local introuvable. Connecte la TV au Wi-Fi ou à l\'Ethernet.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = 'Impossible de démarrer le serveur local : $e';
      });
    }
  }

  /// §webConsolePersist — Arrêt explicite du serveur (l'utilisateur a fini
  /// d'utiliser la télécommande / la console). Ferme la page ensuite.
  Future<void> _stopServer() async {
    await WebConsoleService.instance.stop();
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    // §webConsolePersist — on relâche seulement le wakelock. Le serveur reste
    // actif en arrière-plan (télécommande téléphone) jusqu'à l'arrêt explicite
    // ou le timeout 30 min.
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Console web'), elevation: 0),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _starting
              ? const CircularProgressIndicator()
              : _error != null
                  ? _buildError(cs)
                  : _buildReady(cs),
        ),
      ),
    );
  }

  Widget _buildError(ColorScheme cs) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, size: 56, color: kWarning),
          const SizedBox(height: 16),
          Text(_error!, textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => setState(() { _starting = true; _error = null; _start(); }),
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer'),
          ),
        ],
      );

  Widget _buildReady(ColorScheme cs) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Ouvre cette adresse dans un navigateur\nsur un PC ou un téléphone du même réseau :',
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
        ),
        const SizedBox(height: 20),
        // QR
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kAccentPrimary, width: 2),
            boxShadow: [
              BoxShadow(color: kAccentPrimary.withAlpha(100), blurRadius: 30, spreadRadius: 2),
            ],
          ),
          child: QrImageView(
            data: _url ?? '',
            version: QrVersions.auto,
            size: 220,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
            dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square, color: Colors.black),
          ),
        ),
        const SizedBox(height: 24),
        // URL lisible
        SelectableText(
          'http://$_ip:$_port',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: kAccentPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Code : ', style: TextStyle(color: cs.onSurfaceVariant)),
            SelectableText(
              _token ?? '',
              style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2),
            ),
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: 'Copier l\'URL',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _url ?? ''));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Adresse copiée')),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.lock_outline, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Le serveur reste actif en arrière-plan tant que tu utilises la '
                  'télécommande, même après avoir quitté cet écran. Arrête-le ici '
                  'quand tu as fini (sinon fermeture auto après 30 min).',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _stopServer,
          style: FilledButton.styleFrom(
            backgroundColor: kWarning,
            foregroundColor: Colors.black,
          ),
          icon: const Icon(Icons.power_settings_new),
          label: const Text('Arrêter le serveur'),
        ),
      ],
    );
  }
}
