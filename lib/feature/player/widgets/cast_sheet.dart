import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/themes/colors.dart';
import '../../../core/utils/user_error.dart';
import '../../../data/services/cast_service.dart';
import '../../../widgets/tv/tv_adaptive_modal.dart';
import '../cast_policy.dart';
import '../../../core/utils/device_battery.dart';
import '../cast_relay_policy.dart';
import 'player_options_sheet.dart' show OptionsSheetBody, OptionSheetRow;

/// §castSend — Feuille « Diffuser sur… » : balayage du réseau, liste des
/// récepteurs, puis **contrôle d'éligibilité AVANT de proposer la diffusion**.
///
/// [checkStream] est rappelé au moment où l'utilisateur choisit un appareil,
/// jamais avant : la sonde coûte une requête réseau vers le fournisseur, on ne
/// la fait que si elle sert. Un flux non diffusable le dit ici, en clair
/// (§userError), au lieu d'un écran noir sur le téléviseur.
///
/// [onCast] n'est appelé qu'avec un flux déclaré diffusable ; la feuille se
/// ferme avant, c'est le lecteur qui prend le relais (panneau de diffusion).
/// [relayPlan] — §castRelay : quand AUCUNE piste audio n'est lisible par le
/// récepteur, le téléphone peut convertir le son. On ne le fait jamais sans
/// accord : la feuille montre d'abord ce que ça fait et ce que ça coûte.
Future<void> showCastSheet(
  BuildContext context, {
  required Future<CastEligibility> Function() checkStream,
  required Future<void> Function(CastDevice device) onCast,
  CastDevice? connected,
  Future<void> Function()? onStopCast,
  CastRelayPlan Function()? relayPlan,
  Future<void> Function(CastDevice device)? onRelay,
}) {
  return showAdaptiveActionSheet<void>(
    context: context,
    scrollable: false,
    builder: (_) => _CastSheetBody(
      checkStream: checkStream,
      onCast: onCast,
      connected: connected,
      onStopCast: onStopCast,
      relayPlan: relayPlan,
      onRelay: onRelay,
    ),
  );
}

enum _Phase { searching, list, checking, refused, warning, consent, error }

class _CastSheetBody extends StatefulWidget {
  const _CastSheetBody({
    required this.checkStream,
    required this.onCast,
    required this.connected,
    required this.onStopCast,
    this.relayPlan,
    this.onRelay,
  });

  final Future<CastEligibility> Function() checkStream;
  final Future<void> Function(CastDevice device) onCast;
  final CastDevice? connected;
  final Future<void> Function()? onStopCast;
  final CastRelayPlan Function()? relayPlan;
  final Future<void> Function(CastDevice device)? onRelay;

  @override
  State<_CastSheetBody> createState() => _CastSheetBodyState();
}

class _CastSheetBodyState extends State<_CastSheetBody> {
  _Phase _phase = _Phase.searching;
  List<CastDevice> _devices = const [];
  String _message = '';
  CastDevice? _pending;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() {
      _phase = _Phase.searching;
      _devices = const [];
    });
    try {
      final found = await CastService.discover();
      if (!mounted) return;
      setState(() {
        _devices = found;
        _phase = _Phase.list;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = describeError(e);
        _phase = _Phase.error;
      });
    }
  }

  /// §castBattery — Lue en entrant dans le consentement ; `null` = inconnue.
  DeviceBatteryState _battery = (percent: null, charging: null);

  Future<void> _readBattery() async {
    final b = await DeviceBattery.read();
    if (mounted) setState(() => _battery = b);
  }

  Future<void> _pick(CastDevice device) async {
    setState(() {
      _pending = device;
      _phase = _Phase.checking;
    });
    CastEligibility verdict;
    try {
      verdict = await widget.checkStream();
    } catch (e) {
      verdict = CastEligibility.no(describeError(e));
    }
    if (!mounted) return;
    if (!verdict.castable) {
      setState(() {
        _message = verdict.reason ?? "Ce flux n'est pas diffusable.";
        _phase = _Phase.refused;
      });
      return;
    }
    // Diffusable avec une réserve (son AC3/DTS…) : l'utilisateur tranche,
    // AVANT que le téléviseur n'affiche une image muette.
    if (verdict.warning != null) {
      setState(() {
        _message = verdict.warning!;
        // ⚠️ Un seul écran quand on peut convertir : le consentement
        // explique déjà la réserve. Sinon (pas de conversion possible),
        // l'avertissement simple suffit.
        _phase = _relayOffered ? _Phase.consent : _Phase.warning;
      });
      if (_relayOffered) unawaited(_readBattery());
      return;
    }
    await _go(device);
  }

  Future<void> _go(CastDevice device) async {
    Navigator.of(context).pop();
    await widget.onCast(device);
  }

  /// §castRelay — L'utilisateur a lu et accepté : on convertit.
  Future<void> _goRelay(CastDevice device) async {
    Navigator.of(context).pop();
    await widget.onRelay!(device);
  }

  /// La conversion n'est proposée QUE si elle changerait quelque chose.
  bool get _relayOffered =>
      widget.onRelay != null && (widget.relayPlan?.call().offered ?? false);

  /// §castRelay — L'écran qui explique AVANT de demander : ce que ça fait, ce
  /// que ça coûte, ce que ça ne fera pas. Dans cet ordre, parce que c'est
  /// l'ordre dans lequel on décide.
  List<Widget> _consentRows() {
    final device = _pending;
    final c = castRelayConsent(
      deviceName: device?.displayName ?? '',
      batteryPercent: _battery.percent,
      charging: _battery.charging,
    );
    final bool lowBattery = castBatteryWarning(
          percent: _battery.percent,
          charging: _battery.charging,
        ) !=
        null;
    return [
      _ConsentBlock(icon: Icons.graphic_eq_rounded, text: c.what),
      // ⚠️ Pas de listes titrées ni d'option muette (décision utilisateur) :
      // une note, deux boutons. Rouge si la batterie est déjà basse.
      _StatusLine(
        icon: lowBattery
            ? Icons.battery_alert_rounded
            : Icons.battery_std_rounded,
        color: lowBattery ? kError : kWarning,
        text: c.costs.first,
      ),
      // §castAwake — L'écran peut s'éteindre : c'est nouveau, et c'est ce
      // qui permet de poser le téléphone. Ton neutre, pas une alerte.
      _StatusLine(
        icon: Icons.screen_lock_portrait_rounded,
        text: c.awake,
      ),
      const SizedBox(height: 8),
      OptionSheetRow(
        icon: Icons.play_circle_fill_rounded,
        accent: kAccentPrimary,
        title: c.confirmLabel,
        subtitle: device == null ? null : 'Sur ${device.displayName}',
        onTap: () {
          if (device != null) _goRelay(device);
        },
      ),
      OptionSheetRow(
        icon: Icons.arrow_back_rounded,
        accent: kAccentSecondary,
        title: c.cancelLabel,
        subtitle: null,
        onTap: () => setState(() => _phase = _Phase.list),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bool consent = _phase == _Phase.consent;
    return OptionsSheetBody(
      // ⚠️ Aucun titre sur l'écran de consentement : « Diffuser sur… » n'y
      // veut rien dire (on ne choisit plus d'appareil, on répond à une
      // question). La phrase qui suit se suffit.
      title: consent ? '' : 'Diffuser sur…',
      icon: consent ? Icons.graphic_eq_rounded : Icons.cast_rounded,
      children: switch (_phase) {
        _Phase.searching => [
            _StatusLine(
              spinner: true,
              text: 'Recherche des appareils sur le réseau…',
            ),
          ],
        _Phase.checking => [
            _StatusLine(
              spinner: true,
              text: 'Vérification du flux pour '
                  '${_pending?.displayName ?? 'le téléviseur'}…',
            ),
          ],
        _Phase.refused => [
            _StatusLine(
              icon: Icons.block_rounded,
              color: kWarning,
              text: _message,
            ),
            const SizedBox(height: 6),
            OptionSheetRow(
              icon: Icons.arrow_back_rounded,
              accent: kAccentSecondary,
              title: 'Choisir un autre appareil',
              subtitle: null,
              onTap: () => setState(() => _phase = _Phase.list),
            ),
          ],
        _Phase.consent => _consentRows(),
        _Phase.warning => [
            _StatusLine(
              icon: Icons.volume_off_rounded,
              color: kWarning,
              text: _message,
            ),
            const SizedBox(height: 6),
            // §castRelay — EN PREMIER quand elle est possible : c'est la seule
            // option qui rend vraiment le son, les autres se contentent de
            // constater la panne.
            if (_relayOffered)
              OptionSheetRow(
                icon: Icons.graphic_eq_rounded,
                accent: kAccentPrimary,
                title: 'Convertir le son sur le téléphone',
                subtitle: 'Voir ce que ça implique avant de lancer',
                onTap: () => setState(() => _phase = _Phase.consent),
              ),
            OptionSheetRow(
              icon: Icons.cast_rounded,
              accent: kAccentSecondary,
              title: 'Diffuser quand même',
              subtitle: _pending == null
                  ? null
                  : 'Sur ${_pending!.displayName} — image sans son',
              onTap: () {
                final d = _pending;
                if (d != null) _go(d);
              },
            ),
            OptionSheetRow(
              icon: Icons.arrow_back_rounded,
              accent: kAccentSecondary,
              title: 'Choisir un autre appareil',
              subtitle: null,
              onTap: () => setState(() => _phase = _Phase.list),
            ),
          ],
        _Phase.error => [
            _StatusLine(
              icon: Icons.wifi_off_rounded,
              color: kError,
              text: _message,
            ),
            const SizedBox(height: 6),
            OptionSheetRow(
              icon: Icons.refresh_rounded,
              accent: kAccentPrimary,
              title: 'Réessayer',
              subtitle: null,
              onTap: _search,
            ),
          ],
        _Phase.list => [
            if (widget.connected != null && widget.onStopCast != null)
              OptionSheetRow(
                icon: Icons.cast_connected_rounded,
                accent: kAccentPrimary,
                title: 'Arrêter la diffusion',
                subtitle: 'En cours sur ${widget.connected!.displayName}',
                selected: true,
                onTap: () async {
                  Navigator.of(context).pop();
                  await widget.onStopCast!();
                },
              ),
            if (_devices.isEmpty)
              _StatusLine(
                icon: Icons.tv_off_rounded,
                color: cs.onSurfaceVariant,
                text: 'Aucun Chromecast trouvé. Le téléphone doit être sur le '
                    'même WiFi que le téléviseur, hors réseau invité.',
              )
            else
              for (final d in _devices)
                OptionSheetRow(
                  icon: d.id == widget.connected?.id
                      ? Icons.cast_connected_rounded
                      : Icons.tv_rounded,
                  accent: kAccentSecondary,
                  title: d.displayName,
                  subtitle: d.model ?? d.host,
                  selected: d.id == widget.connected?.id,
                  onTap: () => _pick(d),
                ),
            const SizedBox(height: 6),
            OptionSheetRow(
              icon: Icons.refresh_rounded,
              accent: kAccentTertiary,
              title: 'Rechercher à nouveau',
              subtitle: null,
              onTap: _search,
            ),
          ],
      },
    );
  }
}

/// §castRelay — Le paragraphe « ce que ça fait ».
class _ConsentBlock extends StatelessWidget {
  const _ConsentBlock({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: kAccentPrimary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: cs.onSurface, fontSize: 14, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.text,
    this.spinner = false,
    this.icon,
    this.color,
  });

  final String text;
  final bool spinner;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (spinner)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (icon != null)
            Icon(icon, color: color ?? cs.onSurfaceVariant, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: cs.onSurface, fontSize: 14, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
