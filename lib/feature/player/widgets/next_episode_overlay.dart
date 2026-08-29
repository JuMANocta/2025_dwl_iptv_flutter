import 'package:flutter/material.dart';

import '../../../core/themes/colors.dart';
import '../../../widgets/tv/focusable_card.dart';

/// §autoNextEp — Encart affiché quand la lecture atteint sa fin.
enum EndOfPlaybackKind {
  /// Décompte avant bascule automatique sur l'épisode suivant.
  countdown,

  /// Épisode suivant disponible, mais l'enchaînement auto est désactivé.
  manual,

  /// Le prochain épisode appartient à une autre saison → confirmation.
  endOfSeason,

  /// Plus rien à lire.
  endOfSeries,
}

/// §autoNextEp — Panneau de fin de lecture, façon plateforme de streaming.
///
/// Trois situations, trois traitements délibérément différents :
///
///   - **fin d'épisode** → décompte annulable. C'est l'enchaînement attendu ;
///   - **fin de saison** → **aucun décompte**. Changer de saison est une
///     décision, pas un enchaînement : on ne veut pas y basculer parce que
///     l'utilisateur s'est endormi ;
///   - **fin de série** → plus rien à lire, on propose de revenir à la fiche
///     (où les titres similaires sont déjà affichés).
class NextEpisodeOverlay extends StatelessWidget {
  final EndOfPlaybackKind kind;
  final String? nextTitle;
  final String? nextEpisodeTag;
  final int? nextSeason;

  /// Secondes restantes avant bascule ([EndOfPlaybackKind.countdown]).
  final int remainingSeconds;

  /// Les métadonnées du prochain épisode sont encore en cours de chargement.
  final bool loading;

  final VoidCallback? onPlayNow;
  final VoidCallback onDismiss;

  /// Quitter le player (retour à la fiche).
  final VoidCallback onLeave;

  const NextEpisodeOverlay({
    super.key,
    required this.kind,
    required this.remainingSeconds,
    required this.loading,
    required this.onDismiss,
    required this.onLeave,
    this.nextTitle,
    this.nextEpisodeTag,
    this.nextSeason,
    this.onPlayNow,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        // Voile sombre : la vidéo est terminée, l'attention va sur l'encart.
        color: Colors.black.withValues(alpha: 0.72),
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _content(context),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (loading) {
      return [
        const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
        const SizedBox(height: 16),
        Text('Chargement de l\'épisode suivant…',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurface, fontSize: 15)),
      ];
    }

    switch (kind) {
      case EndOfPlaybackKind.countdown:
        return [
          _eyebrow('ÉPISODE SUIVANT'),
          _title(context, nextTitle ?? ''),
          if (nextEpisodeTag != null) _subtitle(context, nextEpisodeTag!),
          const SizedBox(height: 20),
          _progress(),
          const SizedBox(height: 20),
          _actions(
            primaryLabel: 'Lire maintenant  ·  ${remainingSeconds}s',
            primaryIcon: Icons.play_arrow_rounded,
            onPrimary: onPlayNow,
            secondaryLabel: 'Annuler',
            secondaryIcon: Icons.close_rounded,
            onSecondary: onDismiss,
          ),
        ];

      case EndOfPlaybackKind.manual:
        return [
          _eyebrow('ÉPISODE SUIVANT'),
          _title(context, nextTitle ?? ''),
          if (nextEpisodeTag != null) _subtitle(context, nextEpisodeTag!),
          const SizedBox(height: 20),
          _actions(
            primaryLabel: 'Lire',
            primaryIcon: Icons.play_arrow_rounded,
            onPrimary: onPlayNow,
            secondaryLabel: 'Rester ici',
            secondaryIcon: Icons.close_rounded,
            onSecondary: onDismiss,
          ),
        ];

      case EndOfPlaybackKind.endOfSeason:
        return [
          _eyebrow('FIN DE LA SAISON'),
          _title(
            context,
            nextSeason != null
                ? 'Passer à la saison $nextSeason ?'
                : 'Passer à la saison suivante ?',
          ),
          if (nextTitle != null && nextTitle!.isNotEmpty)
            _subtitle(context, nextTitle!),
          const SizedBox(height: 20),
          _actions(
            primaryLabel: 'Continuer',
            primaryIcon: Icons.skip_next_rounded,
            onPrimary: onPlayNow,
            secondaryLabel: 'Retour à la fiche',
            secondaryIcon: Icons.arrow_back_rounded,
            onSecondary: onLeave,
          ),
        ];

      case EndOfPlaybackKind.endOfSeries:
        return [
          _eyebrow('SÉRIE TERMINÉE'),
          _title(context, 'Vous avez vu le dernier épisode disponible.'),
          const SizedBox(height: 20),
          _actions(
            primaryLabel: 'Retour à la fiche',
            primaryIcon: Icons.arrow_back_rounded,
            onPrimary: onLeave,
            secondaryLabel: 'Rester ici',
            secondaryIcon: Icons.close_rounded,
            onSecondary: onDismiss,
          ),
        ];
    }
  }

  Widget _eyebrow(String text) => Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: kAccentPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.6,
        ),
      );

  Widget _title(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          text,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 22,
            fontWeight: FontWeight.bold,
            height: 1.25,
          ),
        ),
      );

  Widget _subtitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 14,
          ),
        ),
      );

  /// Barre qui se vide au fil du décompte — lecture instantanée du temps
  /// restant, sans avoir à lire le chiffre.
  Widget _progress() => ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: remainingSeconds <= 0 ? 0 : remainingSeconds / 8,
          minHeight: 5,
          backgroundColor: Colors.white24,
          valueColor: AlwaysStoppedAnimation<Color>(kAccentPrimary),
        ),
      );

  Widget _actions({
    required String primaryLabel,
    required IconData primaryIcon,
    required VoidCallback? onPrimary,
    required String secondaryLabel,
    required IconData secondaryIcon,
    required VoidCallback onSecondary,
  }) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _button(
            label: primaryLabel,
            icon: primaryIcon,
            onTap: onPrimary,
            filled: true,
            autofocus: true,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: _button(
            label: secondaryLabel,
            icon: secondaryIcon,
            onTap: onSecondary,
            filled: false,
          ),
        ),
      ],
    );
  }

  Widget _button({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    required bool filled,
    bool autofocus = false,
  }) {
    // Le bouton principal prend le focus d'entrée : à la télécommande, OK
    // relance immédiatement sans avoir à viser.
    return FocusableCard(
      onTap: onTap,
      enabled: onTap != null,
      autofocus: autofocus,
      scaleOnFocus: false,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: filled ? kAccentPrimary : Colors.transparent,
          border: Border.all(
            color: filled ? kAccentPrimary : Colors.white54,
            width: 1.6,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: filled ? Colors.black : Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: filled ? Colors.black : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
