import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/download_task.dart';

/// Service pour gérer la liste des tâches de téléchargement.
/// Il utilise SharedPreferences pour la persistance et un ValueNotifier
/// pour notifier l'UI des changements en temps réel.
class DownloadManagerService {
  // --- Singleton Pattern ---
  // Pour s'assurer qu'il n'y a qu'une seule instance de ce service dans l'application.
  static final DownloadManagerService _instance = DownloadManagerService._internal();
  factory DownloadManagerService() => _instance;
  DownloadManagerService._internal();

  // --- State Management ---
  // ValueNotifier est une façon simple et efficace de notifier les widgets
  // qui écoutent lorsque la liste des tâches change.
  final ValueNotifier<List<DownloadTask>> tasksNotifier = ValueNotifier([]);

  // --- Persistence ---
  static const _storageKey = 'download_tasks_list';
  late SharedPreferences _prefs;

  // --- Initialization ---
  /// Doit être appelé une seule fois au démarrage de l'application (dans main.dart).
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _loadTasksFromDisk();
  }

  // --- Private Methods ---

  /// Charge la liste des tâches depuis SharedPreferences.
  void _loadTasksFromDisk() {
    final jsonString = _prefs.getString(_storageKey);
    if (jsonString != null) {
      try {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        tasksNotifier.value = jsonList
            .map((json) => DownloadTask.fromJson(json as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint("Erreur lors du chargement des tâches de téléchargement : $e");
        tasksNotifier.value = [];
      }
    }
  }

  /// Sauvegarde la liste actuelle des tâches dans SharedPreferences.
  Future<void> _saveTasksToDisk() async {
    try {
      final jsonList = tasksNotifier.value.map((task) => task.toJson()).toList();
      await _prefs.setString(_storageKey, jsonEncode(jsonList));
    } catch (e) {
      debugPrint("Erreur lors de la sauvegarde des tâches de téléchargement : $e");
    }
  }

  // --- Public API ---

  /// Ajoute une nouvelle tâche de téléchargement à la liste et sauvegarde.
  Future<void> addTask(DownloadTask task) async {
    final currentTasks = List<DownloadTask>.from(tasksNotifier.value);
    // On vérifie si une tâche avec le même ID existe déjà pour éviter les doublons
    if (!currentTasks.any((t) => t.id == task.id)) {
      currentTasks.insert(0, task); // Ajoute au début de la liste
      tasksNotifier.value = currentTasks;
      await _saveTasksToDisk();
    }
  }

  /// Met à jour une tâche existante (par exemple, sa progression ou son statut).
  Future<void> updateTask(String taskId, {DownloadStatus? status, double? progress, int? totalSize}) async {
    // On récupère la référence directe à la liste actuelle.
    final tasks = tasksNotifier.value;
    final index = tasks.indexWhere((t) => t.id == taskId);

    if (index != -1) {
      // On met à jour l'objet tâche directement dans la liste.
      tasks[index] = tasks[index].copyWith(
        status: status,
        progress: progress,
        totalSize: totalSize, // Ajout du paramètre manquant
      );

      // LA LIGNE CLÉ :
      // On assigne une NOUVELLE liste (une copie) au notifier.
      // C'est ce qui déclenche la mise à jour de l'UI.
      tasksNotifier.value = List.from(tasks);

      // On sauvegarde l'état mis à jour.
      await _saveTasksToDisk();
    }
  }


  /// Supprime une tâche de la liste et sauvegarde.
  /// La suppression du fichier physique devra être gérée séparément.
  Future<void> removeTask(String taskId) async {
    final currentTasks = List<DownloadTask>.from(tasksNotifier.value);
    currentTasks.removeWhere((t) => t.id == taskId);
    tasksNotifier.value = currentTasks;
    await _saveTasksToDisk();
  }

  /// Retourne la liste actuelle des tâches.
  List<DownloadTask> getTasks() {
    return tasksNotifier.value;
  }
}
