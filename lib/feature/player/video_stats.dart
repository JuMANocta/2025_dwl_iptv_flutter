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

  /// §stallCount — Nombre de fois où la lecture s'est ARRÊTÉE pour attendre le
  /// réseau, depuis le début de la session.
  ///
  /// ⚠️ Ce n'est PAS [droppedFrames], et la nuance est tout l'intérêt : une
  /// image jetée signale que l'appareil ne suit pas ; un blocage signale que la
  /// SOURCE ne suit pas. C'est le second qui dit quel abonnement est mauvais.
  ///
  /// La mise en tampon initiale et celle qui suit un déplacement volontaire
  /// n'en font pas partie (cf. `Media3Engine`).
  final int? stalls;

  /// Temps cumulé passé bloqué, en millisecondes. 3 blocages de 0,3 s et
  /// 3 blocages de 12 s ne se vivent pas du tout pareil.
  final int? stalledMs;

  /// Délai entre l'ouverture et la première image, en millisecondes.
  final int? startupMs;

  // ── §videoStatsPlus — Ce qui est MESURÉ, par opposition à ce qui est déclaré
  //
  // Les champs ci-dessus viennent en grande partie de l'en-tête du flux : ils
  // disent ce que la source PRÉTEND servir. Ceux qui suivent sont observés à
  // l'exécution. Sur une chaîne 4K live réelle, `containerFps` et
  // `videoBitrate` étaient tous deux absents — un flux TS ne les déclare pas —
  // et l'encart n'affichait donc ni images/s ni débit.

  /// Images/s **réellement rendues**, dérivées du compteur du décodeur.
  ///
  /// ⚠️ L'écart avec [containerFps] est le symptôme cherché par §video4k :
  /// « annoncé 50, rendu 33 » dit tout, là où chacun pris seul ne dit rien.
  final double? renderedFps;

  /// Images sautées par le décodeur (distinctes de [droppedFrames], jetées à
  /// l'affichage).
  final int? skippedFrames;

  /// Débit réseau **estimé par le lecteur**, en bits/s.
  ///
  /// La mesure qui manquait le plus : [videoBitrate] est une déclaration du
  /// flux, celui-ci est un constat de ce que le fournisseur sert vraiment.
  /// Un panel qui bride se voit ici, et nulle part ailleurs.
  final int? networkBitrate;

  /// Octets réellement transférés depuis le début de la lecture.
  final int? bytesTransferred;

  /// Avance de tampon disponible.
  ///
  /// Calculée côté Dart (position mise en tampon − position lue) : c'est le
  /// témoin direct de §playerBuffer. Si elle reste collée à zéro, le tampon
  /// configuré ne se remplit jamais — la source ne suit pas.
  final Duration? bufferAhead;

  final String? audioCodec;
  final String? audioDecoder;
  final int? audioBitrate;
  final int? audioChannels;
  final int? audioSampleRate;

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
    this.stalls,
    this.stalledMs,
    this.startupMs,
    this.renderedFps,
    this.skippedFrames,
    this.networkBitrate,
    this.bytesTransferred,
    this.bufferAhead,
    this.audioCodec,
    this.audioDecoder,
    this.audioBitrate,
    this.audioChannels,
    this.audioSampleRate,
  });

  /// §videoStatsPlus — Débit réseau lisible (« 24,1 Mb/s »).
  String? get networkBitrateLabel {
    final b = networkBitrate;
    if (b == null || b <= 0) return null;
    return b >= 1000000
        ? '${(b / 1000000).toStringAsFixed(1).replaceAll('.', ',')} Mb/s'
        : '${(b / 1000).round()} kb/s';
  }

  /// Volume transféré lisible (« 1,2 Go »).
  String? get transferredLabel {
    final n = bytesTransferred;
    if (n == null || n <= 0) return null;
    const mo = 1024 * 1024;
    return n >= 1024 * mo
        ? '${(n / (1024 * mo)).toStringAsFixed(1).replaceAll('.', ',')} Go'
        : '${(n / mo).round()} Mo';
  }

  /// Piste audio lisible (« AAC · 5.1 · 48 kHz »).
  String? get audioLabel {
    final parts = <String>[];
    final c = audioCodec;
    if (c != null && c.isNotEmpty) {
      parts.add(c.replaceFirst('audio/', '').toUpperCase());
    }
    final ch = audioChannels;
    if (ch != null && ch > 0) {
      parts.add(switch (ch) {
        1 => 'mono',
        2 => 'stéréo',
        6 => '5.1',
        8 => '7.1',
        _ => '$ch canaux',
      });
    }
    final sr = audioSampleRate;
    if (sr != null && sr > 0) parts.add('${(sr / 1000).round()} kHz');
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// §stallCount — Ligne prête à afficher, ou `null` si rien n'est mesuré.
  /// Un « 0 blocage » EST une information : on l'affiche.
  String? get stallLabel {
    final n = stalls;
    if (n == null) return null;
    if (n == 0) return 'aucun';
    final s = ((stalledMs ?? 0) / 1000).round();
    return s > 0 ? '$n (${s}s au total)' : '$n';
  }

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
        // §videoStatsPlus — Le trio qui rend un « ça rame » diagnosticable :
        // ce qui est rendu, ce que le réseau sert, et ce qu'il reste d'avance.
        if (renderedFps != null && renderedFps! > 0)
          'rendu=${renderedFps!.toStringAsFixed(1)}img/s',
        if (networkBitrateLabel != null) 'réseau=$networkBitrateLabel',
        if (bufferAhead != null)
          'tampon=${(bufferAhead!.inMilliseconds / 1000).toStringAsFixed(1)}s',
        // §stallCount — Daté dans le journal, un blocage devient rattachable à
        // un moment précis (un match, une heure de pointe) au lieu d'un
        // « ça rame parfois » invérifiable.
        if (stalls != null) 'blocages=$stalls',
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
