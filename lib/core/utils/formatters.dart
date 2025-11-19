import 'dart:math' as math;

String formatFileSize(int bytes) {
  if (bytes <= 0) return "0 B";
  const suffixes = ["B", "KB", "MB", "GB", "TB"];
  final i = (math.log(bytes) / math.log(1024)).floor();
  return "${(bytes / (1 << (10 * i))).toStringAsFixed(2)} ${suffixes[i]}";
}

String formatDuration(int totalSeconds) {
  if (totalSeconds < 0) return "--:--";
  final duration = Duration(seconds: totalSeconds);
  final hours = duration.inHours.toString().padLeft(2, '0');
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return (duration.inHours > 0) ? "$hours:$minutes:$seconds" : "$minutes:$seconds";
}