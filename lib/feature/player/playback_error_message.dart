import '../../core/diagnostics/log_buffer.dart' show sanitizeForLog;

/// §userError — Traduit une erreur Media3 en phrase française affichable.
///
/// **Ce qui arrive ici** : `VideoPlayerObserver.kt` envoie
/// `PlaybackException.message` (« Source error », « Unknown error »,
/// « MediaCodecVideoRenderer error, index=0, format=Format(…) »…) et
/// `errorCodeName` (`ERROR_CODE_IO_BAD_HTTP_STATUS`…). Le message est en
/// anglais et **n'est pas fait pour l'écran** ; le code, lui, dit précisément
/// ce qui s'est passé. On parle donc à partir du code, et le message brut ne
/// sert que de repli — passé par [sanitizeForLog], parce que rien ne garantit
/// qu'une version future de Media3 n'y glissera pas l'URI du flux (avec les
/// identifiants Xtream qu'elle porte).
///
/// ⚠️ La mise en forme ne doit **pas** être branchée sur le texte anglais :
/// `player_error.dart` a déjà payé ce piège (regex sur des libellés mpv,
/// mortes au changement de moteur). Seul `errorCodeName` est stable.
String playbackErrorMessage({
  required String? codeName,
  required String? rawMessage,
}) {
  final String name = (codeName ?? '').trim().toUpperCase();
  final String raw = (rawMessage ?? '').trim();

  // Erreurs synthétiques du paquet Dart (pas de code) : `Buffering timed out
  // after 30s` / `Load timed out after …`.
  if (name.isEmpty && raw.toLowerCase().contains('timed out')) {
    return 'Le flux ne répond plus (délai dépassé).';
  }

  switch (name) {
    // --- Réseau / E-S -------------------------------------------------------
    case 'ERROR_CODE_IO_NETWORK_CONNECTION_FAILED':
      return 'Connexion au serveur impossible. Vérifie le réseau.';
    case 'ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT':
      return 'Le serveur a mis trop de temps à répondre.';
    case 'ERROR_CODE_IO_BAD_HTTP_STATUS':
      return 'Le serveur a refusé le flux (erreur HTTP). '
          'Vérifie le compte ou réessaie plus tard.';
    case 'ERROR_CODE_IO_FILE_NOT_FOUND':
      return 'Flux introuvable sur le serveur.';
    case 'ERROR_CODE_IO_NO_PERMISSION':
      return 'Accès au flux refusé.';
    case 'ERROR_CODE_IO_CLEARTEXT_NOT_PERMITTED':
      return 'Connexion non chiffrée refusée par le système.';
    case 'ERROR_CODE_IO_INVALID_HTTP_CONTENT_TYPE':
      return 'Le serveur ne renvoie pas une vidéo (type de contenu inattendu).';
    case 'ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE':
      return 'Position de lecture hors du flux.';
    case 'ERROR_CODE_IO_UNSPECIFIED':
      return 'Erreur de lecture réseau.';
    case 'ERROR_CODE_BEHIND_LIVE_WINDOW':
      return 'Trop en retard sur le direct : reprise au direct.';
    case 'ERROR_CODE_TIMEOUT':
      return 'Le lecteur n\'a pas répondu à temps.';

    // --- Format / analyse ---------------------------------------------------
    case 'ERROR_CODE_PARSING_CONTAINER_MALFORMED':
    case 'ERROR_CODE_PARSING_MANIFEST_MALFORMED':
      return 'Flux illisible (données corrompues ou inattendues).';
    case 'ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED':
    case 'ERROR_CODE_PARSING_MANIFEST_UNSUPPORTED':
      return 'Format de flux non pris en charge.';

    // --- Décodage -----------------------------------------------------------
    case 'ERROR_CODE_DECODER_INIT_FAILED':
    case 'ERROR_CODE_DECODER_QUERY_FAILED':
      return 'Impossible d\'initialiser le décodeur vidéo.';
    case 'ERROR_CODE_DECODING_FAILED':
      return 'Échec du décodage : le flux est peut-être abîmé.';
    case 'ERROR_CODE_DECODING_FORMAT_EXCEEDS_CAPABILITIES':
      return 'Ce flux dépasse les capacités de l\'appareil (définition ou débit).';
    case 'ERROR_CODE_DECODING_FORMAT_UNSUPPORTED':
      return 'Codec non pris en charge par cet appareil.';
    case 'ERROR_CODE_AUDIO_TRACK_INIT_FAILED':
    case 'ERROR_CODE_AUDIO_TRACK_WRITE_FAILED':
    case 'ERROR_CODE_AUDIO_TRACK_OFFLOAD_INIT_FAILED':
    case 'ERROR_CODE_AUDIO_TRACK_OFFLOAD_WRITE_FAILED':
      return 'Sortie audio indisponible (piste ou format audio non lisible).';

    // --- Divers -------------------------------------------------------------
    case 'ERROR_CODE_REMOTE_ERROR':
      return 'Erreur du lecteur distant.';
    case 'ERROR_CODE_FAILED_RUNTIME_CHECK':
    case 'ERROR_CODE_UNSPECIFIED':
      return 'Le lecteur a rencontré une erreur inattendue.';
  }

  if (name.startsWith('ERROR_CODE_DRM_')) {
    return 'Contenu protégé (DRM) non lisible.';
  }
  if (name.startsWith('ERROR_CODE_IO_')) {
    return 'Erreur de lecture réseau.';
  }
  if (name.startsWith('ERROR_CODE_DECOD')) {
    return 'Échec du décodage vidéo.';
  }

  // Repli : message brut du moteur, expurgé. « Unknown error » et « Source
  // error » ne disent rien à personne → phrase générique.
  final String lower = raw.toLowerCase();
  if (raw.isEmpty || lower == 'unknown error' || lower == 'source error') {
    return 'Lecture impossible.';
  }
  return 'Lecture impossible : ${sanitizeForLog(raw)}';
}
