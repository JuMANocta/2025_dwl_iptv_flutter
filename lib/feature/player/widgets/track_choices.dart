import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../playback_engine.dart';

import '../../../core/utils/app_snackbar.dart';
import '../../../data/services/online_subtitles_service.dart';
import '../../../data/services/subtitle_api_service.dart';
import '../../../data/services/tmdb_service.dart';
import '../../../data/services/track_preferences_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/l10n_ext.dart';
import '../track_language_names.dart';
import 'player_option_bar.dart' show PlayerOptionItem;

// ─── §playerPanel — les choix de pistes du lecteur ──────────────────────────
//
// Audio et Sous-titres se choisissent dans la rangée d'options, DANS l'image
// (`player_option_bar.dart`), au doigt comme à la télécommande. La feuille de
// pistes du téléphone (`showTrackSelector`) est partie avec les autres
// feuilles du lecteur : deux interfaces pour les mêmes réglages finissaient
// par ne plus dire la même chose.
//
// Ce fichier ne dessine rien. Il porte :
// - la logique partagée d'application des pistes (R43, R5, lot 11) ;
// - la construction des listes Audio et Sous-titres ([audioOptionItems],
//   [subtitleOptionItems], [onlineSubtitleOptionItems]), sorties du lecteur
//   pour que leur ORDRE se teste sans monter la page : « Désactivés » en tête
//   s'il y a une piste, « Aucun sous-titre détecté » sinon (R42), la mémoire
//   en fin de section (R43), la recherche en ligne en dernier (lot 11).
//
// Ces fonctions appliquent les pistes, et elles seules : deux copies de la
// règle R43 (« mémoriser seulement si la piste est posée ») finiraient par
// diverger.

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

// ─── §playerPanel — les listes Audio et Sous-titres ─────────────────────────
//
// Construites à chaque ouverture et relues à chaque image (les coches suivent
// le moteur). Une ligne rend `true` quand c'est fait (la liste se referme),
// `false` quand elle doit rester ouverte : l'échec a déjà été DIT par
// [showTrackToast] (R42), ou la liste a été remplacée.
//
// [onApplied] est appelé après chaque changement réussi : le lecteur y relit
// les pistes (le natif applique sur son propre fil, sans rien signaler).

/// R42 — « Aucune piste détectée » : une ligne d'INFORMATION, en tête d'une
/// liste dont le moteur n'a aucune piste. Jamais cochée, et elle n'applique
/// RIEN : la choisir referme simplement la liste. Grâce à elle, une liste
/// n'est jamais vide.
PlayerOptionItem _noTrackItem(String label) => PlayerOptionItem(
      label: label,
      icon: Icons.info_outline_rounded,
      onSelect: () async => true,
    );

/// Liste Audio : les pistes (ou « Aucune piste audio détectée »), puis la
/// mémoire « revenir à l'automatique » (R43 : en FIN de liste, jamais
/// l'action par défaut d'OK).
///
/// ⚠️ R43 — Plus de lignes `'auto'` / `'no'` : `Media3Engine` ne fabrique que
/// des `id: '<index>'`.
List<PlayerOptionItem> audioOptionItems({
  required AetherPlaybackEngine player,
  required AppLocalizations l10n,
  ScaffoldMessengerState? messenger,
  VoidCallback? onApplied,
}) {
  final List<AetherTrack> tracks = player.audioTracks;
  final AetherTrack? cur = player.currentAudioTrack;
  final String? memory = TrackPreferencesService.audio;
  return [
    if (tracks.isEmpty) _noTrackItem(l10n.tracksNoAudio),
    for (final t in tracks)
      PlayerOptionItem(
        label: trackDisplayTitle(t),
        detail: trackDisplayDetail(t),
        selected: t.id == cur?.id,
        onSelect: () async {
          // §trackRebuffer — ne pas ré-appliquer une piste déjà active.
          if (t.id == player.currentAudioTrack?.id) return true;
          // R43 — la langue n'est mémorisée QUE si la piste est posée.
          final bool ok = await applyAudioTrackChoice(player, t);
          if (!ok) showTrackToast(messenger, l10n.tracksTrackFailed);
          if (ok) onApplied?.call();
          return ok;
        },
      ),
    if (memory != null)
      PlayerOptionItem(
        label: l10n.tracksMemoryAudio(
            trackLanguageName(memory) ?? memory.toUpperCase()),
        detail: l10n.tracksMemoryForget,
        icon: Icons.restart_alt_rounded,
        onSelect: () async {
          final bool ok = await player.resetAudioToAuto();
          if (!ok) showTrackToast(messenger, l10n.tracksResetFailed);
          if (ok) onApplied?.call();
          return ok;
        },
      ),
  ];
}

/// Liste Sous-titres : « Désactivés » EN TÊTE dès qu'il y a une piste
/// (§subOff), les pistes, la coupure mémorisée (R43), puis « Chercher en
/// ligne » en DERNIER — une recherche remplace la liste par ses résultats.
///
/// ⛔ R42 — Sans AUCUNE piste, pas de « Désactivés » : des sous-titres
/// INCRUSTÉS dans l'image se présentent ainsi, aucun lecteur ne sait les
/// retirer, et l'interface ne doit pas promettre l'inverse. La tête de liste
/// dit alors « Aucun sous-titre détecté ». La rangée TV de la 1.20.2 l'avait
/// perdu (ligne inconditionnelle) : c'était une régression.
///
/// [onSearchOnline] `null` = la ligne n'existe pas (contenu non identifiable :
/// une chaîne en direct, un titre vide). [onlineBusy] : une recherche est en
/// cours, la ligne le dit (§boundFocus : elle reste activable, c'est
/// [onSearchOnline] qui refuse un second départ).
List<PlayerOptionItem> subtitleOptionItems({
  required AetherPlaybackEngine player,
  required AppLocalizations l10n,
  ScaffoldMessengerState? messenger,
  VoidCallback? onApplied,
  Future<bool> Function()? onSearchOnline,
  bool onlineBusy = false,
}) {
  final List<AetherTrack> tracks = player.subtitleTracks;
  final AetherTrack? cur = player.currentSubtitleTrack;
  return [
    if (tracks.isEmpty)
      _noTrackItem(l10n.tracksNoSubtitles)
    else ...[
      // R42 — coupure SÉMANTIQUE ([disableSubtitles]), jamais un identifiant
      // de piste ; cochée quand le moteur ne lit aucune piste.
      PlayerOptionItem(
        label: l10n.tracksDisabled,
        icon: Icons.subtitles_off_rounded,
        selected: cur == null,
        onSelect: () async {
          // R42 — ATTENDUE : un échec se dit, et c'est le moteur qui mémorise.
          final bool ok = await player.disableSubtitles();
          if (!ok) showTrackToast(messenger, l10n.tracksDisableFailed);
          if (ok) onApplied?.call();
          return ok;
        },
      ),
      for (final t in tracks)
        PlayerOptionItem(
          label: trackDisplayTitle(t),
          detail: trackDisplayDetail(t),
          selected: t.id == cur?.id,
          onSelect: () async {
            // §trackRebuffer — ne pas ré-appliquer une piste déjà active.
            if (t.id == player.currentSubtitleTrack?.id) return true;
            // R43 — rien n'est mémorisé ici : c'est le moteur qui lève la
            // coupure mémorisée, et une piste ne vaut que pour ce titre.
            final bool ok = await player.setSubtitleTrack(t);
            if (!ok) showTrackToast(messenger, l10n.tracksTrackFailed);
            if (ok) onApplied?.call();
            return ok;
          },
        ),
    ],
    // R43 — La coupure mémorisée, visible et réversible — MÊME sur un titre
    // sans piste : c'est justement là qu'on ne pouvait plus la lever.
    if (TrackPreferencesService.subtitle == TrackPreferencesService.kSubtitlesOff)
      PlayerOptionItem(
        label: l10n.tracksMemorySubOff,
        detail: l10n.tracksMemoryForget,
        icon: Icons.restart_alt_rounded,
        onSelect: () async {
          final bool ok = await player.resetSubtitlesToAuto();
          if (!ok) showTrackToast(messenger, l10n.tracksResetFailed);
          if (ok) onApplied?.call();
          return ok;
        },
      ),
    // Lot 11 — EN FIN de liste : à la télécommande, la ligne courante est
    // l'action par défaut d'OK, et partir sur le réseau ne doit pas l'être.
    if (onSearchOnline != null)
      PlayerOptionItem(
        label: l10n.tracksSearchOnline,
        detail: onlineBusy
            ? l10n.tracksOnlineSearching
            : l10n.tracksSearchOnlineSub,
        icon: Icons.travel_explore_rounded,
        onSelect: onSearchOnline,
      ),
  ];
}

/// Lot 11 — Les résultats d'une recherche en ligne, qui REMPLACENT la liste
/// Sous-titres : une ligne par sous-titre proposé, dont le détail dit la
/// VERSION à laquelle il est calé (c'est ce qui distingue deux entrées de la
/// même langue). La ligne télécharge puis pose le fichier, et le dit.
List<PlayerOptionItem> onlineSubtitleOptionItems({
  required AetherPlaybackEngine player,
  required List<OnlineSubtitle> results,
  required AppLocalizations l10n,
  ScaffoldMessengerState? messenger,
  VoidCallback? onApplied,
}) {
  return [
    for (final s in results)
      PlayerOptionItem(
        label: trackLanguageName(s.language) ?? s.display,
        detail: onlineSubtitleDetail(l10n, s),
        onSelect: () async {
          final bool ok = await loadOnlineSubtitle(player, s);
          showTrackToast(messenger,
              ok ? l10n.tracksOnlineAdded : l10n.tracksOnlineAddFailed);
          if (ok) onApplied?.call();
          return ok;
        },
      ),
  ];
}
