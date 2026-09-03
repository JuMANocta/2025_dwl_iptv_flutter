import 'dart:async';

import 'package:flutter/widgets.dart';

import '../diagnostics/log_buffer.dart';
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

  /// Route actuellement au sommet de la pile.
  ///
  /// ⚠️ Indispensable : certains flux **dépilent puis empilent dans la même
  /// frame** (le panneau d'options du player se ferme pour ouvrir le sélecteur
  /// de pistes). La restauration de focus n'a lieu qu'à la fin de l'animation de
  /// sortie — soit bien après. Sans ce contrôle, on rendrait le focus à une
  /// route désormais recouverte, en le volant à l'écran que l'utilisateur
  /// regarde.
  Route<dynamic>? _top;

  @visibleForTesting
  int get trackedRouteCount => _memory.length;

  /// Nœud actuellement mémorisé pour [route] — le CONTRAT de cette classe.
  ///
  /// ⚠️ Exposé pour les tests parce que le focus final ne suffit pas à juger :
  /// dans un `testWidgets` nu, la `FocusScopeNode` de la route révélée restaure
  /// déjà son `focusedChild` toute seule, donc un test qui n'observe que
  /// `primaryFocus` passe **même avec la mémoire empoisonnée**. C'est le repli
  /// de `dpad` — absent en test — qui rend la panne visible sur l'appareil. La
  /// seule chose vérifiable ici, c'est ce qu'on a retenu.
  @visibleForTesting
  FocusNode? memorizedFor(Route<dynamic> route) => _memory[route]?.target;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _top = route;
    if (previousRoute == null) return;
    final FocusNode? focused = FocusManager.instance.primaryFocus;
    if (focused == null || focused is FocusScopeNode) {
      // ⚠️ On n'EFFACE PAS une mémoire déjà en place : « je ne sais pas quoi
      // mémoriser » ne vaut pas « il n'y a rien à restaurer ». La mémoire est
      // consommée au pop, donc une entrée qui survit ici est forcément celle de
      // la route qu'on est en train de recouvrir.
      DiagnosticLog.trace('🧭 push ${_name(route)} — rien à mémoriser');
      return;
    }
    // §tvExitPage — Le nœud doit appartenir à la route qu'on recouvre.
    //
    // ⚠️ **La faille mesurée le 2026-08-30.** `showTvActionSheet.playVersion`
    // fait `Navigator.pop(feuille)` PUIS `Navigator.push(player)` dans la même
    // frame. Au moment du push, la feuille anime encore sa sortie et détient
    // toujours le focus : `primaryFocus` vaut « Regarder · FHD », un nœud de la
    // FEUILLE. On l'enregistrait comme « ce qu'il faudra restaurer sur
    // l'accueil » — écrasant « LCP », la vraie carte d'origine. À la sortie du
    // player ce nœud est mort, la restauration ne fait rien, et c'est le repli
    // de `dpad` (1er nœud `entry` du scope = 1re carte de la 1re rangée) qui
    // décide où atterrir. D'où « on revient ailleurs dans la liste ».
    if (!_belongsTo(focused, previousRoute)) {
      DiagnosticLog.trace('🧭 push ${_name(route)} — focus IGNORÉ (appartient à '
          'une autre route) : ${DiagnosticLog.describeFocusNode(focused)}');
      return;
    }
    _memory[previousRoute] = WeakReference<FocusNode>(focused);
    DiagnosticLog.trace('🧭 push ${_name(route)} — mémorise pour '
        '${_name(previousRoute)} : ${DiagnosticLog.describeFocusNode(focused)}');
  }

  /// [node] vit-il DANS le sous-arbre de [route] ?
  ///
  /// La réponse est exacte, sans heuristique : `ModalRoute.subtreeContext` est
  /// l'élément racine du contenu de la route, il suffit de le chercher parmi les
  /// ancêtres du nœud focalisé. (Le `FocusScopeNode` de la route serait plus
  /// direct, mais il vit dans un `_ModalScopeState` privé.)
  ///
  /// Une route sans sous-arbre identifiable → on garde le comportement
  /// historique (on fait confiance au focus courant) plutôt que de rejeter :
  /// mieux vaut une mémoire imparfaite que pas de mémoire du tout.
  static bool _belongsTo(FocusNode node, Route<dynamic> route) {
    if (route is! ModalRoute) return true;
    final BuildContext? subtree = route.subtreeContext;
    if (subtree == null || !subtree.mounted) return true;
    final BuildContext? ctx = node.context;
    if (ctx == null || !ctx.mounted) return false;
    if (identical(ctx, subtree)) return true;
    bool found = false;
    ctx.visitAncestorElements((Element el) {
      if (identical(el, subtree)) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _memory.remove(route);
    if (identical(_top, route)) _top = previousRoute;
    if (previousRoute == null) return;
    final FocusNode? node = _memory.remove(previousRoute)?.target;
    if (node == null) {
      DiagnosticLog.trace(
          '🧭 pop ${_name(route)} → ${_name(previousRoute)} : aucun nœud mémorisé '
          '(le repli de dpad va décider)');
      return;
    }
    _afterExitTransition(route, () {
      // Une autre route a été empilée entre-temps : c'est elle qui doit garder
      // le focus, pas celle qu'on vient de révéler.
      if (!identical(_top, previousRoute)) {
        // §tvExitPage — On REND le nœud à la mémoire de la route recouverte.
        //
        // Ce chemin est exactement le motif « feuille fermée → écran ouvert
        // dans la même frame » : la restauration n'a pas lieu d'être maintenant,
        // mais elle le sera à la sortie de la route qui vient d'être empilée.
        // Jeter le nœud ici, c'est perdre la SEULE trace de la carte d'origine —
        // et laisser le repli de `dpad` choisir à notre place.
        // ⚠️ `isActive` : la route du dessous peut elle-même être en train de
        // partir (on ferme le sélecteur de pistes ET le player d'affilée) —
        // réarmer une route morte ne laisserait qu'une entrée orpheline dans la
        // table, que plus aucun `didPop` ne viendrait retirer.
        if (previousRoute.isActive && _memory[previousRoute]?.target == null) {
          _memory[previousRoute] = WeakReference<FocusNode>(node);
        }
        DiagnosticLog.trace('🧭 restauration DIFFÉRÉE (une route a été empilée '
            'depuis) — nœud rendu à ${_name(previousRoute)}');
        return;
      }
      DiagnosticLog.trace('🧭 restaure sur ${_name(previousRoute)} : '
          '${DiagnosticLog.describeFocusNode(node)}');
      _restore(node);
    });
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _memory.remove(route);
    if (identical(_top, route)) _top = previousRoute;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _memory.remove(oldRoute);
    if (oldRoute != null && identical(_top, oldRoute)) _top = newRoute;
  }

  /// Nom court d'une route pour les traces (§focusTrace).
  static String _name(Route<dynamic>? route) {
    if (route == null) return 'null';
    final String? n = route.settings.name;
    if (n != null && n.isNotEmpty) return n;
    return '${route.runtimeType}#${identityHashCode(route).toRadixString(16)}';
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
