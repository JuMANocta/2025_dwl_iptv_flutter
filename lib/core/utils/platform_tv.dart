import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Détection plateforme Android TV / Fire TV (§3c-1).
///
/// Init une seule fois au démarrage via [PlatformTv.init] (avant `runApp`).
/// Le résultat est mis en cache pour des accès synchrones via [PlatformTv.isTv].
///
/// Channel natif `aetherstream/tv_detection` → consulte
/// `UiModeManager.UI_MODE_TYPE_TELEVISION` (Android TV / Google TV) et le
/// feature `amazon.hardware.fire_tv` (Fire TV).
///
/// Revue 2026-09-11, D1B-20 — L'heuristique de secours par taille d'écran
/// (`isTvHeuristic`, `isTvFor`) n'avait aucun appelant, et contredisait la
/// règle : **[isTv] est la SEULE porte TV** (une tablette de plus de 600 dp
/// n'est pas un téléviseur). Retirée.
class PlatformTv {
  static const _channel = MethodChannel('aetherstream/tv_detection');

  static bool _cached = false;
  static bool _initialized = false;

  /// Vrai si l'app tourne sur Android TV ou Fire TV.
  /// Disponible synchrone à partir du moment où [init] est résolu.
  static bool get isTv => _cached;

  /// Initialise la détection (appelle le channel natif). À appeler dans `main()`.
  /// Idempotent — un seul appel natif par cycle d'app.
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final res = await _channel.invokeMethod<bool>('isTv');
      _cached = res ?? false;
      debugPrint('📺 PlatformTv.init: isTv=$_cached (native channel)');
    } catch (e) {
      // Channel non dispo (mode test / desktop / iOS) → pas un téléviseur.
      _cached = false;
      debugPrint('📺 PlatformTv.init: channel KO → $e');
    }
  }
}
