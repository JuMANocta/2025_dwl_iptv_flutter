import 'package:flutter/foundation.dart';

import '../../core/themes/theme_service.dart';
import '../../data/models/settings_patch.dart';
import '../../data/services/tmdb_api_service.dart';
import '../../data/services/tmdb_service.dart';
import '../../data/services/xmltv_service.dart';

/// §18 — Applique un [SettingsPatch] reçu via le pairing mobile→TV.
///
/// Chaque sous-application est best-effort et indépendante : une erreur sur un
/// bloc (ex: refresh XMLTV réseau) n'empêche pas les autres (thème, TMDB) d'être
/// appliqués. L'ordre est : thème → TMDB → XMLTV.
class SettingsApplyService {
  /// Applique le patch. Retourne `true` si au moins un changement a été appliqué.
  static Future<bool> apply(SettingsPatch patch) async {
    if (patch.isEmpty) return false;
    var changed = false;

    // ── Thème ──────────────────────────────────────────────────────────────
    if (patch.theme != null) {
      try {
        await ThemeService.save(patch.theme!);
        changed = true;
        debugPrint('✅ SettingsApply: thème mis à jour');
      } catch (e) {
        debugPrint('⚠️ SettingsApply: échec thème — $e');
      }
    }

    // ── Clé TMDB ───────────────────────────────────────────────────────────
    if (patch.tmdbToken != null) {
      try {
        if (patch.tmdbToken!.isEmpty) {
          await TmdbApiService.deleteApiKey();
        } else {
          await TmdbApiService.saveApiKey(patch.tmdbToken!);
        }
        TmdbService.resetInstance();
        changed = true;
        debugPrint('✅ SettingsApply: clé TMDB mise à jour');
      } catch (e) {
        debugPrint('⚠️ SettingsApply: échec TMDB — $e');
      }
    }

    // ── Rafraîchissement EPG XMLTV ───────────────────────────────────────────
    if (patch.refreshXmltv) {
      try {
        XmltvService.invalidate();
        await XmltvService.ensureLoaded();
        changed = true;
        debugPrint('✅ SettingsApply: EPG XMLTV rechargé');
      } catch (e) {
        debugPrint('⚠️ SettingsApply: échec XMLTV — $e');
      }
    }

    return changed;
  }
}
