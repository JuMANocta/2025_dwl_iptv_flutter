import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/settings/perf_config.dart';
import '../../core/settings/performance_settings_service.dart';
import '../../core/themes/colors.dart';
import '../../core/utils/platform_tv.dart';
import 'package:aetherStream/widgets/tv/tv_adaptive_modal.dart';

/// §perfAutoSuggest — Propose UNE FOIS le profil Performance au boot sur
/// box TV détectée (Fire Stick / Android TV), là où le hero fan et les
/// rangées chargées pèsent le plus.
///
/// Conditions d'affichage (toutes) :
///   - plateforme TV (`PlatformTv.isTv`) ;
///   - jamais proposé (flag SharedPreferences one-shot — « Non merci » le
///     pose aussi : on ne re-demande JAMAIS) ;
///   - config perf encore aux défauts (l'utilisateur qui a déjà réglé
///     Paramètres → Optimisation sait ce qu'il fait, on ne le dérange pas).
abstract final class PerfSuggestDialog {
  static const String _kFlag = 'perf_tv_suggest_done_v1';

  static Future<void> maybeShow(BuildContext context) async {
    if (!PlatformTv.isTv) return;
    if (PerformanceSettingsService.config.value != PerfConfig.defaults) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kFlag) ?? false) return;
    await prefs.setBool(_kFlag, true); // posé AVANT l'affichage (jamais 2×)

    if (!context.mounted) return;
    final apply = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.speed, size: 40, color: kAccentSecondary),
        title: const Text('Optimiser pour votre box TV ?'),
        content: const Text(
          'Une box TV a été détectée. Le profil Performance allège la page '
          'd\'accueil (bannière désactivée, rangées plus courtes) pour une '
          'navigation plus fluide sur les appareils modestes (Fire Stick…).\n\n'
          'Modifiable à tout moment dans Paramètres → Optimisation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Non merci'),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Appliquer Performance'),
          ),
        ],
      ),
    );

    if (apply == true) {
      await PerformanceSettingsService.save(PerfConfig.performance);
      debugPrint('🚀 §perfAutoSuggest : profil Performance appliqué (TV)');
    }
  }
}
