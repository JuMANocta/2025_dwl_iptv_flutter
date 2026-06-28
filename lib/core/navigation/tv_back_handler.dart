import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/platform_tv.dart';

/// Handler global de la touche "Retour" pour Android TV / Fire TV (§bug Back TV).
///
/// **Problème** : sur de nombreuses télécommandes Android TV / Fire TV, le
/// bouton *Back* est livré à Flutter comme un **key event** au lieu de
/// déclencher le `popRoute` système. Selon les modèles, ce key event n'est pas
/// celui attendu (`goBack`) et aucun `Shortcuts`/`Focus` de l'app ne le mappe →
/// l'utilisateur reste coincé dans le player / un modal / un écran secondaire.
///
/// **Solution** : on enregistre un handler **global** via
/// [HardwareKeyboard.instance.addHandler], qui reçoit TOUS les key events
/// indépendamment de l'arbre de focus (contrairement à un `Focus.onKeyEvent`
/// qui dépend du nœud focusé et avait échoué). Sur une touche "retour" reconnue,
/// on appelle `maybePop()` sur le Navigator racine.
///
/// **Diagnostic** : en debug, chaque `KeyDownEvent` est loggé sur TV
/// (`🔑 KeyDown: …`). Ça permet de lire dans logcat le code exact émis par le
/// bouton Back de la télécommande testée et d'ajuster [_backKeys] au besoin.
///
/// **Hors TV** : aucun handler n'est posé → le Back natif mobile (popRoute)
/// reste seul maître.
class TvBackHandler extends StatefulWidget {
  final Widget child;

  /// Navigator racine à piloter (l'état du `navigatorKey` global).
  final GlobalKey<NavigatorState> navigatorKey;

  const TvBackHandler({
    super.key,
    required this.child,
    required this.navigatorKey,
  });

  @override
  State<TvBackHandler> createState() => _TvBackHandlerState();
}

class _TvBackHandlerState extends State<TvBackHandler> {
  /// Touches considérées comme "Retour" sur les télécommandes TV.
  static final _backKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.goBack,
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.browserBack,
    LogicalKeyboardKey.gameButtonB,
  };

  DateTime _lastPop = DateTime.fromMillisecondsSinceEpoch(0);
  bool _attached = false;

  @override
  void initState() {
    super.initState();
    if (PlatformTv.isTv) {
      HardwareKeyboard.instance.addHandler(_onKey);
      _attached = true;
    }
  }

  @override
  void dispose() {
    if (_attached) HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    // §diag — log de calibration du bouton Back (lisible dans logcat).
    if (kDebugMode) {
      debugPrint('🔑 KeyDown: ${event.logicalKey.debugName} '
          '(id=0x${event.logicalKey.keyId.toRadixString(16)})');
    }

    if (!_backKeys.contains(event.logicalKey)) return false;

    // Anti-rebond : ignore un second Back rapproché (évite un double-pop si
    // l'OS route aussi l'événement en popRoute quasi simultanément).
    final now = DateTime.now();
    if (now.difference(_lastPop) < const Duration(milliseconds: 300)) {
      return true;
    }

    final nav = widget.navigatorKey.currentState;
    if (nav != null && nav.canPop()) {
      _lastPop = now;
      nav.maybePop();
      return true; // consommé
    }
    // Rien à dépiler (racine) → laisse l'OS gérer (sortie d'app).
    return false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
