import 'package:flutter/material.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/services/favorites_service.dart';
import 'package:aetherStream/data/services/last_watched_channel_service.dart';
import 'package:aetherStream/data/services/tmdb_service.dart';
import 'package:aetherStream/data/services/tmdb_api_service.dart';
import 'package:aetherStream/data/services/replay_service.dart';
import 'package:aetherStream/data/services/watch_progress_service.dart';
import 'package:aetherStream/feature/search/m3u_filter.dart';
import 'package:aetherStream/feature/player/player_page.dart';
import 'package:aetherStream/feature/search/details_page.dart';
import 'package:aetherStream/feature/replay/replay_widget.dart';
import 'package:aetherStream/feature/replay/replay_date_picker_sheet.dart';
import 'package:aetherStream/feature/downloads/logic/download_initiator.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:aetherStream/main.dart';
import 'package:aetherStream/widgets/confirm_or_undo.dart';
import 'package:aetherStream/widgets/media_chips.dart';
import 'package:aetherStream/widgets/aether_image.dart';
import 'package:aetherStream/widgets/quality_buttons.dart';
import 'package:aetherStream/widgets/epg_block.dart';
import 'package:aetherStream/widgets/tv/tv_adaptive_modal.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Sélecteur de version (films/séries avec plusieurs variantes)
// ─────────────────────────────────────────────────────────────────────────────

Future<M3uEntry?> showVersionSelector(BuildContext context, List<M3uEntry> versions) {
  // §3c-4 — bifurque mobile/TV : bottom sheet sur mobile, Dialog centré sur TV.
  return showAdaptiveActionSheet<M3uEntry>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => Container(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text("Choisir une version", style: Theme.of(context).textTheme.titleLarge),
        ),
        const Divider(height: 1),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: versions.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
            itemBuilder: (ctx, i) {
              final v          = versions[i];
              final year       = v.title.year;
              final extraInfo  = v.title.versionLabel ?? "Standard / Inconnue";
              final qChip      = qualityChip(v.title);
              final langChips  = languageChips(v.title);
              final allChips   = <Widget>[];

              if (year != null) {
                allChips.add(Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(border: Border.all(color: Theme.of(ctx).colorScheme.outline.withAlpha(150)), borderRadius: BorderRadius.circular(4)),
                  child: Text(year, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Theme.of(ctx).colorScheme.onSurface)),
                ));
              }
              if (qChip is! SizedBox) allChips.add(qChip);
              allChips.addAll(langChips);

              Widget titleWidget;
              Widget? subtitleWidget;

              if (allChips.isNotEmpty) {
                titleWidget = Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: allChips);
                if (extraInfo.isNotEmpty && extraInfo != "Standard / Inconnue") {
                  subtitleWidget = Text(extraInfo, style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant));
                }
              } else {
                titleWidget = Text(extraInfo, style: const TextStyle(fontWeight: FontWeight.bold));
              }

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                title: titleWidget,
                subtitle: subtitleWidget,
                trailing: Icon(Icons.check_circle_outline, color: Theme.of(ctx).colorScheme.onSurface.withAlpha(60), size: 20),
                onTap: () => Navigator.pop(ctx, v),
              );
            },
          ),
        ),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Action sheet Films / Séries
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showMediaActionSheet(BuildContext context, M3uEntry entry) async {
  final l10n = AppLocalizations.of(context)!;
  final bool hasEpisode = entry.title.isSeriesEpisode;

  Future<dynamic>? tmdbFuture;
  if (hasEpisode && entry.title.seasonNumber != null && entry.title.episodeNumber != null) {
    tmdbFuture = TmdbService.instance.getEpisodeDetails(
      entry.displayName,
      entry.title.seasonNumber!,
      entry.title.episodeNumber!,
      // §epSynopsis — id TMDB provider prioritaire (fallback recherche floue).
      tmdbId: int.tryParse(entry.tmdbId ?? ''),
      yearFilter: entry.title.year,
      groupTitle: entry.groupTitle,
    );
  } else if (entry.type == M3uContentType.movie) {
    tmdbFuture = TmdbService.instance.getFullDetails(
      entry.displayName,
      isTv: false,
      explicitYear: entry.title.year,
      groupTitle: entry.groupTitle,
    );
  } else if (entry.type == M3uContentType.series) {
    tmdbFuture = TmdbService.instance.getFullDetails(
      entry.displayName,
      isTv: true,
      explicitYear: entry.title.year,
      groupTitle: entry.groupTitle,
    );
  }

  // §3c-4 — bifurque mobile/TV.
  await showAdaptiveActionSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // ── HEADER ──────────────────────────────────────────────────────────
          if (entry.title.isSeriesEpisode)
            FutureBuilder<dynamic>(
              future: tmdbFuture,
              builder: (context, snap) {
                final isLoading = snap.connectionState != ConnectionState.done;
                final data      = snap.data as Map<String, dynamic>?;
                final String? stillPath = data?['still_path'] as String?;
                final String? imageUrl  = stillPath != null
                    ? TmdbService.getPosterUrl(stillPath, size: 'w780')
                    : (entry.logoUrl?.isNotEmpty == true ? entry.logoUrl : null);

                String epName = data?['name'] as String? ?? '';
                // §epTitleProvider — fallback titre panel avant l'extraction
                // regex du rawTitle (episodeName).
                if (epName.isEmpty) epName = entry.episodeTitle ?? '';
                if (epName.isEmpty || epName == entry.displayName) {
                  epName = episodeName(entry);
                }

                final double? voteAvg = (data?['vote_average'] as num?)?.toDouble()
                    ?? entry.rating;
                final String? airDate  = data?['air_date'] as String?
                    ?? entry.releaseDate;
                // §epSynopsis — fallback plot PROVIDER de l'épisode (mappé par
                // fetchEpisodes) quand TMDB ne rend rien.
                final String? tmdbOverview = data?['overview'] as String?;
                final String? overview = (tmdbOverview?.isNotEmpty == true)
                    ? tmdbOverview
                    : entry.plot;
                final s = (entry.title.seasonNumber ?? 0).toString().padLeft(2, '0');
                final e = (entry.title.episodeNumber ?? 0).toString().padLeft(2, '0');
                final dimColor = Theme.of(context).colorScheme.onSurface.withAlpha(128);

                return Column(children: [
                  if (imageUrl != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        // §imgDiskCache — cache disque ; §imgPerf cap 720 px.
                        child: AetherImage(
                          url: imageUrl,
                          height: stillPath != null ? 160 : 140,
                          width: double.infinity,
                          fit: stillPath != null ? BoxFit.cover : BoxFit.contain,
                          cacheWidth: 720,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      '${entry.displayName}  ·  S$s E$e',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: dimColor),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (isLoading)
                    // §1i — Skeleton placeholders pendant le chargement TMDB.
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 32, vertical: 6),
                      child: Column(
                        children: [
                          _SkeletonLine(width: 220, height: 22),
                          SizedBox(height: 8),
                          _SkeletonLine(width: 120, height: 14),
                        ],
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text(epName, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                    ),
                  if (!isLoading && (voteAvg != null && voteAvg > 0 || airDate != null))
                    Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        if (voteAvg != null && voteAvg > 0) ...[
                          Icon(Icons.star_rounded, size: 15, color: kWarning),
                          const SizedBox(width: 3),
                          Text(voteAvg.toStringAsFixed(1), style: Theme.of(context).textTheme.bodySmall),
                          if (airDate != null) const SizedBox(width: 12),
                        ],
                        if (airDate != null)
                          Text(airDate, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: dimColor)),
                      ]),
                    ),
                  if (!isLoading && overview != null && overview.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: Text(overview, style: Theme.of(context).textTheme.bodySmall, maxLines: 4, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                    ),
                  if (isLoading)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(32, 10, 32, 0),
                      child: Column(
                        children: [
                          _SkeletonLine(width: double.infinity, height: 10),
                          SizedBox(height: 6),
                          _SkeletonLine(width: double.infinity, height: 10),
                          SizedBox(height: 6),
                          _SkeletonLine(width: 180, height: 10),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                ]);
              },
            )
          else ...[
            if (entry.logoUrl != null && entry.logoUrl!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  // §imgDiskCache — cache disque partagé (AetherImage).
                  child: AetherImage(
                      url: entry.logoUrl, height: 150, cacheWidth: 320),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(entry.displayName, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 8),
          ],
          // ── Chips qualité/langue ─────────────────────────────────────────────
          // §sheetGap — Le `Wrap` et son `SizedBox(24)` étaient posés sans
          // condition. Or `qualityChip` renvoie un `SizedBox.shrink()` quand
          // aucune qualité n'est détectée, et `languageChips` une liste vide :
          // sur un titre sans marqueur, la feuille gardait donc un trou d'une
          // trentaine de pixels plus la marge — un vide inexpliqué entre le
          // titre et « Lire ». On ne réserve la place que s'il y a quelque
          // chose à y mettre.
          ...(() {
            final chips = <Widget>[
              if (entry.title.quality != null) qualityChip(entry.title),
              ...languageChips(entry.title),
            ];
            if (chips.isEmpty) return const <Widget>[SizedBox(height: 8)];
            return <Widget>[
              Wrap(spacing: 8, children: chips),
              const SizedBox(height: 24),
            ];
          })(),
          // ── Bouton Fiche détaillée (masqué si pas de clé TMDB) ──────────────
          FutureBuilder<bool>(
            future: TmdbApiService.hasApiKey(),
            builder: (ctx, snap) {
              if (snap.data != true) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => DetailsPage(entry: entry)));
                    },
                    icon: const Icon(Icons.info_outline),
                    label: const Text("Fiche Détaillée & Infos"),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          // ── Lecture (avec reprise §1e) ──────────────────────────────────────
          _PlayResumeTiles(entry: entry, l10n: l10n),
          // ── Favoris (toggle) ───────────────────────────────────────────────
          _FavoriteToggleTile(entry: entry),
          // ── Replay (TV uniquement) ───────────────────────────────────────────
          if (entry.type == M3uContentType.tv && entry.streamId != null)
            ListTile(
              leading: const Icon(Icons.replay),
              title: Text("Replay${entry.catchupDays != null ? ' (${entry.catchupDays}j)' : ''}"),
              onTap: () async {
                Navigator.pop(context);
                final replayProgram = await showAdaptiveActionSheet<ReplayProgram>(
                  context: context,
                  showDragHandle: true,
                  isScrollControlled: true,
                  builder: (_) => ReplaySheet(streamId: entry.streamId!, streamUrl: entry.url),
                );
                if (replayProgram != null) {
                  final timeshiftUrl = await ReplayService().buildTimeshiftUrl(
                    streamId: entry.streamId!,
                    start: replayProgram.start,
                    end: replayProgram.end,
                    streamUrl: entry.url,
                    catchupSource: entry.catchupSource,
                  );
                  if (timeshiftUrl != null) {
                    Navigator.push(
                      navigatorKey.currentContext!,
                      MaterialPageRoute(builder: (_) => PlayerPage(
                        path: timeshiftUrl,
                        title: replayProgram.title,
                        accountId: entry.accountId,
                        sourceType: VideoSourceType.networkReplay,
                        badgeType: PlayerBadgeType.replay,
                        replayStart: replayProgram.start,
                        replayDuration: replayProgram.end.difference(replayProgram.start),
                      )),
                    );
                  }
                }
              },
            ),
          // ── Téléchargement ──────────────────────────────────────────────────
          ListTile(
            leading: const Icon(Icons.download),
            title: Text(l10n.actionSheetDownload),
            onTap: () {
              Navigator.pop(context);
              final releaseYear = entry.type == M3uContentType.movie ? entry.title.year : null;
              verifierEtTelecharger(
                url: entry.url,
                nom: buildDownloadName(entry),
                releaseYear: releaseYear,
                context: navigatorKey.currentContext!,
              );
            },
          ),
          const SizedBox(height: 16),
        ]),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Action sheet TV (avec EPG + sélection qualité)
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showTvActionSheet(BuildContext context, List<M3uEntry> rawVersions) async {
  // §URGENT — défense en profondeur : dédup qualité au cas où l'appelant
  // fournirait une liste non dédoublonnée (ex: code legacy / nouveau call site).
  final versions = dedupeTvVersions(rawVersions);
  final entry = versions.firstWhere((v) => v.tvgId != null, orElse: () => versions.first);

  const replayQualities = {'FHD', 'HD', 'SD'};
  const qualityOrder    = {'FHD': 0, 'HD': 1, 'SD': 2};

  final entryForReplay = versions.firstWhere(
    (v) => v.streamId != null && v.title.quality == 'FHD',
    orElse: () => versions.firstWhere(
      (v) => v.streamId != null && v.title.quality == 'HD',
      orElse: () => versions.firstWhere(
        (v) => v.streamId != null && v.title.quality == 'SD',
        orElse: () => versions.firstWhere((v) => v.streamId != null, orElse: () => entry),
      ),
    ),
  );

  final replayEntries = versions
      .where((v) => v.streamId != null && replayQualities.contains(v.title.quality))
      .toList()
    ..sort((a, b) => (qualityOrder[a.title.quality] ?? 99).compareTo(qualityOrder[b.title.quality] ?? 99));

  final replayStreams = labeledVersions(replayEntries)
      .map((e) => ReplayStreamOption(
            label: e.$2,
            streamId: e.$1.streamId!,
            streamUrl: e.$1.url,
            catchupSource: e.$1.catchupSource,
            catchupDays: e.$1.catchupDays,
          ))
      .toList();

  void playVersion(M3uEntry v) {
    // Auto-ajout aux favoris au lancement de la lecture (§1d)
    FavoritesService.addEntry(v);
    // §1i — Mémoriser la dernière chaîne pour la tuile "Reprendre la chaîne".
    LastWatchedChannelService.save(
      url: v.url,
      title: v.displayName,
      tvgId: v.tvgId,
      logoUrl: v.logoUrl,
    );
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerPage(
      path: v.url,
      title: v.displayName,
      // §stallCount — rattache les blocages au fournisseur.
      accountId: v.accountId,
      // §watchContext a/c — qualité du flux choisi affichée dans le player
      // (lève l'ambiguïté « sur quel produit/qualité suis-je ? »).
      qualityTag: v.title.qualityOrDefault,
      sourceType: VideoSourceType.network,
      badgeType: PlayerBadgeType.live,
    )));
  }

  // §3c-4 — bifurque mobile/TV pour l'action sheet TV.
  await showAdaptiveActionSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.displayName,
                  style: Theme.of(context).textTheme.headlineSmall,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 12),
              if (entry.tvgId != null)
                EpgNowNextBlock(tvgId: entry.tvgId!, versions: versions, onPlayVersion: playVersion),
              if (entry.tvgId == null)
                QualityButtonsRow(versions: versions, onPlay: playVersion),
              const SizedBox(height: 4),
              // ── Favoris (toggle) ───────────────────────────────────────
              _FavoriteToggleTile(entry: entry),
              if (entryForReplay.streamId != null)
                ListTile(
                  leading: const Icon(Icons.replay_circle_filled),
                  title: Text("Replay${entryForReplay.catchupDays != null ? ' (${entryForReplay.catchupDays}j)' : ''}"),
                  onTap: () async {
                    Navigator.pop(context);
                    final replayProgram = await showAdaptiveActionSheet<ReplayProgram>(
                      context: context,
                      showDragHandle: true,
                      isScrollControlled: true,
                      builder: (_) => ReplayDatePickerSheet(
                        tvgId: entry.tvgId,
                        catchupDays: entryForReplay.catchupDays,
                        streams: replayStreams,
                      ),
                    );
                    if (replayProgram != null) {
                      final timeshiftUrl = await ReplayService().buildTimeshiftUrl(
                        streamId: replayProgram.selectedStreamId ?? entryForReplay.streamId!,
                        start: replayProgram.start,
                        end: replayProgram.end,
                        streamUrl: replayProgram.selectedStreamUrl ?? entryForReplay.url,
                        catchupSource: replayProgram.selectedCatchupSource ?? entryForReplay.catchupSource,
                      );
                      if (timeshiftUrl != null) {
                        Navigator.push(
                          navigatorKey.currentContext!,
                          MaterialPageRoute(builder: (_) => PlayerPage(
                            path: timeshiftUrl,
                            title: replayProgram.title,
                            accountId: entryForReplay.accountId,
                            sourceType: VideoSourceType.networkReplay,
                            badgeType: PlayerBadgeType.replay,
                            replayStart: replayProgram.start,
                            replayDuration: replayProgram.end.difference(replayProgram.start),
                          )),
                        );
                      } else {
                        ScaffoldMessenger.of(navigatorKey.currentContext!)..hideCurrentSnackBar()..showSnackBar(
                          const SnackBar(content: Text("Replay indisponible pour ce flux")),
                        );
                      }
                    }
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ListTile favori — toggle avec feedback visuel (cœur plein/vide) + snackbar
// Utilisé dans showMediaActionSheet et showTvActionSheet.
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// §1e — Tuiles "Reprendre depuis X:XX" + "Lire depuis le début"
// ─────────────────────────────────────────────────────────────────────────────

/// Format Duration → "1h23" ou "12:34" pour un libellé court de reprise.
String _formatResumeLabel(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '${h}h${m.toString().padLeft(2, '0')}';
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

void _launchPlayer(BuildContext context, M3uEntry entry, {Duration? startPosition}) {
  FavoritesService.addEntry(entry);
  Navigator.pop(context);
  Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerPage(
    path: entry.url,
    title: entry.displayName,
    // §stallCount — rattache les blocages au fournisseur.
    accountId: entry.accountId,
    // §watchContext a/b — badges qualité + saison/épisode.
    qualityTag: entry.title.qualityOrDefault,
    episodeTag: entry.title.seasonEpisodeLabel,
    sourceType: VideoSourceType.network,
    badgeType: entry.type == M3uContentType.series
        ? PlayerBadgeType.series
        : PlayerBadgeType.movie,
    startPosition: startPosition,
  )));
}

class _PlayResumeTiles extends StatelessWidget {
  final M3uEntry entry;
  final AppLocalizations l10n;
  const _PlayResumeTiles({required this.entry, required this.l10n});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: WatchProgressService.version,
      builder: (ctx, _, __) {
        final p = WatchProgressService.getProgress(entry.url);
        final hasResume = p != null && p.position.inSeconds > 5;
        if (!hasResume) {
          return ListTile(
            leading: const Icon(Icons.play_arrow),
            title: Text(l10n.actionSheetPlay),
            onTap: () => _launchPlayer(context, entry),
          );
        }
        return Column(
          children: [
            ListTile(
              leading: Icon(Icons.play_arrow, color: kAccentSecondary),
              title: Text(
                'Reprendre depuis ${_formatResumeLabel(p.position)}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: kAccentSecondary,
                ),
              ),
              subtitle: LinearProgressIndicator(
                value: p.ratio,
                minHeight: 3,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation(kAccentSecondary),
              ),
              onTap: () => _launchPlayer(context, entry, startPosition: p.position),
            ),
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: Text(
                'Lire depuis le début',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              dense: true,
              onTap: () {
                WatchProgressService.clearProgress(entry.url);
                _launchPlayer(context, entry);
              },
            ),
            // §forgetResume — Permet à l'utilisateur de retirer la reprise
            // sans lancer la lecture ("plus envie de voir ce film").
            ListTile(
              leading: Icon(Icons.history_toggle_off, color: kWarning),
              title: Text(
                'Oublier la reprise',
                style: TextStyle(fontSize: 13, color: kWarning),
              ),
              dense: true,
              // §undoTv — La feuille reste OUVERTE pendant la décision : sur TV
              // `confirmOrUndo` ouvre un dialogue, qui a besoin d'un contexte
              // encore monté. On ferme donc APRÈS, et seulement si l'action a
              // bien eu lieu — un « Annuler » au D-pad ramène l'utilisateur là
              // où il était, sans le renvoyer à la liste.
              onTap: () async {
                final snapshot = p;
                final done = await confirmOrUndo(
                  context,
                  title: 'Oublier la reprise ?',
                  question: 'La position de lecture de ce titre sera oubliée.',
                  confirmLabel: 'Oublier',
                  doneMessage: 'Reprise oubliée',
                  action: () => WatchProgressService.clearProgress(entry.url),
                  onUndo: () {
                    WatchProgressService.saveProgress(
                      entry.url,
                      snapshot.position,
                      snapshot.duration,
                    );
                  },
                );
                if (done && context.mounted) Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }
}

class _FavoriteToggleTile extends StatelessWidget {
  final M3uEntry entry;
  const _FavoriteToggleTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: FavoritesService.version,
      builder: (ctx, _, __) {
        final isFav = FavoritesService.isEntryFavorite(entry);
        return ListTile(
          // §themePlus — couleur favori unifiée (avant : kAccentTertiary ici
          // mais kFavorite sur la fiche → deux couleurs pour le même concept).
          leading: Icon(
            isFav ? Icons.favorite : Icons.favorite_border,
            color: isFav ? kFavorite : null,
          ),
          title: Text(
            // §l10nMix — Ces deux libellés étaient écrits EN DUR en français,
            // au milieu d'une feuille dont tous les autres passent par l10n.
            // Sur un appareil non francophone, la même feuille affichait donc
            // « Play » / « Download in background » à côté d'« Ajouter aux
            // favoris » (constaté sur l'émulateur, locale en-US).
            isFav
                ? AppLocalizations.of(ctx)!.favoriteRemove
                : AppLocalizations.of(ctx)!.favoriteAdd,
            style: TextStyle(
              color: isFav ? kFavorite : null,
              fontWeight: isFav ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          onTap: () async {
            final messenger = ScaffoldMessenger.of(context);
            final added = await FavoritesService.toggleEntry(entry);
            if (!context.mounted) return;
            messenger..hideCurrentSnackBar()..showSnackBar(SnackBar(
              content: Text(added
                  ? '⭐ "${entry.displayName}" ajouté aux favoris'
                  : '🗑️ "${entry.displayName}" retiré des favoris'),
              duration: const Duration(seconds: 2),
            ));
          },
        );
      },
    );
  }
}


// ─── §1i Skeleton helper pour les chargements TMDB ───────────────────────────

class _SkeletonLine extends StatefulWidget {
  final double width;
  final double height;
  const _SkeletonLine({required this.width, required this.height});

  @override
  State<_SkeletonLine> createState() => _SkeletonLineState();
}

class _SkeletonLineState extends State<_SkeletonLine> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(
            cs.surfaceContainerHighest,
            cs.outline.withAlpha(60),
            _ctrl.value,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}
