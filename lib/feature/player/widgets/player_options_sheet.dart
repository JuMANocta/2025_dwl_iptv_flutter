import 'package:flutter/material.dart';

import '../../../core/themes/colors.dart';
import '../../../core/utils/platform_tv.dart';
import '../../../widgets/tv/focusable_card.dart';
import '../../../widgets/tv/tv_adaptive_modal.dart';
import '../playback_engine.dart';
import '../video_fit.dart';
import '../video_stats.dart';
import '../../../l10n/l10n_ext.dart';

/// §tourFix — LA liste des vitesses de lecture, unique pour toute l'app.
///
/// Elle existait en DOUBLE (ici et dans `PlayerControls._speeds`), chacune
/// alimentant son propre état : le badge inline et la coche du sous-menu
/// pouvaient se contredire (badge TV figé à 1.0×). La vitesse n'a plus qu'un
/// propriétaire (`_PlayerPageState._speed`) et une seule liste — celle-ci.
const List<double> kPlaybackSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

/// §tvPlayerNav — Panneau d'OPTIONS du lecteur : le « centre de contrôle » TV
/// ouvert via ↑ à la télécommande (mobile peut aussi y accéder). Tous les items
/// sont des [FocusableCard] → navigables au D-pad, contrairement aux boutons
/// inline (GestureDetector) inatteignables sur TV. Regroupe : pistes audio/
/// sous-titres, vitesse, épisode suivant.
Future<void> showPlayerOptions(
  BuildContext context, {
  required bool hasNext,
  required String speedLabel,
  required VideoFitMode fitMode,
  required bool statsEnabled,
  required VoidCallback onTracks,
  required VoidCallback onSpeed,
  required VoidCallback onFit,
  required VoidCallback onStats,
  VoidCallback? onNext,
  // §engineFeatures — variantes HLS du flux en cours ; la ligne n'existe
  // que s'il y a un choix à faire (au moins deux variantes hors « auto »).
  List<AetherQuality> qualities = const [],
  AetherQuality? currentQuality,
  VoidCallback? onQuality,
}) {
  final bool hasQualities =
      onQuality != null && qualities.where((q) => !q.isAuto).length >= 2;
  return showAdaptiveActionSheet<void>(
    context: context,
    scrollable: false,
    builder: (sheetCtx) => OptionsSheetBody(
      title: context.l10n.optTitle,
      icon: Icons.tune_rounded,
      children: [
        // §tvOptionsOrder — « Épisode suivant » EN PREMIER (série en cours) :
        // c'est l'action la plus fréquente du panneau, elle reçoit le focus
        // initial au D-pad au lieu d'être en dernière position.
        if (onNext != null)
          OptionSheetRow(
            icon: Icons.skip_next_rounded,
            accent: kAccentTertiary,
            title: context.l10n.optNextEpisode,
            subtitle: context.l10n.optNextEpisodeSub,
            onTap: onNext,
          ),
        OptionSheetRow(
          icon: Icons.subtitles_rounded,
          accent: kAccentSecondary,
          title: context.l10n.optTracksTitle,
          subtitle: context.l10n.optTracksSub,
          onTap: onTracks,
        ),
        OptionSheetRow(
          icon: Icons.speed_rounded,
          accent: kAccentPrimary,
          title: context.l10n.optSpeedTitle,
          subtitle: speedLabel,
          onTap: onSpeed,
        ),
        // §videoFit — Format d'image : le sous-titre annonce le mode ACTIF,
        // pas l'action. Sur TV c'est le seul endroit où on peut lire l'état
        // courant (le bouton inline du lecteur n'existe qu'au tactile).
        OptionSheetRow(
          icon: fitMode.icon,
          accent: kAccentSecondary,
          title: context.l10n.optFitTitle,
          subtitle: '${fitMode.label} · ${fitMode.description}',
          onTap: onFit,
        ),
        // §engineFeatures — Qualité HLS : le sous-titre dit la variante
        // ACTIVE (« Automatique » ou « 720p »), pas l'action.
        if (hasQualities)
          OptionSheetRow(
            icon: Icons.high_quality_rounded,
            accent: kAccentPrimary,
            title: context.l10n.optQualityTitle,
            subtitle: currentQuality == null || currentQuality.isAuto
                ? context.l10n.optQualityAuto
                : currentQuality.label,
            onTap: onQuality,
          ),
        // §videoStats — Interrupteur de l'encart de diagnostic. EN DERNIER :
        // c'est un outil de mise au point, pas une action de lecture, il ne
        // doit pas passer devant « Épisode suivant » au focus D-pad.
        OptionSheetRow(
          icon: statsEnabled ? Icons.speed_outlined : Icons.query_stats_rounded,
          accent: kAccentTertiary,
          title: context.l10n.optVideoInfo,
          subtitle: statsEnabled
              ? context.l10n.optVideoInfoOn
              : context.l10n.optVideoInfoSub,
          selected: statsEnabled,
          onTap: onStats,
        ),
        // §tvOptionsBack — La SORTIE du panneau, signalée le 2026-09-08 :
        // « il faut un bouton pour annuler et revenir sur la vidéo car sinon
        // on fait retour et ça sort de la vidéo ». À la télécommande, le
        // panneau n'offrait AUCUNE issue : la seule était la touche Retour.
        //
        // ⚠️ **En DERNIER, jamais en premier.** `TvAutofocusFirst` donne le
        // focus au premier élément focusable du modal : mettre « fermer » en
        // tête ferait de la fermeture l'action par défaut du panneau qu'on
        // vient d'ouvrir — un appui sur OK et il disparaît.
        BackToVideoRow(onTap: () => Navigator.of(sheetCtx).pop()),
      ],
    ),
  );
}

/// §videoFit — Sous-menu Format d'image, focusable D-pad.
Future<void> showVideoFitMenu(
  BuildContext context, {
  required VideoFitMode current,
  required ValueChanged<VideoFitMode> onSelect,
}) {
  return showAdaptiveActionSheet<void>(
    context: context,
    scrollable: false,
    builder: (sheetCtx) => OptionsSheetBody(
      title: context.l10n.optFitTitle,
      icon: Icons.aspect_ratio_rounded,
      children: [
        for (final mode in VideoFitMode.values)
          OptionSheetRow(
            icon: mode == current ? Icons.check_circle_rounded : mode.icon,
            accent: kAccentSecondary,
            title: mode.label,
            subtitle: mode.description,
            selected: mode == current,
            onTap: () => onSelect(mode),
          ),
        // §tvOptionsBack — ⚠️ Les SOUS-MENUS en avaient autant besoin que le
        // panneau : y entrer sans vouloir rien changer laissait sans issue
        // (signalé le 2026-09-09 : « dans la partie TV des les options j'ai
        // pas genre revenir ou annuler si je choisi aucune option »).
        // Le panneau d'options se ferme AVANT d'ouvrir ce sous-menu
        // (`player_page._showFitMenu`), donc fermer ici rend bien la vidéo.
        BackToVideoRow(onTap: () => Navigator.of(sheetCtx).pop()),
      ],
    ),
  );
}

/// §tvPlayerNav — Sous-menu Vitesse (0.5×→2×), focusable D-pad.
Future<void> showSpeedMenu(
  BuildContext context, {
  required double current,
  required ValueChanged<double> onSelect,
}) {
  return showAdaptiveActionSheet<void>(
    context: context,
    scrollable: false,
    builder: (sheetCtx) => OptionsSheetBody(
      title: context.l10n.optSpeedTitle,
      icon: Icons.speed_rounded,
      children: [
        for (final s in kPlaybackSpeeds)
          OptionSheetRow(
            icon: s == current
                ? Icons.check_circle_rounded
                : Icons.play_arrow_rounded,
            accent: kAccentPrimary,
            title: s == 1.0 ? context.l10n.optSpeedNormal : '$s×',
            subtitle: null,
            selected: s == current,
            onTap: () => onSelect(s),
          ),
        // §tvOptionsBack — voir le sous-menu Format d'image.
        BackToVideoRow(onTap: () => Navigator.of(sheetCtx).pop()),
      ],
    ),
  );
}

/// §engineFeatures — Sous-menu Qualité HLS (« Automatique » + chaque
/// variante, de la plus haute à la plus basse), focusable D-pad.
Future<void> showQualityMenu(
  BuildContext context, {
  required List<AetherQuality> qualities,
  required AetherQuality? current,
  required ValueChanged<AetherQuality> onSelect,
}) {
  return showAdaptiveActionSheet<void>(
    context: context,
    scrollable: false,
    builder: (sheetCtx) => OptionsSheetBody(
      title: context.l10n.optQualityTitle,
      icon: Icons.high_quality_rounded,
      children: [
        for (final q in qualities)
          OptionSheetRow(
            icon: q == current
                ? Icons.check_circle_rounded
                : (q.isAuto ? Icons.auto_awesome_rounded : Icons.hd_rounded),
            accent: kAccentPrimary,
            title: q.isAuto ? context.l10n.optQualityAuto : q.label,
            // Le débit passe par LA règle partagée (`formatBitrate`) : un
            // point décimal en dur affichait « 4.5 Mb/s » ici et « 4,5 Mb/s »
            // dans l'encart de stats, sur le même appareil français.
            subtitle: q.isAuto
                ? context.l10n.optQualityAutoSub
                : formatBitrate(q.bitrate),
            selected: q == current,
            onTap: () => onSelect(q),
          ),
        // §tvOptionsBack — voir le sous-menu Format d'image.
        BackToVideoRow(onTap: () => Navigator.of(sheetCtx).pop()),
      ],
    ),
  );
}

/// §videoStatsTags — Le nom d'une ligne de l'encart, celui qu'elle porte à
/// l'écran.
String videoStatLabel(BuildContext context, VideoStatKey k) {
  final l = context.l10n;
  return switch (k) {
    VideoStatKey.decoding => l.statsDecoding,
    VideoStatKey.output => l.statsOutput,
    VideoStatKey.codec => l.statsCodec,
    VideoStatKey.resolution => l.statsResolution,
    VideoStatKey.announced => l.statsAnnouncedLabel,
    VideoStatKey.hdr => l.statsHdr,
    VideoStatKey.fps => l.statsFps,
    VideoStatKey.lost => l.statsLost,
    VideoStatKey.rendered => l.statsRendered,
    VideoStatKey.dropped => l.statsDropped,
    VideoStatKey.bitrate => l.statsBitrate,
    VideoStatKey.network => l.statsNetwork,
    VideoStatKey.buffer => l.statsBuffer,
    VideoStatKey.transferred => l.statsTransferred,
    VideoStatKey.audio => l.statsAudio,
    VideoStatKey.stalls => l.statsStalls,
    VideoStatKey.startup => l.statsStartup,
  };
}

/// §videoStatsTags — Sous-menu « Infos vidéo » : l'encart oui / non, toujours
/// à l'écran ou seulement avec les contrôles, et la liste des lignes à
/// montrer. Chaque ligne se coche et se décoche sur place (la feuille reste
/// ouverte : à la télécommande, refaire le chemin pour chaque ligne serait
/// une punition), focusable D-pad, sortie en dernier (§tvOptionsBack).
Future<void> showVideoStatsMenu(
  BuildContext context, {
  required bool enabled,
  required bool permanent,
  required Set<VideoStatKey> rows,
  required ValueChanged<bool> onEnabled,
  required ValueChanged<bool> onPermanent,
  required void Function(VideoStatKey key, bool shown) onRow,
}) {
  bool en = enabled;
  bool perm = permanent;
  final Set<VideoStatKey> shown = Set.of(rows);
  return showAdaptiveActionSheet<void>(
    context: context,
    builder: (sheetCtx) => StatefulBuilder(
      builder: (ctx, setLocal) => OptionsSheetBody(
        title: context.l10n.optVideoInfo,
        icon: Icons.query_stats_rounded,
        children: [
          OptionSheetRow(
            icon: en ? Icons.check_circle_rounded : Icons.visibility_off_rounded,
            accent: kAccentTertiary,
            title: context.l10n.optStatsShow,
            subtitle: context.l10n.optStatsShowSub,
            selected: en,
            onTap: () {
              setLocal(() => en = !en);
              onEnabled(en);
            },
          ),
          OptionSheetRow(
            icon: perm ? Icons.check_circle_rounded : Icons.touch_app_rounded,
            accent: kAccentTertiary,
            title: context.l10n.optStatsPermanent,
            subtitle: context.l10n.optStatsPermanentSub,
            selected: perm,
            onTap: () {
              setLocal(() => perm = !perm);
              onPermanent(perm);
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              context.l10n.optStatsRows,
              style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                    color: kAccentTertiary,
                    letterSpacing: 1.2,
                  ),
            ),
          ),
          for (final k in VideoStatKey.values)
            OptionSheetRow(
              icon: shown.contains(k)
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              accent: kAccentTertiary,
              title: videoStatLabel(ctx, k),
              subtitle: null,
              selected: shown.contains(k),
              onTap: () {
                setLocal(() {
                  if (!shown.remove(k)) shown.add(k);
                });
                onRow(k, shown.contains(k));
              },
            ),
          // §tvOptionsBack — voir le sous-menu Format d'image.
          BackToVideoRow(onTap: () => Navigator.of(sheetCtx).pop()),
        ],
      ),
    ),
  );
}

/// §tvOptionsBack — « Revenir à la vidéo », la sortie explicite d'une feuille
/// du lecteur.
///
/// **Pourquoi elle existe** : à la télécommande, un modal sans bouton de
/// fermeture n'a d'autre issue que la touche Retour — et c'est précisément ce
/// qui faisait sortir du FILM (signalement du 2026-09-08). ⚠️ Les SOUS-MENUS
/// (Vitesse, Format d'image) sont dans le même cas dès qu'on y entre sans
/// vouloir changer de valeur : c'est le second signalement, du 2026-09-09.
///
/// ⚠️ **À poser en DERNIER, jamais en premier.** `TvAutofocusFirst` donne le
/// focus au premier élément focusable du modal : « fermer » en tête ferait de
/// la fermeture l'action par défaut du panneau qu'on vient d'ouvrir.
///
/// ⚠️ **TÉLÉVISEUR UNIQUEMENT** (signalé pendant la recette du 2026-09-09 :
/// « c'est pas pour la version téléphone, seulement pour la version PC, car
/// sur téléphone un clic sur l'écran fait un pseudo retour »). Au doigt,
/// taper hors du cadre referme déjà la feuille : la ligne n'y serait que du
/// bruit, une entrée de plus à lire dans un menu. **À la télécommande, il
/// n'y a pas de « hors du cadre »** — le curseur ne peut atteindre que des
/// éléments focusables. C'est la même famille de décision que §pipPhone et
/// §nowPlaying : une affordance qui n'a de sens que sur une seule surface.
class BackToVideoRow extends StatelessWidget {
  const BackToVideoRow({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => !PlatformTv.isTv
      ? const SizedBox.shrink()
      : OptionSheetRow(
        icon: Icons.keyboard_return_rounded,
        accent: kAccentSecondary,
        title: context.l10n.optBackToVideo,
        subtitle: context.l10n.optBackToVideoSub,
        onTap: onTap,
      );
}

class OptionsSheetBody extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const OptionsSheetBody({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxH = MediaQuery.of(context).size.height * 0.72;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Titre vide = pas d'en-tête du tout : garder l'icône seule
                // laisserait une pastille orpheline au-dessus du contenu.
                if (title.isNotEmpty) ...[
                  Row(
                    children: [
                      Icon(icon, color: kAccentPrimary, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OptionSheetRow extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  const OptionSheetRow({
    super.key,
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: FocusableCard(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          decoration: BoxDecoration(
            color: selected ? accent.withAlpha(26) : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? accent : cs.outlineVariant,
              width: selected ? 1.6 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                        color: accent.withAlpha(70),
                        blurRadius: 14,
                        spreadRadius: -3),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withAlpha(28),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accent.withAlpha(90)),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 15,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: cs.onSurfaceVariant.withAlpha(140)),
            ],
          ),
        ),
      ),
    );
  }
}
