import 'dart:async';

/// §episodeMeta / §autoNextEp — Une résolution « épisode suivant » à la fois
/// (revue 2026-09-11, D2A-13).
///
/// ⚠️ `PlayerPage.onRequestNext` FAIT AVANCER l'état de l'appelant
/// (`DetailsPage`) : deux appels = un épisode sauté. Le lecteur mettait bien
/// en cache le RÉSULTAT (`_pendingNext`), mais pas l'appel EN VOL : un ⏭
/// dans la dernière seconde puis la fin de lecture lançaient deux requêtes.
/// La première basculait sur N+1, la seconde posait N+2 et affichait l'encart
/// de fin, compte à rebours compris, sur l'épisode qui venait de démarrer.
///
/// Contrat :
/// - un appel pendant qu'un autre est en vol reçoit le MÊME `Future` (la
///   tâche ne tourne qu'une fois) ;
/// - une fois la tâche terminée (succès ou erreur), le mémo s'efface : un
///   appel suivant relance la tâche. Le résultat utile, lui, est gardé par
///   l'appelant (`_pendingNext`) — un `null` (fin de série, réseau) doit
///   pouvoir être redemandé, comme avant ;
/// - [reset] oublie l'appel en vol (bascule d'épisode) sans l'annuler.
///
/// Pur : aucune dépendance au lecteur, testé par `next_resolver_test.dart`.
class NextResolver<T> {
  Future<T>? _inFlight;

  /// Vrai tant qu'une résolution est en vol.
  bool get busy => _inFlight != null;

  /// Lance [task], ou rend celle déjà en vol.
  Future<T> run(Future<T> Function() task) {
    final Future<T>? pending = _inFlight;
    if (pending != null) return pending;
    final Future<T> started = Future<T>.sync(task);
    _inFlight = started;
    // ⚠️ Écouteur inscrit AVANT celui de l'appelant : il s'exécute d'abord,
    // le mémo est donc déjà effacé quand l'appelant reprend la main. Les
    // erreurs sont absorbées ICI seulement (l'appelant les reçoit par son
    // propre `await`) : sans ce `onError`, cet écouteur produirait une erreur
    // asynchrone non gérée.
    unawaited(started.then<void>((_) {}, onError: (Object _) {}).whenComplete(
      () {
        if (identical(_inFlight, started)) _inFlight = null;
      },
    ));
    return started;
  }

  /// Oublie l'appel en vol (sans l'annuler : son résultat ira à ceux qui
  /// l'attendent déjà, et à eux seuls).
  void reset() => _inFlight = null;
}
