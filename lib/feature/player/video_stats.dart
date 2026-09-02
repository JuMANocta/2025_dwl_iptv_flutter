import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/quality_scale.dart';

/// §videoStats — Ce que le moteur décode RÉELLEMENT, à un instant donné.
///
/// Outil de diagnostic avant tout : sans lui, une lecture 4K qui rame ne laisse
/// que des hypothèses (cf. §video4k — la leçon fondatrice : on mesure AVANT de
/// toucher au décodeur). Toutes les valeurs sont nullables — un flux qui vient
/// de démarrer n'en remplit qu'une partie, et un champ que le moteur ne sait
/// pas renseigner reste `null`, jamais zéro (leçon §hwdecUnknown).
///
/// ⚠️ §tourFix (2026-09-02) — Les champs que seul mpv savait remplir
/// (résolution corrigée du ratio de pixel, format de pixel, fps réellement
/// rendus, pertes décodeur, sync A/V, Hz de l'écran, primaries/signalPeak) ont
/// été retirés avec lui : Media3 ne les publie pas, et une ligne d'encart
/// éternellement vide — ou pire, « — / X » qui se lit comme une mesure — est
/// un mensonge d'interface.
@immutable
class VideoStatsSnapshot {
  /// Résolution DÉCODÉE.
  final int? width;
  final int? height;

  /// Décodage matériel réellement retenu.
  /// `no` (ou vide) = décodage **logiciel** : en 4K, stutter quasi garanti.
  ///
  /// Le nom vient du `hwdec-current` de mpv ; sous Media3 c'est le nom du
  /// décodeur MediaCodec quand il est matériel, `no` sinon, et `null` tant que
  /// l'`AnalyticsListener` n'a pas vu de décodeur s'initialiser
  /// (cf. [hwdecKnown]).
  final String? hwdec;

  final String? codec;
  final String? decoder;

  /// fps annoncé par le conteneur. (Media3 ne publie pas d'images/s réellement
  /// rendues — l'`estimated-vf-fps` de mpv n'a pas d'équivalent.)
  final double? containerFps;

  /// Débit vidéo instantané, en bits/s.
  final int? videoBitrate;

  /// Images jetées à l'affichage (on n'arrive pas à suivre le rythme).
  final int? droppedFrames;

  /// §tourFix — Le flux est-il HDR ? Déduit par le moteur du transfert de
  /// couleur (HLG/ST2084). `null` = le moteur ne SAIT pas (`colorInfo`
  /// absent). Remplace l'astuce `signalPeak > 1` héritée de mpv : poser 2.0 en
  /// dur figeait la ligne HDR de l'encart à « oui ».
  final bool? hdr;

  /// Sortie vidéo réellement active.
  ///
  /// Née pour le banc d'essai §video4kBench (`current-vo` mpv : vérifier qu'un
  /// réglage forcé était RETENU et pas silencieusement refusé). Sous Media3
  /// elle nomme le chemin de rendu — `SurfaceView` — précisément ce qui rend
  /// le HDR natif possible (§engineVendor).
  final String? vo;

  const VideoStatsSnapshot({
    this.width,
    this.height,
    this.hwdec,
    this.codec,
    this.decoder,
    this.containerFps,
    this.videoBitrate,
    this.droppedFrames,
    this.hdr,
    this.vo,
  });

  /// Le décodage passe-t-il par le matériel ?
  ///
  /// Le moteur répond littéralement « no » quand le décodage est logiciel
  /// (convention posée par mpv, conservée par `Media3Engine.readStats`) — un
  /// simple test de nullité passerait donc à côté du cas qu'on cherche.
  bool get hardwareDecoding {
    final h = hwdec?.trim().toLowerCase();
    if (h == null || h.isEmpty) return false;
    return h != 'no' && h != 'none' && h != 'null';
  }

  /// §hwdecUnknown — Le moteur a-t-il seulement RÉPONDU sur le décodage ?
  ///
  /// ⚠️ Distinction indispensable, apprise sous mpv et toujours d'actualité :
  /// au début de CHAQUE lecture la valeur est encore absente (sous Media3,
  /// `hardware` reste `null` tant que l'`AnalyticsListener` n'a pas vu de
  /// décodeur s'initialiser) — [hardwareDecoding] renvoyait alors `false` et
  /// l'encart affichait « LOGICIEL » en ROUGE avec une alerte. Sur les quatre
  /// relevés §video4k, la fausse alerte est apparue quatre fois. C'est le pire
  /// endroit possible pour se tromper : cette ligne est celle sur laquelle
  /// repose tout le diagnostic du ticket, et elle annonçait l'inverse de la
  /// réalité à qui regardait au lancement.
  ///
  /// ⚠️ Ne PAS confondre avec la réponse littérale `no`, qui elle est une vraie
  /// information (décodage logiciel confirmé) — cf. le piège déjà verrouillé
  /// par test dans [hardwareDecoding].
  bool get hwdecKnown => (hwdec?.trim().isNotEmpty) ?? false;

  bool get hasDroppedFrames => (droppedFrames ?? 0) > 0;

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
        if (!hwdecKnown)
          'hw=?'
        else if (hardwareDecoding)
          'hw=$hwdec'
        else
          'hw=NON (logiciel)',
        'codec=${codec ?? "?"}',
        'res=${resolutionLabel ?? "?"}',
        'fps=${containerFps?.toStringAsFixed(1) ?? "?"}',
        // Seulement quand le moteur le CONFIRME : `null` = il ne sait pas,
        // et un « hdr » écrit dans le doute vaudrait un faux relevé.
        if (hdr == true) 'hdr',
        // `vo` est STATIQUE pendant une lecture : sa place est ici, pas dans
        // la signature dynamique.
        if (vo != null) 'vo=$vo',
      ].join(' · ');

  /// §video4kTrace — Les chiffres qui BOUGENT, tenus à part.
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
  ///
  /// Sous mpv, on y lisait aussi le fps réellement rendu et la dérive A/V ;
  /// Media3 ne les publie pas (§tourFix). Restent les pertes et le débit —
  /// « perdues=N » suffit à dater un effondrement.
  String get dynamicSignature => [
        'perdues=${droppedFrames ?? 0}',
        if (bitrateLabel != null) 'débit=$bitrateLabel',
      ].join(' · ');

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
