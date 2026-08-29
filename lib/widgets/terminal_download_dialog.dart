import 'dart:math';
import 'package:flutter/material.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/widgets/matrix_rain.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/models/download_task.dart';
import '../data/services/download_manager_service.dart';
import '../core/utils/formatters.dart';
import '../l10n/app_localizations.dart';

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

  int _retryCount = 0;
  final Set<int> _expandedAccordions = {};

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
      // Reprise après une erreur : replier les erreurs passées dans un accordéon
      if (_hasFatalError) {
        _collapseRecentErrors();
        _logs.add({'message': '> RETRY #$_retryCount — RECONNECTING...', 'type': 'retry'});
      }
      // §dlRestartFix — `_isDownloadComplete` était un drapeau qui ne se
      // RÉARMAIT JAMAIS : après un téléchargement terminé, le moniteur restait
      // verrouillé sur son état final et ne proposait plus que « Fermer », même
      // si un retéléchargement venait d'être lancé. On le remet à zéro dès
      // qu'un transfert repart (symétrique du traitement de `_hasFatalError`).
      if (_isDownloadComplete) {
        _isDownloadComplete = false;
        _stopwatch = null; // vitesse/ETA recalculés pour la nouvelle session
        _logs.add({
          'message': '> RESTART — NEW TRANSFER INITIATED...',
          'type': 'retry',
        });
      }
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

  // Regroupe les entrées d'erreur en fin de log dans un accordéon replié.
  // Appelé quand le téléchargement reprend après un état failed.
  void _collapseRecentErrors() {
    _retryCount++;
    int firstErrorIndex = _logs.length;
    for (int i = _logs.length - 1; i >= 0; i--) {
      if (_logs[i]['type'] == 'error') {
        firstErrorIndex = i;
      } else {
        break;
      }
    }
    if (firstErrorIndex >= _logs.length) return;
    final errorMessages = _logs
        .sublist(firstErrorIndex)
        .map((l) => l['message'] as String)
        .toList();
    _logs.removeRange(firstErrorIndex, _logs.length);
    _logs.add({'type': 'error_accordion', 'messages': errorMessages});
    _hasFatalError = false;
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

  /// §dlErgo — Bouton du moniteur, avec CONTOUR : en simples `TextButton` sur
  /// le fond noir du terminal, les actions se fondaient les unes dans les
  /// autres et l'œil n'en repérait qu'une seule.
  Widget _terminalButton({
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withAlpha(160)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        minimumSize: const Size(0, 38),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: GoogleFonts.vt323(color: color, fontSize: 18),
      ),
    );
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
          // §dlTheme — Fond sombre volontaire (identité « terminal »), mais tiré
          // de la palette du projet plutôt que d'un `Colors.black` brut ; la
          // bordure et le halo suivent l'accent du preset.
          color: kDeepDarkGrey.withAlpha(235),
          border: Border.all(color: kAccentPrimary.withAlpha(70)),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
                color: kAccentPrimary.withAlpha(30),
                blurRadius: 10,
                spreadRadius: 2)
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.terminalTitle,
              style: GoogleFonts.vt323(color: kSuccess, fontSize: 22),
            ),
            Divider(color: kSuccess),
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
                        child: MatrixRain(
                          active: _lastTaskState?.status == DownloadStatus.downloading,
                        ),
                      ),
                    ),
                    ListView.builder(
                      controller: _scrollController,
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[index];
                        final type = log['type'] as String;

                        // Accordéon pour les erreurs passées (retry)
                        if (type == 'error_accordion') {
                          final messages = log['messages'] as List<String>;
                          final isExpanded = _expandedAccordions.contains(index);
                          return GestureDetector(
                            onTap: () => setState(() {
                              if (isExpanded) {
                                _expandedAccordions.remove(index);
                              } else {
                                _expandedAccordions.add(index);
                              }
                            }),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '> [!] ${messages.length} ERREUR(S) PRÉCÉDENTE(S)  ${isExpanded ? '▲ MASQUER' : '▼ AFFICHER'}',
                                  style: GoogleFonts.sourceCodePro(
                                    color: kWarning.withAlpha(200),
                                    fontSize: 12,
                                  ),
                                ),
                                if (isExpanded)
                                  ...messages.map(
                                    (msg) => Padding(
                                      padding: const EdgeInsets.only(left: 12),
                                      child: Text(
                                        msg,
                                        style: GoogleFonts.sourceCodePro(
                                          color: kError.withAlpha(140),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }

                        // §dlTheme — Ces couleurs étaient des hex CODÉS EN DUR
                        // (verts Matrix, rouge fixe) : le moniteur restait vert
                        // même en preset Tron, Synthwave ou Blade Runner. Elles
                        // suivent désormais la palette sémantique.
                        final Color color;
                        switch (type) {
                          case 'stats':  color = kAccentPrimary; break;
                          case 'error':  color = kError; break;
                          case 'matrix': color = kAccentSecondary; break;
                          case 'boot':   color = kAccentPrimary.withAlpha(150); break;
                          case 'retry':  color = kWarning; break;
                          default:       color = kSuccess; break;
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
              Row(
                children: [
                  Text('>', style: TextStyle(color: kAccentPrimary)),
                  const BlinkingCursor(),
                ],
              ),
            Divider(color: kSuccess),
            // §dlErgo — Pendant le téléchargement, le SEUL bouton était
            // « ABORT » : pour laisser tourner en fond il fallait deviner
            // qu'on pouvait fermer en tapant hors du dialogue — impraticable à
            // la télécommande. On sépare donc les deux intentions, « Fermer »
            // (le cas courant) restant à droite, sous le pouce.
            Align(
              alignment: Alignment.centerRight,
              child: Builder(builder: (context) {
                final finished =
                    _isDownloadComplete || _hasFatalError || _isAborting;
                final closeButton = _terminalButton(
                  label: l10n.terminalCloseButton,
                  color: kTextDarkPrimary,
                  onPressed: () => Navigator.of(context).pop(),
                );
                if (finished) {
                  // Annulation en cours : le dialogue va se fermer tout seul.
                  if (_isAborting) {
                    return Text(
                      l10n.terminalAbortingButton,
                      style: GoogleFonts.vt323(
                          color: kTextDarkPrimary, fontSize: 18),
                    );
                  }
                  // ⚠️ Téléchargement TERMINÉ : pas de relance. Le fichier
                  // partiel a été renommé en fichier final, il n'y a plus rien
                  // à reprendre — un « relancer » referait plusieurs Go depuis
                  // zéro. Pour refaire un fichier : le supprimer, puis relancer
                  // depuis sa fiche.
                  if (_isDownloadComplete) return closeButton;
                  // En ERREUR, en revanche, le `.part` est toujours là : la
                  // relance reprend au même octet (`Range`).
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      _terminalButton(
                        label: 'RELANCER',
                        color: kAccentSecondary,
                        onPressed: () {
                          final t = _lastTaskState;
                          if (t == null) return;
                          _downloadManager.restartTask(t);
                        },
                      ),
                      closeButton,
                    ],
                  );
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    // §dlErgo — RELANCER en tête : c'est l'action qu'on cherche
                    // en regardant le moniteur quand le débit s'effondre
                    // (bridage fournisseur). Rétablir la connexion repart
                    // souvent à pleine vitesse, et la reprise `Range` fait
                    // repartir du même octet — rien n'est perdu.
                    _terminalButton(
                      label: 'RELANCER',
                      color: kAccentSecondary,
                      onPressed: () {
                        final t = _lastTaskState;
                        if (t == null) return;
                        _downloadManager.restartTask(t);
                      },
                    ),
                    _terminalButton(
                      label: l10n.terminalAbortButton,
                      color: kWarning,
                      onPressed: () {
                        setState(() => _isAborting = true);
                        _downloadManager.cancelTask(widget.taskId);
                      },
                    ),
                    closeButton,
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Matrix Rain ─────────────────────────────────────────────────────────────


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
        child: Text(
          '_',
          // §dlTheme — suit l'accent du preset (était un vert Matrix figé).
          style: TextStyle(color: kAccentPrimary, fontWeight: FontWeight.bold),
        ),
      );
}
