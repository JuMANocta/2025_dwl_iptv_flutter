// §castRelay — L'indexeur de MP4 fragmenté en cours d'écriture : ce qu'il
// publie, quand, et ce qu'il refuse de publier tant que ce n'est pas complet.
import 'dart:typed_data';

import 'package:aetherStream/data/services/fmp4_index.dart';
import 'package:flutter_test/flutter_test.dart';

// ── Fabrique de boîtes ────────────────────────────────────────────────────────

Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v);
Uint8List _u64(int v) => Uint8List(8)..buffer.asByteData().setUint64(0, v);
Uint8List _ascii(String s) => Uint8List.fromList(s.codeUnits);

Uint8List _cat(List<Uint8List> parts) {
  final b = BytesBuilder(copy: false);
  for (final p in parts) {
    b.add(p);
  }
  return b.takeBytes();
}

Uint8List _box(String type, List<Uint8List> payload) {
  final body = _cat(payload);
  return _cat([_u32(8 + body.length), _ascii(type), body]);
}

/// Boîte à taille 64 bits (`size == 1` + largesize).
Uint8List _bigBox(String type, List<Uint8List> payload) {
  final body = _cat(payload);
  return _cat([_u32(1), _ascii(type), _u64(16 + body.length), body]);
}

Uint8List _fullBox(String type, int version, List<Uint8List> payload) =>
    _box(type, [
      Uint8List.fromList([version, 0, 0, 0]),
      ...payload
    ]);

Uint8List _tkhd(int trackId) => _fullBox(
      'tkhd',
      0,
      [_u32(0), _u32(0), _u32(trackId), _u32(0), _u32(0)],
    );

Uint8List _mdhd(int timescale) =>
    _fullBox('mdhd', 0, [_u32(0), _u32(0), _u32(timescale), _u32(0)]);

Uint8List _hdlr(String handler) =>
    _fullBox('hdlr', 0, [_u32(0), _ascii(handler), _u32(0), _u32(0), _u32(0)]);

Uint8List _trak(int id, int timescale, String handler) => _box('trak', [
      _tkhd(id),
      _box('mdia', [_mdhd(timescale), _hdlr(handler)]),
    ]);

Uint8List _traf(int trackId, int tfdt, {int version = 1}) => _box('traf', [
      _fullBox('tfhd', 0, [_u32(trackId)]),
      _fullBox('tfdt', version, [version == 1 ? _u64(tfdt) : _u32(tfdt)]),
    ]);

Uint8List _mdat(int size, {bool big = false}) =>
    big ? _bigBox('mdat', [Uint8List(size)]) : _box('mdat', [Uint8List(size)]);

/// Un fichier type : vidéo (id 1, 90 kHz) et son (id 2, 48 kHz), le son
/// AVANT la vidéo dans chaque `moof` pour prouver qu'on suit la vidéo.
class _Fixture {
  _Fixture() {
    ftyp = _box('ftyp', [_ascii('isom'), _u32(0)]);
    moov = _box('moov', [_trak(2, 48000, 'soun'), _trak(1, 90000, 'vide')]);
    // Fragments : vidéo à t=0, 2 s, 5 s ; le son à des temps SANS rapport.
    frags = [
      _cat([
        _box('moof', [_traf(2, 0), _traf(1, 0)]),
        _mdat(100),
      ]),
      _cat([
        _box('moof', [_traf(2, 777), _traf(1, 180000)]),
        _mdat(120),
      ]),
      _cat([
        _box('moof', [_traf(2, 999), _traf(1, 450000)]),
        _mdat(80, big: true),
      ]),
    ];
    all = _cat([ftyp, moov, ...frags]);
  }

  late final Uint8List ftyp;
  late final Uint8List moov;
  late final List<Uint8List> frags;
  late final Uint8List all;

  ByteReader readerFor(int available) => (int offset, int length) async {
        final int end = (offset + length).clamp(0, available);
        if (offset >= end) return Uint8List(0);
        return Uint8List.sublistView(all, offset, end);
      };
}

void main() {
  group('Fmp4Index — ce qui est publié, et quand', () {
    test('rien tant que le moov n\'est pas complet', () async {
      final fx = _Fixture();
      final idx = Fmp4Index();
      final int partial = fx.ftyp.length + fx.moov.length - 3;
      await idx.update(partial, fx.readerFor(partial));
      expect(idx.hasInit, isFalse);
      expect(idx.segments(done: false), isEmpty);
    });

    test('le segment d\'initialisation = ftyp + moov exactement', () async {
      final fx = _Fixture();
      final idx = Fmp4Index();
      await idx.update(fx.all.length, fx.readerFor(fx.all.length));
      expect(idx.initEnd, fx.ftyp.length + fx.moov.length);
    });

    test('un fragment n\'est publié que quand le suivant a commencé', () async {
      final fx = _Fixture();
      final idx = Fmp4Index();
      // Tout sauf les 5 derniers octets : le 3e mdat est incomplet.
      final int avail = fx.all.length - 5;
      await idx.update(avail, fx.readerFor(avail));
      expect(idx.fragmentCount, 2);
      final segs = idx.segments(done: false);
      expect(segs, hasLength(1), reason: 'le 2e attend son successeur');
      expect(segs.single.start, fx.ftyp.length + fx.moov.length);
      expect(segs.single.end, segs.single.start + fx.frags[0].length);
      expect(segs.single.duration, const Duration(seconds: 2));
    });

    test('durées déduites des tfdt de la piste VIDÉO, pas de la première',
        () async {
      final fx = _Fixture();
      final idx = Fmp4Index();
      await idx.update(fx.all.length, fx.readerFor(fx.all.length));
      final segs = idx.segments(done: false);
      expect(segs.map((s) => s.duration).toList(), const [
        Duration(seconds: 2),
        Duration(seconds: 3),
      ]);
    });

    test('conversion finie : le dernier prend la durée du précédent', () async {
      final fx = _Fixture();
      final idx = Fmp4Index();
      await idx.update(fx.all.length, fx.readerFor(fx.all.length));
      final segs = idx.segments(done: true);
      expect(segs, hasLength(3));
      expect(segs.last.duration, const Duration(seconds: 3));
      expect(segs.last.end, fx.all.length, reason: 'mdat 64 bits inclus');
    });

    test('update est incrémental et idempotent', () async {
      final fx = _Fixture();
      final idx = Fmp4Index();
      for (int avail = 0; avail <= fx.all.length; avail += 7) {
        await idx.update(avail, fx.readerFor(avail));
      }
      await idx.update(fx.all.length, fx.readerFor(fx.all.length));
      await idx.update(fx.all.length, fx.readerFor(fx.all.length));
      expect(idx.fragmentCount, 3);
      expect(idx.segments(done: true), hasLength(3));
    });

    test('readyDuration = somme des segments publiables', () async {
      final fx = _Fixture();
      final idx = Fmp4Index();
      await idx.update(fx.all.length, fx.readerFor(fx.all.length));
      expect(idx.readyDuration(done: false), const Duration(seconds: 5));
      expect(idx.readyDuration(done: true), const Duration(seconds: 8));
    });
  });

  group('Fmp4Index — reprise par position', () {
    test('position nulle → premier fragment (init inclus avant)', () async {
      final fx = _Fixture();
      final idx = Fmp4Index();
      await idx.update(fx.all.length, fx.readerFor(fx.all.length));
      final int initEnd = fx.ftyp.length + fx.moov.length;
      expect(idx.byteOffsetForPosition(Duration.zero), initEnd);
      expect(idx.byteOffsetForPosition(const Duration(seconds: 1)), initEnd);
    });

    test('milieu → début du fragment qui couvre la position', () async {
      final fx = _Fixture();
      final idx = Fmp4Index();
      await idx.update(fx.all.length, fx.readerFor(fx.all.length));
      final int initEnd = fx.ftyp.length + fx.moov.length;
      // Segments : 2 s, 3 s, 3 s. 2,5 s tombe dans le 2e (début = après frag0).
      final int frag1Start = initEnd + fx.frags[0].length;
      expect(
        idx.byteOffsetForPosition(const Duration(milliseconds: 2500)),
        frag1Start,
      );
    });

    test('au-delà du converti → dernier fragment', () async {
      final fx = _Fixture();
      final idx = Fmp4Index();
      await idx.update(fx.all.length, fx.readerFor(fx.all.length));
      final int frag2Start =
          fx.ftyp.length + fx.moov.length + fx.frags[0].length + fx.frags[1].length;
      expect(idx.byteOffsetForPosition(const Duration(minutes: 5)), frag2Start);
    });
  });

  group('Fmp4Index — la liste HLS', () {
    test('EVENT, avec MAP, sans ENDLIST tant que ça convertit', () async {
      final fx = _Fixture();
      final idx = Fmp4Index();
      await idx.update(fx.all.length, fx.readerFor(fx.all.length));
      final m3u8 = idx.hlsEventPlaylist(done: false);
      expect(m3u8, startsWith('#EXTM3U\n'));
      expect(m3u8, contains('#EXT-X-PLAYLIST-TYPE:EVENT'));
      expect(m3u8, contains('#EXT-X-MAP:URI="init.mp4"'));
      // La durée max réelle est 3 s (2 s puis 3 s) : c'est ce qu'on annonce,
      // pas un plancher confortable — le lecteur y cale ses rechargements.
      expect(m3u8, contains('#EXT-X-TARGETDURATION:3'));
      expect(m3u8, contains('#EXTINF:2.000,\nseg/0.m4s'));
      expect(m3u8, contains('#EXTINF:3.000,\nseg/1.m4s'));
      expect(m3u8, isNot(contains('seg/2.m4s')));
      expect(m3u8, isNot(contains('#EXT-X-ENDLIST')));
    });

    test('ENDLIST et dernier segment une fois la conversion finie', () async {
      final fx = _Fixture();
      final idx = Fmp4Index();
      await idx.update(fx.all.length, fx.readerFor(fx.all.length));
      final m3u8 = idx.hlsEventPlaylist(done: true);
      expect(m3u8, contains('seg/2.m4s'));
      expect(m3u8, endsWith('#EXT-X-ENDLIST\n'));
    });

    test('liste valide même sans aucun segment', () async {
      final idx = Fmp4Index();
      final m3u8 = idx.hlsEventPlaylist(done: false);
      expect(m3u8, contains('#EXT-X-MAP'));
      expect(m3u8, isNot(contains('#EXTINF')));
    });

    test('les adresses de segments sont paramétrables', () async {
      final fx = _Fixture();
      final idx = Fmp4Index();
      await idx.update(fx.all.length, fx.readerFor(fx.all.length));
      final m3u8 = idx.hlsEventPlaylist(
        done: true,
        initUri: 'i.mp4',
        segmentUri: (i) => 's$i.m4s',
      );
      expect(m3u8, contains('URI="i.mp4"'));
      expect(m3u8, contains('\ns0.m4s\n'));
    });
  });
}
