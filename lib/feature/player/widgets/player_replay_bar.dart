import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:media_kit/media_kit.dart';

/// Barre de progression spécifique au mode replay (timeshift).
///
/// Affiche l'heure de début, l'heure actuelle dans le replay
/// et un bouton "DIRECT" pour retourner au flux live.
class PlayerReplayBar extends StatefulWidget {
  final Player player;
  /// Heure de début du replay (pour afficher les horaires).
  final DateTime? replayStart;
  /// Durée totale du replay.
  final Duration? replayDuration;
  final bool visible;

  const PlayerReplayBar({
    super.key,
    required this.player,
    required this.replayStart,
    required this.replayDuration,
    required this.visible,
  });

  @override
  State<PlayerReplayBar> createState() => _PlayerReplayBarState();
}

class _PlayerReplayBarState extends State<PlayerReplayBar> {
  Duration _position = Duration.zero;
  StreamSubscription? _sub;

  final _hhmm = DateFormat('HH:mm');

  @override
  void initState() {
    super.initState();
    _sub = widget.player.stream.position.listen((v) {
      if (mounted) setState(() => _position = v);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.replayStart;
    final total = widget.replayDuration;

    final startLabel = start != null ? _hhmm.format(start) : '--:--';
    final endLabel = (start != null && total != null)
        ? _hhmm.format(start.add(total))
        : '--:--';
    final currentLabel =
        start != null ? _hhmm.format(start.add(_position)) : '--:--';

    return AnimatedOpacity(
      opacity: widget.visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 250),
      child: IgnorePointer(
        ignoring: !widget.visible,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              // Horaires : début → position actuelle → fin.
              Text(
                startLabel,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.arrow_forward,
                  color: Colors.white38, size: 12),
              const SizedBox(width: 6),
              Text(
                currentLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '/ $endLabel',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
