/// §castRelay — Index incrémental d'un **MP4 fragmenté en cours d'écriture**,
/// et sa présentation en liste HLS.
///
/// **Le problème qu'il résout** : le téléphone convertit un film pendant que
/// le téléviseur le lit. Servir le fichier « qui grossit » d'un seul tenant
/// (mesuré le 2026-09-04) donne au récepteur un flux dont il ne connaît ni la
/// taille ni la durée : il a affiché **00:02** — la durée du premier fragment —
/// et n'a jamais avancé. Un fichier progressif n'a pas de mot pour dire « il y
/// en aura d'autres ».
///
/// HLS en a un : une liste **EVENT**, qui s'allonge à chaque rechargement et
/// se termine par `#EXT-X-ENDLIST` quand la conversion est finie. Le récepteur
/// sait exactement quoi en faire — c'est son mode de fonctionnement pour un
/// direct. Chaque segment est un couple `moof`+`mdat` **complet** du fichier,
/// désigné par ses octets exacts : on ne sert jamais rien d'à moitié écrit.
///
/// ⚠️ **Un segment n'est publié que lorsque le SUIVANT a commencé** : sa durée
/// se déduit de l'écart entre deux `tfdt` (temps de décodage de base). La
/// seule exception est la fin de la conversion, où le dernier segment prend
/// la durée du précédent — c'est le seul chiffre approximatif de toute la
/// liste, et il ne concerne que les dernières secondes du film.
///
/// Zéro dépendance : lecture d'octets par une fonction fournie, donc testable
/// sur un tampon en mémoire (`test/fmp4_index_test.dart`).
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Lit `length` octets à partir de `offset`. Peut rendre moins si le fichier
/// est plus court — l'index s'en aperçoit et attend.
typedef ByteReader = Future<Uint8List> Function(int offset, int length);

/// Un couple `moof`+`mdat` complet, avec sa durée.
class Fmp4Segment {
  const Fmp4Segment({
    required this.start,
    required this.end,
    required this.duration,
  });

  /// Offset du `moof` (inclus).
  final int start;

  /// Fin du `mdat` (exclue).
  final int end;

  final Duration duration;

  int get length => end - start;
}

class _Frag {
  _Frag({required this.start, required this.tfdt, required this.trackId});
  final int start;
  final int tfdt;
  final int trackId;
  int? end;
}

class Fmp4Index {
  Fmp4Index({this.fallbackSegment = const Duration(seconds: 2)});

  /// Durée supposée d'un segment quand rien ne permet de la calculer.
  final Duration fallbackSegment;

  int? _initEnd;
  int _scanned = 0;
  int? _videoTrackId;
  final Map<int, int> _timescales = <int, int>{};
  final List<_Frag> _frags = <_Frag>[];
  _Frag? _pendingMoof;

  /// Fin du segment d'initialisation (`ftyp`+`moov`), `null` tant que le
  /// `moov` n'est pas entièrement écrit.
  int? get initEnd => _initEnd;

  bool get hasInit => _initEnd != null;

  /// Fragments complets vus jusqu'ici (publiés ou non).
  int get fragmentCount => _frags.length;

  /// Avance l'index sur les octets `[0, available)` désormais présents.
  /// Idempotent : rappeler avec la même valeur ne fait rien.
  Future<void> update(int available, ByteReader read) async {
    while (true) {
      if (available - _scanned < 8) return;
      final Uint8List head =
          await read(_scanned, math.min(16, available - _scanned));
      if (head.length < 8) return;
      final _BoxHeader? h = _header(head);
      // « jusqu'à la fin » ou en-tête tronqué : on attend.
      if (h == null) return;
      final int end = _scanned + h.size;
      if (end > available) return; // box incomplète : on attend la suite
      final int payload = _scanned + h.headerLength;
      switch (h.type) {
        case 'moov':
          await _parseMoov(payload, end, read);
          _initEnd = end;
        case 'moof':
          _pendingMoof = await _parseMoof(_scanned, payload, end, read);
        case 'mdat':
          final _Frag? p = _pendingMoof;
          if (p != null) {
            p.end = end;
            _frags.add(p);
            _pendingMoof = null;
          }
        default:
          // ftyp, sidx, mfra, free… : rien à en tirer.
          break;
      }
      _scanned = end;
    }
  }

  /// Les segments publiables. Sans [done], le dernier fragment attend son
  /// successeur (sa durée est inconnue) ; avec [done], il prend la durée du
  /// précédent.
  List<Fmp4Segment> segments({required bool done}) {
    final out = <Fmp4Segment>[];
    for (int i = 0; i < _frags.length; i++) {
      final _Frag f = _frags[i];
      final int? end = f.end;
      if (end == null) break;
      Duration d;
      if (i + 1 < _frags.length) {
        final _Frag n = _frags[i + 1];
        final int? ts = _timescales[f.trackId];
        if (ts != null && ts > 0 && n.trackId == f.trackId && n.tfdt > f.tfdt) {
          d = Duration(
            microseconds: ((n.tfdt - f.tfdt) * 1000000 / ts).round(),
          );
        } else {
          d = out.isNotEmpty ? out.last.duration : fallbackSegment;
        }
      } else if (done) {
        d = out.isNotEmpty ? out.last.duration : fallbackSegment;
      } else {
        break;
      }
      out.add(Fmp4Segment(start: f.start, end: end, duration: d));
    }
    return out;
  }

  /// §castRelay — Octet du fragment à lire pour reprendre à [pos]. L'init
  /// (`0..initEnd`) doit être envoyé AVANT, séparément — ceci ne rend que
  /// le début du fragment couvrant [pos]. Position nulle → premier
  /// fragment. Au-delà du converti → dernier fragment (on reprend au plus
  /// près et le flux continue).
  int byteOffsetForPosition(Duration pos) {
    final int base = _initEnd ?? 0;
    if (pos <= Duration.zero) return base;
    final List<Fmp4Segment> segs = segments(done: true);
    if (segs.isEmpty) return base;
    Duration cum = Duration.zero;
    for (final Fmp4Segment s in segs) {
      if (cum + s.duration > pos) return s.start;
      cum += s.duration;
    }
    return segs.last.start;
  }

  /// Durée totale déjà publiable.
  Duration readyDuration({required bool done}) => segments(done: done)
      .fold(Duration.zero, (Duration acc, Fmp4Segment s) => acc + s.duration);

  /// La liste HLS de type EVENT. [segmentUri] rend l'adresse relative du
  /// segment `i` ; [initUri] celle du segment d'initialisation.
  String hlsEventPlaylist({
    required bool done,
    String initUri = 'init.mp4',
    String Function(int index)? segmentUri,
  }) {
    final String Function(int) seg = segmentUri ?? (int i) => 'seg/$i.m4s';
    final List<Fmp4Segment> segs = segments(done: done);
    double maxSec = 0;
    for (final s in segs) {
      maxSec = math.max(maxSec, s.duration.inMilliseconds / 1000);
    }
    // ⚠️ **TARGETDURATION doit être la durée MAXIMALE réelle d'un segment**,
    // arrondie à l'entier supérieur (RFC 8216 §4.3.3.1). Première version :
    // un plancher à 10 s « pour la stabilité » — c'était une faute. Le lecteur
    // s'en sert pour calculer son rythme de rechargement : annoncer 10 s avec
    // des segments de 2 s le fait attendre cinq fois trop longtemps, donc
    // manquer de données en permanence.
    final int target = math.max(1, maxSec.ceil());
    final b = StringBuffer()
      ..writeln('#EXTM3U')
      ..writeln('#EXT-X-VERSION:7')
      ..writeln('#EXT-X-TARGETDURATION:$target')
      ..writeln('#EXT-X-MEDIA-SEQUENCE:0')
      ..writeln('#EXT-X-PLAYLIST-TYPE:EVENT')
      // Pas d'`EXT-X-INDEPENDENT-SEGMENTS` : ce serait AFFIRMER que chaque
      // segment commence par une image clé. Le muxeur coupe bien sur les
      // images clés, mais on ne le vérifie pas — et une affirmation fausse
      // dans un manifeste casse la lecture plus sûrement qu'une absence.
      ..writeln('#EXT-X-MAP:URI="$initUri"');
    for (int i = 0; i < segs.length; i++) {
      final String d =
          (segs[i].duration.inMilliseconds / 1000).toStringAsFixed(3);
      b
        ..writeln('#EXTINF:$d,')
        ..writeln(seg(i));
    }
    if (done) b.writeln('#EXT-X-ENDLIST');
    return b.toString();
  }

  // ── Boîtes ──────────────────────────────────────────────────────────────

  _BoxHeader? _header(Uint8List head) {
    final ByteData bd = ByteData.sublistView(head);
    int size = bd.getUint32(0);
    final String type = String.fromCharCodes(head, 4, 8);
    int headerLength = 8;
    if (size == 1) {
      if (head.length < 16) return null;
      size = bd.getUint64(8);
      headerLength = 16;
    } else if (size == 0) {
      return null;
    }
    if (size < headerLength) return null;
    return _BoxHeader(type: type, size: size, headerLength: headerLength);
  }

  /// Parcourt les boîtes filles de `[start, end)`.
  Future<void> _forEachChild(
    int start,
    int end,
    ByteReader read,
    Future<void> Function(String type, int payload, int boxEnd) visit,
  ) async {
    int off = start;
    while (end - off >= 8) {
      final Uint8List head = await read(off, math.min(16, end - off));
      if (head.length < 8) return;
      final ByteData bd = ByteData.sublistView(head);
      int size = bd.getUint32(0);
      final String type = String.fromCharCodes(head, 4, 8);
      int headerLength = 8;
      if (size == 1) {
        if (head.length < 16) return;
        size = bd.getUint64(8);
        headerLength = 16;
      } else if (size == 0) {
        size = end - off;
      }
      final int boxEnd = off + size;
      if (size < headerLength || boxEnd > end) return;
      await visit(type, off + headerLength, boxEnd);
      off = boxEnd;
    }
  }

  Future<void> _parseMoov(int start, int end, ByteReader read) async {
    await _forEachChild(start, end, read, (type, payload, boxEnd) async {
      if (type != 'trak') return;
      int? trackId;
      int? timescale;
      String? handler;
      await _forEachChild(payload, boxEnd, read, (t, p, e) async {
        if (t == 'tkhd') {
          final Uint8List b = await read(p, math.min(24, e - p));
          if (b.length < 16) return;
          final int version = b[0];
          final int at = version == 1 ? 20 : 12;
          if (b.length >= at + 4) {
            trackId = ByteData.sublistView(b).getUint32(at);
          }
        } else if (t == 'mdia') {
          await _forEachChild(p, e, read, (t2, p2, e2) async {
            if (t2 == 'mdhd') {
              final Uint8List b = await read(p2, math.min(24, e2 - p2));
              if (b.length < 16) return;
              final int version = b[0];
              final int at = version == 1 ? 20 : 12;
              if (b.length >= at + 4) {
                timescale = ByteData.sublistView(b).getUint32(at);
              }
            } else if (t2 == 'hdlr') {
              final Uint8List b = await read(p2, math.min(12, e2 - p2));
              if (b.length >= 12) handler = String.fromCharCodes(b, 8, 12);
            }
          });
        }
      });
      final int? id = trackId;
      if (id == null) return;
      final int? ts = timescale;
      if (ts != null) _timescales[id] = ts;
      if (handler == 'vide') _videoTrackId = id;
    });
  }

  Future<_Frag> _parseMoof(
    int boxStart,
    int payload,
    int end,
    ByteReader read,
  ) async {
    final Map<int, int> tfdtByTrack = <int, int>{};
    int? firstTrack;
    await _forEachChild(payload, end, read, (type, p, e) async {
      if (type != 'traf') return;
      int? trackId;
      int? tfdt;
      await _forEachChild(p, e, read, (t, p2, e2) async {
        if (t == 'tfhd') {
          final Uint8List b = await read(p2, math.min(8, e2 - p2));
          if (b.length >= 8) trackId = ByteData.sublistView(b).getUint32(4);
        } else if (t == 'tfdt') {
          final Uint8List b = await read(p2, math.min(12, e2 - p2));
          if (b.length < 8) return;
          final int version = b[0];
          final ByteData bd = ByteData.sublistView(b);
          tfdt = version == 1
              ? (b.length >= 12 ? bd.getUint64(4) : null)
              : bd.getUint32(4);
        }
      });
      final int? id = trackId;
      final int? t = tfdt;
      if (id != null && t != null) {
        tfdtByTrack[id] = t;
        firstTrack ??= id;
      }
    });
    final int? video = _videoTrackId;
    final int track = (video != null && tfdtByTrack.containsKey(video))
        ? video
        : (firstTrack ?? -1);
    return _Frag(
      start: boxStart,
      tfdt: tfdtByTrack[track] ?? 0,
      trackId: track,
    );
  }
}

class _BoxHeader {
  const _BoxHeader({
    required this.type,
    required this.size,
    required this.headerLength,
  });
  final String type;
  final int size;
  final int headerLength;
}
