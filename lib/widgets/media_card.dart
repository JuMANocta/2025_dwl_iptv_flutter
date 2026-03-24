import 'package:flutter/material.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/widgets/media_chips.dart';

Widget _imagePlaceholder({required IconData icon, required Color color}) {
  return Container(
    width: 45, height: 65,
    decoration: BoxDecoration(color: color.withAlpha(25), borderRadius: BorderRadius.circular(8)),
    child: Icon(icon, color: color),
  );
}

Widget mediaCardImage(List<M3uEntry> versions, IconData fallbackIcon, Color fallbackColor) {
  final logoUrl = versions.isNotEmpty ? versions.first.logoUrl : null;
  return ClipRRect(
    borderRadius: BorderRadius.circular(8.0),
    child: logoUrl != null && logoUrl.isNotEmpty
        ? Image.network(
            logoUrl,
            width: 45, height: 65, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _imagePlaceholder(icon: fallbackIcon, color: fallbackColor),
            loadingBuilder: (_, child, progress) =>
                progress == null ? child : _imagePlaceholder(icon: fallbackIcon, color: fallbackColor),
          )
        : _imagePlaceholder(icon: fallbackIcon, color: fallbackColor),
  );
}

class FilmCard extends StatelessWidget {
  final String filmKey;
  final List<M3uEntry> versions;
  final void Function(List<M3uEntry>) onTap;

  const FilmCard({super.key, required this.filmKey, required this.versions, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final keyParts       = filmKey.split('||');
    final displayTitle   = keyParts[0];
    final categoryLabel  = keyParts.length > 1 ? keyParts[1] : null;
    final uniqueYears    = versions.map((v) => v.title.year).where((y) => y != null).toSet();
    final isHomonymConflict = versions.length > 1 && uniqueYears.length > 1;
    final allQualityChips  = versions.map((v) => qualityChip(v.title));
    final allLanguageChips = versions.expand((v) => languageChips(v.title));
    final uniqueChips = <Widget>{...allQualityChips, ...allLanguageChips}
        .where((w) => w is! SizedBox)
        .toList();

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onTap(versions),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(children: [
            mediaCardImage(versions, Icons.movie, Colors.blue),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(displayTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (categoryLabel != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.withAlpha(40),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.blue.withAlpha(80)),
                      ),
                      child: Text(categoryLabel, style: const TextStyle(fontSize: 11, color: Colors.blue)),
                    ),
                  ],
                ]),
                const SizedBox(height: 4),
                if (isHomonymConflict)
                  Text('Versions disponibles: ${uniqueYears.join(', ')}', style: const TextStyle(color: Colors.white70, fontSize: 12))
                else if (uniqueChips.isNotEmpty)
                  Wrap(spacing: 4, runSpacing: 4, children: uniqueChips),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ]),
        ),
      ),
    );
  }
}

class SerieCard extends StatelessWidget {
  final String seriesKey;
  final Map<String, List<M3uEntry>> saisons;
  final void Function(List<M3uEntry>) onEntrySelected;

  const SerieCard({super.key, required this.seriesKey, required this.saisons, required this.onEntrySelected});

  @override
  Widget build(BuildContext context) {
    final keyParts      = seriesKey.split('||');
    final displayTitle  = keyParts[0];
    final categoryLabel = keyParts.length > 1 ? keyParts[1] : null;
    final totalEpisodes = saisons.values.fold<int>(0, (prev, list) => prev + list.length);
    final allVersions   = saisons.values.expand((list) => list).toList();

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: mediaCardImage(allVersions, Icons.tv, Colors.purple),
          title: Row(children: [
            Expanded(child: Text(displayTitle, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
            if (categoryLabel != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.purple.withAlpha(40),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.purple.withAlpha(80)),
                ),
                child: Text(categoryLabel, style: const TextStyle(fontSize: 11, color: Colors.purple)),
              ),
            ],
          ]),
          subtitle: Text("${saisons.keys.length} Saisons • $totalEpisodes Épisodes", style: const TextStyle(fontSize: 12)),
          children: saisons.entries.map((entry) {
            return ExpansionTile(
              title: Text("Saison ${entry.key}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              leading: const Icon(Icons.folder_open, size: 20),
              children: entry.value.map((ep) => ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 32, right: 16),
                title: Text(episodeName(ep)),
                leading: episodeChip(ep),
                trailing: const Icon(Icons.play_arrow_rounded),
                onTap: () => onEntrySelected([ep]),
              )).toList(),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class TvCard extends StatelessWidget {
  final String displayName;
  final List<M3uEntry> versions;
  final void Function(List<M3uEntry>) onTap;

  const TvCard({super.key, required this.displayName, required this.versions, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasReplay = versions.isNotEmpty && versions.first.supportsCatchup;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onTap(versions),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(children: [
            mediaCardImage(versions, Icons.live_tv, Colors.green),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(children: [
                  if (versions.length > 1)
                    Text('${versions.length} flux', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  if (versions.length > 1 && hasReplay)
                    const Text(" • ", style: TextStyle(color: Colors.white70, fontSize: 12)),
                  if (hasReplay)
                    const Icon(Icons.replay_circle_filled, color: Colors.blueAccent, size: 14),
                ]),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ]),
        ),
      ),
    );
  }
}
