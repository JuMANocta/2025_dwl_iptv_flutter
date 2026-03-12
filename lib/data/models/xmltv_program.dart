import 'package:intl/intl.dart';

/// Programme issu d'un fichier XMLTV (EPG).
class XmltvProgram {
  final String channelId;
  final DateTime start;
  final DateTime stop;
  final String title;
  final String? subtitle;
  final String? description;
  final String? category;
  final String? iconUrl;   // affiche du programme
  final String? rating;    // ex: "Tout public", "-10"

  XmltvProgram({
    required this.channelId,
    required this.start,
    required this.stop,
    required this.title,
    this.subtitle,
    this.description,
    this.category,
    this.iconUrl,
    this.rating,
  });

  /// Vrai si ce programme est diffusé à l'instant [t].
  bool isCurrentAt(DateTime t) => t.isAfter(start) && t.isBefore(stop);

  bool get isNow => isCurrentAt(DateTime.now());

  String get timeRange {
    final fmt = DateFormat('HH:mm');
    return '${fmt.format(start)} – ${fmt.format(stop)}';
  }

  String get durationLabel {
    final d = stop.difference(start);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return h > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '${m}min';
  }

  /// Parse un timestamp XMLTV : "20260312200000 +0100"
  static DateTime parseDate(String s) {
    final parts = s.trim().split(RegExp(r'\s+'));
    final d = parts[0];
    final tz = parts.length > 1 ? parts[1] : '+0000';

    final year   = int.parse(d.substring(0, 4));
    final month  = int.parse(d.substring(4, 6));
    final day    = int.parse(d.substring(6, 8));
    final hour   = int.parse(d.substring(8, 10));
    final minute = int.parse(d.substring(10, 12));
    final second = d.length >= 14 ? int.parse(d.substring(12, 14)) : 0;

    final sign   = tz[0] == '-' ? -1 : 1;
    final tzH    = int.parse(tz.substring(1, 3));
    final tzM    = int.parse(tz.substring(3, 5));
    final offset = Duration(hours: tzH, minutes: tzM) * sign;

    // Crée en UTC puis ajuste le fuseau, convertit en heure locale
    final utc = DateTime.utc(year, month, day, hour, minute, second)
        .subtract(offset);
    return utc.toLocal();
  }
}
