// R5 / §audioFallback / §trackMemory / §userError — recette AVD TV du
// 2026-09-21 : choisir la piste anglaise MP2 (`audio/mpeg-L2`) d'un film que
// le décodeur de l'appareil ne sait pas lire.
//
// Trois défauts, tenus ici sur le message EXACT relevé au journal :
// 1. la bascule audio ne se déclenchait pas (piste fautive inconnue) → le flux
//    était relancé cinq fois puis rouvert sur la même piste ;
// 2. l'écran d'erreur affichait ce message brut du moteur ;
// 3. la langue « en » restait mémorisée pour tous les titres suivants.
import 'package:aetherStream/data/services/track_preferences_service.dart';
import 'package:aetherStream/feature/player/playback_engine.dart';
import 'package:aetherStream/feature/player/playback_error_message.dart';
import 'package:aetherStream/feature/player/player_error.dart';
import 'package:aetherStream/feature/player/widgets/track_choices.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Le message relevé sur l'AVD, mot pour mot.
const String _mp2 = 'MediaCodecAudioRenderer error, index=1, '
    'format=Format(3, null, null, audio/mpeg-L2, null, -1, en, '
    '[-1, -1, -1.0, null], [2, 48000]), format_supported=NO_UNSUPPORTED_TYPE';

const AetherTrack _fr = AetherTrack(
    id: '0', language: 'fr', title: 'French (VFQ)', codec: 'audio/ac3');
const AetherTrack _en =
    AetherTrack(id: '1', language: 'en', codec: 'audio/mpeg-L2');

class _FauxMoteur implements AetherPlaybackEngine {
  AetherTrack? courante = _fr;
  bool accepte = true;

  @override
  List<AetherTrack> get audioTracks => const [_fr, _en];

  @override
  AetherTrack? get currentAudioTrack => courante;

  @override
  Future<bool> setAudioTrack(AetherTrack track) async {
    if (!accepte) return false;
    courante = track;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('1 — la bascule sait QUELLE piste a échoué', () {
    test('le message exact est bien une erreur de son seul', () {
      expect(
        isMedia3AudioError(
            codeName: 'ERROR_CODE_DECODER_INIT_FAILED', rawMessage: _mp2),
        isTrue,
      );
    });

    test('la piste fautive se lit dans le message : MP2 anglaise', () {
      expect(audioTrackNamedByError(_mp2, const [_fr, _en]), _en);
    });

    test('deux pistes du même codec : la langue départage', () {
      const enAc3 = AetherTrack(id: '2', language: 'en', codec: 'audio/ac3');
      const msg = 'MediaCodecAudioRenderer error, index=1, '
          'format=Format(2, null, null, audio/ac3, null, -1, en, [], [6, 48000])';
      expect(audioTrackNamedByError(msg, const [_fr, enAc3]), enAc3);
    });

    test('on ne devine pas : ambigu ou inconnu → null', () {
      const fr2 = AetherTrack(id: '2', language: 'fr', codec: 'audio/ac3');
      const msg = 'MediaCodecAudioRenderer error, index=1, '
          'format=Format(2, null, null, audio/ac3, null, -1, fr, [], [])';
      expect(audioTrackNamedByError(msg, const [_fr, fr2]), isNull,
          reason: 'deux pistes AC3 françaises : impossible de choisir');
      expect(audioTrackNamedByError('Source error', const [_fr, _en]), isNull);
      expect(audioTrackNamedByError(_mp2, const [_fr]), isNull,
          reason: 'aucune piste MP2 connue');
    });
  });

  group('2 — jamais le message du moteur à l\'écran', () {
    test('code décodeur + piste audio : « sortie audio », pas « vidéo »', () {
      final String s = playbackErrorMessage(
          codeName: 'ERROR_CODE_DECODER_INIT_FAILED', rawMessage: _mp2);
      expect(s.toLowerCase(), contains('audio'));
      expect(s.toLowerCase(), isNot(contains('vidéo')));
      expect(s, isNot(contains('MediaCodec')));
    });

    test('à l\'ouverture (LOAD_ERROR, sans code) : même phrase, rien de brut',
        () {
      final String s = openErrorMessage(
          PlatformException(code: 'LOAD_ERROR', message: _mp2));
      expect(s, isNot(contains('MediaCodec')));
      expect(s, isNot(contains('Format(')));
      expect(s,
          playbackErrorMessage(codeName: 'ERROR_CODE_DECODER_INIT_FAILED',
              rawMessage: _mp2));
    });

    test('un message inconnu donne la phrase générique, sans son texte', () {
      expect(
        playbackErrorMessage(
            codeName: null, rawMessage: 'Something new went wrong'),
        'Lecture impossible.',
      );
    });
  });

  group('3 — une piste rejetée défait la langue qu\'elle avait mémorisée', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(
          <String, Object>{'track_pref_audio_v1': 'fr'});
      await TrackPreferencesService.reloadForTest();
    });

    test('choix « en » puis rejet par R5 : la mémoire revient à « fr »',
        () async {
      final moteur = _FauxMoteur();
      expect(await applyAudioTrackChoice(moteur, _en), isTrue);
      expect(TrackPreferencesService.audio, 'en');

      final AudioChoice? defait = await undoAudioChoice(moteur, _en.id);
      expect(defait, isNotNull);
      expect(defait!.trackBefore, _fr.id,
          reason: 'la bascule repart sur la piste qui jouait');
      expect(TrackPreferencesService.audio, 'fr');
      expect(lastAudioChoice(moteur), isNull, reason: 'défait une seule fois');
    });

    test('avant tout choix, pas de mémoire : le rejet la rend vide', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await TrackPreferencesService.reloadForTest();
      final moteur = _FauxMoteur();
      await applyAudioTrackChoice(moteur, _en);
      await undoAudioChoice(moteur, _en.id);
      expect(TrackPreferencesService.audio, isNull);
    });

    test('une AUTRE piste rejetée ne touche pas au choix de l\'utilisateur',
        () async {
      final moteur = _FauxMoteur();
      await applyAudioTrackChoice(moteur, _en);
      expect(await undoAudioChoice(moteur, _fr.id), isNull);
      expect(TrackPreferencesService.audio, 'en');
    });

    test('un choix refusé par le moteur n\'est ni mémorisé ni noté', () async {
      final moteur = _FauxMoteur()..accepte = false;
      expect(await applyAudioTrackChoice(moteur, _en), isFalse);
      expect(TrackPreferencesService.audio, 'fr');
      expect(lastAudioChoice(moteur), isNull);
    });

    test('le choix est propre à CHAQUE moteur', () async {
      final a = _FauxMoteur();
      final b = _FauxMoteur();
      await applyAudioTrackChoice(a, _en);
      expect(lastAudioChoice(b), isNull);
      expect(await undoAudioChoice(b, _en.id), isNull);
    });
  });
}
