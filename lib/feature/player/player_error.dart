/// §audioFallback / R5 (2026-09-16) — Reconnaître, dans ce que Media3 remonte,
/// un échec qui ne concerne QUE le son.
///
/// **Le défaut corrigé (revue 2026-09-11, D2A-10)** : depuis §engineVendor, ce
/// fichier ne contenait qu'une expression taillée sur les MESSAGES de mpv
/// (« Error decoding audio », « decoder for codec 'truehd' ») — Media3 n'en
/// produit aucun, et ce qui sort de `Media3Engine.errorStream` est une phrase
/// TRADUITE construite à partir du code (`playbackErrorMessage`). La bascule
/// « piste suivante, sinon sans son » était donc inatteignable : un rip 4K dont
/// la seule piste TrueHD ne se décode pas finissait sur un écran d'erreur.
///
/// Ce que Media3 donne, lui, c'est un CODE (`errorCodeName`) et un message BRUT
/// (`PlaybackException.message`, dérivé par `ExoPlaybackException` :
/// « MediaCodecAudioRenderer error, index=1, format=Format(…, audio/eac3, …) »).
/// Les codes de sortie audio (`AUDIO_TRACK_*`) sont audio par nature ; les codes
/// de décodeur (`DECODER_*` / `DECODING_*`) valent pour l'image comme pour le
/// son et se départagent sur le message : le RENDU qui a échoué et le type MIME
/// de la piste. Un message qui nomme le rendu vidéo n'est jamais audio.
library;

const Set<String> _audioOnlyCodes = <String>{
  'ERROR_CODE_AUDIO_TRACK_INIT_FAILED',
  'ERROR_CODE_AUDIO_TRACK_WRITE_FAILED',
  'ERROR_CODE_AUDIO_TRACK_OFFLOAD_INIT_FAILED',
  'ERROR_CODE_AUDIO_TRACK_OFFLOAD_WRITE_FAILED',
};

const Set<String> _decoderCodes = <String>{
  'ERROR_CODE_DECODER_INIT_FAILED',
  'ERROR_CODE_DECODER_QUERY_FAILED',
  'ERROR_CODE_DECODING_FAILED',
  'ERROR_CODE_DECODING_FORMAT_UNSUPPORTED',
  'ERROR_CODE_DECODING_FORMAT_EXCEEDS_CAPABILITIES',
};

final RegExp _reAudioSide = RegExp(
  r'(AudioRenderer|AudioSink|AudioTrack\b|\baudio/[a-z0-9.+-]+|mp4a-latm'
  r'|\.(aac|ac3|eac3|ec3|dts|dtshd|truehd|flac|mp3|opus|vorbis|alac)\.decoder)',
  caseSensitive: false,
);

final RegExp _reVideoSide = RegExp(
  r'(VideoRenderer|\bvideo/[a-z0-9.+-]+|\.(avc|hevc|h264|h265|av1|vp9|mpeg2)\.decoder)',
  caseSensitive: false,
);

/// `true` si l'erreur décrite par [codeName] (nom de code Media3, ex.
/// `ERROR_CODE_DECODER_INIT_FAILED`) et [rawMessage] (message brut, non
/// traduit) ne concerne que le son : l'image, elle, peut continuer.
bool isMedia3AudioError({String? codeName, required String rawMessage}) {
  final String code = (codeName ?? '').trim().toUpperCase();
  if (_audioOnlyCodes.contains(code)) return true;
  if (!_decoderCodes.contains(code)) return false;
  if (_reVideoSide.hasMatch(rawMessage)) return false;
  return _reAudioSide.hasMatch(rawMessage);
}
