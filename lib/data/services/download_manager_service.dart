import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:media_store_plus/media_store_plus.dart';
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
        debugPrint("❌ Erreur lors du chargement des tâches : $e");
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
      debugPrint("🔍 [DEBUG-PATH] Tâche '${task.displayName}' -> Chemin: ${task.finalPath}");
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
      debugPrint("❌ Erreur lors de la sauvegarde des tâches : $e");
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

  /// LANCE ET GÈRE UN TÉLÉCHARGEMENT AVEC REPRISE ROBUSTE (FLUX MANUEL)
  Future<void> startDownloadTask(DownloadTask task) async {
    // 0. Sécurité anti-doublon
    if (_cancelTokens.containsKey(task.id)) return;

    final dio = await NetworkUtils.buildDio(task.url);
    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;

    final tempFile = File(task.tempPath);

    // 1. Calcul de l'Offset (ce qu'on a déjà sur le disque)
    int resumedBytes = 0;
    if (await tempFile.exists()) {
      try {
        resumedBytes = await tempFile.length();
      } catch (e) {
        debugPrint("⚠️ Impossible de lire la taille du fichier partiel. Reprise à zéro. Erreur: $e");
        resumedBytes = 0;
      }
    }

    // Cas spécial de sécurité : Fichier déjà complet localement
    if (task.totalSize > 0 && resumedBytes >= task.totalSize) {
      debugPrint("✅ Fichier déjà complet dans le cache, finalisation via MediaStore...");
      // On appelle directement la fonction de déplacement
      final success = await _moveFileToMediaStore(
        tempPath: task.tempPath,
        finalPath: task.finalPath,
      );
      if (success) {
        await updateTask(task.id, status: DownloadStatus.completed, progress: 1.0);
      } else {
        await updateTask(task.id, status: DownloadStatus.failed);
      }
      _cancelTokens.remove(task.id);
      return;
    }

    // Utilisation d'un Completer pour gérer la fin du stream
    final completer = Completer<void>();

    try {
      await updateTask(task.id, status: DownloadStatus.downloading);
      debugPrint("🚀 Démarrage | Offset: $resumedBytes bytes | URL: ${task.url}");

      // 2. Requête en mode STREAM pour un contrôle total
      final response = await dio.get<ResponseBody>(
        task.url,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream, // TRÈS IMPORTANT: On reçoit un flux de données
          headers: {
            'range': 'bytes=$resumedBytes-', // Instruction de reprise explicite
          },
        ),
      );

      // 3. Écriture manuelle et sécurisée du flux dans le fichier
      // On ouvre le fichier en mode APPEND (ajout à la fin). C'est la clé pour éviter la corruption.
      final raf = await tempFile.open(mode: FileMode.append);
      int receivedThisSession = 0;

      // On détermine la taille totale du fichier en se basant sur la réponse du serveur.
      final contentLengthHeader = response.headers.value(Headers.contentLengthHeader);
      final segmentSize = int.tryParse(contentLengthHeader ?? '0') ?? 0;
      final definitiveTotal = segmentSize > 0 ? (resumedBytes + segmentSize) : task.totalSize;

      // Le `listen` s'abonne au flux de données. Il reçoit les données par segments (chunks).
      final streamSubscription = response.data!.stream.listen(
            (chunk) {
          // Écrit le segment reçu à la fin du fichier.
          raf.writeFromSync(chunk);
          receivedThisSession += chunk.length;

          final actualReceived = resumedBytes + receivedThisSession;
          if (definitiveTotal > 0) {
            final progress = (actualReceived / definitiveTotal).clamp(0.0, 1.0);
            updateTask(
              task.id,
              progress: progress,
              totalSize: definitiveTotal,
              status: DownloadStatus.downloading,
            );
          }
        },
        onDone: () async {
          // `onDone` est appelé quand le flux est terminé (téléchargement réussi)
          await raf.close(); // On ferme le fichier proprement
          debugPrint("✅ Téléchargement vers le cache terminé. Déplacement vers le stockage public...");
          await updateTask(task.id, status: DownloadStatus.finalizing);

          final bool success = await _moveFileToMediaStore(
            tempPath: task.tempPath,
            finalPath: task.finalPath,
          );

          if (success) {
            await updateTask(task.id, status: DownloadStatus.completed, progress: 1.0);
            debugPrint("💾 Fichier finalisé avec succès dans Movies : ${task.finalPath}");
          } else {
            debugPrint("❌ Erreur lors du déplacement du fichier vers MediaStore.");
            await updateTask(task.id, status: DownloadStatus.failed);
          }
          if (!completer.isCompleted) completer.complete();
        },
        onError: (e) async {
          // Gestion des erreurs pendant le streaming
          await raf.close();
          debugPrint("💀 Erreur de flux : $e");
          if (e is DioException && e.type == DioExceptionType.cancel) {
            debugPrint("🛑 Flux annulé par l'utilisateur : ${task.id}");
          } else {
            await updateTask(task.id, status: DownloadStatus.failed);
          }
          if (!completer.isCompleted) completer.completeError(e);
        },
        cancelOnError: true, // Stopper l'écoute en cas d'erreur
      );

      // Assurer que l'annulation externe arrête bien le stream
      cancelToken.whenCancel.then((_) {
        streamSubscription.cancel();
      });

      await completer.future; // Attend que le stream soit terminé (onDone ou onError)

    } on DioException catch (e) {
      if (e.response?.statusCode == 416) {
        debugPrint("⚠️ Erreur 416 (Range) -> Fichier considéré comme déjà complet. Forçage de la finalisation...");
        final success = await _moveFileToMediaStore(
          tempPath: task.tempPath,
          finalPath: task.finalPath,
        );
        if (success) {
          await updateTask(task.id, status: DownloadStatus.completed, progress: 1.0);
          debugPrint("💾 Fichier finalisé avec succès (via erreur 416).");
        } else {
          debugPrint("❌ Erreur lors du déplacement du fichier après une erreur 416.");
          await updateTask(task.id, status: DownloadStatus.failed);
        }
      } else if (e.type != DioExceptionType.cancel) {
        debugPrint("💀 Erreur Dio initiale: ${e.message}");
        await updateTask(task.id, status: DownloadStatus.failed);
      }
    } catch (e) {
      debugPrint("💀 Erreur Système non gérée : $e");
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
      _cancelTokens.remove(taskId); // Libération du token pour ne pas boucler lors d'un rechargement
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

/// Déplace un fichier du stockage privé vers le stockage public (Movies) via MediaStore.
/// Retourne `true` en cas de succès.
Future<bool> _moveFileToMediaStore({
  required String tempPath,
  required String finalPath,
}) async {
  final file = File(tempPath);
  if (!await file.exists()) {
    debugPrint("Erreur de déplacement : le fichier source n'existe pas à $tempPath");
    return false;
  }

  try {
    final mediaStore = MediaStore();

    // On appelle la fonction avec TOUS les paramètres requis par le plugin
    await mediaStore.saveFile(
      tempFilePath: tempPath,
      // On spécifie le type général (vidéo)
      dirType: DirType.video,
      // ET le dossier racine correspondant (Movies)
      dirName: DirName.movies,
      // Le sous-dossier dans lequel nous voulons enregistrer.
      // "AetherStream" est maintenant géré par MediaStore.appFolder défini dans main.dart
      // Le plugin va donc créer : /storage/emulated/0/Movies/AetherStream/
      relativePath: null, // Le plugin utilisera MediaStore.appFolder
    );

    return true;

  } catch (e) {
    debugPrint("💀 Erreur MediaStore lors de la sauvegarde du fichier: $e");
    // En cas d'échec, on garde le fichier temporaire pour un éventuel nouvel essai.
    return false;
  }
}
