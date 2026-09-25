/// §notifAudit P5 — Un lecteur est-il ouvert ?
///
/// Une notification de téléchargement touchée pendant un film ne doit pas le
/// couper pour ouvrir l'onglet Téléchargements (`shouldOpenDownloads`).
/// Compteur plutôt que booléen : un lecteur qui s'ouvre pendant que l'ancien
/// se ferme (transition de route) ne doit pas faire croire à « aucun ».
///
/// Posé par `PlayerPage` (`initState` / `dispose`) ; volontairement sans
/// dépendance : le pont des notifications le lit sans tirer le lecteur.
abstract final class PlayerPresence {
  static int _open = 0;

  static bool get isOpen => _open > 0;

  static void enter() => _open++;

  static void leave() {
    if (_open > 0) _open--;
  }
}
