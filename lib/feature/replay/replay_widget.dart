import 'package:flutter/material.dart';
import '../../data/services/replay_service.dart';

/// Feuille affichant les programmes en replay pour un stream donné.
class ReplaySheet extends StatelessWidget {
  final int streamId;
  final String? streamUrl;
  const ReplaySheet({super.key, required this.streamId, this.streamUrl});

  @override
  Widget build(BuildContext context) {
    debugPrint('ReplaySheet: Reçu streamId: $streamId, streamUrl: $streamUrl');
    final service = ReplayService();
    return SafeArea(
      child: FutureBuilder<List<ReplayProgram>>(
        future: service.fetchShortEpg(streamId, streamUrl: streamUrl),
        builder: (context, snap) {
          debugPrint('ReplaySheet FutureBuilder: ConnectionState: ${snap.connectionState}, hasError: ${snap.hasError}, hasData: ${snap.hasData}');
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snap.hasError) {
            debugPrint('ReplaySheet FutureBuilder: Erreur: ${snap.error}');
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text('Erreur EPG: ${snap.error}', style: const TextStyle(color: Colors.red)),
            );
          }
          final programs = snap.data ?? [];
          debugPrint('ReplaySheet FutureBuilder: Nombre de programmes reçus: ${programs.length}');
          if (programs.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(child: Text('Aucun replay disponible.')),
            );
          }
          return ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: programs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final p = programs[i];
              return ListTile(
                leading: Icon(
                  p.hasArchive ? Icons.replay_circle_filled : Icons.replay,
                  color: p.hasArchive ? null : Colors.grey,
                ),
                title: Text(
                  p.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.hasArchive ? null : Colors.grey),
                ),
                subtitle: Text('${p.startLabel}  •  ${p.durationLabel}${p.hasArchive ? '' : '  • non disponible'}'),
                onTap: p.hasArchive ? () => Navigator.of(context).pop(p) : null,
              );
            },
          );
        },
      ),
    );
  }
}
