import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../playback_engine.dart';

import '../../../core/themes/colors.dart';
import '../../../data/models/quality_scale.dart';
import '../video_stats.dart';
import '../../../l10n/l10n_ext.dart';

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

  /// R17 — Distance ABSOLUE entre le haut de l'écran et l'encart, encoche
  /// comprise. L'encart se posait 56 px sous l'encoche : une barre haute
  /// enrichie (série, badges, synopsis sur deux lignes) passait dessous et
  /// devenait illisible. L'appelant mesure la barre et donne le résultat ici ;
  /// ⚠️ ne pas y rajouter `MediaQuery.padding.top`, la mesure le contient déjà.
  final double topInset;

  /// §playerPanel — Distance ABSOLUE entre le BAS de l'écran et le bas de
  /// l'encart, marge du bas comprise. Contrôles visibles, l'appelant y met la
  /// hauteur MESURÉE du bloc bas (rangée d'options + barre de lecture +
  /// temps) : en paysage téléphone, les 13 lignes de l'encart descendaient
  /// jusqu'en bas de l'écran et recouvraient la rangée. L'encart ne dépasse
  /// jamais cette borne : au-delà, ses DERNIÈRES lignes sont tues, jamais
  /// coupées à mi-hauteur ([videoStatsMaxHeight]).
  final double bottomInset;

  /// §videoStatsTags — Les lignes à montrer ; `null` = toutes.
  final Set<VideoStatKey>? visibleRows;

  const VideoStatsOverlay({
    super.key,
    required this.player,
    this.hidden = false,
    this.announcedQuality,
    this.topInset = 72,
    this.bottomInset = 12,
    this.visibleRows,
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
    // §videoStatsTags — Le filtre de l'utilisateur ; tout décoché = rien.
    final Set<VideoStatKey>? shown = widget.visibleRows;
    final List<Widget> rows = _rows(stats)
        .where((w) => w is! _StatRow || shown == null || shown.contains(w.statKey))
        .toList();
    if (rows.isEmpty) return const SizedBox.shrink();

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      // Sous la barre haute des contrôles (retour + titre) pour ne pas la
      // recouvrir quand ils sont visibles (R17 : sa hauteur RÉELLE vient de
      // l'appelant, qui la mesure — encoche comprise).
      top: widget.topInset,
      left: 12,
      child: RepaintBoundary(
        child: IgnorePointer(
          // §playerPanel — Au-dessus du bloc bas des contrôles, jamais dessus.
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: videoStatsMaxHeight(
                screenHeight: MediaQuery.sizeOf(context).height,
                topInset: widget.topInset,
                bottomInset: widget.bottomInset,
              ),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(170),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kAccentPrimary.withAlpha(90)),
              ),
              child: _WholeRows(children: rows),
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
      statKey: VideoStatKey.decoding,
      label: context.l10n.statsDecoding,
      value: !s.hwdecKnown
          ? context.l10n.statsDecodingPending
          : (hw
              ? context.l10n.statsHardwareWith(s.hwdec ?? '')
              : context.l10n.statsSoftware),
      valueColor: !s.hwdecKnown ? null : (hw ? kSuccess : kError),
      alert: s.hwdecKnown && !hw,
    ));

    // §engineVendor étape 6 — La sortie vidéo. Elle était masquée hors banc
    // d'essai parce que sous mpv elle ne disait presque rien (`mediacodec-copy`
    // partout). Sous Media3 elle nomme `SurfaceView`, c'est-à-dire précisément
    // le chemin qui rend le HDR possible — l'information vaut d'être montrée.
    if (s.vo != null) {
      rows.add(_StatRow(statKey: VideoStatKey.output, label: context.l10n.statsOutput, value: s.vo!));
    }

    if (s.codec != null) {
      final decoder = s.decoder;
      rows.add(_StatRow(
        statKey: VideoStatKey.codec,
        label: context.l10n.statsCodec,
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
        statKey: VideoStatKey.resolution,
        label: context.l10n.statsResolution,
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
            statKey: VideoStatKey.announced,
            label: context.l10n.statsAnnouncedLabel,
            value: context.l10n.statsAnnouncedOk(announced),
            valueColor: kSuccess,
          ));
        case QualityVerdict.survendu:
          rows.add(_StatRow(
            statKey: VideoStatKey.announced,
            label: context.l10n.statsAnnouncedLabel,
            value: context.l10n.statsAnnouncedOversold(announced),
            valueColor: kError,
            alert: true,
          ));
        case QualityVerdict.sousEstime:
          rows.add(_StatRow(
            statKey: VideoStatKey.announced,
            label: context.l10n.statsAnnouncedLabel,
            value: context.l10n.statsAnnouncedBetter(announced),
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
      statKey: VideoStatKey.hdr,
      label: context.l10n.statsHdr,
      value: s.hdr == null
          ? '—'
          : (s.hdr! ? context.l10n.statsYes : context.l10n.statsNo),
      valueColor: s.hdr == true ? kAccentSecondary : null,
    ));

    // ── Fluidité ─────────────────────────────────────────────────────────────
    // §tourFix — fps du CONTENEUR uniquement : Media3 ne publie pas d'images/s
    // réellement rendues, et l'ancien « — / X » laissait lire l'absence de
    // mesure comme une mesure.
    final target = s.containerFps;
    if (target != null) {
      rows.add(_StatRow(statKey: VideoStatKey.fps, label: context.l10n.statsFps, value: target.toStringAsFixed(1)));
    }
    if (s.hasDroppedFrames) {
      rows.add(_StatRow(
        statKey: VideoStatKey.lost,
        label: context.l10n.statsLost,
        value: '${s.droppedFrames ?? 0}',
        valueColor: kWarning,
        alert: true,
      ));
    }

    // §videoStatsPlus — Images/s MESURÉES, à côté de l'annoncé.
    //
    // Affichées ensemble et jamais séparément : « annoncé 50 · rendu 33 » dit
    // tout, chacun pris seul ne dit rien. C'est le relevé qui a permis §video4k.
    final rendered = s.renderedFps;
    if (rendered != null && rendered > 0) {
      final annonce = s.containerFps;
      final manque = annonce != null && annonce > 0 && rendered < annonce * 0.9;
      rows.add(_StatRow(
        statKey: VideoStatKey.rendered,
        label: context.l10n.statsRendered,
        value: manque
            ? context.l10n.statsRenderedVsAnnounced(
                rendered.toStringAsFixed(1), annonce.toStringAsFixed(0))
            : context.l10n.statsRenderedValue(rendered.toStringAsFixed(1)),
        valueColor: manque ? kWarning : null,
        alert: manque,
      ));
    }
    if ((s.skippedFrames ?? 0) > 0) {
      rows.add(_StatRow(statKey: VideoStatKey.dropped, label: context.l10n.statsDropped, value: '${s.skippedFrames}'));
    }

    final bitrate = s.bitrateLabel;
    if (bitrate != null) {
      rows.add(_StatRow(statKey: VideoStatKey.bitrate, label: context.l10n.statsBitrate, value: bitrate));
    }

    // §videoStatsPlus — Le débit RÉELLEMENT servi, et le tampon qu'il remplit.
    final net = s.networkBitrateLabel;
    if (net != null) {
      rows.add(_StatRow(statKey: VideoStatKey.network, label: context.l10n.statsNetwork, value: net));
    }
    final buf = s.bufferAhead;
    if (buf != null) {
      // Sous 2 s d'avance, la moindre irrégularité coupe : c'est le seuil qui
      // précède un blocage, pas une valeur anodine.
      final court = buf.inMilliseconds < 2000;
      rows.add(_StatRow(
        statKey: VideoStatKey.buffer,
        label: context.l10n.statsBuffer,
        value: context.l10n.statsSecondsValue(
            (buf.inMilliseconds / 1000).toStringAsFixed(1)),
        valueColor: court ? kWarning : null,
        alert: court,
      ));
    }
    final transferred = s.transferredLabel;
    if (transferred != null) {
      rows.add(_StatRow(statKey: VideoStatKey.transferred, label: context.l10n.statsTransferred, value: transferred));
    }
    final audio = s.audioLabel;
    if (audio != null) {
      rows.add(_StatRow(statKey: VideoStatKey.audio, label: context.l10n.statsAudio, value: audio));
    }

    // §stallCount — La ligne qui accuse la SOURCE et non l'appareil.
    //
    // « Perdues » ci-dessus dit que le matériel ne suit pas ; « Blocages » dit
    // que le flux ne suit pas. Ce sont deux verdicts opposés, et les confondre
    // fait changer de box quand il fallait changer d'abonnement.
    //
    // Un « aucun » est affiché volontairement : c'est une mesure, pas un vide.
    final stall = s.stallLabel;
    if (stall != null) {
      final bad = (s.stalls ?? 0) > 0;
      rows.add(_StatRow(
        statKey: VideoStatKey.stalls,
        label: context.l10n.statsStalls,
        value: stall,
        valueColor: bad ? kWarning : null,
        alert: bad,
      ));
    }
    final start = s.startupMs;
    if (start != null && start > 0) {
      rows.add(_StatRow(
        statKey: VideoStatKey.startup,
        label: context.l10n.statsStartup,
        value: context.l10n.statsSecondsValue((start / 1000).toStringAsFixed(1)),
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

  /// §videoStatsTags — La clé de la ligne, pour le filtre de l'utilisateur.
  final VideoStatKey statKey;

  const _StatRow({
    required this.statKey,
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

/// §playerPanel — La hauteur que l'encart peut occuper entre [topInset] et
/// [bottomInset] (distances aux bords haut et bas d'un écran haut de
/// [screenHeight]), jamais négative.
///
/// Mesuré en recette (téléphone paysage, ~915×411 dp) : barre du haut ~82 dp,
/// bloc bas ~140 dp — il reste ~190 dp, quand les 13 lignes en demandent ~250.
double videoStatsMaxHeight({
  required double screenHeight,
  required double topInset,
  required double bottomInset,
}) =>
    math.max(0.0, screenHeight - topInset - bottomInset);

/// §playerPanel — La colonne de l'encart, bornée en hauteur : elle montre, dans
/// l'ordre, autant de lignes ENTIÈRES que la place en laisse, et tait les
/// suivantes. Une ligne coupée à mi-hauteur se lirait mal, et un défilement
/// n'aurait pas de sens dans un encart qu'on ne touche pas.
///
/// Les lignes du bas sont donc les premières à se taire quand les contrôles
/// sont affichés ; elles reviennent dès qu'ils se masquent (l'encart reprend
/// alors toute la hauteur).
class _WholeRows extends MultiChildRenderObjectWidget {
  const _WholeRows({required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderWholeRows();
}

class _WholeRowsParentData extends ContainerBoxParentData<RenderBox> {
  /// La ligne tient dans la hauteur disponible (peinte), ou non (tue).
  bool shown = false;
}

class _RenderWholeRows extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _WholeRowsParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _WholeRowsParentData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _WholeRowsParentData) {
      child.parentData = _WholeRowsParentData();
    }
  }

  @override
  void performLayout() {
    final BoxConstraints rowConstraints =
        BoxConstraints(maxWidth: constraints.maxWidth);
    double y = 0;
    double width = 0;
    bool full = false;
    RenderBox? child = firstChild;
    while (child != null) {
      final _WholeRowsParentData pd = child.parentData! as _WholeRowsParentData;
      child.layout(rowConstraints, parentUsesSize: true);
      final double h = child.size.height;
      // Dès qu'une ligne ne tient plus, les suivantes se taisent aussi :
      // l'ordre de lecture ne saute jamais une ligne.
      pd.shown = !full && y + h <= constraints.maxHeight;
      if (pd.shown) {
        pd.offset = Offset(0, y);
        y += h;
        width = math.max(width, child.size.width);
      } else {
        full = true;
        pd.offset = Offset.zero;
      }
      child = pd.nextSibling;
    }
    size = constraints.constrain(Size(width, y));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    RenderBox? child = firstChild;
    while (child != null) {
      final _WholeRowsParentData pd = child.parentData! as _WholeRowsParentData;
      if (pd.shown) context.paintChild(child, offset + pd.offset);
      child = pd.nextSibling;
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    RenderBox? child = lastChild;
    while (child != null) {
      final _WholeRowsParentData pd = child.parentData! as _WholeRowsParentData;
      if (pd.shown &&
          result.addWithPaintOffset(
            offset: pd.offset,
            position: position,
            hitTest: (BoxHitTestResult r, Offset p) =>
                child!.hitTest(r, position: p),
          )) {
        return true;
      }
      child = pd.previousSibling;
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    RenderObject? child = firstChild;
    while (child != null) {
      final _WholeRowsParentData pd = child.parentData! as _WholeRowsParentData;
      if (pd.shown) visitor(child);
      child = pd.nextSibling;
    }
  }
}
