import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../main.dart' show navigatorKey;

/// §dpadRestore — Mémoire de focus attachée aux routes.
///
/// **Le problème.** Le package `dpad` installe un filet de sécurité : dès que le
/// nœud focalisé meurt (pop de route, reconstruction de liste), il planifie une
/// restauration de focus. Quand le nœud mémorisé appartient à un autre scope,
/// ce filet retombe sur `DpadMarks.initialCandidate`, qui retourne **le premier
/// nœud marqué `entry` du scope**. Or chaque rangée de l'accueil marque sa 1re
/// carte comme `entry` (entrée verticale de région, usage parfaitement légitime)
/// → le repli atterrit systématiquement sur la 1re carte de la 1re rangée, et
/// l'auto-scroll de `DpadFocusable` ramène la liste tout en haut. L'utilisateur
/// voit « la page s'est rechargée » en revenant d'une fiche ou du player.
///
/// Flutter, lui, restaure correctement : la `FocusScopeNode` de la route révélée
/// retrouve son `focusedChild`. C'est une **course** entre cette restauration
/// native et le post-frame + microtask de `dpad`, d'où le caractère intermittent.
///
/// **La correction.** On mémorise nous-mêmes le nœud focalisé au moment où une
/// route en couvre une autre, et on le re-demande **après la fin de la
/// transition de sortie** (`TransitionRoute.completed` = route disposée), donc
/// après le repli de `dpad`. Un seul `requestFocus`, jamais de bagarre avec
/// l'utilisateur : une fois le bon nœud focalisé, le filet de `dpad` s'abstient
/// de lui-même (il ne se déclenche que si plus rien de réel n'a le focus).
///
/// Restaurer le **bon** nœud rend aussi l'`ensureVisible` de `DpadFocusable`
/// inopérant (l'item est déjà à l'écran) → plus de saut de scroll.
class FocusRouteMemory extends NavigatorObserver {
  /// Nœud focalisé au moment où chaque route a été recouverte.
  ///
  /// `WeakReference` : si le `FocusNode` disparaît entre-temps (liste
  /// reconstruite, écran démonté), on ne le maintient pas artificiellement en
  /// vie et la restauration se contente de ne rien faire.
  final Map<Route<dynamic>, WeakReference<FocusNode>> _memory =
      <Route<dynamic>, WeakReference<FocusNode>>{};

  @visibleForTesting
  int get trackedRouteCount => _memory.length;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null) return;
    final FocusNode? focused = FocusManager.instance.primaryFocus;
    if (focused == null || focused is FocusScopeNode) {
      _memory.remove(previousRoute);
      return;
    }
    _memory[previousRoute] = WeakReference<FocusNode>(focused);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _memory.remove(route);
    if (previousRoute == null) return;
    final FocusNode? node = _memory.remove(previousRoute)?.target;
    if (node == null) return;
    _afterExitTransition(route, () => _restore(node));
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _memory.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _memory.remove(oldRoute);
  }

  /// Exécute [action] une fois la route sortante réellement disposée.
  ///
  /// Tant que la route poppée est encore « courante », Flutter **ignore** les
  /// demandes de focus visant la route du dessous (`_shouldIgnoreFocusRequest`) :
  /// restaurer trop tôt ne ferait rien du tout.
  void _afterExitTransition(Route<dynamic> route, VoidCallback action) {
    if (route is TransitionRoute) {
      route.completed.whenComplete(action);
      return;
    }
    action();
  }

  void _restore(FocusNode node, {int attemptsLeft = 5}) {
    // Post-frame + microtask : même ordonnancement que le filet de `dpad`, mais
    // planifié plus tard → on repasse toujours derrière lui.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduleMicrotask(() {
        if (!_isUsable(node)) {
          // La route du dessous se reconstruit peut-être encore.
          if (attemptsLeft > 0) _restore(node, attemptsLeft: attemptsLeft - 1);
          return;
        }
        if (identical(FocusManager.instance.primaryFocus, node)) return;
        node.requestFocus();
      });
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// Un nœud n'est focusable que s'il est **rattaché** à l'arbre de focus : un
  /// `context` encore monté ne prouve rien (l'élément peut avoir été recyclé).
  static bool _isUsable(FocusNode node) {
    if (node.parent == null || !node.canRequestFocus) return false;
    final BuildContext? context = node.context;
    return context != null && context.mounted;
  }
}

/// §dpadRestore — Sauvegarde/restauration de focus **hors navigation**.
///
/// Certaines bascules ne poussent aucune route mais détruisent quand même les
/// focusables (mode recherche de l'accueil, changement d'onglet) : elles passent
/// par `ExcludeFocus`, ce qui tue le nœud focalisé et réveille exactement le même
/// repli de `dpad`. Ce helper leur offre le même filet que les routes.
class FocusSnapshot {
  FocusSnapshot._(this._node);

  final WeakReference<FocusNode>? _node;

  /// Capture le nœud actuellement focalisé (à appeler **avant** la bascule).
  factory FocusSnapshot.capture() {
    final FocusNode? focused = FocusManager.instance.primaryFocus;
    if (focused == null || focused is FocusScopeNode) {
      return FocusSnapshot._(null);
    }
    return FocusSnapshot._(WeakReference<FocusNode>(focused));
  }

  /// Re-demande le focus si le nœud a survécu à la bascule.
  void restore() {
    final FocusNode? node = _node?.target;
    if (node == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduleMicrotask(() {
        if (!FocusRouteMemory._isUsable(node)) return;
        if (identical(FocusManager.instance.primaryFocus, node)) return;
        node.requestFocus();
      });
    });
  }
}

/// §dpadBack — Chemin **unique** du bouton Retour.
///
/// Avant, quatre chemins indépendants coexistaient : la touche physique
/// (`maybePop` + debounce), le `PopScope` racine, la télécommande web
/// (`maybePop` brut, sans debounce) et le bouton retour du player (`pop()`
/// direct). Tout passe désormais par ici → une seule sémantique, un seul
/// debounce.
abstract final class AppBack {
  /// Les télécommandes TV répètent la touche Retour tant qu'elle est enfoncée :
  /// sans ce garde-fou, un appui un peu long dépile plusieurs écrans d'un coup.
  static const Duration _debounce = Duration(milliseconds: 350);

  static DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  @visibleForTesting
  static void resetDebounceForTest() =>
      _last = DateTime.fromMillisecondsSinceEpoch(0);

  static bool _throttled() {
    final DateTime now = DateTime.now();
    if (now.difference(_last) < _debounce) return true;
    _last = now;
    return false;
  }

  /// Touche Retour **physique**. Retourne `true` si l'appui est consommé.
  ///
  /// Quand il n'y a rien à dépiler, on retourne `false` volontairement : le
  /// système reprend la main (`popRoute` → `PopScope` racine → onglet Accueil
  /// puis double-back pour quitter). C'est ce qui permet aussi de quitter depuis
  /// l'écran de chargement, qui n'a aucun `PopScope`.
  static bool pop() {
    final NavigatorState? nav = navigatorKey.currentState;
    if (nav == null || !nav.canPop()) return false;
    if (_throttled()) return true;
    nav.maybePop();
    return true;
  }

  /// Retour déclenché depuis l'**interface** (bouton retour du player,
  /// télécommande web). Ne quitte jamais l'application : un bouton à l'écran ne
  /// doit pas pouvoir fermer l'app.
  static void popFromUi() {
    if (_throttled()) return;
    navigatorKey.currentState?.maybePop();
  }
}
