import 'package:flutter/material.dart';

import '../core/themes/colors.dart';
import '../core/utils/platform_tv.dart';
import '../data/models/device_caps.dart';
import '../data/models/m3u_entry.dart';
import '../data/services/device_caps_service.dart';
import '../l10n/l10n_ext.dart';
import 'tv/tv_adaptive_modal.dart';

/// §deviceCaps — La PORTE avant la lecture : une version que l'appareil ne
/// peut pas lire est REFUSÉE, avec la raison mesurée.
///
/// Décision de l'utilisateur (2026-09-06) : « si des versions ne sont pas
/// lisibles, refuser au client de lire le fichier, si 4K pas dispo sur le
/// téléviseur ». Le refus s'appuie sur la sonde (`DeviceCaps.verdictFor`),
/// jamais sur une supposition : sans mesure complète, la porte laisse passer.
///
/// ⚠️ Une seule porte pour les TROIS points de lancement (fiche, accueil,
/// feuille d'action) : trois règles auraient divergé, comme §detailsLive l'a
/// montré pour le rapprochement des versions.
abstract final class PlaybackGate {
  /// Vrai si la lecture peut partir. Sinon, un dialogue a expliqué pourquoi.
  static Future<bool> allow(BuildContext context, M3uEntry entry) async {
    final DeviceCaps? caps = DeviceCapsService.caps.value;
    if (caps == null) return true;
    // L'écran ne compte que sur téléviseur (cf. `DeviceCaps.verdictFor`).
    final PlayVerdict v = caps.verdictFor(entry.title.quality,
        requireDisplay: PlatformTv.isTv);
    if (v == PlayVerdict.ok || v == PlayVerdict.unknown) return true;

    final l10n = context.l10n;
    final String body = switch (v) {
      PlayVerdict.decoderTooSmall => l10n.refuse4kDecoder,
      PlayVerdict.displayTooSmall => l10n.refuse4kDisplay(
          caps.display?.longSide ?? 0, caps.display?.shortSide ?? 0),
      _ => '',
    };
    debugPrint('⛔ §deviceCaps : lecture refusee (${v.name}) pour ${entry.title.quality}');
    await showAppDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.block, size: 40, color: kError),
        title: Text(l10n.refuse4kTitle),
        content: Text(body),
        actions: [
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.refuseOk),
          ),
        ],
      ),
    );
    return false;
  }
}
