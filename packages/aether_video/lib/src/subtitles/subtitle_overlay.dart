import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/native_video_player_subtitle_style.dart';
import 'subtitle_lift.dart';

/// Subtitle layer rendering the active sidecar cue lines at the position
/// configured in [NativeVideoPlayerSubtitleStyle] (bottom-center by
/// default; any alignment supported).
///
/// Sits in the NativeVideoPlayer stack above the platform view and below
/// the custom controls overlay; never intercepts touches.
class SubtitleOverlay extends StatelessWidget {
  const SubtitleOverlay({
    required this.cueLines,
    required this.style,
    this.videoAspectRatio,
    this.bottomInset,
    super.key,
  });

  final ValueListenable<List<String>> cueLines;
  final NativeVideoPlayerSubtitleStyle style;

  /// Aspect ratio of the displayed video, when known. When set, the cue block
  /// is constrained to the video's letterboxed content rect (the same
  /// Center+AspectRatio fit the texture path uses) so captions sit at the
  /// video's edge rather than the full widget's edge — e.g. just above the
  /// video in portrait fullscreen, not at the bottom of the screen. Null
  /// falls back to aligning against the whole widget.
  final double? videoAspectRatio;

  /// AetherStream patch 28 (R50) — Hauteur (pixels logiques) du bas du widget
  /// recouverte par les contrôles de l'app. Les répliques remontent de la
  /// part qui mord sur le cadre de l'image ([subtitleLiftInBox]), en douceur,
  /// et redescendent quand les contrôles disparaissent. `null` ou 0 = rien.
  final ValueListenable<double>? bottomInset;

  /// Durée de la montée / descente : celle du fondu des contrôles de l'app.
  static const Duration liftDuration = Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: ValueListenableBuilder<List<String>>(
            valueListenable: cueLines,
            builder: (context, lines, _) {
              if (lines.isEmpty) return const SizedBox.shrink();

              final Widget cueBlock = Align(
                alignment: style.alignment,
                child: Padding(
                  padding: style.padding,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final line in lines)
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          color: style.backgroundColor,
                          child: _buildCueLine(line),
                        ),
                    ],
                  ),
                ),
              );

              final double? known = videoAspectRatio;
              final double aspectRatio =
                  known != null && known > 0 ? known : 0;
              final bool hasAspect = aspectRatio > 0;

              // Pin the cue block to the video's content rect so the
              // alignment/padding are measured against the video, not the
              // letterbox bars (mirrors the texture path's letterbox fit).
              Widget inVideoRect(Widget child) => hasAspect
                  ? Center(
                      child: AspectRatio(
                        aspectRatio: aspectRatio,
                        child: child,
                      ),
                    )
                  : child;

              // Patch 28 (R50) — sans marge demandée, le rendu d'origine.
              final ValueListenable<double>? inset = bottomInset;
              if (inset == null) return inVideoRect(cueBlock);

              // La marge se mesure contre le widget ENTIER (les contrôles
              // sont posés au bas de l'écran), le décalage s'applique DANS le
              // cadre de l'image : d'où le `LayoutBuilder` au-dessus du cadre.
              return LayoutBuilder(
                builder: (context, constraints) =>
                    ValueListenableBuilder<double>(
                  valueListenable: inset,
                  builder: (context, value, _) {
                    final double h = constraints.maxHeight;
                    final double w = constraints.maxWidth;
                    // Hauteur du cadre : celle que `Center` + `AspectRatio`
                    // lui donnent dans `inVideoRect`.
                    final double boxHeight =
                        hasAspect && w.isFinite && w / aspectRatio < h
                            ? w / aspectRatio
                            : h;
                    final double lift = h.isFinite
                        ? subtitleLiftInBox(
                            inset: value,
                            gapBelowBox: (h - boxHeight) / 2,
                            boxHeight: boxHeight,
                          )
                        : 0;
                    return inVideoRect(
                      AnimatedPadding(
                        padding: EdgeInsets.only(bottom: lift),
                        duration: liftDuration,
                        curve: Curves.easeOut,
                        child: cueBlock,
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Renders a single cue line. With an outline configured, the glyphs are
  /// drawn twice — a stroked pass underneath and a filled pass on top — for a
  /// crisp, even outline at any width (`color` and `foreground` can't coexist
  /// on one [TextStyle], so the two passes are stacked).
  Widget _buildCueLine(String line) {
    final TextStyle baseStyle = TextStyle(
      fontSize: style.fontSize,
      fontWeight: style.fontWeight,
      fontStyle: style.fontStyle,
      fontFamily: style.fontFamily,
      height: style.lineHeight,
      decoration: TextDecoration.none,
    );

    final Widget fill = Text(
      line,
      textAlign: style.textAlign,
      style: baseStyle.copyWith(color: style.textColor),
    );

    final Color? outlineColor = style.outlineColor;
    if (outlineColor == null || style.outlineWidth <= 0) {
      return fill;
    }

    return Stack(
      children: [
        Text(
          line,
          textAlign: style.textAlign,
          style: baseStyle.copyWith(
            foreground: ui.Paint()
              ..style = ui.PaintingStyle.stroke
              ..strokeWidth = style.outlineWidth
              ..strokeJoin = ui.StrokeJoin.round
              ..color = outlineColor,
          ),
        ),
        fill,
      ],
    );
  }
}
