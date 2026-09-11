/// §dlRangeCheck (revue 2026-09-11, D3A-01) — Que faire de la réponse du GET
/// de téléchargement, AVANT d'en écrire le moindre octet.
///
/// **Le défaut payé** : le GET de flux héritait de `validateStatus: s < 500`
/// (`NetworkUtils.buildBaseDio`) et son statut n'était JAMAIS lu. Un
/// `403 Too many connections` — cas documenté par §dlQueue et §hostGate, et
/// déclenché par une simple lecture sur le même abonnement — voyait donc son
/// corps d'erreur AJOUTÉ au partiel ; la barre passait à 100 %, le partiel était
/// renommé en film et la tâche finissait « Terminé ». Même issue avec un
/// serveur qui ignore `Range` : le fichier COMPLET était ajouté derrière les
/// octets déjà reçus.
///
/// Fonction pure : c'est ce qui la rend testable, le service traîne un Dio, des
/// fichiers et un singleton.
library;

/// Ce que le téléchargeur doit faire de la réponse reçue.
enum RangeVerdict {
  /// Écrire le corps à la suite du partiel (reprise alignée, ou partiel vide).
  append,

  /// Le serveur a ignoré `Range` et renvoie le fichier ENTIER : repartir de
  /// zéro (tronquer le partiel), sinon le fichier serait dupliqué.
  restartFromZero,

  /// `416` sur un partiel non vide : il n'y a plus rien à recevoir.
  alreadyComplete,

  /// Réponse inutilisable (refus, redirection non suivie, reprise décalée) :
  /// ne RIEN écrire, la tâche échoue et le partiel reste intact.
  reject,
}

/// Décide du sort de la réponse.
///
/// [resumedBytes] = taille du partiel au moment de la requête (l'offset
/// demandé dans `Range: bytes=<resumedBytes>-`).
/// [contentRangeStart] = premier octet annoncé par `Content-Range`, `null`
/// si l'en-tête est absent ou illisible.
RangeVerdict rangeResponseVerdict({
  required int? statusCode,
  required int resumedBytes,
  int? contentRangeStart,
}) {
  final int code = statusCode ?? 0;
  if (code == 416) {
    // Rien à reprendre si le partiel est vide : un 416 est alors un refus.
    return resumedBytes > 0 ? RangeVerdict.alreadyComplete : RangeVerdict.reject;
  }
  if (code == 206) {
    // ⚠️ Un 206 qui ne commence pas à l'offset demandé ne peut être ni ajouté
    // (trou ou recouvrement) ni écrit au début (il ne commence pas à 0).
    if (contentRangeStart != null && contentRangeStart != resumedBytes) {
      return RangeVerdict.reject;
    }
    return RangeVerdict.append;
  }
  if (code >= 200 && code < 300) {
    // 200 = le fichier entier. Sur un partiel vide c'est le cas normal ; sur
    // une reprise, le serveur a ignoré `Range`.
    return resumedBytes > 0 ? RangeVerdict.restartFromZero : RangeVerdict.append;
  }
  return RangeVerdict.reject;
}

/// Premier octet d'un en-tête `Content-Range` (« bytes 100-999/1000 » → 100).
/// `null` si l'en-tête est absent ou n'a pas cette forme.
int? parseContentRangeStart(String? header) {
  if (header == null) return null;
  final m = RegExp(r'^\s*bytes\s+(\d+)-').firstMatch(header);
  return m == null ? null : int.tryParse(m.group(1)!);
}

/// Statuts qu'un GET de flux ou une sonde de taille accepte comme réponse.
/// Tout le reste lève (`DioExceptionType.badResponse`, classé « source »),
/// y compris `416`, que le téléchargeur traite dans son `catch`.
bool isDownloadableStatus(int? status) =>
    status != null && status >= 200 && status < 300;
