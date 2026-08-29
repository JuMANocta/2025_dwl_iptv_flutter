/// §audioFallback — Classification des erreurs remontées par mpv.
///
/// Le lecteur doit répondre différemment selon la nature de la panne : un flux
/// injoignable se retente (réseau), une piste audio indécodable se contourne
/// (on change de piste). Les confondre donne le comportement observé sur
/// device : trois tentatives réseau brûlées pour un problème qui n'avait rien
/// à voir avec le réseau, sur un fichier dont la vidéo décodait très bien.
library;

/// Reconnaît un échec de décodage **AUDIO**.
///
/// mpv le formule de deux façons, et la seconde ne contient pas le mot
/// « audio » — d'où la liste explicite de codecs :
///   - `Error decoding audio.`
///   - `Failed to initialize a decoder for codec 'truehd'.`
///
/// ⚠️ La liste ne retient que des codecs **audio**. Y glisser un codec vidéo
/// (hevc, av1…) ferait changer de piste audio pour un problème d'image : on
/// perdrait le son sans rien résoudre, et on masquerait la vraie panne.
final RegExp _reAudioDecodeError = RegExp(
  r'(error\s+decoding\s+audio'
  r"|decoder\s+for\s+codec\s+'(truehd|eac3|ac3|dts|dtshd|aac|opus|flac|mp3|vorbis|alac|pcm[a-z0-9_]*)'"
  r'|could\s+not\s+open\s+audio'
  r'|audio\s+(decoder|device)\s+init)',
  caseSensitive: false,
);

bool isAudioDecodeError(String error) => _reAudioDecodeError.hasMatch(error);
