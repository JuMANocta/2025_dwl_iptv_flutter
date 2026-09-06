import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/download_task.dart';
import 'download_stall_policy.dart';
import '../../core/settings/performance_settings_service.dart';
import '../../core/utils/network_kind.dart';
import '../../feature/downloads/logic/download_scheduler.dart';
import '../../core/utils/log_sanitizer.dart';
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

  // ── §dlProgress — Throttle de la progression ───────────────────────────────
  //
  // La progression arrivait à CHAQUE chunk reçu (8–64 Ko), et chaque appel
  // réécrivait TOUTE la liste des tâches en JSON dans SharedPreferences en plus
  // de notifier l'UI. Sur un film de 4 Go, cela représentait des dizaines de
  // milliers de sérialisations + écritures disque pendant tout le
  // téléchargement — une des causes du « ça consomme trop », indépendante de la
  // copie finale.
  //
  // On dissocie donc les deux cadences :
  //   - AFFICHAGE  : throttle TEMPOREL court (voir [progressNotifyInterval]) ;
  //   - PERSISTANCE : au plus une fois par seconde. Inutile d'être plus fin :
  //     au redémarrage la progression est de toute façon recalculée depuis la
  //     taille du fichier partiel (cf. `startDownloadTask`).
  //
  // ⚠️ La 1re version notifiait au changement de **pourcentage entier** (motif
  // repris de §bootStatus). Erreur d'analogie : le moniteur recalcule la
  // VITESSE et l'ETA à chaque notification, or sur un gros fichier 1 % peut
  // durer plusieurs secondes → les compteurs paraissaient figés. Un boot n'a
  // pas ce problème (il n'affiche qu'un pourcentage). D'où un throttle
  // temporel ici : la finesse doit suivre le RAFRAÎCHISSEMENT PERÇU, pas la
  // progression.
  final Map<String, int> _lastNotifiedPct = {};
  final Map<String, DateTime> _lastNotifiedAt = {};
  final Map<String, DateTime> _lastPersistedAt = {};
  static const Duration _progressPersistInterval = Duration(seconds: 1);

  /// Intervalle minimal entre deux notifications d'UI. ~4 rafraîchissements par
  /// seconde : la vitesse et l'ETA restent vivants, sans rebuilder à chaque
  /// chunk réseau (des dizaines de milliers par film).
  @visibleForTesting
  static Duration progressNotifyInterval = const Duration(milliseconds: 250);

  /// Garde-fou contre un `saveFile` qui ne répondrait JAMAIS : le plugin
  /// `media_store_plus` logue ses exceptions sans jamais compléter le `Result`
  /// (MediaStorePlusPlugin.kt), ce qui laissait la tâche figée en `finalizing`.
  static const Duration _finalizeTimeout = Duration(minutes: 30);

  /// Doit être appelé une seule fois au démarrage de l'application (dans main.dart).
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _loadTasksFromDisk();
    _reconcileTasksOnStartup();
    // §dlQueue — Les tâches restées « en attente » (jamais parties) repartent
    // d'elles-mêmes, dans l'ordre, sous les mêmes limites.
    // §dlWifi — Et un réglage qui change (Wi-Fi seulement, plafond) se
    // relit tout de suite : sinon décocher « Wi-Fi seulement » laisserait
    // la file retenue jusqu'au prochain sondage.
    PerformanceSettingsService.config.addListener(pump);
    pump();
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
      // §dlStuckFinalizing — `finalizing` DOIT être réinitialisé lui aussi :
      // il n'était pas traité ici, donc une finalisation interrompue (ou un
      // `saveFile` natif qui n'a jamais rendu la main) laissait la tâche figée
      // DÉFINITIVEMENT, y compris après relance de l'app.
      // §dlQueue — `queued` n'est plus « bloquée » : c'est une tâche qui
      // attend sa place et repartira (`pump()` après l'init). Seuls un
      // transfert ou une finalisation interrompus passent en échec.
      if (task.status == DownloadStatus.downloading ||
          task.status == DownloadStatus.finalizing) {
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

  /// Transferts réellement en vol, pour pouvoir attendre leur fin (§dlErgo).
  final Map<String, Future<void>> _inFlight = {};

  /// §dlQueue — Met la tâche EN ATTENTE et laisse la file décider quand elle
  /// part : un transfert à la fois par abonnement, `maxParallelDownloads` en
  /// tout. C'est le point d'entrée normal (nouvelle tâche, reprise d'un échec) ;
  /// `startDownloadTask` reste le chemin DIRECT, pour une relance qui garde sa
  /// place (§dlErgo) ou pour la file elle-même.
  Future<void> enqueue(DownloadTask task) async {
    if (_inFlight.containsKey(task.id)) return;
    if (task.status != DownloadStatus.queued) {
      await updateTask(task.id, status: DownloadStatus.queued);
    }
    pump();
  }

  /// §dlWifi — Pourquoi la file est retenue (`wifi` : réseau facturé et
  /// réglage « Wi-Fi seulement » ; `offline` : aucun réseau), ou `null`. Lu
  /// par la tuile et le moniteur pour dire POURQUOI ça attend.
  final ValueNotifier<DownloadHold?> hold = ValueNotifier<DownloadHold?>(null);

  /// §dlWifi — Tant que des tâches attendent le réseau, on re-regarde toutes
  /// les 20 s ; dès qu'il revient, elles partent. Pas d'abonnement natif :
  /// un sondage court, seulement quand il y a quelque chose à attendre.
  Timer? _holdPoll;
  static const Duration _holdPollEvery = Duration(seconds: 20);

  bool _pumping = false;
  bool _pumpAgain = false;

  /// §dlQueue — Fait partir tout ce qui peut partir. Appelée après chaque mise
  /// en attente, après chaque fin de transfert (succès, échec, annulation) et
  /// par le sondage réseau. Sérialisée : deux appels qui se chevauchent ne
  /// feraient partir une tâche qu'une fois (`_inFlight` est vérifié par
  /// `startDownloadTask`), mais autant ne pas sonder le réseau deux fois.
  Future<void> pump() async {
    if (_pumping) {
      _pumpAgain = true;
      return;
    }
    _pumping = true;
    try {
      do {
        _pumpAgain = false;
        await _pumpOnce();
      } while (_pumpAgain);
    } finally {
      _pumping = false;
    }
  }

  Future<void> _pumpOnce() async {
    final bool anyQueued =
        tasksNotifier.value.any((t) => t.status == DownloadStatus.queued);
    if (!anyQueued) {
      _setHold(null);
      return;
    }
    // §dlWifi — Le réseau n'est regardé que s'il y a quelque chose à faire
    // partir : un appel natif de moins par fin de transfert.
    final perf = PerformanceSettingsService.config.value;
    final NetState net = await currentNetState();
    final DownloadHold? h = downloadHoldFor(
      wifiOnly: perf.downloadsWifiOnly,
      kind: net.kind,
      metered: net.metered,
    );
    _setHold(h);
    if (h != null) {
      debugPrint('📥 §dlWifi — file retenue (${h.name}) : réseau ${net.kind.name}'
          '${net.metered ? ' facturé' : ''}');
      return;
    }
    final picks = pickStartable(
      tasks: tasksNotifier.value,
      inFlightIds: _inFlight.keys.toSet(),
      maxParallel: perf.maxParallelDownloads,
    );
    for (final DownloadTask t in picks) {
      debugPrint('📥 §dlQueue — départ : ${t.displayName}');
      startDownloadTask(t);
    }
  }

  void _setHold(DownloadHold? h) {
    if (hold.value != h) hold.value = h;
    if (h == null) {
      _holdPoll?.cancel();
      _holdPoll = null;
    } else {
      _holdPoll ??= Timer.periodic(_holdPollEvery, (_) => pump());
    }
  }

  /// LANCE ET GÈRE UN TÉLÉCHARGEMENT AVEC REPRISE ROBUSTE (FLUX MANUEL)
  Future<void> startDownloadTask(DownloadTask task) {
    // 0. Sécurité anti-doublon
    if (_cancelTokens.containsKey(task.id)) return Future.value();
    final run = _runDownload(task);
    _inFlight[task.id] = run;
    run.whenComplete(() {
      if (identical(_inFlight[task.id], run)) _inFlight.remove(task.id);
      // §dlQueue — une place se libère : au suivant. Après le retrait, sinon
      // la tâche qui vient de finir compterait encore comme en vol.
      pump();
    });
    return run;
  }

  /// §dlErgo — **Relance** : coupe le transfert en cours puis le reprend au
  /// même octet (`Range`). L'usage visé est de rétablir une connexion dont le
  /// débit s'est effondré (bridage fournisseur) — reconnecter repart souvent à
  /// pleine vitesse.
  ///
  /// ⚠️ On attend la fin RÉELLE du flux précédent avant de relancer : son
  /// `RandomAccessFile` (ouvert en `append`) doit être refermé, sinon deux
  /// handles écrivent en parallèle dans le même fichier partiel — corruption
  /// silencieuse, et une taille lue trop courte fausserait la reprise.
  Future<void> restartTask(DownloadTask task) async {
    // §dlWatchdog — Le compteur est incrémenté AVANT l'annulation, pas après :
    // `cancelTask` publie `canceled`, et c'est à cet instant que le moniteur
    // décide quoi écrire. Bumpé après, il affichait « ABORT : annulé par
    // l'utilisateur » — alors que l'utilisateur venait de demander l'inverse.
    final bumped = _bumpRetryCount(task.id) ?? task;

    final previous = _inFlight[task.id];
    if (previous != null) {
      await cancelTask(task.id);
      try {
        // Garde-fou : quoi qu'il arrive côté flux, la relance doit partir.
        // Mieux vaut relancer avec un handle peut-être encore ouvert que de
        // laisser l'utilisateur devant un bouton qui ne fait rien.
        await previous.timeout(const Duration(seconds: 8));
      } catch (_) {
        // Annulation (DioException) ou timeout : sans intérêt ici.
      }
    }
    // La tâche vient de passer en `canceled` : on repart d'un état propre.
    _cancelTokens.remove(task.id);
    if (previous != null) {
      // Un transfert qui TOURNAIT garde sa place : il repart tout de suite.
      await startDownloadTask(bumped);
      return;
    }
    // §dlQueue — Rien n'était en vol (échec, annulation) : la relance passe
    // par la file, sinon « Appuyer pour relancer » ouvrait une seconde
    // connexion sur le même abonnement (constaté : deux transferts VOD en
    // parallèle malgré la règle).
    await enqueue(bumped);
  }

  Future<void> _runDownload(DownloadTask task) async {

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
      final success = await _finalizeDownload(
        tempPath: task.tempPath,
        finalPath: task.finalPath,
        expectedSize: task.totalSize,
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
      debugPrint("🚀 Démarrage | Offset: $resumedBytes bytes | URL: ${redactUrl(task.url)}");

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
      // §dlTmpDir (2026-09-06) — Le dossier du fichier partiel peut avoir
      // DISPARU entre la création de la tâche et son départ : le cache
      // externe (`Android/data/<pkg>/cache`) est vidé à une mise à jour de
      // l'app, et Android peut le vider sous pression de stockage. Constaté
      // sur l'émulateur : une tâche en attente relancée au démarrage
      // (§dlQueue) échouait en `PathNotFoundException`. On recrée le dossier ;
      // le transfert repart alors de zéro (l'offset lu plus haut est 0).
      await tempFile.parent.create(recursive: true);
      final raf = await tempFile.open(mode: FileMode.append);
      int receivedThisSession = 0;

      // §dlRestartFix — Fermeture IDEMPOTENTE du handle. Trois chemins peuvent
      // y mener (fin normale, erreur, annulation) et `close()` deux fois lève.
      var rafClosed = false;
      Future<void> closeRaf() async {
        if (rafClosed) return;
        rafClosed = true;
        try {
          await raf.close();
        } catch (_) {
          // handle déjà invalide : sans conséquence ici
        }
      }

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
            // §dlProgress — Chemin THROTTLÉ (voir `_lastNotifiedPct`) : appeler
            // `updateTask` ici réécrivait toute la liste sur disque à chaque
            // chunk.
            reportProgress(
              task.id,
              progress: progress,
              totalSize: definitiveTotal,
            );
          }
        },
        onDone: () async {
          // `onDone` est appelé quand le flux est terminé (téléchargement réussi)
          await closeRaf(); // On ferme le fichier proprement
          debugPrint("✅ Téléchargement vers le cache terminé. Déplacement vers le stockage public...");
          await updateTask(task.id, status: DownloadStatus.finalizing);

          final bool success = await _finalizeDownload(
            tempPath: task.tempPath,
            finalPath: task.finalPath,
            expectedSize: definitiveTotal,
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
          await closeRaf();
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

      // §dlRestartFix — Assurer que l'annulation externe arrête bien le stream,
      // ET libère la tâche.
      //
      // ⚠️ Annuler un `StreamSubscription` ne déclenche **ni `onDone` ni
      // `onError`** : sans le `complete()` ci-dessous, le `Completer` n'était
      // jamais complété, donc `await completer.future` restait suspendu à vie.
      // Le handle de fichier n'était pas refermé non plus — deux transferts
      // successifs pouvaient alors écrire en parallèle dans le même `.part`.
      // Invisible tant que personne n'attendait la fin ; « Relancer » (qui
      // attend, justement) ne repartait donc jamais.
      cancelToken.whenCancel.then((_) async {
        await streamSubscription.cancel();
        await closeRaf();
        if (!completer.isCompleted) completer.complete();
      });

      await completer.future; // Attend que le stream soit terminé (onDone ou onError)

    } on DioException catch (e) {
      if (e.response?.statusCode == 416) {
        debugPrint("⚠️ Erreur 416 (Range) -> Fichier considéré comme déjà complet. Forçage de la finalisation...");
        final success = await _finalizeDownload(
          tempPath: task.tempPath,
          finalPath: task.finalPath,
          expectedSize: task.totalSize,
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
        await updateTask(task.id, status: DownloadStatus.failed, errorMessage: e.message);
      }
    } catch (e) {
      debugPrint("💀 Erreur Système non gérée : $e");
      await updateTask(task.id, status: DownloadStatus.failed, errorMessage: e.toString());
    } finally {
      _cancelTokens.remove(task.id);
      _clearProgressThrottle(task.id);
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

  /// §dlProgress — Met à jour la PROGRESSION (chemin chaud, appelé à chaque
  /// chunk réseau). Notifie l'UI au changement de pourcentage entier et ne
  /// persiste qu'au plus une fois par seconde.
  ///
  /// À ne PAS utiliser pour les transitions d'état : celles-ci passent par
  /// [updateTask], qui persiste immédiatement.
  @visibleForTesting
  void reportProgress(
    String taskId, {
    required double progress,
    required int totalSize,
  }) {
    final clamped = progress.clamp(0.0, 1.0);
    final now = DateTime.now();

    if (clamped >= 1.0) {
      // La complétion est TOUJOURS publiée, mais une seule fois : sans ce
      // traitement à part, un throttle temporel pouvait avaler le dernier
      // chunk et laisser la barre figée à 99,x %.
      if (_lastNotifiedPct[taskId] == 101) return;
      _lastNotifiedPct[taskId] = 101;
    } else {
      final lastAt = _lastNotifiedAt[taskId];
      if (lastAt != null && now.difference(lastAt) < progressNotifyInterval) {
        return;
      }
    }
    _lastNotifiedAt[taskId] = now;
    // §dlWatchdog — Mesure du débit côté SERVICE (cf. `_traceThroughput`).
    _traceThroughput(taskId, (clamped * totalSize).round());

    final currentTasks = List<DownloadTask>.from(tasksNotifier.value);
    final index = currentTasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;
    currentTasks[index] = currentTasks[index].copyWith(
      progress: clamped,
      totalSize: totalSize,
      status: DownloadStatus.downloading,
    );
    tasksNotifier.value = currentTasks;

    final last = _lastPersistedAt[taskId];
    if (last == null || now.difference(last) >= _progressPersistInterval) {
      _lastPersistedAt[taskId] = now;
      _saveTasksToDisk(); // fire & forget : l'UI est déjà à jour
    }
  }


  /// §dlWatchdog — Incrémente le nombre de relances d'une tâche et renvoie la
  /// version à jour. `null` si la tâche n'existe plus.
  DownloadTask? _bumpRetryCount(String taskId) {
    final tasks = List<DownloadTask>.from(tasksNotifier.value);
    final i = tasks.indexWhere((t) => t.id == taskId);
    if (i == -1) return null;
    final updated = tasks[i].copyWith(retryCount: tasks[i].retryCount + 1);
    tasks[i] = updated;
    tasksNotifier.value = tasks;
    _saveTasksToDisk(); // fire & forget
    debugPrint('🔁 §dlWatchdog — « ${updated.displayName} » relancée '
        '(${updated.retryCount}× au total)');
    return updated;
  }

  /// §dlWatchdog — Débit moyen observé, par tâche, en octets/seconde.
  ///
  /// **Pourquoi dans le SERVICE et pas dans le dialogue.** `_speed` et `_eta`
  /// vivent aujourd'hui dans `TerminalDownloadDialog`, donc ils disparaissent
  /// dès qu'on ferme le dialogue — alors que le transfert continue. Une
  /// détection de bridage ne peut pas s'appuyer là-dessus.
  ///
  /// ⚠️ **Instrument, pas encore correctif.** La roadmap (§dlWatchdog, volet A)
  /// impose de CONFIRMER l'hypothèse avant de coder la relance automatique :
  /// le serveur bride-t-il vraiment (débit qui décroît), ou coupe-t-il la
  /// connexion (autre correctif) ? Ce journal donne la réponse ; la relance
  /// automatique viendra après, sur des faits.
  final Map<String, ({DateTime at, int bytes, double? peak})> _throughput = {};

  void _traceThroughput(String taskId, int received) {
    final now = DateTime.now();
    final prev = _throughput[taskId];
    if (prev == null) {
      _throughput[taskId] = (at: now, bytes: received, peak: null);
      return;
    }
    final elapsed = now.difference(prev.at);
    // Fenêtre de 5 s : assez longue pour lisser les à-coups d'un flux HTTP,
    // assez courte pour voir un décrochage avant qu'il ne dure des minutes.
    if (elapsed.inMilliseconds < 5000) return;
    final delta = received - prev.bytes;
    final speed = delta / (elapsed.inMilliseconds / 1000);
    final peak = (prev.peak == null || speed > prev.peak!) ? speed : prev.peak!;
    _throughput[taskId] = (at: now, bytes: received, peak: peak);

    // On ne journalise QUE le décrochage : un débit stable n'apprend rien et
    // noierait le journal sur un transfert de plusieurs Go.
    if (isStalled(speed: speed, peak: prev.peak)) {
      debugPrint('🐌 §dlWatchdog — décrochage : '
          '${(speed / 1024).round()} ko/s contre ${(peak / 1024).round()} ko/s '
          'au mieux (tâche $taskId)');
      _maybeAutoRestart(taskId, received, now);
    }
  }

  final Map<String, DateTime> _lastAutoRestart = {};
  final Map<String, int> _bytesAtLastAutoRestart = {};

  /// §dlWatchdog — Relance automatiquement un transfert qui décroche.
  ///
  /// C'est ce qui rend le bouton « Relancer » inutile : l'utilisateur n'a plus
  /// à surveiller son débit pour appuyer au bon moment. La relance est
  /// SILENCIEUSE (même barre de progression, reprise `Range` au même octet) ;
  /// son seul témoin est le compteur « relancé ×N ».
  void _maybeAutoRestart(String taskId, int received, DateTime now) {
    final last = _lastAutoRestart[taskId];
    final before = _bytesAtLastAutoRestart[taskId];
    if (!shouldAutoRestart(
      sinceLastRestart: last == null ? null : now.difference(last),
      gainSinceLastRestart: before == null ? null : received - before,
    )) {
      return;
    }

    final tasks = tasksNotifier.value;
    final i = tasks.indexWhere((t) => t.id == taskId);
    if (i == -1 || tasks[i].status != DownloadStatus.downloading) return;

    _lastAutoRestart[taskId] = now;
    _bytesAtLastAutoRestart[taskId] = received;
    // Le plafond repart de zéro : la nouvelle connexion a le sien, et comparer
    // son débit à celui de la précédente relancerait en boucle.
    _throughput[taskId] = (at: now, bytes: received, peak: null);

    debugPrint('♻️ §dlWatchdog — relance automatique de '
        '« ${tasks[i].displayName} »');
    restartTask(tasks[i]); // fire & forget : la progression reprend seule
  }

  /// Remet à zéro les compteurs de throttle d'une tâche. Le service étant un
  /// SINGLETON, son état statique survit d'un test à l'autre : à appeler en
  /// `setUp` sous peine de faux échecs.
  @visibleForTesting
  void resetProgressThrottle(String taskId) => _clearProgressThrottle(taskId);

  /// Libère les compteurs de throttle d'une tâche terminée/supprimée.
  void _clearProgressThrottle(String taskId) {
    _lastNotifiedPct.remove(taskId);
    _lastNotifiedAt.remove(taskId);
    _lastPersistedAt.remove(taskId);
    _throughput.remove(taskId); // §dlWatchdog
    _lastAutoRestart.remove(taskId);
    _bytesAtLastAutoRestart.remove(taskId);
  }

  /// Met à jour une tâche existante et notifie l'UI.
  Future<void> updateTask(String taskId, {DownloadStatus? status, double? progress, int? totalSize, String? errorMessage}) async {
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
        errorMessage: errorMessage,
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
    _clearProgressThrottle(taskId);
    final currentTasks = List<DownloadTask>.from(tasksNotifier.value);
    currentTasks.removeWhere((t) => t.id == taskId);
    tasksNotifier.value = currentTasks;
    await _saveTasksToDisk();
  }
}

/// §dlDirectWrite — Amène le fichier partiel à sa destination finale.
///
/// **Cas nominal** : le fichier a été téléchargé DIRECTEMENT dans le dossier de
/// destination (cf. `_resolvePartPath`), donc sur le même volume → un simple
/// `rename()`, purement métadonnées et instantané.
///
/// Auparavant, ce passage recopiait intégralement le fichier via
/// `media_store_plus.saveFile`, dont le handler natif s'exécute **sur le thread
/// principal Android** avec un buffer de 8 Ko : sur plusieurs Go, l'UI était
/// gelée le temps de centaines de milliers d'itérations → ANR, l'OS tuait
/// l'app. La copie exigeait en plus un pic d'espace disque de 2× la taille du
/// film.
///
/// **Repli** : quand le partiel est resté dans le cache privé (dossier public
/// non inscriptible), on repasse par MediaStore — sous timeout, car le plugin
/// peut ne jamais compléter son `Result`.
///
/// [expectedSize] `> 0` → refuse un fichier **tronqué**. Volontairement
/// asymétrique : on ne rejette que `taille < attendue`. Une taille supérieure
/// ou une valeur attendue imprécise (serveur sans `content-length` fiable, ou
/// taille simplement sondée à la création de la tâche) ne doit PAS faire passer
/// en échec un téléchargement complet. Le repli MediaStore, lui, n'est pas
/// vérifiable ainsi : il peut renommer le fichier en cas de doublon.
Future<bool> _finalizeDownload({
  required String tempPath,
  required String finalPath,
  int expectedSize = 0,
}) async {
  final file = File(tempPath);
  if (!await file.exists()) {
    debugPrint("Erreur de finalisation : le fichier source n'existe pas à $tempPath");
    return false;
  }

  // Le partiel est-il déjà dans le dossier de destination ? On le déduit des
  // dossiers parents plutôt que d'un champ du modèle : les tâches DÉJÀ
  // persistées (partiel en cache) prennent ainsi automatiquement le repli,
  // sans migration.
  if (file.parent.path == File(finalPath).parent.path) {
    try {
      final renamed = await file.rename(finalPath);
      final size = await renamed.length();
      if (expectedSize > 0 && size < expectedSize) {
        debugPrint("⚠️ Fichier tronqué : $size / $expectedSize octets");
        return false;
      }
      debugPrint("⚡ Finalisation instantanée (rename) — $finalPath");
      return true;
    } catch (e) {
      debugPrint("⚠️ Rename impossible ($e) → repli MediaStore");
    }
  }

  return _copyToMediaStore(tempPath);
}

/// Repli historique : copie du cache privé vers le stockage public via
/// MediaStore. Retourne `true` en cas de succès.
Future<bool> _copyToMediaStore(String tempPath) async {
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
    ).timeout(
      DownloadManagerService._finalizeTimeout,
      // §dlStuckFinalizing — Sans ce garde-fou, une exception côté plugin
      // (qui ne complète alors NI success NI error) laissait le `await`
      // suspendu à vie et la tâche figée en `finalizing`.
      onTimeout: () => throw TimeoutException(
          'MediaStore n\'a pas répondu', DownloadManagerService._finalizeTimeout),
    );

    return true;

  } catch (e) {
    debugPrint("💀 Erreur MediaStore lors de la sauvegarde du fichier: $e");
    // En cas d'échec, on garde le fichier temporaire pour un éventuel nouvel essai.
    return false;
  }
}
