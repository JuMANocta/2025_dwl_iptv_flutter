import 'package:flutter/material.dart';
import 'package:aetherStream/core/themes/colors.dart';
import '../../core/utils/log_sanitizer.dart';
import '../../core/utils/user_error.dart';
import '../../data/services/replay_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/tv/focusable_card.dart';

/// Feuille affichant les programmes en replay pour un stream donné.
class ReplaySheet extends StatelessWidget {
  final int streamId;
  final String? streamUrl;
  const ReplaySheet({super.key, required this.streamId, this.streamUrl});

  @override
  Widget build(BuildContext context) {
    debugPrint('ReplaySheet: Reçu streamId: $streamId, streamUrl: ${redactUrl(streamUrl)}');
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
            // §userError — plus de `snap.error` brut à l'écran : une
            // DioException peut embarquer l'URL avec les identifiants.
            return EmptyState(
              icon: Icons.cloud_off,
              title: 'Guide indisponible',
              subtitle: describeError(snap.error),
              accentColor: kError,
            );
          }
          final programs = snap.data ?? [];
          debugPrint('ReplaySheet FutureBuilder: Nombre de programmes reçus: ${programs.length}');
          if (programs.isEmpty) {
            // §12-b — Empty state unifié.
            return const EmptyState(
              icon: Icons.replay_circle_filled,
              title: 'Aucun replay disponible',
              subtitle:
                  'Cette chaîne n\'expose pas d\'EPG Xtream ou son timeshift est désactivé. Essaie le picker manuel depuis l\'action sheet TV.',
            );
          }
          return ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: programs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final p = programs[i];
              // §dpadAlign — Cette liste n'avait aucun focusable : à la
              // télécommande, on ne voyait pas quel programme était sélectionné.
              // Les entrées sans archive restent non focusables (rien à lancer).
              final tile = ListTile(
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
              if (!p.hasArchive) return tile;
              return FocusableCard(
                onTap: () => Navigator.of(context).pop(p),
                scaleOnFocus: false,
                decorateOnly: true,
                child: tile,
              );
            },
          );
        },
      ),
    );
  }
}
