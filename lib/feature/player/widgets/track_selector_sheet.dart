import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../playback_engine.dart';

import '../../../core/themes/colors.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../data/services/online_subtitles_service.dart';
import '../../../data/services/subtitle_api_service.dart';
import '../../../data/services/tmdb_service.dart';
import '../../../data/services/track_preferences_service.dart';
import '../../../widgets/tv/focusable_card.dart';
import '../../../widgets/tv/tv_adaptive_modal.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/l10n_ext.dart';
import '../track_language_names.dart';
import 'player_options_sheet.dart' show BackToVideoRow;

/// §5 — Sélecteur de pistes **audio** et **sous-titres**. Ouvert depuis le
/// bouton CC de `PlayerControls`. Sheet adaptatif (bottom sheet mobile,
/// Dialog + D-pad sur TV via [showAdaptiveActionSheet]).
///
/// §trackSheetUI — Style aligné sur l'app : en-tête, sections colorées (audio
/// vert / sous-titres cyan) avec barre d'accent, badges de langue, et état
/// sélectionné en contour néon + glow.
///
/// R43 — Ce que la feuille MÉMORISE, et le dit : une langue AUDIO choisie vaut
/// pour les prochains titres ; une piste de SOUS-TITRES ne vaut que pour
/// celui-ci ; « Désactivés » vaut pour les suivants. Quand une mémoire existe,
/// une ligne de fin de section l'annonce (« … pour les prochains titres
/// aussi ») et la DÉFAIT d'un geste. Avant, la coupure était retenue sans le
/// dire, et le seul retour épinglait une langue pour toujours.
///
/// Lot 11 — [onlineSearch] décrit le contenu en cours pour la recherche de
/// sous-titres en ligne. `null` = la ligne « Chercher en ligne » n'existe pas
/// (contenu non identifiable : une chaîne en direct, un titre vide).
Future<void> showTrackSelector(
  BuildContext context,
  AetherPlaybackEngine player, {
  SubtitleSearchContext? onlineSearch,
}) {
  return showAdaptiveActionSheet<void>(
    context: context,
    // §5 — Le sélecteur fournit son PROPRE scroll borné (cf. _TrackSelector) :
    // sans ça, beaucoup de pistes faisaient déborder la Column (RenderFlex
    // overflow sur mobile, où showAdaptiveActionSheet n'ajoute pas de scroll).
    scrollable: false,
    builder: (sheetCtx) => _TrackSelector(
      player: player,
      onlineSearch: onlineSearch,
      onClose: () => Navigator.of(sheetCtx).pop(),
    ),
  );
}

// ─── Logique partagée (§tvPlayerPanel) ──────────────────────────────────────
//
// La feuille ci-dessous (téléphone) et la rangée d'options TV
// (`tv_option_bar.dart`) appliquent les pistes par ces fonctions, et elles
// seules : deux copies de la règle R43 (« mémoriser seulement si la piste est
// posée ») finiraient par diverger.

/// Le nom d'une piste tel qu'on l'affiche : sa langue, sinon son titre, sinon
/// « Piste N ».
String trackDisplayTitle(AetherTrack t) =>
    trackLanguageName(t.language) ??
    t.title?.trim() ??
    L10n.current.tracksTrackN(t.id);

/// Le titre de la piste quand il dit AUTRE CHOSE que [trackDisplayTitle]
/// (« Commentaire », « VFQ »…), sinon `null`.
String? trackDisplayDetail(AetherTrack t) {
  final String title = trackDisplayTitle(t);
  final String? raw = t.title?.trim();
  return (raw != null && raw.isNotEmpty && raw != title) ? raw : null;
}

/// R43 — Pose une piste audio choisie par l'utilisateur, puis mémorise SA
/// LANGUE pour les prochains titres — seulement si la piste est posée : avant,
/// le canal vendoré avalait l'échec et l'app mémorisait une langue qu'aucune
/// piste ne portait. ⛔ Jamais un numéro ni « unknown » (`languageKeyFor`).
///
/// §trackMemory + R5 (recette 2026-09-21) — « posée » ne veut pas dire
/// « décodable » : le décodeur peut échouer APRÈS (piste MP2 sur l'AVD), et la
/// langue restait mémorisée pour tous les titres suivants — chacun rouvert sur
/// la piste indécodable. Le choix est donc NOTÉ ([AudioChoice]) : si la bascule
/// R5 rejette cette piste, [undoAudioChoice] rend la mémoire d'avant.
Future<bool> applyAudioTrackChoice(
    AetherPlaybackEngine player, AetherTrack t) async {
  final String? memoryBefore = TrackPreferencesService.audio;
  final String? trackBefore = player.currentAudioTrack?.id;
  final bool ok = await player.setAudioTrack(t);
  if (!ok) return false;
  final key = TrackPreferencesService.languageKeyFor(t.language);
  if (key != null) await TrackPreferencesService.setAudio(key);
  _audioChoices[player] = AudioChoice(
    trackId: t.id,
    memoryBefore: memoryBefore,
    trackBefore: trackBefore,
  );
  return true;
}

/// R5 + §trackMemory — Le dernier choix de piste audio fait par
/// l'utilisateur sur un moteur : la piste choisie, la langue mémorisée AVANT
/// ce choix, et la piste qui jouait avant lui.
class AudioChoice {
  const AudioChoice({
    required this.trackId,
    required this.memoryBefore,
    required this.trackBefore,
  });

  final String trackId;
  final String? memoryBefore;
  final String? trackBefore;
}

/// Un choix par moteur, qui meurt avec lui (pas de fuite, pas de registre).
final Expando<AudioChoice> _audioChoices = Expando<AudioChoice>('audioChoice');

/// Le dernier choix audio fait sur [player], ou `null`.
AudioChoice? lastAudioChoice(AetherPlaybackEngine player) =>
    _audioChoices[player];

/// R5 — La piste [rejectedTrackId] ne se décode pas. Si c'est celle que
/// l'utilisateur vient de choisir, la langue mémorisée par ce choix est
/// DÉFAITE (valeur d'avant rendue) et le choix oublié. Rend le choix défait,
/// ou `null` si la piste rejetée n'était pas un choix de l'utilisateur.
Future<AudioChoice?> undoAudioChoice(
    AetherPlaybackEngine player, String rejectedTrackId) async {
  final AudioChoice? c = _audioChoices[player];
  if (c == null || c.trackId != rejectedTrackId) return null;
  _audioChoices[player] = null;
  await TrackPreferencesService.setAudio(c.memoryBefore);
  debugPrint('↩️ R5 — piste « $rejectedTrackId » indécodable : langue mémorisée rendue (${c.memoryBefore ?? 'auto'})');
  return c;
}

/// Un échec se DIT, et la liste reste ouverte (R42) — même toast partout.
/// ⚠️ Durée EXPLICITE : un `SnackBar` nu prend le défaut de Flutter (4 s),
/// pas celui de l'app (2 s) — `showVia` ne l'impose pas.
void showTrackToast(ScaffoldMessengerState? messenger, String text) {
  if (messenger == null) return;
  AppSnackBar.showVia(
    messenger,
    SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
  );
}

/// Lot 11 — Recherche de sous-titres en ligne pour [search] : les résultats,
/// ou la phrase à dire à l'utilisateur (`error`, déjà traduite). Jamais les
/// deux.
Future<({List<OnlineSubtitle> results, String? error})> findOnlineSubtitles(
  SubtitleSearchContext search,
  AppLocalizations l10n,
) async {
  const none = <OnlineSubtitle>[];
  final String? key = await SubtitleApiService.getApiKey();
  if (key == null || key.isEmpty) {
    return (results: none, error: l10n.tracksOnlineNoKey);
  }

  // La langue de l'interface d'abord, l'anglais ensuite : c'est la paire qui
  // couvre presque tout, et demander TOUTES les langues rendait des centaines
  // de lignes à faire défiler à la télécommande.
  final String ui = l10n.localeName;
  final String languages = ui == 'en' ? 'en' : '$ui,en';

  // Le fournisseur travaille sur un identifiant TMDB ; nos listes n'en
  // portent pas. `resolveTmdbId` fait la recherche et la mémorise.
  final int? tmdbId = await TmdbService.instance.resolveTmdbId(
    query: search.query,
    isTv: search.isTv,
  );
  if (tmdbId == null) return (results: none, error: l10n.tracksOnlineNoTitle);

  final SubtitleSearchOutcome outcome = await OnlineSubtitlesService.search(
    tmdbId: tmdbId,
    languages: languages,
    apiKey: key,
    season: search.season,
    episode: search.episode,
  );
  if (!outcome.isOk) {
    return (
      results: none,
      error: switch (outcome.error!) {
        SubtitleSearchError.badKey => l10n.tracksOnlineBadKey,
        SubtitleSearchError.quota => l10n.tracksOnlineQuota,
        SubtitleSearchError.network => l10n.tracksOnlineFailed,
      },
    );
  }
  if (outcome.results.isEmpty) {
    return (results: none, error: l10n.tracksOnlineNone);
  }
  return (results: outcome.results, error: null);
}

/// Lot 11 — Télécharge [s] puis le pose dans le moteur, qui le charge ET le
/// sélectionne ; la piste rejoint ensuite la liste ordinaire (cf.
/// `loadExternalSubtitle`). `false` = rien n'a été posé.
Future<bool> loadOnlineSubtitle(
    AetherPlaybackEngine player, OnlineSubtitle s) async {
  final Directory cache = await getTemporaryDirectory();
  final String? path = await OnlineSubtitlesService.download(s, cacheDir: cache);
  if (path == null) return false;
  final bool ok = await player.loadExternalSubtitle(
    filePath: path,
    language: s.language,
    label: s.display,
  );
  if (ok) debugPrint('✅ lot 11 — sous-titre en ligne posé (${s.language})');
  return ok;
}

/// Lot 11 — Ce qui distingue un résultat des autres de la même langue : la
/// version, la provenance, et la mention « sourds et malentendants ».
String? onlineSubtitleDetail(AppLocalizations l10n, OnlineSubtitle s) {
  final parts = <String>[
    if (s.release != null) s.release!,
    if (s.source != null && s.source!.isNotEmpty) s.source!,
    if (s.hearingImpaired) l10n.tracksOnlineHearing,
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

class _TrackSelector extends StatelessWidget {
  final AetherPlaybackEngine player;

  /// Lot 11 — Ce qu'il faut pour chercher en ligne, ou `null`.
  final SubtitleSearchContext? onlineSearch;

  /// §tvOptionsBack — Ferme la feuille. Sans elle, la seule sortie à la
  /// télécommande était la touche Retour.
  final VoidCallback onClose;

  const _TrackSelector({
    required this.player,
    required this.onClose,
    this.onlineSearch,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // §engineVendor étape 3 — listes et sélection viennent du moteur, plus
    // d'un objet d'état propre au moteur.
    final audio = player.audioTracks;
    final subs = player.subtitleTracks;
    final curAudio = player.currentAudioTrack;
    final curSub = player.currentSubtitleTrack;
    final maxH = MediaQuery.of(context).size.height * 0.72;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // En-tête.
                Row(
                  children: [
                    Icon(Icons.subtitles_rounded,
                        color: kAccentSecondary, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      context.l10n.tracksTitle,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      context.l10n.tracksSubtitle,
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // ── AUDIO (accent vert) ────────────────────────────────────
                _SectionBar(
                    label: context.l10n.tracksAudio,
                    icon: Icons.graphic_eq_rounded,
                    accent: kAccentPrimary),
                const SizedBox(height: 8),
                if (audio.isEmpty)
                  _emptyHint(context.l10n.tracksNoAudio, cs)
                else
                  ...audio.map((t) => _audioRow(context, t, curAudio)),
                // R43 — La mémoire audio, visible et réversible. EN FIN de
                // section : à la télécommande, la première ligne est l'action
                // par défaut du bouton OK, et « oublier ma langue » ne doit
                // pas l'être.
                if (TrackPreferencesService.audio != null)
                  _memoryRow(
                    context,
                    accent: kAccentPrimary,
                    title: context.l10n.tracksMemoryAudio(
                      trackLanguageName(TrackPreferencesService.audio) ??
                          TrackPreferencesService.audio!.toUpperCase(),
                    ),
                    onTap: () => _resetAudio(context),
                  ),

                const SizedBox(height: 20),

                // ── SOUS-TITRES (accent cyan) ──────────────────────────────
                _SectionBar(
                    label: context.l10n.tracksSubtitles,
                    icon: Icons.closed_caption_rounded,
                    accent: kAccentSecondary),
                const SizedBox(height: 8),
                if (subs.isEmpty)
                  _emptyHint(context.l10n.tracksNoSubtitles, cs)
                else ...[
                  // R42 — EN TÊTE et INCONDITIONNELLE. Elle ne dépendait que
                  // d'une piste d'identifiant `'no'` (vestige mpv) qu'aucun
                  // moteur ne fabrique : elle ne pouvait donc JAMAIS s'afficher,
                  // et une piste FORCED auto-sélectionnée par ExoPlayer restait
                  // incoupable.
                  _subtitleOffRow(context, selected: curSub == null),
                  ...subs.map((t) => _subtitleRow(context, t, curSub)),
                ],
                // R43 — La coupure mémorisée, visible et réversible — MÊME sur
                // un titre sans piste : c'est justement là qu'on ne pouvait
                // plus la lever (le seul retour était de choisir une piste).
                // « Désactivés » reste en tête (R42) ; celle-ci ferme la
                // section.
                if (TrackPreferencesService.subtitle ==
                    TrackPreferencesService.kSubtitlesOff)
                  _memoryRow(
                    context,
                    accent: kAccentSecondary,
                    title: context.l10n.tracksMemorySubOff,
                    onTap: () => _resetSubtitles(context),
                  ),

                // Lot 11 — Chercher des sous-titres en ligne. EN FIN de
                // section, pour la même raison que la ligne de mémoire : à la
                // télécommande, la première ligne est l'action par défaut du
                // bouton OK, et partir sur le réseau ne doit pas l'être.
                if (onlineSearch != null)
                  _OnlineSubtitleRow(
                    player: player,
                    search: onlineSearch!,
                    onLoaded: onClose,
                  ),

                // §tvOptionsBack — Même manque que le panneau d'options : à la
                // télécommande, rien ne permettait de refermer cette feuille.
                // ⚠️ En DERNIER (`TvAutofocusFirst` focalise le premier
                // élément : « fermer » ne doit pas être l'action par défaut).
                const SizedBox(height: 18),
                BackToVideoRow(onTap: onClose),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// ⚠️ R43 — Plus de branches `'auto'` / `'no'` ici : même constat que
  /// `_subtitleRow` (R42), `Media3Engine` ne fabrique que des `id: '<index>'`.
  /// Elles portaient le dernier « Auto » écrit en dur de la feuille.
  Widget _audioRow(
      BuildContext context, AetherTrack t, AetherTrack? cur) {
    return _TrackRow(
      accent: kAccentPrimary,
      leading: _LangBadge(trackLanguageShort(t.language), kAccentPrimary),
      title: trackDisplayTitle(t),
      subtitle: trackDisplayDetail(t),
      selected: t.id == cur?.id,
      onTap: () async {
        final messenger = ScaffoldMessenger.maybeOf(context);
        final nav = Navigator.of(context);
        final echec = context.l10n.tracksTrackFailed;
        // R43 — ATTENDU, et la mémoire n'est écrite QUE si la piste est
        // posée (`applyAudioTrackChoice`, partagé avec la rangée TV).
        final ok = await applyAudioTrackChoice(player, t);
        if (!ok) {
          _toast(messenger, echec);
          return;
        }
        nav.pop();
      },
    );
  }

  /// R43 — La ligne de mémoire d'une section : dit ce qui s'appliquera aux
  /// prochains titres, et rend la main au moteur d'un geste. Jamais cochée :
  /// ce n'est pas une piste, c'est un retour en arrière.
  Widget _memoryRow(
    BuildContext context, {
    required Color accent,
    required String title,
    required VoidCallback onTap,
  }) {
    return _TrackRow(
      accent: accent,
      leading: _IconBadge(Icons.restart_alt_rounded, accent),
      title: title,
      subtitle: context.l10n.tracksMemoryForget,
      selected: false,
      onTap: onTap,
    );
  }

  Future<void> _resetSubtitles(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final nav = Navigator.of(context);
    final echec = context.l10n.tracksResetFailed;
    final ok = await player.resetSubtitlesToAuto();
    if (!ok) {
      _toast(messenger, echec);
      return;
    }
    nav.pop();
  }

  Future<void> _resetAudio(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final nav = Navigator.of(context);
    final echec = context.l10n.tracksResetFailed;
    final ok = await player.resetAudioToAuto();
    if (!ok) {
      _toast(messenger, echec);
      return;
    }
    nav.pop();
  }

  /// Un échec se DIT, et la feuille reste ouverte (R42) : [showTrackToast].
  static void _toast(ScaffoldMessengerState? messenger, String text) =>
      showTrackToast(messenger, text);

  /// R42 — « Désactivés » : coupure **sémantique** ([disableSubtitles]), jamais
  /// un identifiant de piste — ceux-ci ne sont pas portables d'un moteur à
  /// l'autre, et c'est exactement ce qui rendait cette ligne morte.
  ///
  /// [selected] vaut « aucune piste courante » : l'état se lit sur le moteur,
  /// pas sur une entrée fantôme dans la liste.
  Widget _subtitleOffRow(BuildContext context, {required bool selected}) {
    return _TrackRow(
      accent: kAccentSecondary,
      leading: _IconBadge(Icons.subtitles_off_rounded, kAccentSecondary),
      title: context.l10n.tracksDisabled,
      subtitle: null,
      selected: selected,
      onTap: () async {
        // Tout ce qui vient du contexte est pris AVANT l'attente : refermer la
        // feuille invalide le contexte de la bottom sheet.
        final messenger = ScaffoldMessenger.maybeOf(context);
        final nav = Navigator.of(context);
        final echec = context.l10n.tracksDisableFailed;

        // ⚠️ ATTENDUE, et la suite en dépend. Sans attente, une coupure ratée
        // refermait quand même la feuille — donc se lisait comme un succès — et
        // « coupés » restait mémorisé pour tous les titres suivants.
        final ok = await player.disableSubtitles();
        if (!ok) {
          // La feuille RESTE ouverte : l'utilisateur voit que rien n'a changé
          // et peut réessayer. La mémorisation appartient au moteur, qui ne l'a
          // pas écrite non plus.
          _toast(messenger, echec);
          return;
        }
        nav.pop();
      },
    );
  }

  /// ⚠️ R42 — Plus de branches `'no'` / `'auto'` ici : `AetherTrack` n'est
  /// construit qu'en deux points (`media3_engine.dart:270` et `:281`), toujours
  /// avec `id: '<index>'` et un index ≥ 0. Elles étaient donc inatteignables —
  /// et franchement trompeuses maintenant qu'une vraie ligne de coupure existe
  /// juste au-dessus.
  Widget _subtitleRow(
      BuildContext context, AetherTrack t, AetherTrack? cur) {
    return _TrackRow(
      accent: kAccentSecondary,
      leading: _LangBadge(trackLanguageShort(t.language), kAccentSecondary),
      title: trackDisplayTitle(t),
      subtitle: trackDisplayDetail(t),
      selected: t.id == cur?.id,
      onTap: () async {
        final messenger = ScaffoldMessenger.maybeOf(context);
        final nav = Navigator.of(context);
        final echec = context.l10n.tracksTrackFailed;
        // R43 — La feuille n'écrit plus RIEN ici : c'est le moteur qui lève la
        // coupure mémorisée pendant cet appel, et une piste choisie ne vaut
        // que pour ce titre (mémoriser sa langue allumerait les sous-titres
        // français de tous les films français).
        final ok = await player.setSubtitleTrack(t);
        if (!ok) {
          _toast(messenger, echec);
          return;
        }
        nav.pop();
      },
    );
  }

  Widget _emptyHint(String text, ColorScheme cs) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
        child: Text(text,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
      );
}

/// En-tête de section : barre d'accent verticale + icône + label (style fiche).
class _SectionBar extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accent;
  const _SectionBar(
      {required this.label, required this.icon, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Icon(icon, size: 17, color: accent),
        const SizedBox(width: 7),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            color: accent,
          ),
        ),
      ],
    );
  }
}

/// Badge de langue (ex. « FR ») coloré à l'accent de la section.
class _LangBadge extends StatelessWidget {
  final String code;
  final Color accent;
  const _LangBadge(this.code, this.accent);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withAlpha(110)),
      ),
      child: Text(
        code,
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.w800,
          fontSize: 12,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Badge à icône (Auto / Aucune / Désactivés).
class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color accent;
  const _IconBadge(this.icon, this.accent);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withAlpha(22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withAlpha(90)),
      ),
      child: Icon(icon, size: 18, color: accent),
    );
  }
}

class _TrackRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;
  const _TrackRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.selected,
    required this.onTap,
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
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
                      spreadRadius: -3,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              leading,
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
                            selected ? FontWeight.w700 : FontWeight.w500,
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
              const SizedBox(width: 10),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected ? accent : cs.onSurfaceVariant.withAlpha(120),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lot 11 — La ligne « Chercher en ligne » et tout ce qu'elle déclenche.
///
/// Elle porte son PROPRE état de chargement : la feuille de pistes est
/// `StatelessWidget`, et la chaîne (identifier le titre auprès de TMDB, puis
/// interroger le fournisseur) prend deux à trois secondes — sans indicateur,
/// l'utilisateur appuie une deuxième fois.
///
/// ⚠️ Elle n'ouvre la feuille de résultats qu'APRÈS avoir obtenu la liste, et
/// par-dessus la feuille de pistes plutôt qu'à sa place : refermer celle-ci
/// d'abord invaliderait le contexte dont on a besoin pour ouvrir la suivante.
class _OnlineSubtitleRow extends StatefulWidget {
  final AetherPlaybackEngine player;
  final SubtitleSearchContext search;

  /// Appelé quand un sous-titre est posé : la feuille de pistes se referme,
  /// on revient à la vidéo qui les affiche déjà.
  final VoidCallback onLoaded;

  const _OnlineSubtitleRow({
    required this.player,
    required this.search,
    required this.onLoaded,
  });

  @override
  State<_OnlineSubtitleRow> createState() => _OnlineSubtitleRowState();
}

class _OnlineSubtitleRowState extends State<_OnlineSubtitleRow> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return _TrackRow(
      accent: kAccentSecondary,
      leading: _busy
          ? const SizedBox(
              width: 42,
              height: 30,
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : _IconBadge(Icons.travel_explore_rounded, kAccentSecondary),
      title: context.l10n.tracksSearchOnline,
      subtitle: _busy
          ? context.l10n.tracksOnlineSearching
          : context.l10n.tracksSearchOnlineSub,
      selected: false,
      // ⚠️ §boundFocus — la ligne reste TOUJOURS activable : la neutraliser
      // pendant la recherche lui ferait perdre le focus à la télécommande.
      // C'est `_start` qui refuse un second départ.
      onTap: _start,
    );
  }

  Future<void> _start() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      // Lot 11 — La chaîne (clé, identification TMDB, fournisseur) est
      // partagée avec la rangée TV : `findOnlineSubtitles`.
      final found = await findOnlineSubtitles(widget.search, l10n);
      if (found.error != null) {
        _TrackSelector._toast(messenger, found.error!);
        return;
      }
      if (!mounted) return;
      await _showResults(found.results);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showResults(List<OnlineSubtitle> results) {
    return showAdaptiveActionSheet<void>(
      context: context,
      builder: (sheetCtx) => _OnlineResults(
        results: results,
        onPick: (s) => _apply(sheetCtx, s),
        onClose: () => Navigator.of(sheetCtx).pop(),
      ),
    );
  }

  /// Télécharge puis pose le fichier (`loadOnlineSubtitle`). ⚠️ Tout ce qui
  /// vient d'un contexte est pris AVANT les attentes : les deux feuilles se
  /// referment en chemin.
  Future<void> _apply(BuildContext sheetCtx, OnlineSubtitle s) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = context.l10n;
    final nav = Navigator.of(sheetCtx);

    if (!await loadOnlineSubtitle(widget.player, s)) {
      _TrackSelector._toast(messenger, l10n.tracksOnlineAddFailed);
      return;
    }
    if (nav.canPop()) nav.pop();
    widget.onLoaded();
    _TrackSelector._toast(messenger, l10n.tracksOnlineAdded);
  }
}

/// Lot 11 — La liste des sous-titres proposés. Le sous-titre d'une ligne dit
/// la VERSION à laquelle il est calé : c'est la seule chose qui distingue deux
/// entrées de la même langue, et donc la seule qui aide à choisir.
class _OnlineResults extends StatelessWidget {
  final List<OnlineSubtitle> results;
  final ValueChanged<OnlineSubtitle> onPick;
  final VoidCallback onClose;

  const _OnlineResults({
    required this.results,
    required this.onPick,
    required this.onClose,
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
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.travel_explore_rounded,
                        color: kAccentSecondary, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      context.l10n.tracksOnlineTitle,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                ...results.map((s) => _TrackRow(
                      accent: kAccentSecondary,
                      leading: _LangBadge(
                          trackLanguageShort(s.language), kAccentSecondary),
                      title: trackLanguageName(s.language) ?? s.display,
                      subtitle: onlineSubtitleDetail(context.l10n, s),
                      selected: false,
                      onTap: () => onPick(s),
                    )),
                // §tvOptionsBack — La sortie, en dernier.
                const SizedBox(height: 18),
                BackToVideoRow(onTap: onClose),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
