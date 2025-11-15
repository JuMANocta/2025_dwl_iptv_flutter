import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/download_task.dart';
import '../utils/network.dart';

/// Service pour gérer la liste des tâches de téléchargement.
/// Il utilise SharedPreferences pour la persistance et un ValueNotifier
/// pour notifier l'UI des changements en temps réel.
class DownloadManagerService {
  // --- Singleton Pattern (assure qu'il n'y a qu'une seule instance de ce service) ---
  static final DownloadManagerService _instance = DownloadManagerService._internal();
  factory DownloadManagerService() => _instance;
  DownloadManagerService._internal();

  // --- State Management (le coeur de la notification) ---
  final ValueNotifier<List<DownloadTask>> tasksNotifier = ValueNotifier([]);

  // --- Persistence ---
  static const _storageKey = 'download_tasks_list';
  late SharedPreferences _prefs;

  /// Doit être appelé une seule fois au démarrage de l'application (dans main.dart).
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _loadTasksFromDisk();
  }

  // --- Méthodes privées ---

  void _loadTasksFromDisk() {
    final jsonString = _prefs.getString(_storageKey);
    if (jsonString != null) {
      try {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        tasksNotifier.value = jsonList
            .map((json) => DownloadTask.fromJson(json as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint("Erreur lors du chargement des tâches : $e");
        tasksNotifier.value = [];
      }
    }
  }

  Future<void> _saveTasksToDisk() async {
    try {
      final jsonList = tasksNotifier.value.map((task) => task.toJson()).toList();
      await _prefs.setString(_storageKey, jsonEncode(jsonList));
    } catch (e) {
      debugPrint("Erreur lors de la sauvegarde des tâches : $e");
    }
  }

  // --- Méthodes publiques (utilisées par le reste de l'app) ---

  /// Ajoute une nouvelle tâche à la liste.
  Future<void> addTask(DownloadTask task) async {
    final currentTasks = List<DownloadTask>.from(tasksNotifier.value);
    if (!currentTasks.any((t) => t.id == task.id)) {
      currentTasks.insert(0, task);
      tasksNotifier.value = currentTasks;
      await _saveTasksToDisk();
    }
  }

  // On garde une trace des CancelToken pour pouvoir annuler les tâches.
  final Map<String, CancelToken> _cancelTokens = {};

  /// LANCE ET GÈRE UN TÉLÉCHARGEMENT EN ARRIÈRE-PLAN
  Future<void> startDownloadTask(DownloadTask task) async {
    if (_cancelTokens.containsKey(task.id)) return; // Déjà en cours

    final dio = await NetworkUtils.buildIptvDio(task.url);
    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;

    try {
      // Met à jour le statut pour que l'UI affiche "En attente" ou "En cours"
      await updateTask(task.id, status: DownloadStatus.downloading, progress: 0.0);

      await dio.download(
        task.url,
        '${task.finalPath}.downloading', // On télécharge dans un fichier temporaire
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          final totalBytes = total > 0 ? total : task.totalSize;
          if (totalBytes > 0) {
            final progress = received / totalBytes;
            // C'est ici que la magie opère : mise à jour en temps réel
            updateTask(
              task.id,
              progress: progress,
              totalSize: totalBytes,
              status: DownloadStatus.downloading,
            );
          }
        },
      );

      // Renomme le fichier temporaire en fichier final
      await File('${task.finalPath}.downloading').rename(task.finalPath);
      await updateTask(task.id, status: DownloadStatus.completed, progress: 1.0);

    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        await updateTask(task.id, status: DownloadStatus.canceled);
      } else {
        await updateTask(task.id, status: DownloadStatus.failed);
      }
    } catch (e) {
      await updateTask(task.id, status: DownloadStatus.failed);
    } finally {
      // Nettoyage impératif pour permettre de relancer la tâche
      _cancelTokens.remove(task.id);
    }
  }

  /// Annule un téléchargement en cours.
  Future<void> cancelTask(String taskId) async {
    if (_cancelTokens.containsKey(taskId)) {
      _cancelTokens[taskId]?.cancel();
      // Le bloc `catch` dans `startDownloadTask` mettra à jour le statut.
    }
  }

  /// Met à jour une tâche existante et notifie l'UI.
  Future<void> updateTask(String taskId, {DownloadStatus? status, double? progress, int? totalSize}) async {
    final tasks = tasksNotifier.value;
    final index = tasks.indexWhere((t) => t.id == taskId);

    if (index != -1) {
      tasks[index] = tasks[index].copyWith(
        status: status,
        progress: progress,
        totalSize: totalSize,
      );
      // LA LIGNE CLÉ : On assigne une NOUVELLE liste pour déclencher le ValueNotifier.
      tasksNotifier.value = List.from(tasks);
      await _saveTasksToDisk();
    }
  }

  /// Supprime une tâche de la liste.
  Future<void> removeTask(String taskId) async {
    // Annuler si en cours
    await cancelTask(taskId);
    // Supprimer de la liste
    final currentTasks = List<DownloadTask>.from(tasksNotifier.value);
    currentTasks.removeWhere((t) => t.id == taskId);
    tasksNotifier.value = currentTasks;
    await _saveTasksToDisk();
  }
}
