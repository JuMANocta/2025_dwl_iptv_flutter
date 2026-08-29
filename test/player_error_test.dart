import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/feature/player/player_error.dart';

void main() {
  group('§audioFallback — reconnaître un échec de décodage audio', () {
    test('les deux formulations réellement observées sur device', () {
      // Relevées au logcat sur l'émulateur, sur deux fichiers 4K différents.
      // La seconde ne contient PAS le mot « audio » : un test naïf sur ce mot
      // laisserait passer le cas qui a fait échouer la lecture.
      expect(isAudioDecodeError('Error decoding audio.'), isTrue);
      expect(
        isAudioDecodeError("Failed to initialize a decoder for codec 'truehd'."),
        isTrue,
      );
    });

    test('les autres codecs audio courants des rips 4K', () {
      for (final codec in ['eac3', 'ac3', 'dts', 'dtshd', 'aac', 'opus',
                           'flac', 'mp3', 'vorbis', 'alac', 'pcm_s24le']) {
        expect(
          isAudioDecodeError("Failed to initialize a decoder for codec '$codec'."),
          isTrue,
          reason: codec,
        );
      }
    });

    test('la casse ne change pas le verdict', () {
      expect(isAudioDecodeError('ERROR DECODING AUDIO.'), isTrue);
    });

    test('un codec VIDÉO ne doit jamais déclencher la bascule audio', () {
      // Y glisser un codec vidéo ferait changer de piste audio pour un problème
      // d'image : on perdrait le son sans rien résoudre, et on masquerait la
      // vraie panne — celle que §video4k cherche justement à identifier.
      for (final codec in ['hevc', 'h264', 'av1', 'vp9', 'mpeg2video']) {
        expect(
          isAudioDecodeError("Failed to initialize a decoder for codec '$codec'."),
          isFalse,
          reason: codec,
        );
      }
    });

    test('une panne réseau reste une panne réseau', () {
      // Ces erreurs doivent continuer à passer par la reconnexion ×3.
      for (final e in [
        'Failed to open http://serveur/movie/1234.mkv.',
        'Connection timed out.',
        'HTTP error 403 Forbidden',
        '',
      ]) {
        expect(isAudioDecodeError(e), isFalse, reason: e);
      }
    });
  });
}
