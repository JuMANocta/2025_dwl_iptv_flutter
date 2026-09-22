import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show PlatformException;

import '../../core/diagnostics/log_buffer.dart' show sanitizeForLog;
import '../../core/utils/user_error.dart' show describeError;
import '../../l10n/l10n_ext.dart';
import 'player_error.dart'
    show isMedia3AudioError, rawMessageNamesAudioRenderer;

/// §userError — Phrase d'écran pour une erreur levée à l'OUVERTURE du flux
/// (`initialize` / `loadUrl`), c'est-à-dire hors de `errorStream`.
///
/// Revue 2026-09-11 (trouvé en recette, émulateur téléphone) : l'écran
/// d'erreur affichait « PlatformException(LOAD_ERROR, Source error, null,
/// null) ». Le `catch` d'ouverture passait `e.toString()` au lecteur, puis
/// `describeError` recevait une simple CHAÎNE : il n'avait plus rien à
/// traduire et rendait le texte brut. Une `PlatformException` du moteur passe
/// désormais par la même table que `errorStream` ([playbackErrorMessage]) :
/// son code s'il en porte un, sinon la phrase générique.
String openErrorMessage(Object error) {
  if (error is PlatformException) {
    final Object? details = error.details;
    String? codeName;
    if (details is Map && details['errorCodeName'] is String) {
      codeName = details['errorCodeName'] as String;
    } else if (error.code.toUpperCase().startsWith('ERROR_CODE_')) {
      codeName = error.code;
    }
    return playbackErrorMessage(codeName: codeName, rawMessage: error.message);
  }
  return describeError(error);
}

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
    return L10n.current.perrTimedOut;
  }

  // R5 (recette 2026-09-21) — Un décodeur qui échoue sur une piste AUDIO
  // n'est pas « le décodeur vidéo » : `DECODER_INIT_FAILED` sur une piste MP2
  // disait « Impossible d'initialiser le décodeur vidéo ».
  if (isMedia3AudioError(codeName: name, rawMessage: raw)) {
    return L10n.current.perrAudioOutput;
  }

  switch (name) {
    // --- Réseau / E-S -------------------------------------------------------
    case 'ERROR_CODE_IO_NETWORK_CONNECTION_FAILED':
      return L10n.current.perrConnectionFailed;
    case 'ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT':
      return L10n.current.perrConnectionTimeout;
    case 'ERROR_CODE_IO_BAD_HTTP_STATUS':
      return L10n.current.perrBadHttpStatus;
    case 'ERROR_CODE_IO_FILE_NOT_FOUND':
      return L10n.current.perrFileNotFound;
    case 'ERROR_CODE_IO_NO_PERMISSION':
      return L10n.current.perrNoPermission;
    case 'ERROR_CODE_IO_CLEARTEXT_NOT_PERMITTED':
      return L10n.current.perrCleartextNotPermitted;
    case 'ERROR_CODE_IO_INVALID_HTTP_CONTENT_TYPE':
      return L10n.current.perrInvalidContentType;
    case 'ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE':
      return L10n.current.perrPositionOutOfRange;
    case 'ERROR_CODE_IO_UNSPECIFIED':
      return L10n.current.perrNetwork;
    case 'ERROR_CODE_BEHIND_LIVE_WINDOW':
      return L10n.current.perrBehindLiveWindow;
    case 'ERROR_CODE_TIMEOUT':
      return L10n.current.perrPlayerTimeout;

    // --- Format / analyse ---------------------------------------------------
    case 'ERROR_CODE_PARSING_CONTAINER_MALFORMED':
    case 'ERROR_CODE_PARSING_MANIFEST_MALFORMED':
      return L10n.current.perrMalformed;
    case 'ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED':
    case 'ERROR_CODE_PARSING_MANIFEST_UNSUPPORTED':
      return L10n.current.perrUnsupportedFormat;

    // --- Décodage -----------------------------------------------------------
    case 'ERROR_CODE_DECODER_INIT_FAILED':
    case 'ERROR_CODE_DECODER_QUERY_FAILED':
      return L10n.current.perrDecoderInit;
    // §tvDecoderReclaim (2026-09-12, sur la TV réelle) — le système a REPRIS le
    // décodeur : une autre application l'a demandé, ou le pipeline vidéo n'en
    // avait plus à donner. ⚠️ Sans ce `case`, le repli par préfixe
    // `ERROR_CODE_DECOD` répondait « Échec du décodage vidéo » : on accusait le
    // flux alors qu'il est intact (Media3 joint `format_supported=YES`), et le
    // seul geste utile — fermer les autres applications — n'était pas dit.
    case 'ERROR_CODE_DECODING_RESOURCES_RECLAIMED':
      return L10n.current.perrDecoderReclaimed;
    case 'ERROR_CODE_DECODING_FAILED':
      return L10n.current.perrDecodingFailed;
    case 'ERROR_CODE_DECODING_FORMAT_EXCEEDS_CAPABILITIES':
      return L10n.current.perrExceedsCapabilities;
    case 'ERROR_CODE_DECODING_FORMAT_UNSUPPORTED':
      return L10n.current.perrCodecUnsupported;
    case 'ERROR_CODE_AUDIO_TRACK_INIT_FAILED':
    case 'ERROR_CODE_AUDIO_TRACK_WRITE_FAILED':
    case 'ERROR_CODE_AUDIO_TRACK_OFFLOAD_INIT_FAILED':
    case 'ERROR_CODE_AUDIO_TRACK_OFFLOAD_WRITE_FAILED':
      return L10n.current.perrAudioOutput;

    // --- Divers -------------------------------------------------------------
    case 'ERROR_CODE_REMOTE_ERROR':
      return L10n.current.perrRemote;
    case 'ERROR_CODE_FAILED_RUNTIME_CHECK':
    case 'ERROR_CODE_UNSPECIFIED':
      return L10n.current.perrUnexpected;
  }

  if (name.startsWith('ERROR_CODE_DRM_')) {
    return L10n.current.perrDrm;
  }
  if (name.startsWith('ERROR_CODE_IO_')) {
    return L10n.current.perrNetwork;
  }
  if (name.startsWith('ERROR_CODE_DECOD')) {
    return L10n.current.perrDecodeVideo;
  }

  // Sans code (erreur levée à l'OUVERTURE : `LOAD_ERROR` ne joint pas le
  // code Media3) — le message brut dit au moins QUEL rendu a échoué.
  if (name.isEmpty && rawMessageNamesAudioRenderer(raw)) {
    return L10n.current.perrAudioOutput;
  }

  // Repli : la phrase générique. ⛔ Plus jamais le message brut à l'écran
  // (recette AVD du 2026-09-21 : « Playback failed: MediaCodecAudioRenderer
  // error, index=1, format=Format(3, null, null, audio/mpeg-L2… » s'affichait
  // tel quel) — §userError, « un code natif inconnu ne s'affiche jamais ».
  // Il part au journal, expurgé.
  if (raw.isNotEmpty) {
    debugPrint('⚠️ §userError — erreur de lecture non reconnue : ${name.isEmpty ? 'sans code' : name} — ${sanitizeForLog(raw)}');
  }
  return L10n.current.perrCannotPlay;
}
