import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/matrix_rain.dart';
import 'version_diff_line.dart';
import '../../data/services/update_service.dart';
import 'package:aetherStream/widgets/tv/tv_adaptive_modal.dart';

/// §updateGreen — Vert vif du dialog de MAJ (style « Matrix terminal », figé,
/// indépendant du thème). Remplace `kSuccess` (#4CAF50, trop terne sur fond
/// sombre) pour rendre les boutons/séparateurs bien visibles.
const Color _kTermGreen = Color(0xFF00FF41);

/// Dialogue de mise à jour in-app — style terminal Matrix.
/// Cohérent avec [TerminalDownloadDialog].
class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;

  const UpdateDialog({super.key, required this.info});

  static Future<void> show(BuildContext context, UpdateInfo info) {
    return showAppDialog(
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

  /// §updateBanner — Ouvre la page GitHub de la release.
  ///
  /// ⚠️ Repli sur la liste des releases quand `html_url` manque (release
  /// éditée à la main, ou champ absent du JSON) : mieux vaut la bonne page à
  /// un clic près qu'un bouton mort.
  Future<void> _openRelease() async {
    final url = widget.info.htmlUrl ??
        'https://github.com/JuMANocta/2025_dwl_iptv_flutter/releases';
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('⚠️ §updateBanner — ouverture de la release impossible : $e');
    }
  }

  /// Bouton « terminal » discret, pour les actions secondaires.
  Widget _terminalLinkButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: GoogleFonts.sourceCodePro(
          color: _kTermGreen,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sizeStr = widget.info.sizeBytes != null
        ? '${(widget.info.sizeBytes! / 1024 / 1024).toStringAsFixed(1)} MB'
        : null;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withAlpha((255 * 0.93).round()),
          border: Border.all(color: _kTermGreen.withAlpha(60)),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(color: _kTermGreen.withAlpha(25), blurRadius: 12, spreadRadius: 2),
          ],
        ),
        // §updateBanner — La pluie Matrix passe DERRIÈRE tout le bandeau, au
        // lieu de n'exister que derrière la barre de progression (donc
        // seulement pendant le téléchargement, donc presque jamais vue).
        //
        // ⚠️ `alpha: 45` : à pleine intensité elle rend le texte illisible.
        // ⚠️ `ClipRRect` obligatoire, sinon elle déborde des coins arrondis.
        // ⚠️ `IgnorePointer` : elle ne doit intercepter ni les taps ni le
        // focus, sinon elle volerait la cible du D-pad sur TV.
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              const Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(child: MatrixRain(alpha: 45)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
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

                    // §updateBanner — Versions confrontées, la nouvelle se
                    // « décode » et la partie qui CHANGE est mise en évidence.
                    // Avant : « > REMOTE : v1.15.9 » seul, sans jamais dire de
                    // quelle version on part.
                    VersionDiffLine(
                      localVersion: widget.info.localVersion,
                      remoteVersion: widget.info.tagName,
                    ),

                    if (sizeStr != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '> SIZE   : $sizeStr',
                        style: GoogleFonts.sourceCodePro(
                          color: const Color(0xFFADFF2F), fontSize: 12),
                      ),
                    ],

                    // §updateBanner — Le changelog GitHub était dumpé en
                    // Markdown BRUT dans un scroll de 260 px : illisible, et
                    // impraticable à la télécommande. On renvoie vers la
                    // source, qui le rend correctement.
                    const SizedBox(height: 8),
                    Text(
                      '> DIFF    : voir la release sur GitHub',
                      style: GoogleFonts.sourceCodePro(
                          color: const Color(0xFF00AA00), fontSize: 11),
                    ),
                    const SizedBox(height: 4),
                    _terminalLinkButton(
                      label: '[ VIEW CHANGELOG ]',
                      onPressed: _openRelease,
                    ),

                    const SizedBox(height: 10),

                    // ── Progression ────────────────────────────────────────
                    if (_state == _DownloadState.downloading) ...[
                      Text(
                        '> DOWNLOADING...',
                        style: GoogleFonts.sourceCodePro(
                          color: const Color(0xFFADFF2F), fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 48,
                        child: Stack(children: [
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
                    // §updateBanner — Autofocus : le dialogue n'avait AUCUN
                    // focus initial, donc à la télécommande il fallait
                    // « chercher » le bouton à l'aveugle avant de pouvoir
                    // faire quoi que ce soit.
                    autofocus: true,
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
            ],
          ),
        ),
      ),
    );
  }
}

enum _DownloadState { idle, downloading, error }
