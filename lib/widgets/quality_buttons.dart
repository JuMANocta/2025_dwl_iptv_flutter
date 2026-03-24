import 'package:flutter/material.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/core/themes/colors.dart';

/// Trie les versions par qualité décroissante et génère un label lisible.
List<(M3uEntry, String)> labeledVersions(List<M3uEntry> versions) {
  const order = {'4K': 0, 'UHD': 0, 'FHD': 1, 'HD': 2, 'SD': 3};
  final sorted = List<M3uEntry>.from(versions)
    ..sort((a, b) => (order[a.title.quality] ?? 99)
        .compareTo(order[b.title.quality] ?? 99));

  return sorted.indexed.map((e) {
    final i = e.$1;
    final v = e.$2;
    final label = v.title.quality ??
        (v.title.languages.isNotEmpty ? v.title.languages.first : null) ??
        v.title.versionLabel ??
        'Flux ${i + 1}';
    return (v, label);
  }).toList();
}

class QualityButtonsRow extends StatelessWidget {
  final List<M3uEntry> versions;
  final void Function(M3uEntry) onPlay;

  const QualityButtonsRow({super.key, required this.versions, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final labeled = labeledVersions(versions);
    if (labeled.length == 1) {
      return SizedBox(
        width: double.infinity,
        child: _playButton(labeled.first.$1, labeled.first.$2, full: true),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: labeled.map((e) => _playButton(e.$1, e.$2)).toList(),
    );
  }

  Widget _playButton(M3uEntry v, String label, {bool full = false}) {
    return SizedBox(
      height: 36,
      width: full ? double.infinity : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: kAetherGradient,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onPlay(v),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: full ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.play_arrow_rounded, color: kWhite, size: 16),
                  const SizedBox(width: 4),
                  Text(label, style: const TextStyle(color: kWhite, fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
