import 'package:flutter/foundation.dart';
import '../../l10n/l10n_ext.dart';

enum DownloadStatus {
  queued,      // En attente de démarrage
  downloading, // En cours de téléchargement
  completed,   // Terminé avec succès
  failed,      // Échec
  canceled,    // Annulé par l'utilisateur
  paused,      // En pause (pour une future évolution)
  finalizing,  // En cours de finalisation (déplacement du fichier)
}

/// Relit un statut persisté (D3A-14).
///
/// ⚠️ **L'écriture reste par INDEX** (`status.index`) : l'écrire par nom
/// rendrait la liste illisible à un APK antérieur, qui fait
/// `DownloadStatus.values[json['status'] as int]` — un retour arrière perdrait
/// alors TOUS les téléchargements. La lecture, elle, accepte les deux formes
/// et replie un statut inconnu sur `failed` (reprenable) au lieu de lever.
/// Corollaire : l'ordre de l'enum est FIGÉ, n'insérer une valeur qu'à la fin.
DownloadStatus downloadStatusFromJson(Object? raw) {
  if (raw is int && raw >= 0 && raw < DownloadStatus.values.length) {
    return DownloadStatus.values[raw];
  }
  if (raw is String) {
    for (final s in DownloadStatus.values) {
      if (s.name == raw) return s;
    }
  }
  return DownloadStatus.failed;
}

@immutable
class DownloadTask {
  final String id;          // Un identifiant unique, ex: un timestamp ou un UUID
  final String url;         // L'URL source du fichier
  final String displayName; // Le nom du fichier choisi par l'utilisateur
  final String finalPath;   // ex: /storage/emulated/0/Movies/AetherStream/film.mp4
  final String tempPath;    // ex: /data/user/0/com.javu.aetherstream/cache/dl_tmp/task_123.mp4
  final DownloadStatus status; // L'état actuel du téléchargement
  final double progress;       // La progression de 0.0 à 1.0
  final int totalSize;         // La taille totale du fichier en octets
  final DateTime createdAt;    // La date de création de la tâche
  final DateTime? updatedAt;   // La date de la dernière mise à jour de l'état
  final String? errorMessage;
  final String? releaseYear;   // L'année de sortie du contenu

  /// §dlWatchdog — Nombre de relances subies par ce transfert.
  ///
  /// ⚠️ Il vivait UNIQUEMENT dans `TerminalDownloadDialog` (`_retryCount`) :
  /// il disparaissait donc à la fermeture du dialogue, alors que le
  /// téléchargement, lui, continue. Persisté ici, la tuile de la liste peut
  /// afficher « relancé ×N » même après un redémarrage de l'app.
  final int retryCount;

  const DownloadTask({
    required this.id,
    required this.url,
    required this.displayName,
    required this.finalPath,
    required this.tempPath,
    required this.createdAt,
    this.status = DownloadStatus.queued,
    this.progress = 0.0,
    this.totalSize = 0,
    this.updatedAt,
    this.errorMessage,
    this.releaseYear,
    this.retryCount = 0,
  });

  DownloadTask copyWith({
    DownloadStatus? status,
    double? progress,
    int? totalSize,
    String? errorMessage,
    String? finalPath,
    String? tempPath,
    String? releaseYear,
    int? retryCount,
  }) {
    String? finalErrorMessage = errorMessage;
    if (status == DownloadStatus.failed && errorMessage == null) {
      finalErrorMessage = L10n.current.errUnknown;
    }

    return DownloadTask(
      id: id,
      url: url,
      displayName: displayName,
      finalPath: finalPath ?? this.finalPath,
      tempPath: tempPath ?? this.tempPath,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      status: status ?? this.status,
      progress: progress ?? this.progress,
      totalSize: totalSize ?? this.totalSize,
      errorMessage: finalErrorMessage,
      releaseYear: releaseYear ?? this.releaseYear,
      retryCount: retryCount ?? this.retryCount,
    );
  }

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      id: json['id'] as String,
      url: json['url'] as String,
      displayName: json['displayName'] as String,
      finalPath: json['finalPath'] as String,
      tempPath: json['tempPath'] as String? ?? '',
      status: downloadStatusFromJson(json['status']),
      progress: (json['progress'] as num).toDouble(),
      totalSize: json['totalSize'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt'] as String) : null,
      errorMessage: json['errorMessage'] as String?,
      releaseYear: json['releaseYear'] as String?,
      // Tâche enregistrée avant §dlWatchdog : aucune relance connue.
      retryCount: json['retryCount'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'displayName': displayName,
      'finalPath': finalPath,
      'tempPath': tempPath,
      'status': status.index,
      'progress': progress,
      'totalSize': totalSize,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'errorMessage': errorMessage,
      'releaseYear': releaseYear,
      'retryCount': retryCount,
    };
  }

  /// Crée une instance "vide" de tâche.
  factory DownloadTask.empty() {
    return DownloadTask(
      id: '',
      url: '',
      displayName: '',
      finalPath: '',
      tempPath: '',
      createdAt: DateTime.fromMicrosecondsSinceEpoch(0),
      releaseYear: null,
    );
  }
}
