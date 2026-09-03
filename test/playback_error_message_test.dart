import 'package:aetherStream/feature/player/playback_error_message.dart';
import 'package:flutter_test/flutter_test.dart';

/// §userError — Ce qui part de `Media3Engine._onActivity` finit À L'ÉCRAN.
/// Ces tests verrouillent trois choses : le français, l'absence d'URL et le
/// fait qu'on parle à partir du CODE, pas du texte anglais du moteur.
void main() {
  group('playbackErrorMessage — parle à partir du code', () {
    test('un code connu donne une phrase française, quel que soit le texte', () {
      final String s = playbackErrorMessage(
        codeName: 'ERROR_CODE_IO_BAD_HTTP_STATUS',
        rawMessage: 'Source error',
      );
      expect(s, contains('serveur'));
      expect(s.toLowerCase(), isNot(contains('source error')));
    });

    test('le code est lu sans tenir compte de la casse ni des espaces', () {
      expect(
        playbackErrorMessage(
            codeName: ' error_code_decoding_format_unsupported ',
            rawMessage: null),
        contains('Codec'),
      );
    });

    test('les familles DRM / IO / DECOD inconnues ont un repli par préfixe', () {
      expect(playbackErrorMessage(codeName: 'ERROR_CODE_DRM_FUTURE', rawMessage: ''),
          contains('DRM'));
      expect(playbackErrorMessage(codeName: 'ERROR_CODE_IO_FUTURE', rawMessage: ''),
          contains('réseau'));
      expect(
          playbackErrorMessage(
              codeName: 'ERROR_CODE_DECODING_FUTURE', rawMessage: ''),
          contains('décodage'));
    });

    test('le délai synthétique du paquet Dart (sans code) est reconnu', () {
      expect(
        playbackErrorMessage(
            codeName: null, rawMessage: 'Buffering timed out after 30s'),
        contains('délai'),
      );
    });
  });

  group('playbackErrorMessage — le repli ne fuit rien', () {
    test('« Unknown error » et « Source error » donnent la phrase générique', () {
      expect(playbackErrorMessage(codeName: null, rawMessage: 'Unknown error'),
          'Lecture impossible.');
      expect(playbackErrorMessage(codeName: '', rawMessage: 'source error'),
          'Lecture impossible.');
      expect(playbackErrorMessage(codeName: null, rawMessage: null),
          'Lecture impossible.');
    });

    test('une URL Xtream dans le texte brut est expurgée', () {
      final String s = playbackErrorMessage(
        codeName: 'ERROR_CODE_SOMETHING_NEW',
        rawMessage:
            'Failed http://h.example:8080/live/SECRETU/SECRETP/42.ts (Response code: 403)',
      );
      expect(s, isNot(contains('SECRETU')));
      expect(s, isNot(contains('SECRETP')));
      expect(s, contains('***'));
      expect(s, startsWith('Lecture impossible'));
    });

    test('une query username/password dans le texte brut est expurgée', () {
      final String s = playbackErrorMessage(
        codeName: 'ERROR_CODE_SOMETHING_NEW',
        rawMessage: 'GET http://h/get.php?username=SECRETU&password=SECRETP',
      );
      expect(s, isNot(contains('SECRETU')));
      expect(s, isNot(contains('SECRETP')));
    });
  });
}
