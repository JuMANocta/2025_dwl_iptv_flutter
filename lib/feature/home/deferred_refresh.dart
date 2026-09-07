import 'package:flutter/foundation.dart';

/// §pageTick (2026-09-07) — Rafraîchissement DIFFÉRÉ tant qu'on ne voit pas.
///
/// Depuis §tabPageKeep, les trois pages de l'accueil sont des instances
/// stables : un `setState` de la HomePage ne les reconstruit plus. Tout signal
/// de contenu (favoris, reprises, catégories apprises, réglages) doit donc
/// leur parvenir DIRECTEMENT — et seule la page VISIBLE doit y répondre. Une
/// page cachée note qu'elle est périmée et se reconstruit une seule fois,
/// quand elle revient à l'écran. Rien ne bouge pour une page que personne ne
/// regarde : c'est ce qui garde la bascule d'onglet à zéro reconstruction.
///
/// Pur, sans widget : le `State` ne fait que brancher `apply` sur `setState`.
class DeferredRefresh {
  DeferredRefresh({required this.apply, bool visible = true})
      : _visible = visible;

  /// Ce qu'on fait quand il faut vraiment reconstruire.
  final VoidCallback apply;

  bool _visible;
  bool _stale = false;

  /// Vrai si un signal est arrivé pendant que la page était cachée et n'a pas
  /// encore été appliqué.
  bool get stale => _stale;

  bool get visible => _visible;

  /// Un signal de contenu : appliqué tout de suite si la page est visible,
  /// sinon retenu (plusieurs signaux cachés = UNE application plus tard).
  void signal() {
    if (_visible) {
      apply();
    } else {
      _stale = true;
    }
  }

  /// La page entre ou sort de l'écran. En entrant, on rattrape ce qui a été
  /// retenu — une fois. En sortant, rien.
  set visible(bool value) {
    if (value == _visible) return;
    _visible = value;
    if (value && _stale) {
      _stale = false;
      apply();
    }
  }
}
