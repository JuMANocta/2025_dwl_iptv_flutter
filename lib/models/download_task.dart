import 'package:flutter/foundation.dart';

// Énumération pour représenter l'état d'un téléchargement.
// C'est plus propre et plus sûr que d'utiliser des chaînes de caractères.
enum DownloadStatus {
  queued,      // En attente de démarrage
  downloading, // En cours de téléchargement
  completed,   // Terminé avec succès
  failed,      // Échec
  canceled,    // Annulé par l'utilisateur
  paused,      // En pause (pour une future évolution)
}

@immutable
class DownloadTask {
  final String id;          // Un identifiant unique, ex: un timestamp ou un UUID
  final String url;         // L'URL source du fichier
  final String displayName; // Le nom du fichier choisi par l'utilisateur
  final String finalPath;   // Le chemin final où le fichier est (ou sera) sauvegardé

  final DownloadStatus status; // L'état actuel du téléchargement
  final double progress;       // La progression de 0.0 à 1.0
  final int totalSize;         // La taille totale du fichier en octets

  final DateTime createdAt; // La date de création de la tâche
  final DateTime? updatedAt;  // La date de la dernière mise à jour de l'état

  const DownloadTask({
    required this.id,
    required this.url,
    required this.displayName,
    required this.finalPath,
    this.status = DownloadStatus.queued,
    this.progress = 0.0,
    this.totalSize = 0,
    required this.createdAt,
    this.updatedAt,
  });

  // Méthode 'copyWith' pour créer une nouvelle instance avec des valeurs modifiées.
  // C'est une bonne pratique pour les objets immuables.
  DownloadTask copyWith({
    String? id,
    String? url,
    String? displayName,String? finalPath,
    DownloadStatus? status,
    double? progress,
    int? totalSize, // <--- 1. AJOUTER LE PARAMÈTRE ICI
    DateTime? createdAt,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      url: url ?? this.url,
      displayName: displayName ?? this.displayName,
      finalPath: finalPath ?? this.finalPath,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      totalSize: totalSize ?? this.totalSize, // <--- 2. UTILISER LE NOUVEAU PARAMÈTRE ICI
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // Méthodes pour la sérialisation/désérialisation en JSON.
  // Essentiel pour sauvegarder la liste des tâches sur le disque.
  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      id: json['id'] as String,
      url: json['url'] as String,
      displayName: json['displayName'] as String,
      finalPath: json['finalPath'] as String,
      status: DownloadStatus.values[json['status'] as int],
      progress: (json['progress'] as num).toDouble(),
      totalSize: json['totalSize'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt'] as String) : null,
    );
  }

  /// Crée une instance "vide" de tâche.
  /// Utile pour les retours de fonctions comme `firstWhere` quand aucun élément n'est trouvé.
  factory DownloadTask.empty() {
    return DownloadTask(
      id: '', // L'ID vide est la clé pour savoir qu'elle est "vide"
      url: '',
      displayName: '',
      finalPath: '',
      createdAt: DateTime.fromMicrosecondsSinceEpoch(0),
      status: DownloadStatus.queued, // Un statut par défaut
      progress: 0.0,
      totalSize: 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'displayName': displayName,
      'finalPath': finalPath,
      'status': status.index, // On stocke l'index de l'enum, c'est plus robuste
      'progress': progress,
      'totalSize': totalSize,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}
