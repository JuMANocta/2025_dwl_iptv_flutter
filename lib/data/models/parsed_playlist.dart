import 'package:aetherStream/data/models/m3u_entry.dart';

/// Résultat complet du parsing d'une playlist M3U pour un compte donné.
/// Sert de container sérialisable pour le cache disque (JSON.gz) et de source
/// de vérité en mémoire pour toute l'application.
class ParsedPlaylist {
  /// Version du schéma de sérialisation.
  /// Incrémenter quand la structure de [M3uEntry] ou [TitleMetadata] change
  /// → invalide automatiquement tous les caches disque existants.
  static const int schemaVersion = 6; // v6 : cache disque NDJSON streamé (anti-OOM grosse liste)

  final String accountId;
  /// Version du schéma au moment de la sauvegarde — comparé à [schemaVersion] à la relecture.
  final int schema;
  /// Date de dernière modification du fichier .m3u source — invalidation si changée.
  final DateTime m3uModifiedAt;
  /// Toutes les entrées brutes (films + séries + TV confondus).
  final List<M3uEntry> entries;

  ParsedPlaylist({
    required this.accountId,
    required this.schema,
    required this.m3uModifiedAt,
    required this.entries,
  });

  // ── Getters calculés en mémoire (non stockés dans le JSON) ────────────────

  late final List<M3uEntry> films  = entries.where((e) => e.type == M3uContentType.movie).toList();
  late final List<M3uEntry> series = entries.where((e) => e.type == M3uContentType.series).toList();
  late final List<M3uEntry> tv     = entries.where((e) => e.type == M3uContentType.tv).toList();

  // ── Sérialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'schema':       schema,
    'accountId':    accountId,
    'm3uModAt':     m3uModifiedAt.toIso8601String(),
    'entries':      entries.map((e) => e.toJson()).toList(),
  };

  factory ParsedPlaylist.fromJson(Map<String, dynamic> j) => ParsedPlaylist(
    schema:       j['schema']    as int,
    accountId:    j['accountId'] as String,
    m3uModifiedAt: DateTime.parse(j['m3uModAt'] as String),
    entries:      (j['entries'] as List)
        .map((e) => M3uEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
