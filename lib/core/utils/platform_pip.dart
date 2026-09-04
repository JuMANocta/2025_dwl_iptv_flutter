import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// §pipPhone — Façade sur le canal MAISON `aetherstream/pip`.
///
/// ⚠️ **Pourquoi un canal maison et pas le PiP du paquet vendoré** (`floating`,
/// déjà en dépendance transitive) : celui-ci exige `_state.isFullScreen`, que
/// l'app ne met jamais à `true` — elle ne monte jamais `FullscreenVideoPlayer`,
/// ses contrôles sont 100 % custom et pensés D-pad. L'adopter pour avoir le PiP
/// aurait remplacé tout le chrome du lecteur pour un bénéfice sans rapport.
/// Voir `packages/aether_video/VENDORING.md` (réserve §engineFeatures) et
/// `.claude/decisions.md` (§pipPhone) pour le détail de cette décision.
///
/// Même idiome que `PlatformTv` : un `MethodChannel`, un cache, jamais levé
/// vers l'appelant — un appareil sans PiP doit se comporter comme s'il
/// n'existait pas, pas planter.
abstract final class PlatformPip {
  static const MethodChannel _channel = MethodChannel('aetherstream/pip');

  static bool _wired = false;
  static bool? _supportedCache;

  /// `true` tant que la fenêtre PiP est affichée. Le lecteur s'en sert pour
  /// masquer ses propres contrôles (rien n'y est cliquable en PiP).
  static final ValueNotifier<bool> active = ValueNotifier<bool>(false);

  /// Émis quand l'utilisateur a FERMÉ la fenêtre PiP (croix), par opposition à
  /// un simple retour au plein écran. `PlayerPage` s'en sert pour mettre la
  /// lecture en pause plutôt que de laisser un son sans image.
  static Stream<void> get dismissed => _dismissedCtrl.stream;
  static final StreamController<void> _dismissedCtrl =
      StreamController<void>.broadcast();

  /// Le SYSTÈME accepte-t-il le PiP sur cet appareil (feature + API ≥ 26) ?
  /// Mémorisé : c'est une propriété de l'appareil, elle ne change pas en vol.
  static Future<bool> isSupported() async {
    final cached = _supportedCache;
    if (cached != null) return cached;
    _ensureWired();
    try {
      final res = await _channel.invokeMethod<bool>('isSupported');
      return _supportedCache = res ?? false;
    } catch (e) {
      debugPrint('⚠️ PlatformPip.isSupported : $e');
      return _supportedCache = false;
    }
  }

  /// Entre en PiP MAINTENANT, avec le ratio [width]/[height] — déjà borné par
  /// `pipAspectFor` (§pipPhone) : ce canal ne re-vérifie rien, il fait
  /// confiance à l'appelant Dart. Rend `false` si le système refuse
  /// (appareil sans le feature, activité pas éligible) — jamais une exception.
  static Future<bool> enter({required int width, required int height}) async {
    _ensureWired();
    try {
      final res = await _channel
          .invokeMethod<bool>('enter', {'width': width, 'height': height});
      return res ?? false;
    } catch (e) {
      debugPrint('⚠️ PlatformPip.enter : $e');
      return false;
    }
  }

  /// Arme (ou désarme) le PiP automatique au geste Accueil. Appelé à chaque
  /// changement d'éligibilité (§1i verrou, erreur, TV) — jamais qu'une fois.
  static Future<void> setAutoEnter({
    required bool enabled,
    int width = 16,
    int height = 9,
  }) async {
    _ensureWired();
    try {
      await _channel.invokeMethod('setAutoEnter',
          {'enabled': enabled, 'width': width, 'height': height});
    } catch (e) {
      debugPrint('⚠️ PlatformPip.setAutoEnter : $e');
    }
  }

  static void _ensureWired() {
    if (_wired) return;
    _wired = true;
    _channel.setMethodCallHandler(_onNativeCall);
  }

  static Future<void> _onNativeCall(MethodCall call) async {
    if (call.method != 'onPipChanged') return;
    final args = (call.arguments as Map?) ?? const {};
    final bool isActive = args['active'] == true;
    active.value = isActive;
    if (!isActive && args['dismissed'] == true) {
      _dismissedCtrl.add(null);
    }
  }

  /// Tests uniquement : remet la façade à son état initial.
  @visibleForTesting
  static void resetForTest() {
    _wired = false;
    _supportedCache = null;
    active.value = false;
  }
}
