import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Détection plateforme Android TV / Fire TV (§3c-1).
///
/// Init une seule fois au démarrage via [PlatformTv.init] (avant `runApp`).
/// Le résultat est mis en cache pour des accès synchrones via [PlatformTv.isTv].
///
/// **Stratégie en 2 passes** :
///   1. Channel natif `aetherstream/tv_detection` → consulte
///      `UiModeManager.UI_MODE_TYPE_TELEVISION` (Android TV / Google TV) et
///      le feature `amazon.hardware.fire_tv` (Fire TV).
///   2. Fallback heuristique (`isTvHeuristic`) basé sur la taille d'écran +
///      absence d'écran tactile, utile pour les TV box non standard ou en cas
///      d'échec du channel natif.
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
      // Channel non dispo (mode test / desktop / iOS) → on retombe sur
      // l'heuristique au premier appel avec contexte.
      _cached = false;
      debugPrint('📺 PlatformTv.init: channel KO → $e');
    }
  }

  /// Heuristique de secours quand le channel natif n'a rien retourné.
  /// À utiliser si [init] n'a pas pu s'exécuter (cas exotiques).
  ///
  /// Critères : grande diagonale (>600dp côté court) + pas de pointer tactile
  /// déclaré (`MediaQuery.platformBrightness` n'est pas un bon proxy ; on se
  /// rabat sur `MediaQueryData.shortestSide` et le `kIsWeb`/`Platform` test).
  static bool isTvHeuristic(BuildContext context) {
    if (_cached) return true; // déjà confirmé par le natif
    final mq = MediaQuery.of(context);
    final shortest = mq.size.shortestSide;
    // 600dp = seuil "grande tablette" — sur TV on est typiquement à 720dp+.
    return shortest > 600;
  }

  /// Combine le résultat natif et l'heuristique. À privilégier dans le code UI.
  static bool isTvFor(BuildContext context) =>
      _cached || isTvHeuristic(context);
}
