import 'package:flutter/material.dart';

import '../../core/themes/colors.dart';
import '../../core/utils/platform_tv.dart';
import '../../data/models/device_caps.dart';
import '../../data/services/device_caps_service.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_ext.dart';
import '../../widgets/tv/focusable_card.dart';

/// §deviceCaps (2026-09-06) — « Ce que ton appareil sait faire ».
///
/// La page ne fait qu'AFFICHER la mesure (`DeviceCapsService.caps`) : écran,
/// mémoire, décodeurs, et le verdict 4K qui en découle. Le bouton relance la
/// sonde. Aucune interprétation ici — elle vit dans `DeviceCaps`, testée.
class DeviceCapsPage extends StatefulWidget {
  const DeviceCapsPage({super.key});

  @override
  State<DeviceCapsPage> createState() => _DeviceCapsPageState();
}

class _DeviceCapsPageState extends State<DeviceCapsPage> {
  bool _measuring = false;

  Future<void> _measure() async {
    if (_measuring) return;
    setState(() => _measuring = true);
    await DeviceCapsService.probe();
    if (mounted) setState(() => _measuring = false);
  }

  @override
  void initState() {
    super.initState();
    // Jamais mesuré → on mesure à l'ouverture, sans attendre un appui.
    if (DeviceCapsService.caps.value == null) _measure();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.capsTitle)),
      body: ValueListenableBuilder<DeviceCaps?>(
        valueListenable: DeviceCapsService.caps,
        builder: (context, caps, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              Text(l10n.capsSub,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              const SizedBox(height: 4),
              Text(
                caps?.measuredAt == null
                    ? l10n.capsNever
                    : l10n.capsMeasuredAt(_shortDate(caps!.measuredAt!)),
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(height: 12),
              FocusableCard(
                  autofocus: true,
                  borderRadius: BorderRadius.circular(12),
                  onTap: _measuring ? null : _measure,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_measuring)
                          const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                        else
                          Icon(Icons.refresh, color: kAccentPrimary),
                        const SizedBox(width: 10),
                        Text(l10n.capsMeasure,
                            style: TextStyle(
                                color: kAccentPrimary,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
              ),
              if (caps != null) ...[
                const SizedBox(height: 20),
                _verdict4k(l10n, cs, caps),
                const SizedBox(height: 20),
                _section(l10n.capsDisplay, cs),
                _row(cs, '${caps.manufacturer} ${caps.model}', 'Android ${caps.sdk}'),
                if (caps.display != null)
                  _row(
                    cs,
                    l10n.capsDisplayValue(caps.display!.width,
                        caps.display!.height, caps.display!.refreshHz.round()),
                    caps.display!.hdr.isEmpty ? '—' : caps.display!.hdr.join(', '),
                  ),
                const SizedBox(height: 16),
                _section(l10n.capsMemory, cs),
                if (caps.memory != null)
                  _row(
                    cs,
                    l10n.capsMemoryValue(
                        caps.memory!.totalMb, caps.memory!.availMb),
                    caps.memory!.lowRamDevice ? l10n.capsLowRam : '${caps.cores} CPU',
                  ),
                const SizedBox(height: 16),
                _section(l10n.capsDecoders, cs),
                for (final e in caps.decoders.entries)
                  _decoderRow(l10n, cs, e.key, e.value),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _verdict4k(AppLocalizations l10n, ColorScheme cs, DeviceCaps caps) {
    final PlayVerdict v =
        caps.verdictFor('4K', requireDisplay: PlatformTv.isTv);
    final (String text, Color color) = switch (v) {
      PlayVerdict.ok => (l10n.capsYes, kSuccess),
      PlayVerdict.decoderTooSmall => (l10n.capsNoDecoder4k, kError),
      PlayVerdict.displayTooSmall => (l10n.capsNoDisplay4k, kWarning),
      PlayVerdict.unknown => (l10n.capsUnknown, cs.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Row(
        children: [
          Icon(Icons.four_k_outlined, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.capsVerdict4k,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                Text(text,
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, ColorScheme cs) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
      );

  Widget _row(ColorScheme cs, String left, String right) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
                child: Text(left,
                    style: TextStyle(fontSize: 13, color: cs.onSurface))),
            Text(right,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ],
        ),
      );

  Widget _decoderRow(
      AppLocalizations l10n, ColorScheme cs, String codec, DecoderCaps? d) {
    final String label = switch (codec) {
      'avc' => 'H.264',
      'hevc' => 'HEVC',
      'av1' => 'AV1',
      'vp9' => 'VP9',
      _ => codec,
    };
    if (d == null) return _row(cs, label, l10n.capsNoDecoder);
    final kind = d.hardware ? l10n.capsHardware : l10n.capsSoftware;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
              width: 56,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface))),
          Expanded(
            child: Text(
              l10n.capsDecoderValue(d.name, kind, d.maxWidth, d.maxHeight),
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            d.supports2160 ? '4K' : (d.supports1080 ? 'FHD' : '—'),
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: d.supports2160 ? kQuality4K : cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  static String _shortDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
