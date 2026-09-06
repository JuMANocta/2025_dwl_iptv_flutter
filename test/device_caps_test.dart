// §deviceCaps (2026-09-06) — Les règles PURES qui transforment la mesure de
// l'appareil (décodeurs, écran, mémoire) en verdict et en profil.
//
// ⚠️ Décoder n'est pas afficher : la 4K exige les deux. Et une absence de
// mesure ne refuse jamais rien.

import 'package:flutter_test/flutter_test.dart';

import 'package:aetherStream/data/models/device_caps.dart';

DeviceCaps _caps({
  Map<String, dynamic>? hevc,
  Map<String, dynamic>? avc,
  Map<String, dynamic>? display,
  Map<String, dynamic>? memory,
  int cores = 8,
}) =>
    DeviceCaps.fromMap({
      'model': 'Test',
      'manufacturer': 'Lab',
      'sdk': 34,
      'cores': cores,
      'memory': memory,
      'display': display,
      'decoders': {'avc': avc, 'hevc': hevc, 'av1': null, 'vp9': null},
    });

const _hw4k = {
  'name': 'c2.qti.hevc.decoder',
  'hardware': true,
  'maxWidth': 4096,
  'maxHeight': 2304,
  'fps1080': 240.0,
  'fps2160': 60.0,
};
const _hw1080 = {
  'name': 'OMX.rk.video_decoder.avc',
  'hardware': true,
  'maxWidth': 1920,
  'maxHeight': 1088,
  'fps1080': 60.0,
  'fps2160': 0.0,
};
const _tv4k = {'width': 3840, 'height': 2160, 'refreshHz': 60.0, 'hdr': ['HDR10']};
const _box1080 = {'width': 1920, 'height': 1080, 'refreshHz': 60.0};
const _phone = {'width': 1080, 'height': 2340, 'refreshHz': 120.0};

void main() {
  group('verdictFor — la 4K exige le décodeur ET l écran', () {
    test('décodeur 4K + écran 4K → ok', () {
      expect(_caps(hevc: _hw4k, display: _tv4k).verdictFor('4K'), PlayVerdict.ok);
    });

    test('aucun décodeur 2160p → decoderTooSmall', () {
      expect(_caps(avc: _hw1080, display: _tv4k).verdictFor('4K'),
          PlayVerdict.decoderTooSmall);
    });

    test('§caps4kDisplay — un écran annoncé en 1080p ne refuse PLUS la 4K', () {
      // Le téléviseur 4K de l'utilisateur : Android rend 1920×1080 pour
      // l'interface, la vidéo sort en 2160p. Tous les décodeurs présents →
      // la 4K passe. L'écran n'est qu'une information.
      expect(_caps(hevc: _hw4k, display: _box1080).verdictFor('4K'),
          PlayVerdict.ok);
      expect(_caps(hevc: _hw4k, display: _phone).verdictFor('4K'),
          PlayVerdict.ok);
    });

    test('les modes annoncés remontent le plus grand, à titre informatif', () {
      final d = DisplayCaps.fromMap({
        'width': 1920,
        'height': 1080,
        'refreshHz': 60.0,
        'modes': [
          {'width': 1920, 'height': 1080, 'refreshHz': 60.0},
          {'width': 3840, 'height': 2160, 'refreshHz': 60.0},
        ],
      })!;
      expect((d.maxModeWidth, d.maxModeHeight), (3840, 2160));
      expect(d.is2160, isTrue);
      expect(d.announcesMoreThanShown, isTrue);
      // Persisté puis relu : le plus grand mode survit sans la liste.
      final again = DisplayCaps.fromMap(d.toMap())!;
      expect((again.maxModeWidth, again.maxModeHeight), (3840, 2160));
    });

    test('la FHD, la HD et une définition inconnue passent toujours', () {
      final c = _caps(avc: _hw1080, display: _box1080);
      expect(c.verdictFor('FHD'), PlayVerdict.ok);
      expect(c.verdictFor('HD'), PlayVerdict.ok);
      expect(c.verdictFor(null), PlayVerdict.ok);
    });

    test('⚠️ sans mesure complète, on ne refuse RIEN', () {
      expect(_caps(display: _box1080).verdictFor('4K'), PlayVerdict.unknown);
      expect(_caps(hevc: _hw4k).verdictFor('4K'), PlayVerdict.unknown);
    });

    test('UHD et 2160p sont lus comme de la 4K', () {
      final c = _caps(avc: _hw1080, display: _tv4k);
      expect(c.verdictFor('UHD'), PlayVerdict.decoderTooSmall);
      expect(c.verdictFor('2160p'), PlayVerdict.decoderTooSmall);
    });
  });

  group('best2160 — le matériel gagne sur le logiciel', () {
    test('un décodeur logiciel 4K compte, mais un matériel est préféré', () {
      final sw = {..._hw4k, 'name': 'c2.android.hevc.decoder', 'hardware': false};
      final c = _caps(hevc: sw, avc: _hw4k);
      expect(c.best2160!.hardware, isTrue);
      expect(c.best2160!.name, _hw4k['name']);
    });
  });

  group('suggestedProfile — d après la mémoire et les cœurs', () {
    test('appareil à faible mémoire → performance (le plus léger)', () {
      final c = _caps(memory: {'totalMb': 1500, 'availMb': 300, 'lowRamDevice': true});
      expect(c.suggestedProfile, SuggestedProfile.performance);
    });

    test('moins de 2 Go → performance même sans le drapeau', () {
      final c = _caps(memory: {'totalMb': 1900, 'availMb': 900, 'lowRamDevice': false});
      expect(c.suggestedProfile, SuggestedProfile.performance);
    });

    test('2 à 3,5 Go ou 4 cœurs → équilibré', () {
      expect(
          _caps(memory: {'totalMb': 2900, 'availMb': 1000, 'lowRamDevice': false})
              .suggestedProfile,
          SuggestedProfile.equilibre);
      expect(
          _caps(memory: {'totalMb': 8000, 'availMb': 4000, 'lowRamDevice': false}, cores: 4)
              .suggestedProfile,
          SuggestedProfile.equilibre);
    });

    test('8 Go et 8 cœurs → confort (le comportement historique)', () {
      final c = _caps(memory: {'totalMb': 8000, 'availMb': 4000, 'lowRamDevice': false});
      expect(c.suggestedProfile, SuggestedProfile.confort);
    });

    test('sans mesure de mémoire → confort, on ne dégrade pas à l aveugle', () {
      expect(_caps().suggestedProfile, SuggestedProfile.confort);
    });
  });

  group('sérialisation — la mesure survit au redémarrage', () {
    test('toMap → fromMap garde décodeurs, écran, mémoire', () {
      final c = _caps(
          hevc: _hw4k,
          display: _tv4k,
          memory: {'totalMb': 3000, 'availMb': 1200, 'lowRamDevice': false, 'memoryClassMb': 256});
      final back = DeviceCaps.fromMap(c.toMap());
      expect(back.decoders['hevc']!.fps2160, 60.0);
      expect(back.display!.hdr, ['HDR10']);
      expect(back.memory!.memoryClassMb, 256);
      expect(back.decoders['av1'], isNull);
      expect(back.verdictFor('4K'), PlayVerdict.ok);
    });
  });
}
