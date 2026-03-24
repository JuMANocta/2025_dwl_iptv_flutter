import 'package:flutter/material.dart';
import 'package:aetherStream/data/models/m3u_entry.dart';
import 'package:aetherStream/data/models/xmltv_program.dart';
import 'package:aetherStream/data/services/xmltv_service.dart';
import 'package:aetherStream/core/themes/colors.dart';
import 'package:aetherStream/widgets/quality_buttons.dart';

class EpgNowNextBlock extends StatefulWidget {
  final String tvgId;
  final List<M3uEntry> versions;
  final void Function(M3uEntry)? onPlayVersion;

  const EpgNowNextBlock({
    super.key,
    required this.tvgId,
    this.versions = const [],
    this.onPlayVersion,
  });

  @override
  State<EpgNowNextBlock> createState() => _EpgNowNextBlockState();
}

class _EpgNowNextBlockState extends State<EpgNowNextBlock> {
  XmltvProgram? _current;
  XmltvProgram? _next;
  String? _channelIconUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Future.any([
      _doLoad(),
      Future.delayed(const Duration(seconds: 12)),
    ]);
    if (mounted && _loading) setState(() => _loading = false);
  }

  Future<void> _doLoad() async {
    final current     = await XmltvService.getCurrentProgram(widget.tvgId);
    final next        = await XmltvService.getNextProgram(widget.tvgId);
    final channelIcon = await XmltvService.getChannelIconUrl(widget.tvgId);
    if (mounted) setState(() {
      _current       = current;
      _next          = next;
      _channelIconUrl = channelIcon;
      _loading       = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (_current == null && _next == null) {
      if (widget.versions.isEmpty || widget.onPlayVersion == null) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: QualityButtonsRow(versions: widget.versions, onPlay: widget.onPlayVersion!),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: kContainerDark.withOpacity(0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kAetherPrimaryPurple.withOpacity(0.3)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Column(
          children: [
            if (_current != null)
              EpgProgramRow(
                program: _current!,
                isNow: true,
                versions: widget.versions,
                onPlayVersion: widget.onPlayVersion,
                channelIconUrl: _channelIconUrl,
              ),
            if (_current != null && _next != null)
              const Divider(height: 1, indent: 12, endIndent: 12),
            if (_next != null)
              EpgProgramRow(
                program: _next!,
                isNow: false,
                channelIconUrl: _channelIconUrl,
              ),
          ],
        ),
      ),
    );
  }
}

class EpgProgramRow extends StatelessWidget {
  final XmltvProgram program;
  final bool isNow;
  final List<M3uEntry> versions;
  final void Function(M3uEntry)? onPlayVersion;
  final String? channelIconUrl;

  const EpgProgramRow({
    super.key,
    required this.program,
    required this.isNow,
    this.versions = const [],
    this.onPlayVersion,
    this.channelIconUrl,
  });

  @override
  Widget build(BuildContext context) {
    final showQualityButtons = isNow && versions.isNotEmpty && onPlayVersion != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (program.iconUrl != null || channelIconUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    program.iconUrl ?? channelIconUrl!,
                    width: 54,
                    height: 38,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) {
                      if (program.iconUrl != null && channelIconUrl != null) {
                        return Image.network(
                          channelIconUrl!,
                          width: 54, height: 38, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox(width: 54, height: 38),
                        );
                      }
                      return const SizedBox(width: 54, height: 38);
                    },
                  ),
                )
              else
                const SizedBox(width: 54, height: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isNow
                                ? kAetherVibrantMagenta.withOpacity(0.9)
                                : kAetherPrimaryPurple.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isNow ? '● EN COURS' : 'ENSUITE',
                            style: const TextStyle(color: kWhite, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(program.timeRange, style: const TextStyle(fontSize: 11, color: kMediumGrey)),
                        const SizedBox(width: 4),
                        Text('(${program.durationLabel})', style: const TextStyle(fontSize: 10, color: kMediumGrey)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      program.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    if (program.category != null)
                      Text(program.category!, style: const TextStyle(fontSize: 11, color: kMediumGrey), maxLines: 1),
                  ],
                ),
              ),
            ],
          ),
          if (showQualityButtons) ...[
            const SizedBox(height: 10),
            QualityButtonsRow(versions: versions, onPlay: onPlayVersion!),
          ],
        ],
      ),
    );
  }
}
