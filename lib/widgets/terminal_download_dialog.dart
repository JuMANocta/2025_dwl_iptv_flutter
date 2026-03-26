import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/models/download_task.dart';
import '../data/services/download_manager_service.dart';
import '../core/utils/formatters.dart';
import '../l10n/app_localizations.dart';

const String _kMatrixChars =
    '01234567890'
    'アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン'
    'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    '#\$%&?<>!@=+*:-|';

// Pool de messages de boot Matrix (1 tiré au sort)
const List<String> _kBootPool = [
  '> WAKE UP, NEO...',
  '> THE MATRIX HAS YOU...',
  '> FOLLOW THE WHITE RABBIT.',
  '> KNOCK KNOCK, NEO.',
  '> INITIATING NEURAL LINK...',
  '> BYPASS SECURITY PROTOCOLS...',
  '> DECRYPTING MAINFRAME...',
  '> SCANNING FOR AGENTS...',
  '> LOADING OPERATOR INTERFACE...',
  '> ESTABLISHING ENCRYPTED TUNNEL...',
  '> MORPHEUS IS WAITING.',
  '> DO YOU WANT TO KNOW WHAT IT IS?',
  '> I KNOW WHY YOU\'RE HERE, NEO.',
  '> FREE YOUR MIND.',
  '> SECURE CHANNEL ESTABLISHED \u2713',
];

class TerminalDownloadDialog extends StatefulWidget {
  final String taskId;
  final bool isResume;

  const TerminalDownloadDialog({
    super.key,
    required this.taskId,
    this.isResume = false,
  });

  @override
  State<TerminalDownloadDialog> createState() => _TerminalDownloadDialogState();
}

class _TerminalDownloadDialogState extends State<TerminalDownloadDialog> {
  final DownloadManagerService _downloadManager = DownloadManagerService();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _logs = [];

  DownloadTask? _lastTaskState;
  AppLocalizations? _cachedL10n;

  Stopwatch? _stopwatch;
  int _lastReceivedBytes = 0;
  double _speed = 0;
  int _eta = 0;

  bool _isDownloadComplete = false;
  bool _hasFatalError = false;
  bool _isAborting = false;
  bool _initMessageAdded = false;
  bool _initScheduled = false;

  @override
  void initState() {
    super.initState();
    // 1 seul message de boot tiré au sort dans le pool
    final rng = Random();
    final bootMsg = (_kBootPool..toList())[rng.nextInt(_kBootPool.length)];
    _logs.addAll([
      {'message': bootMsg, 'type': 'boot'},
      {'message': '', 'type': 'log'},
    ]);

    _downloadManager.tasksNotifier.addListener(_onTaskUpdated);

    final initialTask = _downloadManager.tasksNotifier.value.firstWhere(
      (t) => t.id == widget.taskId,
      orElse: () => DownloadTask.empty(),
    );
    if (initialTask.id.isNotEmpty && initialTask.totalSize > 0) {
      _lastReceivedBytes = (initialTask.progress * initialTask.totalSize).toInt();
    }
  }

  void _onTaskUpdated() {
    if (!mounted) return;
    final task = _downloadManager.tasksNotifier.value.firstWhere(
      (t) => t.id == widget.taskId,
      orElse: () => _lastTaskState ?? DownloadTask.empty(),
    );
    if (task.id.isEmpty) return;
    _updateLogs(task);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _updateLogs(DownloadTask task) {
    // Attendre que le contexte ait fourni l10n (via build)
    final l10n = _cachedL10n;
    if (l10n == null) return;

    // Guard : skip si même état exact
    if (_lastTaskState?.status == task.status &&
        _lastTaskState?.progress == task.progress) {
      return;
    }

    // Message initial (une seule fois)
    if (!_initMessageAdded) {
      _initMessageAdded = true;
      if (widget.isResume) {
        _logs.add({'message': l10n.terminalResumeMessage(task.displayName), 'type': 'log'});
      } else {
        _logs.add({'message': l10n.terminalStartMessage(task.displayName), 'type': 'log'});
      }
      if (task.totalSize > 0) {
        _logs.add({'message': l10n.terminalFileSizeMessage(formatFileSize(task.totalSize)), 'type': 'log'});
      }
    }

    if (task.status == DownloadStatus.downloading) {
      _stopwatch ??= Stopwatch()..start();
      const barLength = 20;
      final filled = (task.progress * barLength).clamp(0, barLength).toInt();
      final bar = '█' * filled + '▒' * (barLength - filled);

      if (_stopwatch!.elapsedMilliseconds > 500) {
        final currentReceived = (task.progress * task.totalSize).toInt();
        final receivedSinceLast = currentReceived - _lastReceivedBytes;
        final elapsedSeconds = _stopwatch!.elapsedMilliseconds / 1000.0;
        if (elapsedSeconds > 0 && receivedSinceLast > 0) {
          _speed = receivedSinceLast / elapsedSeconds;
          final remainingBytes = task.totalSize - currentReceived;
          if (_speed > 0) _eta = (remainingBytes / _speed).round();
        }
        _lastReceivedBytes = currentReceived;
        _stopwatch!.reset();
      }

      final speedInfo = _speed > 0 ? '\n🚀 ${l10n.terminalSpeedMessage} : ${formatFileSize(_speed.toInt())}/s' : '';
      final etaInfo = _eta > 0 ? '\n⏳ ${l10n.terminalEtaMessage} : ${formatDuration(_eta)}' : '';
      final formatted = '\n[$bar] ${(task.progress * 100).toStringAsFixed(1)}%$speedInfo$etaInfo';

      if (_logs.isNotEmpty && _logs.last['type'] == 'stats') {
        _logs[_logs.length - 1] = {'message': formatted, 'type': 'stats'};
      } else {
        _logs.add({'message': formatted, 'type': 'stats'});
      }
    } else if (task.status == DownloadStatus.finalizing &&
        _lastTaskState?.status != DownloadStatus.finalizing) {
      // Forcer la barre à 100% avant le message de finalisation
      _forceFullBar();
      _logs.add({'message': l10n.terminalFinalizingMessage, 'type': 'log'});
    } else if (task.status == DownloadStatus.completed &&
        _lastTaskState?.status != DownloadStatus.completed) {
      // Si on a sauté l'état finalizing (transition trop rapide), on le rattrape
      if (_lastTaskState?.status != DownloadStatus.finalizing) {
        _forceFullBar();
        _logs.add({'message': l10n.terminalFinalizingMessage, 'type': 'log'});
      }
      _logs.add({'message': l10n.terminalSuccessMessage, 'type': 'log'});
      _logs.add({'message': '\n> THERE IS NO SPOON.', 'type': 'matrix'});
      _isDownloadComplete = true;
    } else if (task.status == DownloadStatus.failed &&
        _lastTaskState?.status != DownloadStatus.failed) {
      _logs.add({'message': l10n.terminalFatalErrorMessage, 'type': 'error'});
      _logs.add({'message': '\n> CONNECTION TO THE MATRIX LOST.', 'type': 'error'});
      _hasFatalError = true;
    } else if (task.status == DownloadStatus.canceled &&
        _lastTaskState?.status != DownloadStatus.canceled) {
      _logs.add({'message': l10n.terminalCancelMessage, 'type': 'log'});
      _logs.add({'message': '\n> YOU TOOK THE RED PILL.', 'type': 'matrix'});
    }

    setState(() => _lastTaskState = task);
    _scrollToBottom();
  }

  void _forceFullBar() {
    final fullBar = '█' * 20;
    // Si aucune barre de progression n'a encore été affichée (téléchargement
    // trop rapide pour avoir reçu des updates 'downloading'), on insère d'abord
    // un palier à 95 % pour ne pas casser l'effet visuel.
    final hasStats = _logs.any((l) => l['type'] == 'stats');
    if (!hasStats) {
      // 19/20 colonnes = 95 %
      final partialBar = '${'█' * 19}▒';
      _logs.add({'message': '\n[$partialBar] 95.0%', 'type': 'stats'});
    }
    if (_logs.isNotEmpty && _logs.last['type'] == 'stats') {
      _logs[_logs.length - 1] = {'message': '\n[$fullBar] 100.0%', 'type': 'stats'};
    } else {
      _logs.add({'message': '\n[$fullBar] 100.0%', 'type': 'stats'});
    }
  }

  @override
  void dispose() {
    _downloadManager.tasksNotifier.removeListener(_onTaskUpdated);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mettre en cache l10n dès le premier build pour utilisation dans _updateLogs
    _cachedL10n ??= AppLocalizations.of(context);
    final l10n = _cachedL10n!;

    final currentTask = _downloadManager.tasksNotifier.value.firstWhere(
      (t) => t.id == widget.taskId,
      orElse: () => _lastTaskState ?? DownloadTask.empty(),
    );

    final navigator = Navigator.of(context);

    if (currentTask.id.isEmpty) {
      Future.microtask(() {
        if (mounted && navigator.canPop()) navigator.pop();
      });
      return const SizedBox.shrink();
    }

    if (_isAborting && currentTask.status == DownloadStatus.canceled) {
      Future.microtask(() {
        if (mounted && navigator.canPop()) navigator.pop();
      });
      return const SizedBox.shrink();
    }

    // Premier passage : déclencher _updateLogs via microtask (une seule fois)
    if (!_initScheduled) {
      _initScheduled = true;
      Future.microtask(() {
        if (mounted) _updateLogs(currentTask);
      });
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha((255 * 0.9).round()),
          border: Border.all(color: Colors.green.withAlpha(50)),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [BoxShadow(color: Colors.green.withAlpha(20), blurRadius: 10, spreadRadius: 2)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.terminalTitle,
              style: GoogleFonts.vt323(color: Colors.green, fontSize: 22),
            ),
            const Divider(color: Colors.green),
            Flexible(
              child: SizedBox(
                width: double.maxFinite,
                height: 300,
                child: Stack(
                  children: [
                    AnimatedOpacity(
                      opacity: _lastTaskState?.status == DownloadStatus.downloading ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 600),
                      child: RepaintBoundary(
                        child: _MatrixRainBackground(
                          active: _lastTaskState?.status == DownloadStatus.downloading,
                        ),
                      ),
                    ),
                    ListView.builder(
                      controller: _scrollController,
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[index];
                        final Color color;
                        switch (log['type']) {
                          case 'stats':  color = const Color(0xFF33FF33); break;
                          case 'error':  color = const Color(0xFFFF5555); break;
                          case 'matrix': color = Colors.white; break;
                          case 'boot':   color = const Color(0xFF00AA00); break;
                          default:       color = const Color(0xFFADFF2F); break;
                        }
                        return Text(
                          log['message'],
                          style: GoogleFonts.sourceCodePro(color: color, fontSize: 12),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            if (!_isDownloadComplete &&
                !_hasFatalError &&
                _lastTaskState?.status == DownloadStatus.downloading)
              const Row(
                children: [
                  Text('>', style: TextStyle(color: Color(0xFF33FF33))),
                  BlinkingCursor(),
                ],
              ),
            const Divider(color: Colors.green),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  if (_isDownloadComplete || _hasFatalError || _isAborting) {
                    Navigator.of(context).pop();
                  } else {
                    setState(() => _isAborting = true);
                    _downloadManager.cancelTask(widget.taskId);
                  }
                },
                child: Text(
                  _isDownloadComplete || _hasFatalError
                      ? l10n.terminalCloseButton
                      : _isAborting
                          ? l10n.terminalAbortingButton
                          : l10n.terminalAbortButton,
                  style: GoogleFonts.vt323(color: Colors.white, fontSize: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Matrix Rain ─────────────────────────────────────────────────────────────

class _RainDrop {
  final double xFraction;
  final double phase;
  final double speed;
  const _RainDrop({required this.xFraction, required this.phase, required this.speed});
}

class _MatrixRainBackground extends StatefulWidget {
  final bool active;
  const _MatrixRainBackground({this.active = true});

  @override
  State<_MatrixRainBackground> createState() => _MatrixRainBackgroundState();
}

class _MatrixRainBackgroundState extends State<_MatrixRainBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_RainDrop> _drops;

  static const int _dropCount = 14;

  @override
  void initState() {
    super.initState();
    final rng = Random();
    _drops = List.generate(
      _dropCount,
      (i) => _RainDrop(
        xFraction: i / _dropCount + rng.nextDouble() * 0.04,
        phase: rng.nextDouble(),
        // Speed entier obligatoire : garantit (1.0*n + phase) % 1.0 == phase
        // → pas de saut de position au rebouclage du controller
        speed: (rng.nextInt(3) + 1).toDouble(), // 1x, 2x ou 3x par cycle
      ),
    );
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
  }

  @override
  void didUpdateWidget(_MatrixRainBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _controller.repeat();
    } else if (!widget.active && oldWidget.active) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => SizedBox.expand(
        child: CustomPaint(
          painter: _MatrixRainPainter(_drops, _controller.value),
        ),
      ),
    );
  }
}

class _MatrixRainPainter extends CustomPainter {
  final List<_RainDrop> drops;
  final double animValue;

  const _MatrixRainPainter(this.drops, this.animValue);

  @override
  void paint(Canvas canvas, Size size) {
    const chars = _kMatrixChars;
    const trailSteps = 8;
    const charHeight = 9.0;

    for (int i = 0; i < drops.length; i++) {
      final drop = drops[i];
      final x = drop.xFraction * size.width;
      final yProgress = (animValue * drop.speed + drop.phase) % 1.0;
      final yHead = yProgress * (size.height + trailSteps * charHeight) - trailSteps * charHeight;

      // Traîne dégradée
      for (int j = 1; j <= trailSteps; j++) {
        final yTrail = yHead - j * charHeight;
        if (yTrail < 0 || yTrail > size.height) continue;
        final alpha = (1.0 - j / trailSteps) * 0.12;
        canvas.drawRect(
          Rect.fromLTWH(x - 4, yTrail, 10, charHeight),
          Paint()..color = Color.fromRGBO(0, 180, 0, alpha),
        );
      }

      // Caractère de tête
      if (yHead >= -charHeight && yHead <= size.height) {
        final charIndex =
            ((animValue * 30 + i * 4.3 + drop.phase * 10).floor()).abs() % chars.length;
        final tp = TextPainter(
          text: TextSpan(
            text: chars[charIndex],
            style: TextStyle(
              color: Colors.greenAccent.withAlpha(140),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        tp.paint(canvas, Offset(x - 4, yHead));
      }
    }
  }

  @override
  bool shouldRepaint(_MatrixRainPainter old) => old.animValue != animValue;
}

// ─── Widgets utilitaires ──────────────────────────────────────────────────────

class BlinkingCursor extends StatefulWidget {
  const BlinkingCursor({super.key});

  @override
  State<BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _controller,
        child: const Text(
          '_',
          style: TextStyle(color: Color(0xFF33FF33), fontWeight: FontWeight.bold),
        ),
      );
}
