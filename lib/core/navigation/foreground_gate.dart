import 'package:flutter/widgets.dart';

/// Revue 2026-09-11, D3B-13 — « Seulement quand l'accueil est à l'écran ».
///
/// **Le défaut corrigé.** Trois dialogues partaient sur MINUTERIE, par-dessus
/// n'importe quel écran : la mise à jour (10 s après l'accueil, dialogue non
/// fermable par la barrière), l'alerte d'expiration d'abonnement (4 s) et
/// l'annonce du profil de performance (2,5 s). Un film lancé depuis
/// « Reprendre » dans les dix premières secondes voyait donc, sur TV, le
/// dialogue de mise à jour s'ouvrir par-dessus la vidéo et lui prendre le
/// focus.
///
/// Une action passée à [runOrDefer] s'exécute tout de suite si l'accueil est
/// la route visible, sinon elle ATTEND que l'accueil le redevienne (retour
/// du lecteur, d'une fiche, des réglages) et part après la frame suivante —
/// jamais pendant un build.
///
/// L'état « au premier plan » est celui de `HomePage.isForeground` (qui
/// délègue ici) : un seul endroit le tient, `didChangeDependencies` /
/// `didPushNext` / `didPopNext` de l'accueil.
///
/// **Pure** hormis la planification, injectable ([schedule]) — testée.
class ForegroundGate {
  ForegroundGate({void Function(VoidCallback run)? schedule})
      : _schedule = schedule ?? _afterNextFrame;

  final void Function(VoidCallback run) _schedule;
  bool _foreground = false;
  final List<VoidCallback> _pending = <VoidCallback>[];

  bool get foreground => _foreground;

  /// Nombre d'actions en attente (diagnostic, tests).
  int get pendingCount => _pending.length;

  set foreground(bool value) {
    if (_foreground == value) return;
    _foreground = value;
    if (value && _pending.isNotEmpty) _schedule(_flush);
  }

  /// Exécute [action] maintenant si l'accueil est à l'écran, sinon plus tard.
  void runOrDefer(VoidCallback action) {
    if (_foreground) {
      action();
    } else {
      _pending.add(action);
    }
  }

  void _flush() {
    // Une route a pu être re-poussée entre-temps : on attend encore.
    if (!_foreground) return;
    final List<VoidCallback> due = List<VoidCallback>.of(_pending);
    _pending.clear();
    for (final VoidCallback a in due) {
      try {
        a();
      } catch (e) {
        debugPrint('⚠️ D3B-13 — action différée en échec : $e');
      }
    }
  }

  static void _afterNextFrame(VoidCallback run) {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => run())
      ..ensureVisualUpdate();
  }
}

/// L'état « accueil au premier plan », partagé par `HomePage` et les
/// dialogues différés de `main.dart` / `MainNavigation`.
final ForegroundGate homeForeground = ForegroundGate();
