import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/download_task.dart';
import '../../core/utils/network.dart';

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

  // On garde une trace des CancelToken pour pouvoir annuler les tâches.
  final Map<String, CancelToken> _cancelTokens = {};

  /// Doit être appelé une seule fois au démarrage de l'application (dans main.dart).
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _loadTasksFromDisk();
    _reconcileTasksOnStartup();
  }

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

  /// Au démarrage, réinitialise les tâches qui étaient "en cours" car elles ne peuvent pas survivre à un redémarrage.
  void _reconcileTasksOnStartup() {
    final tasks = List<DownloadTask>.from(tasksNotifier.value);
    bool hasChanged = false;

    // On crée une nouvelle liste avec les statuts mis à jour
    final reconciledTasks = tasks.map((task) {
      if (task.status == DownloadStatus.downloading || task.status == DownloadStatus.queued) {
        hasChanged = true;
        // On considère la tâche comme échouée pour permettre à l'utilisateur de la relancer.
        // On ne modifie pas la progression pour qu'il voie où ça s'est arrêté.
        return task.copyWith(status: DownloadStatus.failed);
      }
      return task;
    }).toList();

    if (hasChanged) {
      debugPrint("🧹 Nettoyage de ${reconciledTasks.where((t) => t.status == DownloadStatus.failed).length} tâches bloquées au démarrage.");
      tasksNotifier.value = reconciledTasks;
      _saveTasksToDisk(); // On sauvegarde immédiatement le nouvel état propre.
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

  /// Ajoute une nouvelle tâche à la liste.
  Future<void> addTask(DownloadTask task) async {
    final currentTasks = List<DownloadTask>.from(tasksNotifier.value);
    if (!currentTasks.any((t) => t.id == task.id)) {
      currentTasks.insert(0, task);
      tasksNotifier.value = currentTasks;
      await _saveTasksToDisk();
    }
  }

  /// LANCE ET GÈRE UN TÉLÉCHARGEMENT EN ARRIÈRE-PLAN
  Future<void> startDownloadTask(DownloadTask task) async {
    // 0. Vérification si déjà actif
    if (_cancelTokens.containsKey(task.id)) return;

    final dio = await NetworkUtils.buildDio(task.url);
    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;

    final tempPath = '${task.finalPath}.downloading';
    final tempFile = File(tempPath);

    // 1. On détermine la quantité de données déjà téléchargées (Offset)
    int resumedBytes = 0;
    if (await tempFile.exists()) {
      resumedBytes = await tempFile.length();
    }

    // Cas spécial : si le fichier est déjà complet mais n'a pas été renommé
    if (task.totalSize > 0 && resumedBytes >= task.totalSize) {
      debugPrint("✅ Fichier déjà complet sur le disque, finalisation immédiate: ${task.id}");
      await File(tempPath).rename(task.finalPath);
      await updateTask(task.id, status: DownloadStatus.completed, progress: 1.0);
      return;
    }

    try {
      await updateTask(task.id, status: DownloadStatus.downloading);

      debugPrint("🚀 Démarrage download | Offset: $resumedBytes bytes | URL: ${task.url}");

      // 2. LE CŒUR DU FIX : On force l'en-tête 'Range' manuellement
      await dio.download(
        task.url,
        tempPath,
        cancelToken: cancelToken,
        // CRITIQUE : Empêche Dio de supprimer le fichier partiel en cas d'erreur/cancel
        deleteOnError: false,
        options: Options(
          headers: {
            // On dit explicitement au serveur : "Donne-moi la suite à partir de là"
            'range': 'bytes=$resumedBytes-',
          },
        ),
        onReceiveProgress: (received, total) {
          final currentTask = tasksNotifier.value.firstWhere(
                  (t) => t.id == task.id,
              orElse: () => DownloadTask.empty()
          );

          if (currentTask.status == DownloadStatus.canceled) return;

          // 3. Calcul de progression hybride
          // received = octets de CETTE session
          // resumedBytes = octets DÉJÀ présents
          if (task.totalSize > 0) {
            final totalProgress = (resumedBytes + received) / task.totalSize;

            updateTask(
              task.id,
              progress: totalProgress.clamp(0.0, 1.0),
              status: DownloadStatus.downloading,
            );
          }
        },
      );

      // 4. Succès : Renommage final
      if (await File(tempPath).exists()) {
        await File(tempPath).rename(task.finalPath);
        await updateTask(task.id, status: DownloadStatus.completed, progress: 1.0);
        debugPrint("💾 Fichier sauvegardé : ${task.finalPath}");
      }

    } on DioException catch (e) {
      // Gestion erreur 416 (Range Not Satisfiable) -> Fichier déjà fini en réalité
      if (e.response?.statusCode == 416) {
        debugPrint("⚠️ Range 416: Le serveur dit que le fichier est déjà complet.");
        if (await File(tempPath).exists()) {
          await File(tempPath).rename(task.finalPath);
          await updateTask(task.id, status: DownloadStatus.completed, progress: 1.0);
        }
      }
      else if (e.type == DioExceptionType.cancel) {
        debugPrint("🛑 Téléchargement ${task.id} annulé par l'utilisateur.");
        // On laisse le statut en 'paused' ou 'canceled' selon ta logique updateTask
      }
      else {
        debugPrint("💀 Erreur Dio: ${e.message}");
        await updateTask(task.id, status: DownloadStatus.failed);
      }
    } catch (e) {
      debugPrint("💀 Erreur Générale: $e");
      await updateTask(task.id, status: DownloadStatus.failed);
    } finally {
      _cancelTokens.remove(task.id);
    }
  }

  /// Annule un téléchargement en cours.
  Future<void> cancelTask(String taskId) async {
    // On annule le token Dio s'il existe, pour stopper le processus réseau.
    if (_cancelTokens.containsKey(taskId)) {
      _cancelTokens[taskId]?.cancel();
      // Le `finally` dans `startDownloadTask` s'occupera de retirer le token.
    }
    // On met à jour l'état IMMÉDIATEMENT et EXPLICITEMENT.
    // Cela garantit que l'UI est notifiée, quoi qu'il arrive.
    await updateTask(taskId, status: DownloadStatus.canceled);
  }

  /// Met à jour une tâche existante et notifie l'UI.
  Future<void> updateTask(String taskId, {DownloadStatus? status, double? progress, int? totalSize}) async {
    // 1. On crée une NOUVELLE liste (une copie) IMMÉDIATEMENT.
    final currentTasks = List<DownloadTask>.from(tasksNotifier.value);
    final index = currentTasks.indexWhere((t) => t.id == taskId);

    if (index != -1) {
      // 2. On récupère l'ancienne tâche pour la mettre à jour.
      final oldTask = currentTasks[index];

      // 3. On remplace l'élément dans NOTRE COPIE avec la version mise à jour.
      currentTasks[index] = oldTask.copyWith(
        status: status,
        progress: progress,
        totalSize: totalSize,
      );

      // 4. On assigne notre copie modifiée au notifier.
      // L'UI est maintenant garantie de se mettre à jour.
      tasksNotifier.value = currentTasks;
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
