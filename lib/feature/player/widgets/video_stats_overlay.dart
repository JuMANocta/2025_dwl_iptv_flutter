import 'dart:async';

import 'package:flutter/material.dart';
import '../playback_engine.dart';

import '../../../core/themes/colors.dart';
import '../../../data/models/quality_scale.dart';
import '../video_render.dart';
import '../video_stats.dart';

/// §videoStats — Encart de diagnostic vidéo, en direct par-dessus l'image.
///
/// Répond à une question que rien d'autre ne sait poser sur TV (pas de
/// logcat, cf. §tvLogs) : **qu'est-ce que mpv décode vraiment ?** Décodage
/// matériel ou logiciel, résolution réelle, fps tenu contre fps annoncé,
/// images perdues. C'est le préalable posé par la roadmap avant de toucher au
/// décodeur pour §video4k — on mesure d'abord.
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
      // ⚠️ Le PREMIER décrochage est écrit tout de suite, sans attendre le
      // prochain palier : c'est l'instant qui intéresse, et il peut précéder
      // un plantage — auquel cas la ligne suivante n'arrivera jamais.
      final firstDrop = !_loggedDrop && (stats.isDroppingRate || stats.hasDroppedFrames);
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
    // « la box n'y arrive pas » et « mpv décode en logiciel ».
    // §hwdecUnknown — Tant que mpv n'a pas répondu (1 à 3 s au démarrage de
    // CHAQUE lecture), on n'affirme rien. Afficher « LOGICIEL » en rouge dans
    // cette fenêtre était une fausse alerte systématique, sur la ligne même
    // dont dépend tout le diagnostic §video4k.
    final hw = s.hardwareDecoding;
    rows.add(_StatRow(
      label: 'Décodage',
      value: !s.hwdecKnown
          ? 'en cours…'
          : (hw ? 'matériel · ${s.hwdec}' : 'LOGICIEL'),
      valueColor: !s.hwdecKnown ? null : (hw ? kSuccess : kError),
      alert: s.hwdecKnown && !hw,
    ));

    // §video4kBench — La sortie effectivement retenue par mpv. Elle suit
    // « Décodage » parce que les deux décrivent le même chemin : le relevé
    // §video4k a montré que le défaut y met `mediacodec-copy`, c'est-à-dire une
    // copie mémoire par image. Affichée seulement quand le banc d'essai est
    // actif ou qu'un mode direct est en place — sinon c'est du bruit pour
    // quelqu'un qui regarde juste un film.
    if (s.vo != null && (VideoRenderPreference.isOverridden || s.vo == 'mediacodec_embed')) {
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

    if (s.isAnamorphic && s.displayWidth != null && s.displayHeight != null) {
      // Affiché SEULEMENT si les pixels sont non carrés : sinon la ligne
      // répéterait la résolution et laisserait croire à un redimensionnement.
      rows.add(_StatRow(
        label: 'Affichée',
        value: '${s.displayWidth}×${s.displayHeight}'
            '  (pixels ${s.pixelAspectRatio!.toStringAsFixed(2)})',
      ));
    }
    final pixelFormat = s.hwPixelFormat ?? s.pixelFormat;
    if (pixelFormat != null) {
      rows.add(_StatRow(label: 'Pixels', value: pixelFormat));
    }
    if ((s.signalPeak ?? 0) > 1.0) {
      rows.add(_StatRow(
        label: 'HDR',
        value: s.primaries ?? 'oui',
        valueColor: kAccentSecondary,
      ));
    }

    // ── Fluidité ─────────────────────────────────────────────────────────────
    final rendered = s.renderedFps;
    final target = s.containerFps;
    if (rendered != null || target != null) {
      final left = rendered?.toStringAsFixed(1) ?? '—';
      final right = target?.toStringAsFixed(1) ?? '—';
      rows.add(_StatRow(
        label: 'Images/s',
        value: '$left / $right',
        valueColor: s.isDroppingRate ? kError : null,
        alert: s.isDroppingRate,
      ));
    }
    if (s.hasDroppedFrames) {
      final display = s.droppedFrames ?? 0;
      final decoder = s.decoderDroppedFrames ?? 0;
      rows.add(_StatRow(
        label: 'Perdues',
        value: decoder > 0 ? '$display  (décodeur $decoder)' : '$display',
        valueColor: kWarning,
        alert: true,
      ));
    }

    // §video4kBench — Le plafond de l'affichage. Sans lui, « 16 img/s tenus »
    // ne dit pas si c'est la source ou l'écran qui borne.
    final dfps = s.displayFps;
    if (dfps != null && dfps > 0) {
      rows.add(_StatRow(label: 'Écran', value: '${dfps.toStringAsFixed(0)} Hz'));
    }

    final bitrate = s.bitrateLabel;
    if (bitrate != null) {
      rows.add(_StatRow(label: 'Débit', value: bitrate));
    }

    // Dérive A/V : la seule façon de voir le prix d'un `video-sync` allégé.
    final av = s.avSync;
    if (av != null) {
      final drift = av.abs() > 0.15;
      rows.add(_StatRow(
        label: 'Sync A/V',
        value: '${av.toStringAsFixed(3)} s',
        valueColor: drift ? kWarning : null,
        alert: drift,
      ));
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
