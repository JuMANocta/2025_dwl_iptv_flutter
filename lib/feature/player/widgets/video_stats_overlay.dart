import 'dart:async';

import 'package:flutter/material.dart';
import '../playback_engine.dart';

import '../../../core/themes/colors.dart';
import '../../../data/models/quality_scale.dart';
import '../video_stats.dart';

/// §videoStats — Encart de diagnostic vidéo, en direct par-dessus l'image.
///
/// Répond à une question que rien d'autre ne sait poser sur TV (pas de
/// logcat, cf. §tvLogs) : **qu'est-ce que le moteur (Media3/ExoPlayer) décode
/// vraiment ?** Décodage matériel ou logiciel, résolution réelle, HDR confirmé
/// ou non, images perdues. Né pour §video4k, dont la leçon reste la règle
/// ici : on mesure d'abord, on ne touche au décodeur qu'ensuite.
///
/// ⚠️ **Il ne doit pas fausser ce qu'il mesure** : rafraîchissement à 1 Hz,
/// isolé dans un [RepaintBoundary], et jamais deux lectures concourantes
/// (`_reading`). Un overlay qui coûterait cher pendant une lecture 4K déjà en
/// difficulté rendrait ses propres chiffres suspects.
class VideoStatsOverlay extends StatefulWidget {
  final AetherPlaybackEngine player;

  /// Masqué en mode lock, comme les autres surcouches du lecteur.
  final bool hidden;

  /// §qualityTruth — Qualité ANNONCÉE par la liste pour ce flux
  /// (`TitleMetadata.quality`, telle qu'affichée sur la vignette).
  ///
  /// C'est elle qui donne son intérêt principal à l'encart : beaucoup de
  /// fournisseurs vendent du « 4K » et servent du 1080p. Sans cette
  /// confrontation, l'utilisateur n'a aucun moyen de le savoir.
  final String? announcedQuality;

  const VideoStatsOverlay({
    super.key,
    required this.player,
    this.hidden = false,
    this.announcedQuality,
  });

  @override
  State<VideoStatsOverlay> createState() => _VideoStatsOverlayState();
}

class _VideoStatsOverlayState extends State<VideoStatsOverlay> {
  static const _period = Duration(seconds: 1);

  Timer? _timer;
  VideoStatsSnapshot? _stats;

  /// Garde de ré-entrance : sur une box lente, une lecture peut dépasser la
  /// seconde. Sans elle, les tics s'empileraient jusqu'à saturer le canal
  /// natif — exactement le coût qu'on veut éviter.
  bool _reading = false;

  /// Dernière signature journalisée — on n'écrit dans le journal que sur
  /// CHANGEMENT, pas à chaque tic.
  String? _loggedSignature;

  /// §video4kTrace — Dernière écriture des chiffres dynamiques, et mémoire du
  /// décrochage déjà signalé.
  DateTime? _lastDynamicLog;
  bool _loggedDrop = false;
  static const Duration _dynamicPeriod = Duration(seconds: 10);

  /// §qualityTruth — Un flux ne se fait épingler qu'UNE fois par lecture :
  /// la ligne intéresse, sa répétition à chaque changement de débit non.
  bool _loggedVerdict = false;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(_period, (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    if (_reading || !mounted) return;
    _reading = true;
    try {
      final stats = await widget.player.readStats();
      if (!mounted) return;
      // §tvLogs — La TV n'a pas de logcat : tant que l'encart est actif, ce
      // qu'il affiche part aussi dans le journal, lisible depuis la console
      // web sur le téléphone. Bien plus confortable que de relever des
      // chiffres à l'œil sur un téléviseur, et ça laisse une trace datée.
      final signature = stats.diagnosticSignature;
      if (signature != _loggedSignature) {
        _loggedSignature = signature;
        debugPrint('🔍 §videoStats — $signature');
      }
      // §qualityTruth — Une liste qui survend laisse une trace datée dans le
      // journal : c'est ce qui permet, après coup, de savoir QUEL fournisseur
      // ment et sur quels titres.
      // §video4kTrace — Les chiffres qui bougent, à cadence LENTE : le rythme
      // tenu et les pertes. Une ligne toutes les 10 s suffit à voir une lecture
      // s'effondrer, sans transformer le journal en flot continu.
      final now = DateTime.now();
      final due = _lastDynamicLog == null ||
          now.difference(_lastDynamicLog!) >= _dynamicPeriod;
      // ⚠️ Les PREMIÈRES pertes sont écrites tout de suite, sans attendre le
      // prochain palier : c'est l'instant qui intéresse, et il peut précéder
      // un plantage — auquel cas la ligne suivante n'arrivera jamais.
      final firstDrop = !_loggedDrop && stats.hasDroppedFrames;
      if (due || firstDrop) {
        _lastDynamicLog = now;
        if (firstDrop) _loggedDrop = true;
        debugPrint('📉 §videoStats — ${stats.dynamicSignature}');
      }
      if (!_loggedVerdict &&
          stats.verdictFor(widget.announcedQuality) ==
              QualityVerdict.survendu) {
        _loggedVerdict = true;
        debugPrint('⚠️ §qualityTruth — annoncé ${widget.announcedQuality}, '
            'réel ${stats.definitionLabel} (${stats.resolutionLabel})');
      }
      setState(() => _stats = stats);
    } catch (_) {
      // Best-effort : on garde le dernier instantané valide.
    } finally {
      _reading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    if (widget.hidden || stats == null) return const SizedBox.shrink();

    return Positioned(
      // Sous la barre haute des contrôles (retour + titre) pour ne pas la
      // recouvrir quand ils sont visibles.
      top: MediaQuery.of(context).padding.top + 56,
      left: 12,
      child: RepaintBoundary(
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(170),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kAccentPrimary.withAlpha(90)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _rows(stats),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _rows(VideoStatsSnapshot s) {
    final rows = <Widget>[];

    // ── Décodage : LA ligne du ticket §video4k ───────────────────────────────
    // Elle est en tête et colorée parce qu'elle tranche à elle seule entre
    // « la box n'y arrive pas » et « le moteur décode en logiciel ».
    // §hwdecUnknown — Tant que le moteur n'a pas répondu (sous Media3,
    // `hardware` reste nul tant que l'AnalyticsListener n'a pas vu de décodeur
    // s'initialiser — au démarrage de CHAQUE lecture), on n'affirme rien.
    // Afficher « LOGICIEL » en rouge dans cette fenêtre était une fausse
    // alerte systématique, sur la ligne même dont dépend tout le diagnostic.
    final hw = s.hardwareDecoding;
    rows.add(_StatRow(
      label: 'Décodage',
      value: !s.hwdecKnown
          ? 'en cours…'
          : (hw ? 'matériel · ${s.hwdec}' : 'LOGICIEL'),
      valueColor: !s.hwdecKnown ? null : (hw ? kSuccess : kError),
      alert: s.hwdecKnown && !hw,
    ));

    // §engineVendor étape 6 — La sortie vidéo. Elle était masquée hors banc
    // d'essai parce que sous mpv elle ne disait presque rien (`mediacodec-copy`
    // partout). Sous Media3 elle nomme `SurfaceView`, c'est-à-dire précisément
    // le chemin qui rend le HDR possible — l'information vaut d'être montrée.
    if (s.vo != null) {
      rows.add(_StatRow(label: 'Sortie', value: s.vo!));
    }

    if (s.codec != null) {
      final decoder = s.decoder;
      rows.add(_StatRow(
        label: 'Codec',
        value: decoder == null || decoder == s.codec
            ? s.codec!
            : '${s.codec} · $decoder',
      ));
    }

    // ── Image ────────────────────────────────────────────────────────────────
    final resolution = s.resolutionLabel;
    if (resolution != null) {
      final def = s.definitionLabel;
      rows.add(_StatRow(
        label: 'Résolution',
        value: def == null ? resolution : '$resolution  ($def)',
      ));
    }
    // §qualityTruth — LA ligne : ce que la liste promet, face au réel.
    // Placée juste sous la résolution pour qu'on lise l'écart d'un seul coup
    // d'œil, sans avoir à se souvenir de ce qu'affichait la vignette.
    final verdict = s.verdictFor(widget.announcedQuality);
    if (verdict != QualityVerdict.unknown) {
      final announced = widget.announcedQuality!.trim().toUpperCase();
      switch (verdict) {
        case QualityVerdict.conforme:
          rows.add(_StatRow(
            label: 'Annoncé',
            value: '$announced · conforme',
            valueColor: kSuccess,
          ));
        case QualityVerdict.survendu:
          rows.add(_StatRow(
            label: 'Annoncé',
            value: '$announced — la liste SURVEND',
            valueColor: kError,
            alert: true,
          ));
        case QualityVerdict.sousEstime:
          rows.add(_StatRow(
            label: 'Annoncé',
            value: '$announced · mieux que promis',
            valueColor: kAccentSecondary,
          ));
        case QualityVerdict.unknown:
          break;
      }
    }

    // §tourFix — Ce que Media3 SAIT du HDR (transfert HLG/ST2084), tri-état :
    // oui / non / « — » quand `colorInfo` est absent. L'ancienne astuce
    // `signalPeak: 2.0` posée en dur ne laissait à cette ligne qu'une seule
    // réponse possible — elle affichait TOUJOURS « oui ».
    rows.add(_StatRow(
      label: 'HDR',
      value: s.hdr == null ? '—' : (s.hdr! ? 'oui' : 'non'),
      valueColor: s.hdr == true ? kAccentSecondary : null,
    ));

    // ── Fluidité ─────────────────────────────────────────────────────────────
    // §tourFix — fps du CONTENEUR uniquement : Media3 ne publie pas d'images/s
    // réellement rendues, et l'ancien « — / X » laissait lire l'absence de
    // mesure comme une mesure.
    final target = s.containerFps;
    if (target != null) {
      rows.add(_StatRow(label: 'Images/s', value: target.toStringAsFixed(1)));
    }
    if (s.hasDroppedFrames) {
      rows.add(_StatRow(
        label: 'Perdues',
        value: '${s.droppedFrames ?? 0}',
        valueColor: kWarning,
        alert: true,
      ));
    }

    final bitrate = s.bitrateLabel;
    if (bitrate != null) {
      rows.add(_StatRow(label: 'Débit', value: bitrate));
    }

    return rows;
  }
}

/// Une ligne « libellé : valeur » de l'encart.
class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  /// Ajoute un ⚠ devant la valeur : sur un téléviseur regardé de loin, la
  /// couleur seule ne suffit pas à faire ressortir une anomalie.
  final bool alert;

  const _StatRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.alert = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withAlpha(150),
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Text(
            alert ? '⚠ $value' : value,
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
