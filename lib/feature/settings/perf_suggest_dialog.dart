import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/settings/perf_config.dart';
import '../../core/settings/performance_settings_service.dart';
import '../../core/themes/colors.dart';
import '../../data/models/device_caps.dart';
import '../../data/services/device_caps_service.dart';
import '../../l10n/l10n_ext.dart';
import '../../widgets/tv/tv_adaptive_modal.dart';

/// §autoProfile (2026-09-06) — Le profil de performance est CHOISI PAR LA
/// SONDE au premier lancement, puis annoncé UNE fois.
///
/// Remplace §perfAutoSuggest (2026-07), qui devinait : « une box TV a été
/// détectée » → « appliquer Performance ? ». Une détection de plateforme n'est
/// pas une mesure : un Shield TV avec 3 Go et un décodeur AV1 matériel n'a
/// rien d'un Fire Stick, et un téléphone à 2 Go a besoin d'aide que la
/// question TV n'aurait jamais posée. La sonde (§deviceCaps) mesure la RAM,
/// les cœurs, l'écran et les décodeurs — et le profil en découle.
///
/// Conditions (toutes) :
///   - jamais fait (drapeau one-shot posé AVANT l'affichage : jamais deux fois) ;
///   - la config est encore aux défauts (l'utilisateur qui a réglé
///     Paramètres → Optimisation sait ce qu'il fait, on ne le dérange pas) ;
///   - la sonde a répondu (sans mesure, on ne change rien et on redemandera).
abstract final class PerfSuggestDialog {
  static const String _kFlag = 'perf_tv_suggest_done_v1';

  static Future<void> maybeShow(BuildContext context) async {
    if (PerformanceSettingsService.config.value != PerfConfig.defaults) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kFlag) ?? false) return;

    final DeviceCaps? caps = DeviceCapsService.caps.value ??
        await DeviceCapsService.probe();
    if (caps == null) return; // pas de mesure → pas de décision, on réessaiera

    final SuggestedProfile suggested = caps.suggestedProfile;
    await prefs.setBool(_kFlag, true); // posé AVANT l'affichage (jamais 2×)
    await DeviceCapsService.probeAndAutoProfileIfFirstRun();

    // Confort = les défauts : rien n'a changé, rien à annoncer.
    if (suggested == SuggestedProfile.confort) return;
    if (!context.mounted) return;

    final l10n = context.l10n;
    final String name = switch (suggested) {
      SuggestedProfile.confort => l10n.perfProfileConfort,
      SuggestedProfile.equilibre => l10n.perfProfileEquilibre,
      SuggestedProfile.performance => l10n.perfProfilePerformance,
    };
    final int ram = caps.memory?.totalMb ?? 0;
    await showAppDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.speed, size: 40, color: kAccentSecondary),
        title: Text(l10n.autoProfileTitle(name)),
        content: Text(l10n.autoProfileBody(name, ram, caps.cores)),
        actions: [
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.autoProfileOk),
          ),
        ],
      ),
    );
    debugPrint('\u{1F680} §autoProfile : ${suggested.name} annoncé');
  }
}
