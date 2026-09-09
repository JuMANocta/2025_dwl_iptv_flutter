import 'package:flutter/material.dart';
import 'package:aetherStream/core/themes/colors.dart';
import '../../core/utils/log_sanitizer.dart';
import '../../core/utils/user_error.dart';
import '../../data/services/replay_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/sheet_close_tile.dart';
import '../../widgets/tv/focusable_card.dart';
import '../../l10n/l10n_ext.dart';

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
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                EmptyState(
                  icon: Icons.cloud_off,
                  title: 'Guide indisponible',
                  subtitle: describeError(snap.error),
                  accentColor: kError,
                ),
                // §tvOptionsBack — un échec de chargement est une impasse
                // comme les autres : sans cette ligne, seule la touche
                // Retour permettait de refermer (et referme aussi une vidéo
                // en cours ailleurs dans l'app, §dpadBack). Un seul élément
                // focusable ici, la position « dernier » est déjà acquise.
                const SheetCloseTile(),
              ],
            );
          }
          final programs = snap.data ?? [];
          debugPrint('ReplaySheet FutureBuilder: Nombre de programmes reçus: ${programs.length}');
          if (programs.isEmpty) {
            // §12-b — Empty state unifié.
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                EmptyState(
                  icon: Icons.replay_circle_filled,
                  title: context.l10n.replayNoneTitle,
                  subtitle:
                      context.l10n.replayNoneBody,
                ),
                // §tvOptionsBack — même sans programme, la feuille reste un
                // modal sans issue déclarée hors la touche Retour.
                const SheetCloseTile(),
              ],
            );
          }
          return ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 16),
            // +1 : la ligne de sortie (§tvOptionsBack), voir plus bas.
            itemCount: programs.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              // §tvOptionsBack — la feuille n'offrait aucune sortie neutre :
              // chaque ligne LANCE le replay, il ne restait que la touche
              // Retour (buguée : elle ferme un film en cours ailleurs dans
              // l'app). ⚠️ En DERNIER (i == programs.length), jamais en
              // premier : `TvAutofocusFirst` focus le premier élément
              // focusable du modal, qui doit rester le premier programme.
              if (i == programs.length) return const SheetCloseTile();
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
