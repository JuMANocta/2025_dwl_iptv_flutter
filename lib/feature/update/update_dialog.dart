import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../core/themes/colors.dart';
import '../../data/services/update_service.dart';

/// Dialogue de mise à jour in-app.
///
/// Affiche le changelog de la release GitHub et permet de télécharger
/// puis installer l'APK directement depuis l'application.
class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;

  const UpdateDialog({super.key, required this.info});

  /// Affiche le dialogue — à appeler avec [navigatorKey.currentContext].
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

class _UpdateDialogState extends State<UpdateDialog> {
  _DownloadState _state = _DownloadState.idle;
  double _progress = 0.0;
  String? _errorMessage;
  CancelToken? _cancelToken;

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
      // L'installeur Android prend la main — on ferme le dialogue
      if (mounted) Navigator.of(context).pop();
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        if (mounted) { setState(() => _state = _DownloadState.idle); }
      } else {
        if (mounted) { setState(() {
          _state = _DownloadState.error;
          _errorMessage = 'Erreur réseau : ${e.message}';
        }); }
      }
    } catch (e) {
      if (mounted) { setState(() {
        _state = _DownloadState.error;
        _errorMessage = e.toString();
      }); }
    }
  }

  void _cancel() {
    _cancelToken?.cancel();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.system_update_rounded,
              color: kAetherSecondaryCyan, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.info.releaseName,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Taille APK
            if (widget.info.sizeBytes != null)
              Text(
                '${(widget.info.sizeBytes! / 1024 / 1024).toStringAsFixed(1)} MB',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            const SizedBox(height: 12),

            // Changelog
            if (widget.info.body != null && widget.info.body!.trim().isNotEmpty) ...[
              const Text(
                'Nouveautés',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: SingleChildScrollView(
                  child: Text(
                    widget.info.body!.trim(),
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Barre de progression
            if (_state == _DownloadState.downloading) ...[
              LinearProgressIndicator(
                value: _progress,
                backgroundColor: kAetherPrimaryPurple.withValues(alpha: 0.2),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(kAetherSecondaryCyan),
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 8),
              Text(
                '${(_progress * 100).toStringAsFixed(0)} %',
                style: const TextStyle(fontSize: 12),
              ),
            ],

            // Erreur
            if (_state == _DownloadState.error && _errorMessage != null)
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
          ],
        ),
      ),
      actions: [
        // Bouton "Plus tard" / "Annuler"
        TextButton(
          onPressed: _cancel,
          child: Text(
            _state == _DownloadState.downloading ? 'Annuler' : 'Plus tard',
          ),
        ),

        // Bouton "Mettre à jour"
        if (_state != _DownloadState.downloading)
          FilledButton.icon(
            onPressed: _startDownload,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(
              _state == _DownloadState.error ? 'Réessayer' : 'Mettre à jour',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: kAetherPrimaryPurple,
            ),
          ),
      ],
    );
  }
}

enum _DownloadState { idle, downloading, error }
