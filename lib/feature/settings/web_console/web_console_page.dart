import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/themes/colors.dart';
import '../../../core/utils/user_error.dart';
import '../../../core/themes/theme_service.dart';
import '../../../core/utils/platform_tv.dart';
import '../../../data/services/web_console_service.dart';
import '../../../l10n/app_localizations.dart';

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
///
/// §webConsoleOnly — Cet écran remplace l'ancien `PairingPage` sur **tous** les
/// points d'entrée QR. Deux paramètres rendent ce remplacement indolore :
/// [initialView] (le QR ouvre directement la bonne page côté navigateur) et
/// [embedded] (rendu sans Scaffold, pour l'onboarding TV).
class WebConsolePage extends StatefulWidget {
  /// Vue ouverte côté navigateur au scan : `accounts`, `tmdb`, `backup`…
  /// `null` = tableau de bord complet.
  final String? initialView;

  /// Rendu sans `Scaffold` ni AppBar, pour intégration dans un slide.
  final bool embedded;

  /// Notifie chaque action appliquée depuis le navigateur (onboarding TV).
  final void Function(WebConsoleEvent event)? onEvent;

  const WebConsolePage({
    super.key,
    this.initialView,
    this.embedded = false,
    this.onEvent,
  });

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
    WebConsoleService.instance.lastEvent.addListener(_onServiceEvent);
    _start();
  }

  void _onServiceEvent() {
    final e = WebConsoleService.instance.lastEvent.value;
    if (e != null && mounted) widget.onEvent?.call(e);
  }

  Future<void> _start() async {
    try {
      // §webConsolePersist — Si une session tourne déjà (on revient sur l'écran
      // pendant que la télécommande téléphone est active), on la réutilise au
      // lieu de la redémarrer : sinon un nouveau token invaliderait la session
      // ouverte sur le téléphone.
      if (WebConsoleService.instance.isRunning) {
        // §webConsoleOnly — Session réutilisée : on réoriente juste le QR vers
        // la vue demandée par l'écran appelant (token et serveur intacts).
        WebConsoleService.instance.setInitialView(widget.initialView);
      } else {
        await WebConsoleService.instance.start(
          theme: ThemeService.config.value,
          initialView: widget.initialView,
        );
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
        _error = 'Impossible de démarrer le serveur local : ${describeError(e)}';
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
    WebConsoleService.instance.lastEvent.removeListener(_onServiceEvent);
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final content = Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(widget.embedded ? 8 : 24),
        child: _starting
            ? const CircularProgressIndicator()
            : _error != null
                ? _buildError(cs)
                : _buildReady(cs),
      ),
    );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.webConsoleTitle), elevation: 0),
      body: content,
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

  /// §tvConsoleFit — Le QR encadré, seul (partagé entre les deux mises en page).
  Widget _buildQr({required bool compact}) => Container(
        padding: EdgeInsets.all(compact ? 8 : 12),
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
          size: compact ? 168 : 220,
          backgroundColor: Colors.white,
          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
          dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square, color: Colors.black),
        ),
      );

  Widget _buildReady(ColorScheme cs) {
    // §webConsoleOnly — En mode embarqué (slide d'onboarding), on compacte : le
    // slide porte déjà son propre titre et le bouton d'arrêt n'a pas de sens
    // avant même que la config soit faite.
    final compact = widget.embedded;

    // §tvConsoleFit — Sur TV (16/9, pas de défilement au doigt), la colonne
    // unique débordait : la note et « Arrêter le serveur » passaient SOUS le
    // bord de l'écran, et rien n'était focusable pour faire défiler. Deux
    // colonnes : le QR à gauche, tout le texte à droite — tout tient sans
    // défiler, et le bouton d'arrêt est visible et atteignable.
    if (!compact && PlatformTv.isTv) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildQr(compact: false),
            const SizedBox(width: 48),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ouvre cette adresse dans un navigateur\nsur un PC ou un téléphone du même réseau :',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  ..._buildAddressAndCode(cs, compact: false, centered: false),
                  const SizedBox(height: 20),
                  _buildNote(cs),
                  const SizedBox(height: 16),
                  _buildStopButton(),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!compact) ...[
          Text(
            'Ouvre cette adresse dans un navigateur\nsur un PC ou un téléphone du même réseau :',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
          ),
          const SizedBox(height: 20),
        ],
        _buildQr(compact: compact),
        SizedBox(height: compact ? 14 : 24),
        ..._buildAddressAndCode(cs, compact: compact, centered: true),
        if (!compact) ...[
          const SizedBox(height: 24),
          _buildNote(cs),
          const SizedBox(height: 16),
          _buildStopButton(),
        ],
      ],
    );
  }

  /// URL lisible + ligne « Code : … » + bouton copier.
  List<Widget> _buildAddressAndCode(ColorScheme cs,
      {required bool compact, required bool centered}) {
    return [
      SelectableText(
        'http://$_ip:$_port',
        textAlign: centered ? TextAlign.center : TextAlign.start,
        style: TextStyle(
          color: kAccentPrimary,
          fontSize: compact ? 17 : 20,
          fontWeight: FontWeight.bold,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      const SizedBox(height: 6),
      Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment:
            centered ? MainAxisAlignment.center : MainAxisAlignment.start,
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
    ];
  }

  Widget _buildNote(ColorScheme cs) => Container(
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
      );

  Widget _buildStopButton() => FilledButton.icon(
        onPressed: _stopServer,
        style: FilledButton.styleFrom(
          backgroundColor: kWarning,
          foregroundColor: Colors.black,
        ),
        icon: const Icon(Icons.power_settings_new),
        label: const Text('Arrêter le serveur'),
      );
}

