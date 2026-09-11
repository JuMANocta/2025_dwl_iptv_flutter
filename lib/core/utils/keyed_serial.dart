import 'dart:async';

/// revue 2026-09-11, D1A-02 + D1A-04 — Une file PAR CLÉ : deux travaux de la
/// même clé ne se chevauchent jamais, deux clés différentes restent libres.
///
/// **Pourquoi pas un simple « futur en vol partagé »** (comme
/// `PlaylistService._inFlight` ou `ParsedPlaylistService._singleFlight`) :
/// ici le second appelant ne veut pas le RÉSULTAT du premier, il veut faire
/// SON travail — mais après lui. Un rechargement forcé qui arrive pendant un
/// contrôle de fraîcheur doit réellement retélécharger ; une seconde
/// sauvegarde du cache doit réellement écrire la version la plus récente. Ce
/// qu'on interdit, c'est seulement le chevauchement : deux flux dans le même
/// `.part`, deux téléchargements concurrents vers un panel qui n'accepte
/// qu'une connexion (§hostGate).
///
/// Ordre d'arrivée respecté (FIFO). Une erreur d'un travail remonte à SON
/// appelant et ne bloque jamais la file : le suivant démarre quand même.
class KeyedSerial {
  final Map<String, Future<void>> _tails = <String, Future<void>>{};

  /// Vrai si un travail de cette clé est en cours ou en attente.
  bool isBusy(String key) => _tails.containsKey(key);

  /// Exécute [body] quand tous les travaux déjà mis en file pour [key] sont
  /// terminés (avec ou sans succès).
  Future<T> run<T>(String key, Future<T> Function() body) {
    final Future<void> previous = _tails[key] ?? Future<void>.value();
    // La queue de file est un Completer qui se TERMINE toujours sans erreur :
    // le travail suivant l'attend sans jamais hériter d'une exception.
    final Completer<void> done = Completer<void>();
    final Future<void> tail = done.future;
    _tails[key] = tail;
    return previous.then<T>((_) => body()).whenComplete(() {
      // ⚠️ Retirer l'entrée AVANT de libérer le suivant, et seulement si
      // personne ne s'est mis en file derrière : sinon on effacerait la queue
      // d'un travail encore en attente.
      if (identical(_tails[key], tail)) _tails.remove(key);
      done.complete();
    });
  }
}
