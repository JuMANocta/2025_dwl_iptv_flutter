import 'package:flutter/material.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/services/tmdb_service.dart';
import 'package:aetherStream/data/services/replay_service.dart';
import 'package:aetherStream/feature/player/player_page.dart';
import 'package:aetherStream/feature/search/details_page.dart';
import 'package:aetherStream/feature/replay/replay_widget.dart';
import 'package:aetherStream/feature/replay/replay_date_picker_sheet.dart';
import 'package:aetherStream/feature/downloads/logic/download_initiator.dart';
import 'package:aetherStream/l10n/app_localizations.dart';
import 'package:aetherStream/main.dart';
import 'package:aetherStream/widgets/media_chips.dart';
import 'package:aetherStream/widgets/quality_buttons.dart';
import 'package:aetherStream/widgets/epg_block.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Sélecteur de version (films/séries avec plusieurs variantes)
// ─────────────────────────────────────────────────────────────────────────────

Future<M3uEntry?> showVersionSelector(BuildContext context, List<M3uEntry> versions) {
  return showModalBottomSheet<M3uEntry>(
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

  await showModalBottomSheet(
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
                if (epName.isEmpty || epName == entry.displayName) {
                  epName = episodeName(entry);
                }

                final double? voteAvg = (data?['vote_average'] as num?)?.toDouble();
                final String? airDate  = data?['air_date'] as String?;
                final String? overview = data?['overview'] as String?;
                final s = (entry.title.seasonNumber ?? 0).toString().padLeft(2, '0');
                final e = (entry.title.episodeNumber ?? 0).toString().padLeft(2, '0');
                final dimColor = Theme.of(context).colorScheme.onSurface.withAlpha(128);

                return Column(children: [
                  if (imageUrl != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          imageUrl,
                          height: stillPath != null ? 160 : 140,
                          width: double.infinity,
                          fit: stillPath != null ? BoxFit.cover : BoxFit.contain,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
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
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: SizedBox(height: 4, width: 100, child: LinearProgressIndicator()),
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
                          const Icon(Icons.star_rounded, size: 15, color: Colors.amber),
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
                  child: Image.network(entry.logoUrl!, height: 150, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(entry.displayName, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 8),
          ],
          // ── Chips qualité/langue ─────────────────────────────────────────────
          Wrap(
            spacing: 8,
            children: [qualityChip(entry.title), ...languageChips(entry.title)],
          ),
          const SizedBox(height: 24),
          // ── Bouton Fiche détaillée ───────────────────────────────────────────
          Padding(
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
          ),
          const SizedBox(height: 16),
          // ── Lecture ─────────────────────────────────────────────────────────
          ListTile(
            leading: const Icon(Icons.play_arrow),
            title: Text(l10n.actionSheetPlay),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerPage(
                path: entry.url,
                title: entry.displayName,
                sourceType: VideoSourceType.network,
                badgeType: entry.type == M3uContentType.series ? PlayerBadgeType.series : PlayerBadgeType.movie,
              )));
            },
          ),
          // ── Replay (TV uniquement) ───────────────────────────────────────────
          if (entry.type == M3uContentType.tv && entry.streamId != null)
            ListTile(
              leading: const Icon(Icons.replay),
              title: Text("Replay${entry.catchupDays != null ? ' (${entry.catchupDays}j)' : ''}"),
              onTap: () async {
                Navigator.pop(context);
                final replayProgram = await showModalBottomSheet<ReplayProgram>(
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

Future<void> showTvActionSheet(BuildContext context, List<M3uEntry> versions) async {
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
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerPage(
      path: v.url,
      title: v.displayName,
      sourceType: VideoSourceType.network,
      badgeType: PlayerBadgeType.live,
    )));
  }

  await showModalBottomSheet(
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
              if (entryForReplay.streamId != null)
                ListTile(
                  leading: const Icon(Icons.replay_circle_filled),
                  title: Text("Replay${entryForReplay.catchupDays != null ? ' (${entryForReplay.catchupDays}j)' : ''}"),
                  onTap: () async {
                    Navigator.pop(context);
                    final replayProgram = await showModalBottomSheet<ReplayProgram>(
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
                            sourceType: VideoSourceType.networkReplay,
                            badgeType: PlayerBadgeType.replay,
                            replayStart: replayProgram.start,
                            replayDuration: replayProgram.end.difference(replayProgram.start),
                          )),
                        );
                      } else {
                        ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
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
