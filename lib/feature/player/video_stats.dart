import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/quality_scale.dart';

/// §videoStats — Ce que mpv décode RÉELLEMENT, à un instant donné.
///
/// Outil de diagnostic avant tout : sans lui, une lecture 4K qui rame ne laisse
/// que des hypothèses (cf. §video4k). Toutes les valeurs sont nullables — un
/// flux qui vient de démarrer, ou un build sans accès aux propriétés mpv, n'en
/// remplit qu'une partie.
@immutable
class VideoStatsSnapshot {
  /// Résolution DÉCODÉE, sans correction de ratio de pixel.
  final int? width;
  final int? height;

  /// Résolution d'AFFICHAGE = décodée corrigée du ratio de pixel.
  ///
  /// ⚠️ Un écart avec [width]/[height] signifie des **pixels non carrés**
  /// (source anamorphique), PAS un redimensionnement de la texture de sortie.
  /// C'est une nuance qui compte pour §video4k : voir cet écart et conclure
  /// « ça downscale » serait une fausse piste.
  final int? displayWidth;
  final int? displayHeight;

  /// Ratio de pixel. ≠ 1 ⇒ source anamorphique (explique l'écart ci-dessus).
  final double? pixelAspectRatio;

  final String? pixelFormat;

  /// Format de pixel matériel. Renseigné uniquement quand le décodage passe
  /// par le GPU — c'est la corroboration de [hwdec].
  final String? hwPixelFormat;

  /// Décodeur matériel réellement retenu par mpv (`hwdec-current`).
  /// `no` (ou vide) = décodage **logiciel** : en 4K, stutter quasi garanti.
  final String? hwdec;

  final String? codec;
  final String? decoder;

  /// fps annoncé par le conteneur (ce qu'il FAUDRAIT tenir).
  final double? containerFps;

  /// fps réellement rendu (`estimated-vf-fps`) — ce qu'on tient vraiment.
  final double? renderedFps;

  /// Débit vidéo instantané, en bits/s.
  final int? videoBitrate;

  /// Images jetées à l'affichage (on n'arrive pas à suivre le rythme).
  final int? droppedFrames;

  /// Images jetées par le décodeur lui-même (encore plus grave).
  final int? decoderDroppedFrames;

  /// Pic lumineux signalé par la source (> 1 ⇒ contenu HDR).
  final double? signalPeak;
  final String? primaries;

  const VideoStatsSnapshot({
    this.width,
    this.height,
    this.displayWidth,
    this.displayHeight,
    this.pixelAspectRatio,
    this.pixelFormat,
    this.hwPixelFormat,
    this.hwdec,
    this.codec,
    this.decoder,
    this.containerFps,
    this.renderedFps,
    this.videoBitrate,
    this.droppedFrames,
    this.decoderDroppedFrames,
    this.signalPeak,
    this.primaries,
  });

  /// Le décodage passe-t-il par le matériel ?
  ///
  /// mpv répond littéralement « no » quand il est retombé en logiciel — un
  /// simple test de nullité passerait donc à côté du cas qu'on cherche.
  bool get hardwareDecoding {
    final h = hwdec?.trim().toLowerCase();
    if (h == null || h.isEmpty) return false;
    return h != 'no' && h != 'none' && h != 'null';
  }

  /// Source anamorphique (pixels non carrés).
  bool get isAnamorphic {
    final par = pixelAspectRatio;
    if (par == null) return false;
    return (par - 1.0).abs() > 0.01;
  }

  /// Le rendu décroche-t-il du rythme annoncé ?
  ///
  /// Marge de 10 % : `estimated-vf-fps` est une moyenne glissante qui oscille
  /// naturellement de quelques dixièmes, un seuil strict crierait au loup en
  /// permanence.
  bool get isDroppingRate {
    final target = containerFps;
    final actual = renderedFps;
    if (target == null || actual == null || target <= 0) return false;
    return actual < target * 0.9;
  }

  bool get hasDroppedFrames =>
      (droppedFrames ?? 0) > 0 || (decoderDroppedFrames ?? 0) > 0;

  /// Résolution telle qu'on l'affiche : « 3840×2160 ».
  String? get resolutionLabel =>
      (width != null && height != null) ? '$width×$height' : null;

  /// Étiquette courte de la définition (4K / FHD / HD / SD), pour lire d'un
  /// coup d'œil ce qui est VRAIMENT décodé — un flux annoncé 4K qui affiche
  /// « FHD » ici, c'est la source qui ment, pas le lecteur.
  String? get definitionLabel {
    final h = height;
    if (h == null || h <= 0) return null;
    return QualityScale.labelForHeight(h);
  }

  /// §qualityTruth — Confronte la qualité ANNONCÉE par la liste (parsing du
  /// titre, `TitleMetadata.quality`) à ce qui est RÉELLEMENT décodé.
  QualityVerdict verdictFor(String? announced) =>
      QualityScale.compare(announced, definitionLabel);

  /// Résumé sur une ligne des seuls champs qui orientent un diagnostic.
  ///
  /// Sert de **clé de changement** pour le journal §tvLogs : la TV n'a pas de
  /// logcat, mais elle a la console web — encore faut-il n'y écrire qu'aux
  /// moments utiles. Le débit et les compteurs de pertes en sont volontairement
  /// exclus : ils bougent en permanence et noieraient le journal.
  String get diagnosticSignature => [
        hardwareDecoding ? 'hw=${hwdec ?? "?"}' : 'hw=NON (logiciel)',
        'codec=${codec ?? "?"}',
        'res=${resolutionLabel ?? "?"}',
        'fps=${containerFps?.toStringAsFixed(1) ?? "?"}',
        if (isAnamorphic) 'par=${pixelAspectRatio!.toStringAsFixed(2)}',
        if ((signalPeak ?? 0) > 1.0) 'hdr',
      ].join(' · ');

  /// §video4kTrace — Les deux chiffres qui décrivent le SYMPTÔME, à part.
  ///
  /// ⚠️ Ils ne peuvent pas rejoindre [diagnosticSignature] : celle-ci sert de
  /// clé de dédoublonnage (`if (signature != _loggedSignature)`), et une valeur
  /// qui bouge à chaque tick la ferait écrire une fois par seconde — le journal
  /// se noierait au lieu d'informer.
  ///
  /// Pourquoi ils sont indispensables : sur la box, le journal §tvLogs est le
  /// SEUL canal (pas de logcat). Sans eux, un utilisateur qui rapporte « une
  /// image toutes les X secondes » n'a rien dans le journal qui le montre — le
  /// symptôme reste invisible à celui qui doit le corriger.
  String get dynamicSignature {
    final target = containerFps;
    final actual = renderedFps;
    final rendu = (target != null && actual != null)
        ? '${actual.toStringAsFixed(1)}/${target.toStringAsFixed(1)} img/s'
        : (actual?.toStringAsFixed(1) ?? '?');
    return [
      'rendu=$rendu',
      'perdues=${droppedFrames ?? 0}',
      if ((decoderDroppedFrames ?? 0) > 0) 'décodeur=$decoderDroppedFrames',
      if (bitrateLabel != null) 'débit=$bitrateLabel',
      if (isDroppingRate) 'DÉCROCHE',
    ].join(' · ');
  }

  /// Débit lisible : « 18,4 Mb/s ».
  String? get bitrateLabel {
    final b = videoBitrate;
    if (b == null || b <= 0) return null;
    if (b >= 1000000) {
      return '${(b / 1000000).toStringAsFixed(1).replaceAll('.', ',')} Mb/s';
    }
    return '${(b / 1000).round()} kb/s';
  }
}

/// §videoStats — Lit un instantané des paramètres vidéo.
abstract final class VideoStatsReader {
  /// Une lecture complète : l'état media_kit (synchrone) + les propriétés que
  /// seul mpv connaît (asynchrones).
  ///
  /// Best-effort de bout en bout : toute propriété absente reste `null` plutôt
  /// que de faire échouer l'instantané entier — un overlay de diagnostic qui
  /// disparaît au premier flux exotique ne diagnostique rien.
  static Future<VideoStatsSnapshot> read(Player player) async {
    final params = player.state.videoParams;
    final track = player.state.track.video;

    String? hwdec;
    double? renderedFps;
    double? containerFps;
    int? bitrate;
    int? dropped;
    int? decoderDropped;

    final platform = player.platform;
    if (platform is NativePlayer) {
      Future<String?> prop(String name) async {
        try {
          final v = await platform.getProperty(name);
          return v.isEmpty ? null : v;
        } catch (_) {
          return null;
        }
      }

      // En parallèle : 6 allers-retours natifs séquentiels tiendraient mal la
      // cadence d'une seconde sur une box déjà en difficulté.
      final values = await Future.wait([
        prop('hwdec-current'),
        prop('estimated-vf-fps'),
        prop('container-fps'),
        prop('video-bitrate'),
        prop('frame-drop-count'),
        prop('decoder-frame-drop-count'),
      ]);
      hwdec = values[0];
      renderedFps = double.tryParse(values[1] ?? '');
      containerFps = double.tryParse(values[2] ?? '');
      bitrate = double.tryParse(values[3] ?? '')?.round();
      dropped = int.tryParse(values[4] ?? '');
      decoderDropped = int.tryParse(values[5] ?? '');
    }

    return VideoStatsSnapshot(
      width: params.w ?? track.w,
      height: params.h ?? track.h,
      displayWidth: params.dw,
      displayHeight: params.dh,
      pixelAspectRatio: params.par,
      pixelFormat: params.pixelformat,
      hwPixelFormat: params.hwPixelformat,
      hwdec: hwdec,
      codec: track.codec,
      decoder: track.decoder,
      // `container-fps` manque sur beaucoup de flux HLS → repli sur le fps
      // annoncé par le demuxer de la piste.
      containerFps: containerFps ?? track.fps,
      renderedFps: renderedFps,
      videoBitrate: bitrate ?? track.bitrate,
      droppedFrames: dropped,
      decoderDroppedFrames: decoderDropped,
      signalPeak: params.sigPeak,
      primaries: params.primaries,
    );
  }
}

/// §videoStats — Interrupteur de l'overlay, mémorisé d'une lecture à l'autre.
///
/// Persistant **par choix** : sur TV il n'y a pas de logcat (§tvLogs), et un
/// diagnostic se fait sur plusieurs films d'affilée. Le remettre à zéro à
/// chaque lecture obligerait à replonger dans les menus entre deux essais.
///
/// ⚠️ Comme `VideoFitPreference`, délibérément **hors de `PerfConfig`** : ce
/// n'est ni un réglage de performance ni une préférence de fond, et ça n'a
/// rien à faire dans les presets ni dans les backups `.aether`.
abstract final class VideoStatsPreference {
  static const _key = 'player_video_stats_v1';

  static bool _enabled = false;

  static bool get enabled => _enabled;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_key) ?? false;
      if (_enabled) debugPrint('🔍 §videoStats — overlay actif');
    } catch (e) {
      debugPrint('⚠️ §videoStats — lecture impossible : $e');
    }
  }

  static void set(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool(_key, value))
        .catchError((e) {
      debugPrint('⚠️ §videoStats — écriture impossible : $e');
      return false;
    });
  }
}
