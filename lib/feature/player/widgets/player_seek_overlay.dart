import 'package:flutter/material.dart';

enum SeekOverlayType { seekLeft, seekRight, brightness, volume }

/// Overlay visuel affiché brièvement lors d'une action (seek ±Xs, volume, luminosité).
class PlayerSeekOverlay extends StatelessWidget {
  final SeekOverlayType type;
  final String label;

  const PlayerSeekOverlay({
    super.key,
    required this.type,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final isLeft =
        type == SeekOverlayType.seekLeft || type == SeekOverlayType.brightness;

    final icon = switch (type) {
      SeekOverlayType.seekLeft => Icons.replay_10,
      SeekOverlayType.seekRight => Icons.forward_10,
      SeekOverlayType.brightness => Icons.brightness_6,
      SeekOverlayType.volume => Icons.volume_up,
    };

    return Container(
        decoration: BoxDecoration(
          borderRadius: isLeft
              ? const BorderRadius.horizontal(right: Radius.circular(80))
              : const BorderRadius.horizontal(left: Radius.circular(80)),
          color: Colors.black45,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 40),
            if (label.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
    );
  }
}
