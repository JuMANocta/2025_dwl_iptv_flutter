/// §1e / §castSend / §castResume — Décisions PURES de la reprise écrite par le
/// LECTEUR (revue 2026-09-11, D2A-01 + D2L-01).
///
/// Deux questions, tranchées ici plutôt qu'au fil de `_saveProgress` parce que
/// c'est là que les deux défauts se cachaient :
///
/// 1. **Quelle position écrire ?** Pendant une diffusion de CE contenu, la
///    vérité est celle du téléviseur ; sinon celle du lecteur local.
///    ⚠️ D2A-01 : l'ancien calcul lisait `_cast!.position` dès qu'un relais
///    existait (`_relay != null`), SANS vérifier qu'une diffusion existait.
///    Or le relais publie son état 6 à 60 s AVANT que le récepteur n'accepte
///    quoi que ce soit (écran « Préparation ») : `_cast` est alors nul, et le
///    « Null check » levé interrompait `dispose()` — moteur jamais libéré,
///    téléphone bloqué en paysage, observateur inscrit sur une page morte.
///
/// 2. **Faut-il écrire tout court ?** ⚠️ D2L-01 : quand la diffusion de CE
///    contenu se termine côté téléviseur (fin du film, arrêt depuis la télé,
///    Wi-Fi perdu), `CastService` a DÉJÀ écrit la bonne reprise — ou l'a
///    effacée en fin de film. Le lecteur local, lui, est resté en pause là où
///    la diffusion avait commencé : sa position est PÉRIMÉE. L'écrire 10 s
///    plus tard faisait reculer « Reprendre », et ressortir un film vu en
///    entier. On se tait donc jusqu'à ce que le lecteur local rejoue.
///
/// Rien ici ne touche au moteur ni au service : c'est ce qui les rend
/// testables sous `flutter test`.
library;

/// Position et durée à enregistrer pour le contenu courant.
typedef PlayerResumeProgress = ({Duration position, Duration duration});

/// Position/durée de reprise, selon qui lit VRAIMENT le contenu.
///
/// [castsThisMedia] — le téléviseur lit-il CE contenu ? (critère de la page,
/// `_castsThisMedia`).
/// [castPosition] / [castDuration] — ce que rapporte le récepteur ; `null`
/// quand AUCUNE diffusion n'existe (c'est le cas de l'écran « Préparation »
/// d'un relais : conversion lancée, récepteur pas encore sollicité).
/// [relayOffset] — §castResume : le flux converti repart à zéro, ce décalage
/// lui rend sa place dans le film. `null` = pas de relais.
///
/// ⚠️ La durée d'un flux RELAYÉ n'est pas celle du film (le manifeste grandit
/// encore) : on garde alors la durée LOCALE, sinon la règle des 95 % de
/// `WatchProgressService` effacerait la reprise pendant qu'on regarde.
PlayerResumeProgress resumeProgressFor({
  required bool castsThisMedia,
  required Duration? castPosition,
  required Duration? castDuration,
  required Duration? relayOffset,
  required Duration localPosition,
  required Duration localDuration,
}) {
  // Sans position du récepteur, rien ne vient de lui — quel que soit l'état
  // du relais (D2A-01 : c'est exactement la fenêtre « Préparation »).
  if (!castsThisMedia || castPosition == null) {
    return (position: localPosition, duration: localDuration);
  }
  if (relayOffset != null) {
    return (position: relayOffset + castPosition, duration: localDuration);
  }
  return (position: castPosition, duration: castDuration ?? localDuration);
}

/// La page doit-elle écrire une reprise maintenant ?
///
/// - [finished] (§endOfMovie) ou [skip] (direct, replay) → jamais ;
/// - le téléviseur lit CE contenu → oui : la position écrite est la sienne ;
/// - [handedBack] — la diffusion de CE contenu vient de s'arrêter hors de la
///   page, et le lecteur local n'a pas rejoué depuis → non : sa position est
///   celle du lancement de la diffusion, et `CastService` a déjà écrit la
///   vraie (D2L-01) ;
/// - sinon, lecture locale ordinaire → oui.
bool shouldWriteLocalProgress({
  required bool castsThisMedia,
  required bool handedBack,
  required bool finished,
  required bool skip,
}) {
  if (finished || skip) return false;
  if (castsThisMedia) return true;
  return !handedBack;
}

/// Nouvel état du drapeau « rendu par le téléviseur » après un changement de
/// `CastService.state`.
///
/// Il se LÈVE quand le téléviseur cesse de lire CE contenu ([wasCastingThis]
/// vrai, [castsThisNow] faux) : fin de lecture, arrêt depuis la télé,
/// connexion perdue, ou autre contenu envoyé à sa place. Il ne se BAISSE
/// jamais ici : c'est la reprise de la lecture LOCALE (ou « Reprendre sur le
/// téléphone », qui repositionne le lecteur) qui rend sa position fiable.
bool castHandedBackAfter({
  required bool previous,
  required bool wasCastingThis,
  required bool castsThisNow,
}) =>
    previous || (wasCastingThis && !castsThisNow);
