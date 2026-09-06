import 'package:flutter/material.dart';

import '../../../core/themes/colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/services/cast_relay_service.dart';
import '../../../data/services/cast_service.dart';

/// §castSend — Panneau affiché DANS le lecteur pendant une diffusion : l'image
/// est sur le téléviseur, le téléphone devient la télécommande.
///
/// Remplace les contrôles habituels (masqués) plutôt que de s'y superposer :
/// un curseur de lecture local n'aurait aucun sens pendant que le récepteur
/// lit. Tout ce qui est ici rappelle `CastService` — la même vérité que la
/// notification.
///
/// [castThisTitle] non nul : le lecteur a ouvert un AUTRE contenu que celui
/// diffusé (l'utilisateur est sorti puis a lancé autre chose) → un bouton
/// propose de l'envoyer au téléviseur à son tour.
class CastOverlay extends StatelessWidget {
  const CastOverlay({
    super.key,
    required this.state,
    required this.onToggle,
    required this.onStop,
    required this.onSeekBy,
    required this.onBack,
    this.castThisTitle,
    this.onCastThis,
    this.diagnostics,
    this.isRelay = false,
    this.onRestartRelay,
  });

  final CastState state;
  final VoidCallback onToggle;
  final VoidCallback onStop;
  final ValueChanged<Duration> onSeekBy;
  final VoidCallback onBack;
  final String? castThisTitle;
  final VoidCallback? onCastThis;

  /// §castAudio — Ce que le RÉCEPTEUR annonce avoir trouvé comme pistes.
  /// Affiché seulement quand « Infos vidéo » est activé : c'est la seule
  /// façon de savoir, sur un appareil donné, si le choix de piste audio à
  /// distance est possible (le récepteur générique n'annonce souvent rien
  /// pour un conteneur progressif). `null` = rien à afficher.
  final String? diagnostics;

  /// §castRelay — `true` quand le flux diffusé est une conversion en
  /// cours : pas de durée totale fiable (le fichier grandit), donc AUCUNE
  /// barre de progression de lecture — juste le temps écoulé et l'état de
  /// la conversion. Sinon les barres mentent (constaté le 2026-09-04 :
  /// l'une pleine, l'autre figée).
  final bool isRelay;

  /// §castResume — Remet l'image et le son en phase, en relançant la
  /// conversion là où le téléviseur en est.
  ///
  /// ⚠️ **L'app ne sait PAS détecter un son décalé** : le fichier est
  /// irréprochable dans les deux cas (mesuré le 2026-09-05 — le décalage
  /// vivait dans le contenu, pas dans les horodatages). C'est donc l'oreille
  /// de l'utilisateur qui juge, et ce bouton qui agit.
  final VoidCallback? onRestartRelay;

  @override
  Widget build(BuildContext context) {
    final Duration? dur = state.duration;
    final bool showTime =
        !state.live && !isRelay && dur != null && dur > Duration.zero;
    final double progress = showTime
        ? (state.position.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Positioned.fill(
      child: Container(
        color: Colors.black.withAlpha(235),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: 4,
                left: 4,
                child: IconButton(
                  tooltip: 'Retour (la diffusion continue)',
                  onPressed: onBack,
                  icon:
                      const Icon(Icons.arrow_back_rounded, color: Colors.white),
                ),
              ),
              // ⚠️ **Défilant, sinon ça déborde en paysage.** Le téléphone est
              // couché pendant une diffusion (le lecteur est en paysage) : il
              // reste ~1000 px de haut, et l'ajout de la progression de
              // conversion (§castRelay) a fait déborder de 12 px. Un panneau
              // d'état ne doit jamais tronquer ses propres boutons.
              Center(
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.cast_connected_rounded,
                            color: kAccentPrimary,
                            size: 44,
                            shadows: [
                              Shadow(
                                color: kAccentPrimary.withAlpha(150),
                                blurRadius: 18,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'DIFFUSION SUR ${state.device.displayName.toUpperCase()}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: kAccentPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            state.title,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (state.subtitle != null &&
                              state.subtitle!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                state.subtitle!,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withAlpha(180),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          const SizedBox(height: 18),
                          if (showTime) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 4,
                                backgroundColor: Colors.white.withAlpha(40),
                                color: kAccentSecondary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  formatDuration(state.position.inSeconds),
                                  style: _timeStyle,
                                ),
                                Text(
                                  formatDuration(dur.inSeconds),
                                  style: _timeStyle,
                                ),
                              ],
                            ),
                          ] else if (isRelay)
                            Text(
                              state.buffering
                                  ? 'Démarrage sur le téléviseur…'
                                  // §castResume — Position DU FILM : le flux
                                  // converti repart à zéro, le décalage la
                                  // remet à sa vraie valeur.
                                  : 'En lecture · ${formatDuration(CastRelayService.filmPosition(state.position).inSeconds)}',
                              style: TextStyle(
                                color: Colors.white.withAlpha(180),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                            )
                          else
                            Text(
                              state.live
                                  ? 'EN DIRECT'
                                  : (state.buffering
                                      ? 'Chargement sur le téléviseur…'
                                      : ''),
                              style: TextStyle(
                                color: state.live
                                    ? kBadgeLive
                                    : Colors.white.withAlpha(160),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                            ),
                          const _RelayStatus(),
                          // §castBattery — Même vérité que la notification :
                          // sous 15 % hors charge, on le dit ici en rouge.
                          if (state.batteryWarning != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.battery_alert_rounded,
                                      color: kError, size: 18),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      state.batteryWarning!,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ).copyWith(color: kError),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (showTime)
                                _RoundButton(
                                  icon: Icons.replay_30_rounded,
                                  tooltip: 'Reculer de 30 s',
                                  onTap: () =>
                                      onSeekBy(const Duration(seconds: -30)),
                                ),
                              const SizedBox(width: 18),
                              _RoundButton(
                                icon: state.playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                tooltip: state.playing ? 'Pause' : 'Lecture',
                                size: 64,
                                accent: true,
                                onTap: onToggle,
                              ),
                              const SizedBox(width: 18),
                              if (showTime)
                                _RoundButton(
                                  icon: Icons.forward_30_rounded,
                                  tooltip: 'Avancer de 30 s',
                                  onTap: () =>
                                      onSeekBy(const Duration(seconds: 30)),
                                ),
                            ],
                          ),
                          if (diagnostics != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              'Récepteur · ${diagnostics!}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: kAccentSecondary.withAlpha(210),
                                fontSize: 11,
                                height: 1.3,
                              ),
                            ),
                          ],
                          const SizedBox(height: 22),
                          if (castThisTitle != null && onCastThis != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: FilledButton.icon(
                                onPressed: onCastThis,
                                icon: const Icon(Icons.cast_rounded),
                                label: Text(
                                  'Diffuser « $castThisTitle »',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          // ⚠️ **Côte à côte, pas empilés.** Le lecteur est en
                          // paysage : empilés, le second bouton passait sous le
                          // bord de l'écran et devenait inatteignable.
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isRelay && onRestartRelay != null) ...[
                                Flexible(
                                  child: OutlinedButton.icon(
                                    onPressed: onRestartRelay,
                                    icon: const Icon(Icons.refresh_rounded),
                                    // Nommé par le problème qu'il résout, pas
                                    // par le mécanisme : « conversion » ne dit
                                    // rien au client, « image et son » si.
                                    label: const Text(
                                      "Resynchroniser l'image et le son",
                                      maxLines: 2,
                                      textAlign: TextAlign.center,
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: BorderSide(
                                          color: Colors.white.withAlpha(120)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                              ],
                              Flexible(
                                child: OutlinedButton.icon(
                                  onPressed: onStop,
                                  icon: const Icon(Icons.phone_android_rounded),
                                  label: const Text(
                                    'Reprendre sur le téléphone',
                                    maxLines: 2,
                                    textAlign: TextAlign.center,
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: BorderSide(
                                        color: Colors.white.withAlpha(120)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static final TextStyle _timeStyle = TextStyle(
    color: Colors.white.withAlpha(170),
    fontSize: 12,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.size = 48,
    this.accent = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final double size;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: accent ? kAccentPrimary : Colors.white.withAlpha(30),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              color: accent ? Colors.black : Colors.white,
              size: size * 0.55,
            ),
          ),
        ),
      ),
    );
  }
}

/// §castRelay — Ce que le téléphone est en train de faire pendant qu'il sert
/// le téléviseur.
///
/// ⚠️ **Sans cette ligne, l'attente est muette.** Mesuré le 2026-09-04 : le
/// panneau affichait « Chargement sur le téléviseur… » pendant trois minutes
/// sans rien dire de la conversion en cours — l'utilisateur ne pouvait pas
/// distinguer un relais qui travaille d'une diffusion en panne.
class _RelayStatus extends StatelessWidget {
  const _RelayStatus();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CastRelayState?>(
      valueListenable: CastRelayService.state,
      builder: (context, relay, _) {
        if (relay == null) return const SizedBox.shrink();

        if (relay.error != null) {
          return Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              relay.error!,
              textAlign: TextAlign.center,
              // kWarning/kError sont des GETTERS thémés : jamais dans un const.
              style: const TextStyle(fontSize: 12).copyWith(color: kError),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(
            children: [
              Text(
                relay.done
                    ? 'Son entièrement converti'
                    : 'Conversion du son en cours',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withAlpha(200),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                // Indéterminée tant que ça convertit : honnête sur le fait
                // qu'on ne connaît pas d'avance utile en secondes.
                child: LinearProgressIndicator(
                  value: relay.done ? 1.0 : null,
                  minHeight: 3,
                  backgroundColor: Colors.white.withAlpha(30),
                  color: kAccentTertiary,
                ),
              ),
              if (!relay.done) ...[
                const SizedBox(height: 6),
                Text(
                  'Le téléviseur lit pendant la conversion. '
                  "Garder l'application ouverte.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withAlpha(120),
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// §castRelay — **Ce qu'on montre entre l'accord et la lecture sur la télé.**
///
/// Sans lui, le téléphone reste sur le film pendant toute la conversion
/// (retour utilisateur du 2026-09-04) : rien ne dit que quelque chose est en
/// cours, et un film en pause ressemble à un plantage. Une diffusion commence
/// quand l'utilisateur l'accepte, pas quand le recepteur daigne repondre —
/// l'ecran doit dire la meme chose.
class CastPreparingOverlay extends StatelessWidget {
  const CastPreparingOverlay({
    super.key,
    required this.deviceName,
    required this.title,
    required this.onCancel,
  });

  final String deviceName;
  final String title;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withAlpha(235),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cast_rounded, color: kAccentPrimary, size: 44),
                      const SizedBox(height: 10),
                      Text(
                        'PRÉPARATION POUR ${deviceName.toUpperCase()}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: kAccentPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const _RelayStatus(),
                      const SizedBox(height: 22),
                      OutlinedButton.icon(
                        onPressed: onCancel,
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('Annuler la conversion'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Colors.white.withAlpha(120)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
