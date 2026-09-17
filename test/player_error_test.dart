import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/feature/player/player_error.dart';

void main() {
  group('R5 / §audioFallback — reconnaître un échec qui ne concerne que le son', () {
    test('un décodeur AUDIO qui ne s\'initialise pas (message brut Media3)', () {
      expect(
        isMedia3AudioError(
          codeName: 'ERROR_CODE_DECODER_INIT_FAILED',
          rawMessage: 'MediaCodecAudioRenderer error, index=1, '
              'format=Format(1, null, null, audio/true-hd, mlpa, -1, null, '
              '[-1, -1, -1.0, null], [8, 48000]), format_supported=NO_UNSUPPORTED_TYPE',
        ),
        isTrue,
      );
    });

    test('un échec de décodage en cours de lecture, côté audio', () {
      expect(
        isMedia3AudioError(
          codeName: 'ERROR_CODE_DECODING_FAILED',
          rawMessage: 'MediaCodecAudioRenderer error, index=1, '
              'format=Format(…, audio/eac3, ec-3, …), format_supported=YES',
        ),
        isTrue,
      );
    });

    test('les codes de SORTIE audio sont audio par nature, quel que soit le message', () {
      for (final code in [
        'ERROR_CODE_AUDIO_TRACK_INIT_FAILED',
        'ERROR_CODE_AUDIO_TRACK_WRITE_FAILED',
        'ERROR_CODE_AUDIO_TRACK_OFFLOAD_INIT_FAILED',
        'ERROR_CODE_AUDIO_TRACK_OFFLOAD_WRITE_FAILED',
      ]) {
        expect(isMedia3AudioError(codeName: code, rawMessage: ''), isTrue,
            reason: code);
        expect(isMedia3AudioError(codeName: code.toLowerCase(), rawMessage: ''),
            isTrue, reason: 'casse de $code');
      }
    });

    test('un décodeur VIDÉO en échec ne déclenche JAMAIS la bascule audio', () {
      for (final msg in [
        'MediaCodecVideoRenderer error, index=0, format=Format(…, video/hevc, …)',
        'Decoder init failed: c2.qti.hevc.decoder, Format(…, video/hevc, …)',
        'MediaCodecVideoRenderer error, index=0, format=Format(…, video/av01, …)',
      ]) {
        for (final code in [
          'ERROR_CODE_DECODER_INIT_FAILED',
          'ERROR_CODE_DECODING_FAILED',
          'ERROR_CODE_DECODING_FORMAT_EXCEEDS_CAPABILITIES',
        ]) {
          expect(isMedia3AudioError(codeName: code, rawMessage: msg), isFalse,
              reason: '$code / $msg');
        }
      }
    });

    test('un code de décodeur sans indice de piste ne se devine pas', () {
      expect(
        isMedia3AudioError(
            codeName: 'ERROR_CODE_DECODER_INIT_FAILED', rawMessage: ''),
        isFalse,
      );
      expect(
        isMedia3AudioError(
            codeName: 'ERROR_CODE_DECODING_FAILED',
            rawMessage: 'Decoder failed'),
        isFalse,
      );
    });

    test('une panne réseau ou de source reste une panne, même si le message parle d\'audio', () {
      for (final code in [
        'ERROR_CODE_IO_NETWORK_CONNECTION_FAILED',
        'ERROR_CODE_IO_BAD_HTTP_STATUS',
        'ERROR_CODE_PARSING_CONTAINER_MALFORMED',
        'ERROR_CODE_BEHIND_LIVE_WINDOW',
        'ERROR_CODE_UNSPECIFIED',
        null,
      ]) {
        expect(
          isMedia3AudioError(
              codeName: code,
              rawMessage: 'MediaCodecAudioRenderer error, format=audio/aac'),
          isFalse,
          reason: '$code',
        );
      }
    });

    test('sincérité : sans le nom du rendu ni le type MIME, un code de décodeur ne suffit pas', () {
      // Retirer le test sur le message (ne garder que le code) ferait passer
      // ce cas à vrai : c'est la mutation que ce test attrape.
      expect(
        isMedia3AudioError(
            codeName: 'ERROR_CODE_DECODING_FORMAT_UNSUPPORTED',
            rawMessage: 'Format unsupported'),
        isFalse,
      );
    });
  });
}
