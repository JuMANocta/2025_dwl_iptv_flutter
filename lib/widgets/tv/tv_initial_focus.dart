import 'package:flutter/widgets.dart';

import '../../core/utils/platform_tv.dart';
import 'tv_adaptive_modal.dart' show hasFocusInside;

/// §dpadAlign — Focus initial d'une page sur TV.
///
/// Sans ça, une page fraîchement poussée n'a aucun focus visible : l'utilisateur
/// appuie sur une direction « dans le vide » avant que quoi que ce soit
/// s'allume. Le correctif traînait recopié à l'identique dans **18 endroits**
/// (`postFrame → FocusScope.nextFocus()`), avec deux défauts partout :
///
///   - un seul post-frame, donc raté quand le contenu arrive d'un `FutureBuilder` ;
///   - aucun garde-fou : le focus était volé même à un champ de saisie en
///     `autofocus` ou à une restauration en cours (§dpadRestore).
///
/// Usage : `class _MaPageState extends State<MaPage> with TvInitialFocus { … }`
/// — rien d'autre à écrire, `initState` est pris en charge.
mixin TvInitialFocus<T extends StatefulWidget> on State<T> {
  /// Passer à `false` pour une page qui gère elle-même son focus d'entrée.
  bool get tvInitialFocusEnabled => PlatformTv.isTv;

  @override
  void initState() {
    super.initState();
    if (!tvInitialFocusEnabled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Quelque chose de CETTE page a déjà le focus (champ autofocus,
        // restauration de route) → on ne le lui prend pas. Le test doit être
        // limité au sous-arbre : un nœud encore vivant d'un écran en train de
        // se fermer ne doit pas nous empêcher de prendre le focus.
        if (hasFocusInside(context)) return;
        FocusScope.of(context).nextFocus();
      });
    });
  }
}
