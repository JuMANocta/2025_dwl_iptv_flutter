import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/services/update_service.dart';

/// §updateGreen — Vert vif du dialog de MAJ (style « Matrix terminal », figé,
/// indépendant du thème). Remplace `Colors.green` (#4CAF50, trop terne sur fond
/// sombre) pour rendre les boutons/séparateurs bien visibles.
const Color _kTermGreen = Color(0xFF00FF41);

/// Dialogue de mise à jour in-app — style terminal Matrix.
/// Cohérent avec [TerminalDownloadDialog].
class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;

  const UpdateDialog({super.key, required this.info});

  static Future<void> show(BuildContext context, UpdateInfo info) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(info: info),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

// Pool de messages de boot pour l'update
const List<String> _kUpdateBootPool = [
  '> INCOMING TRANSMISSION...',
  '> NEW PACKAGE DETECTED.',
  '> UPGRADE SIGNAL RECEIVED.',
  '> THE SYSTEM WANTS YOU TO UPDATE.',
  '> ARCHITECT HAS PUSHED A NEW BUILD.',
  '> OPERATOR: "YOU NEED THE NEW VERSION."',
];

class _UpdateDialogState extends State<UpdateDialog> {
  _DownloadState _state = _DownloadState.idle;
  double _progress = 0.0;
  String? _errorMessage;
  CancelToken? _cancelToken;
  late final String _bootMsg;

  @override
  void initState() {
    super.initState();
    final rng = Random();
    _bootMsg = _kUpdateBootPool[rng.nextInt(_kUpdateBootPool.length)];
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  Future<void> _startDownload() async {
    setState(() {
      _state = _DownloadState.downloading;
      _progress = 0.0;
      _errorMessage = null;
      _cancelToken = CancelToken();
    });

    try {
      await UpdateService.downloadAndInstall(
        widget.info.downloadUrl,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        cancelToken: _cancelToken,
      );
      if (mounted) Navigator.of(context).pop();
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        if (mounted) setState(() => _state = _DownloadState.idle);
      } else {
        if (mounted) {
          setState(() {
            _state = _DownloadState.error;
            _errorMessage = e.message ?? 'Erreur réseau';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _DownloadState.error;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _cancel() {
    _cancelToken?.cancel();
    if (_state != _DownloadState.downloading) Navigator.of(context).pop();
  }

  /// Barre ASCII identique à TerminalDownloadDialog
  String _asciiBar(double progress, {int length = 20}) {
    final filled = (progress * length).clamp(0, length).toInt();
    return '[${'█' * filled}${'▒' * (length - filled)}] ${(progress * 100).toStringAsFixed(1)}%';
  }

  @override
  Widget build(BuildContext context) {
    final sizeStr = widget.info.sizeBytes != null
        ? '${(widget.info.sizeBytes! / 1024 / 1024).toStringAsFixed(1)} MB'
        : null;

    // Changelog formaté en lignes terminal
    final changelogLines = widget.info.body
        ?.trim()
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .map((l) => '  ${l.trim()}')
        .join('\n');

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha((255 * 0.93).round()),
          border: Border.all(color: _kTermGreen.withAlpha(60)),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(color: _kTermGreen.withAlpha(25), blurRadius: 12, spreadRadius: 2),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Titre ──────────────────────────────────────────────────────
            Text(
              '> SYSTEM UPDATE',
              style: GoogleFonts.vt323(color: _kTermGreen, fontSize: 22),
            ),
            Divider(color: _kTermGreen, height: 12),

            // ── Corps terminal ─────────────────────────────────────────────
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // Message de boot
                    Text(
                      _bootMsg,
                      style: GoogleFonts.sourceCodePro(
                        color: const Color(0xFF00AA00), fontSize: 11),
                    ),
                    const SizedBox(height: 6),

                    // Versions
                    Text(
                      '> REMOTE : ${widget.info.tagName}\n'
                      '> RELEASE: ${widget.info.releaseName}',
                      style: GoogleFonts.sourceCodePro(
                        color: const Color(0xFFADFF2F), fontSize: 12),
                    ),

                    if (sizeStr != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '> SIZE   : $sizeStr',
                        style: GoogleFonts.sourceCodePro(
                          color: const Color(0xFFADFF2F), fontSize: 12),
                      ),
                    ],

                    // Changelog
                    if (changelogLines != null && changelogLines.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '> CHANGELOG:',
                        style: GoogleFonts.sourceCodePro(
                          color: _kTermGreen, fontSize: 12,
                          fontWeight: FontWeight.bold),
                      ),
                      Text(
                        changelogLines,
                        style: GoogleFonts.sourceCodePro(
                          color: const Color(0xFF33FF33), fontSize: 11),
                      ),
                    ],

                    const SizedBox(height: 10),

                    // ── Progression ────────────────────────────────────────
                    if (_state == _DownloadState.downloading) ...[
                      Text(
                        '> DOWNLOADING...',
                        style: GoogleFonts.sourceCodePro(
                          color: const Color(0xFFADFF2F), fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      // Pluie Matrix pendant le téléchargement
                      SizedBox(
                        height: 48,
                        child: Stack(children: [
                          RepaintBoundary(child: _MiniMatrixRain()),
                          Center(
                            child: Text(
                              _asciiBar(_progress),
                              style: GoogleFonts.sourceCodePro(
                                color: const Color(0xFF33FF33),
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ],

                    // ── Erreur ─────────────────────────────────────────────
                    if (_state == _DownloadState.error) ...[
                      Text(
                        '> ERROR: ${_errorMessage ?? "UNKNOWN"}',
                        style: GoogleFonts.sourceCodePro(
                          color: const Color(0xFFFF5555), fontSize: 12),
                      ),
                      Text(
                        '> CONNECTION TO THE MATRIX LOST.',
                        style: GoogleFonts.sourceCodePro(
                          color: const Color(0xFFFF5555), fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            Divider(color: _kTermGreen, height: 16),

            // ── Actions terminal ──────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Annuler / Plus tard
                TextButton(
                  onPressed: _cancel,
                  child: Text(
                    _state == _DownloadState.downloading
                        ? '[ ABORT ]'
                        : '[ LATER ]',
                    style: GoogleFonts.vt323(color: _kTermGreen, fontSize: 18),
                  ),
                ),

                // Mettre à jour / Réessayer
                if (_state != _DownloadState.downloading) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _startDownload,
                    style: TextButton.styleFrom(
                      backgroundColor: _kTermGreen.withAlpha(25),
                      side: const BorderSide(color: _kTermGreen, width: 1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    child: Text(
                      _state == _DownloadState.error
                          ? '[ RETRY ]'
                          : '[ INSTALL UPDATE ]',
                      style: GoogleFonts.vt323(
                        color: _kTermGreen, fontSize: 18,
                        fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _DownloadState { idle, downloading, error }

// ─── Mini Matrix Rain (version compacte pour la barre de progression) ─────────

class _MiniMatrixRain extends StatefulWidget {
  @override
  State<_MiniMatrixRain> createState() => _MiniMatrixRainState();
}

class _MiniMatrixRainState extends State<_MiniMatrixRain>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<({double x, double phase, double speed})> _drops;

  @override
  void initState() {
    super.initState();
    final rng = Random();
    _drops = List.generate(10, (i) => (
      x: i / 10 + rng.nextDouble() * 0.04,
      phase: rng.nextDouble(),
      speed: (rng.nextInt(3) + 1).toDouble(),
    ));
    _controller = AnimationController(
      vsync: this, duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => CustomPaint(
        painter: _MiniRainPainter(_drops, _controller.value),
        size: Size.infinite,
      ),
    );
  }
}

class _MiniRainPainter extends CustomPainter {
  final List<({double x, double phase, double speed})> drops;
  final double t;
  const _MiniRainPainter(this.drops, this.t);

  static const _chars = '01アイウエオABCDEF#\$%';

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < drops.length; i++) {
      final d = drops[i];
      final yProgress = (t * d.speed + d.phase) % 1.0;
      final y = yProgress * size.height;
      final charIndex = ((t * 20 + i * 3.7) * _chars.length).floor().abs() % _chars.length;
      final tp = TextPainter(
        text: TextSpan(
          text: _chars[charIndex],
          style: TextStyle(
            color: Colors.greenAccent.withAlpha(80),
            fontSize: 9, fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(d.x * size.width, y));
    }
  }

  @override
  bool shouldRepaint(_MiniRainPainter old) => old.t != t;
}
