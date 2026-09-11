/// §bootActiveCap + §bootEscape — revue 2026-09-11, D3B-01 — Ce que le
/// démarrage fait quand il cesse d'attendre la liste principale.
///
/// **Le défaut corrigé.** La phase TÉLÉCHARGEMENT distinguait déjà les deux
/// sorties (bouton « Entrer sans attendre » → l'accueil ; plafond ou
/// immobilité → écran d'erreur), mais la phase ANALYSE, juste en dessous,
/// faisait `return null` dans les deux cas — et le décideur fait d'un `null`
/// l'écran « aucun compte configuré ». Un utilisateur qui appuyait sur le
/// bouton pendant une grosse analyse atterrissait donc sur un MENSONGE, et
/// relançait une seconde analyse du même catalogue en passant par Comptes.
///
/// La décision tient désormais dans une fonction pure, la MÊME pour les deux
/// phases : aucune d'elles ne peut plus mener à « aucun compte ». ⛔ §bootEscape
/// — jamais `return null` quand le compte existe.
library;

/// Issue d'une attente du démarrage.
enum BootWaitOutcome {
  /// La tâche est terminée : on continue le démarrage normalement (et une
  /// erreur éventuelle de la tâche est relevée par l'appelant).
  proceed,

  /// L'utilisateur a demandé à entrer : on ouvre l'accueil, le travail
  /// continue en arrière-plan (rien n'est annulé).
  enterNow,

  /// Personne n'a rien demandé, la tâche est immobile ou le plafond est
  /// atteint : écran d'erreur avec « Réessayer ».
  stalled,
}

/// [finished] : l'attente a vu la tâche se terminer (avec ou sans erreur).
/// [skipRequested] : l'utilisateur a appuyé sur « Entrer sans attendre ».
///
/// ⚠️ Une tâche TERMINÉE l'emporte sur la sortie manuelle : si elle a fini
/// pendant le dernier tour d'attente, on a tout ce qu'il faut pour démarrer
/// normalement — inutile d'entrer « à moitié ».
BootWaitOutcome decideBootWait({
  required bool finished,
  required bool skipRequested,
}) {
  if (finished) return BootWaitOutcome.proceed;
  if (skipRequested) return BootWaitOutcome.enterNow;
  return BootWaitOutcome.stalled;
}
