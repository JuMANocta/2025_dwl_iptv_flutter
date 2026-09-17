/// Lot 6b / §castLocal (2026-09-16) — Quand le lecteur ouvre-t-il la feuille
/// Cast de lui-même ?
///
/// **Pourquoi ce chemin existe.** La tuile « Diffuser » d'un téléchargement ne
/// peut pas connaître les pistes audio du fichier : seul le moteur les énumère
/// (§engineVendor patch 11). Une tuile qui lancerait la diffusion elle-même
/// enverrait donc un AC3 au téléviseur **sans la réserve sur le son** — image
/// sans son, exactement ce que §castSend avait mesuré. On ouvre plutôt le
/// lecteur sur le fichier avec `openCastOnStart`, et tout le chemin existant
/// s'applique : sonde d'éligibilité, réserve sur le son, consentement au
/// relais (§castRelay).
///
/// **Les trois pièges que cette règle tient** :
///   1. ⛔ jamais AVANT que les pistes soient énumérées — la réserve serait
///      aveugle, et c'est toute la raison d'être du détour ;
///   2. ⛔ jamais deux fois pour un même chargement — la feuille se rouvrirait
///      par-dessus elle-même à chaque reprise de lecture ;
///   3. ⛔ jamais indéfiniment : un flux qui n'énumère aucune piste (direct,
///      moteur qui tarde) ne doit pas rendre la feuille inatteignable. Passé
///      le délai de grâce, on ouvre quand même — `_checkCastable` sait se
///      rabattre sur le codec en cours de décodage.
///
/// Fonction pure : c'est elle qu'on teste.
///
/// [requested] : `PlayerPage.openCastOnStart`. [alreadyOpened] : la feuille a
/// déjà été ouverte pour CE chargement. [playing] : le moteur rend vraiment
/// (pas seulement « ouvert »). [audioTrackCount] : pistes énumérées, hors
/// entrées spéciales. [waited] : temps écoulé depuis le début de la lecture.
bool shouldOpenCastSheetOnStart({
  required bool requested,
  required bool alreadyOpened,
  required bool playing,
  required int audioTrackCount,
  required Duration waited,
  Duration grace = kCastAutostartGrace,
}) {
  if (!requested || alreadyOpened || !playing) return false;
  return audioTrackCount > 0 || waited >= grace;
}

/// Délai au-delà duquel on ouvre la feuille sans attendre l'énumération.
///
/// ⚠️ Assez long pour qu'un fichier local ait le temps d'énumérer (mesuré à
/// moins d'une seconde sur un MKV), assez court pour qu'un geste resté sans
/// effet ne passe pas pour une panne.
const Duration kCastAutostartGrace = Duration(seconds: 4);
