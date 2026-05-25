import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/platform_tv.dart';

/// Handler global de la touche "Retour" pour Android TV / Fire TV (§bug Back TV).
///
/// **Problème** : sur de nombreuses télécommandes Android TV / Fire TV, le
/// bouton *Back* est livré à Flutter comme un **key event** (`goBack`) au lieu
/// de déclencher le `popRoute` système. Aucun `Shortcuts`/`Focus` de l'app ne
/// mappe `goBack` → l'événement est ignoré → l'utilisateur reste coincé dans
/// le player, un modal ou un écran secondaire (impossible de revenir).
///
/// **Solution** : on enveloppe toute l'app dans un [Focus] de dernier recours
/// (placé au-dessus du `Navigator`). Les key events remontent l'arbre de focus
/// depuis le nœud actif jusqu'à la racine : ce handler ne se déclenche donc
/// **qu'en dernier**, si aucun descendant (contrôles player, dialog, etc.) n'a
/// déjà consommé la touche. Il appelle alors `maybePop()` sur le Navigator
/// racine.
///
/// **Hors TV** (`PlatformTv.isTv` false) : passthrough total. Le Back natif
/// mobile fonctionne déjà via `onBackPressed` → `popRoute`, on n'y touche pas.
///
/// Un petit anti-rebond (250 ms) évite un double-pop si l'OS finit aussi par
/// router le Back en `popRoute` quasi simultanément.
class TvBackHandler extends StatefulWidget {
  final Widget child;

  /// Navigator racine à piloter. En pratique l'état du `navigatorKey` global.
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
  static final _backKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.goBack,
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.browserBack,
  };

  DateTime _lastPop = DateTime.fromMillisecondsSinceEpoch(0);

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!_backKeys.contains(event.logicalKey)) return KeyEventResult.ignored;

    // Anti-rebond : ignore un second Back rapproché (évite double-pop si l'OS
    // route aussi l'événement en popRoute).
    final now = DateTime.now();
    if (now.difference(_lastPop) < const Duration(milliseconds: 250)) {
      return KeyEventResult.handled;
    }

    final nav = widget.navigatorKey.currentState;
    if (nav != null && nav.canPop()) {
      _lastPop = now;
      nav.maybePop();
      return KeyEventResult.handled;
    }
    // Rien à dépiler (on est à la racine) → on laisse l'OS gérer (sortie app).
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformTv.isTv) return widget.child;
    return Focus(
      // Dernier recours : ne prend jamais le focus lui-même, ne participe pas
      // à la traversée D-pad. Il observe seulement les events qui remontent.
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: widget.child,
    );
  }
}
