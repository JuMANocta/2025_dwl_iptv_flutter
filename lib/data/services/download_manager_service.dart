import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:media_store_plus/media_store_plus.dart';
import '../models/download_task.dart';
import 'download_stall_policy.dart';
import 'download_retry_policy.dart';
import 'download_range_policy.dart';
import '../../core/utils/user_error.dart';
import '../../feature/downloads/logic/download_naming.dart';
import '../../core/settings/performance_settings_service.dart';
import '../../core/utils/network_kind.dart';
import '../../feature/downloads/logic/download_scheduler.dart';
import '../../core/utils/log_sanitizer.dart';
import '../../core/utils/network.dart';
import '../../core/platform/storage_service.dart';
import 'network_status_service.dart';

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

  /// Entrées de la liste persistée qu'on n'a pas su relire, mises de côté
  /// plutôt qu'écrasées par la prochaine sauvegarde (D3A-14).
  static const _unreadableKey = 'download_tasks_unreadable';

  /// `true` une fois l'écouteur des réglages posé : [init] peut être rejoué
  /// sans l'empiler (D3A-05).
  bool _listening = false;

  /// Au démarrage de l'application (dans main.dart). Rejouable sans risque :
  /// les transferts EN VOL ne sont ni relus depuis le disque ni réconciliés.
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _loadTasksFromDisk();
    _reconcileTasksOnStartup();
    // §dlQueue — Les tâches restées « en attente » (jamais parties) repartent
    // d'elles-mêmes, dans l'ordre, sous les mêmes limites.
    // §dlWifi — Et un réglage qui change (Wi-Fi seulement, plafond) se
    // relit tout de suite : sinon décocher « Wi-Fi seulement » laisserait
    // la file retenue jusqu'au prochain sondage.
    if (!_listening) {
      _listening = true;
      PerformanceSettingsService.config.addListener(pump);
    }
    pump();
  }

  /// Relit la liste depuis le disque (tirer pour rafraîchir).
  ///
  /// ⚠️ Revue 2026-09-11 (D3A-05) : la page appelait [init], qui basculait
  /// TOUTE tâche `downloading`/`finalizing` en échec — y compris celles en
  /// cours — d'où une fausse notification d'échec et le service de premier
  /// plan coupé sur un simple geste. Les tâches en vol gardent désormais leur
  /// état en mémoire.
  Future<void> refreshFromDisk() => init();

  void _loadTasksFromDisk() {
    final jsonString = _prefs.getString(_storageKey);
    if (jsonString == null) return;
    final List<dynamic> jsonList;
    try {
      jsonList = jsonDecode(jsonString) as List<dynamic>;
    } catch (e) {
      // Illisible en bloc : on le met de côté et on garde la mémoire. Avant,
      // la liste repartait vide et la sauvegarde suivante effaçait tout.
      debugPrint("❌ Liste des téléchargements illisible, mise de côté : $e");
      _prefs.setString(_unreadableKey, jsonString);
      return;
    }
    // Un transfert en vol : sa version en mémoire est la vérité.
    final Map<String, DownloadTask> inFlight = {
      for (final t in tasksNotifier.value)
        if (_inFlight.containsKey(t.id)) t.id: t,
    };
    final loaded = <DownloadTask>[];
    final unreadable = <dynamic>[];
    for (final json in jsonList) {
      try {
        final t = DownloadTask.fromJson(json as Map<String, dynamic>);
        loaded.add(inFlight.remove(t.id) ?? t);
      } catch (e) {
        // D3A-14 — Une entrée illisible ne fait plus disparaître les autres.
        debugPrint("⚠️ Tâche de téléchargement illisible, mise de côté : $e");
        unreadable.add(json);
      }
    }
    loaded.insertAll(0, inFlight.values);
    if (unreadable.isNotEmpty) {
      _prefs.setString(_unreadableKey, jsonEncode(unreadable));
    }
    tasksNotifier.value = loaded;
  }

  /// Au démarrage, réinitialise les tâches qui étaient "en cours" car elles ne peuvent pas survivre à un redémarrage.
  void _reconcileTasksOnStartup() {
    final tasks = List<DownloadTask>.from(tasksNotifier.value);
    bool hasChanged = false;

    // On crée une nouvelle liste avec les statuts mis à jour
    final reconciledTasks = tasks.map((task) {
      if (kDebugMode) {
        debugPrint("🔍 [DEBUG-PATH] Tâche '${task.displayName}' -> Chemin: ${task.finalPath}");
      }
      // D3A-05 — Un transfert réellement en vol n'est pas « interrompu ».
      if (_inFlight.containsKey(task.id)) return task;
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
    // D3A-17 — Reprendre à la main un échec ou une annulation rend son crédit
    // de remises en file réseau : sinon la première micro-coupure suivante
    // tombait directement en échec. (§dlLoop : l'historique des relances
    // AUTOMATIQUES, lui, n'est pas touché.)
    final DownloadStatus current = tasksNotifier.value
        .firstWhere((t) => t.id == task.id, orElse: () => task)
        .status;
    if (current == DownloadStatus.failed || current == DownloadStatus.canceled) {
      _networkRequeues.remove(task.id);
    }
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
    final NetState net = await currentNetState();
    // D3L-01 — Les réglages sont lus APRÈS l'attente : lus avant, un réglage
    // chargé pendant ce temps (démarrage) n'était pas vu et « Wi-Fi seulement »
    // était ignoré pour les tâches qui partaient à ce tour.
    final perf = PerformanceSettingsService.config.value;
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
    // D3A-06 — Le jeton est posé ICI, de façon synchrone. Posé après
    // l'`await buildDio` de `_runDownload`, une annulation ou une suppression
    // arrivée pendant cette attente ne trouvait aucun jeton : le transfert
    // partait quand même, jusqu'au renommage du film sans tâche associée.
    final CancelToken token = CancelToken();
    _cancelTokens[task.id] = token;
    final run = _runDownload(task, token);
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
  Future<void> restartTask(DownloadTask task) {
    // D3A-06 — Une relance à la fois par tâche : relance manuelle et relance
    // automatique simultanées ouvraient deux flux `append` sur le même partiel.
    final Future<void>? pending = _restarting[task.id];
    if (pending != null) return pending;
    late final Future<void> f;
    f = _restartTaskImpl(task).whenComplete(() {
      if (identical(_restarting[task.id], f)) _restarting.remove(task.id);
    });
    _restarting[task.id] = f;
    return f;
  }

  final Map<String, Future<void>> _restarting = {};

  Future<void> _restartTaskImpl(DownloadTask task) async {
    // §dlWatchdog — Le compteur est incrémenté AVANT l'annulation, pas après :
    // `cancelTask` publie `canceled`, et c'est à cet instant que le moniteur
    // décide quoi écrire. Bumpé après, il affichait « ABORT : annulé par
    // l'utilisateur » — alors que l'utilisateur venait de demander l'inverse.
    // Une finalisation ne se relance pas : le partiel est en train de devenir
    // le fichier final, repartir referait le film depuis zéro.
    final DownloadStatus? now = tasksNotifier.value
        .where((t) => t.id == task.id)
        .map((t) => t.status)
        .firstOrNull;
    if (now == DownloadStatus.finalizing || now == DownloadStatus.completed) {
      debugPrint('↩️ Relance ignorée : « ${task.displayName} » est ${now!.name}');
      return;
    }

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

  Future<void> _runDownload(DownloadTask task, CancelToken cancelToken) async {
    // Le jeton n'est rendu que s'il est encore le NÔTRE : après une relance
    // dont l'attente a expiré (8 s), le transfert suivant a déjà posé le sien,
    // et l'effacer rouvrirait la porte aux doublons.
    void releaseToken() {
      if (identical(_cancelTokens[task.id], cancelToken)) {
        _cancelTokens.remove(task.id);
      }
    }

    final Dio dio;
    try {
      dio = await NetworkUtils.buildDio(task.url);
    } catch (e) {
      releaseToken();
      if (!cancelToken.isCancelled) await _failOrRequeue(task.id, e);
      return;
    }
    // D3A-06 — Annulée ou supprimée pendant l'attente : on ne touche à rien.
    if (cancelToken.isCancelled ||
        !tasksNotifier.value.any((t) => t.id == task.id)) {
      debugPrint('🛑 Départ abandonné (annulé pendant la préparation) : ${task.id}');
      releaseToken();
      return;
    }

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
      // D3A-07 — `finalizing` affiché ici aussi : sinon la tâche restait
      // `queued` pendant la copie et « Annuler » restait proposé.
      await updateTask(task.id, status: DownloadStatus.finalizing);
      // On appelle directement la fonction de déplacement
      final written = await _finalizeDownload(
        tempPath: task.tempPath,
        finalPath: task.finalPath,
        expectedSize: task.totalSize,
      );
      if (written != null) {
        await updateTask(task.id,
            status: DownloadStatus.completed, progress: 1.0, finalPath: written);
      } else {
        await updateTask(task.id, status: DownloadStatus.failed);
      }
      releaseToken();
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
          // §dlRangeCheck (D3A-01) — 2xx seulement. Le Dio IPTV accepte tout
          // ce qui est < 500 : un `403 Too many connections` voyait son corps
          // AJOUTÉ au partiel, puis la tâche finissait « Terminé ». Un 4xx lève
          // désormais (`badResponse`, classé « source »), et le `416` atteint
          // enfin sa branche du `catch`.
          validateStatus: isDownloadableStatus,
        ),
      );

      // §dlRangeCheck (D3A-01) — Un serveur qui ignore `Range` renvoie le
      // fichier ENTIER : l'ajouter derrière le partiel le dupliquerait.
      final RangeVerdict verdict = rangeResponseVerdict(
        statusCode: response.statusCode,
        resumedBytes: resumedBytes,
        contentRangeStart: parseContentRangeStart(
            response.headers.value(HttpHeaders.contentRangeHeader)),
      );
      if (verdict == RangeVerdict.reject) {
        // Le corps n'a pas été lu : on ferme le flux avant de lever.
        try {
          await response.data?.stream.listen(null).cancel();
        } catch (_) {}
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          // Diagnostic seulement : l'écran passe par `describeError`, qui
          // lit le statut HTTP, jamais ce texte.
          message: 'range-mismatch ${response.statusCode}',
        );
      }
      final bool restartFromZero = verdict == RangeVerdict.restartFromZero;
      if (restartFromZero) {
        debugPrint("↩️ §dlRangeCheck : le serveur ignore Range — reprise depuis zéro ($resumedBytes octets écartés)");
        resumedBytes = 0;
      }

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
      final raf = await tempFile.open(
          mode: restartFromZero ? FileMode.write : FileMode.append);
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

      // D3A-03 — Une écriture qui échoue (disque plein) lève DANS `onData` :
      // l'exception partait à la zone, l'abonnement continuait, et `onDone`
      // finalisait un fichier dont une partie n'avait jamais été écrite.
      bool writeFailed = false;

      // Le `listen` s'abonne au flux de données. Il reçoit les données par segments (chunks).
      late final StreamSubscription<List<int>> streamSubscription;
      streamSubscription = response.data!.stream.listen(
            (chunk) {
          if (writeFailed) return;
          // Écrit le segment reçu à la fin du fichier.
          try {
            raf.writeFromSync(chunk);
          } catch (e) {
            writeFailed = true;
            debugPrint("💀 Écriture du partiel impossible : $e");
            unawaited(() async {
              await streamSubscription.cancel();
              await closeRaf();
              // Le partiel reste en place : la reprise repartira de ce qui a
              // réellement été écrit.
              await _failOrRequeue(task.id, e);
              if (!completer.isCompleted) completer.complete();
            }());
            return;
          }
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

          final String? written = await _finalizeDownload(
            tempPath: task.tempPath,
            finalPath: task.finalPath,
            expectedSize: definitiveTotal,
          );

          if (written != null) {
            await updateTask(task.id,
                status: DownloadStatus.completed,
                progress: 1.0,
                finalPath: written);
            debugPrint("💾 Fichier finalisé avec succès dans Movies : $written");
          } else {
            debugPrint("❌ Erreur lors du déplacement du fichier.");
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
            // §dlNetRetry — une coupure réseau repart en file, pas en échec.
            await _failOrRequeue(task.id, e);
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
        await updateTask(task.id, status: DownloadStatus.finalizing);
        final String? written = await _finalizeDownload(
          tempPath: task.tempPath,
          finalPath: task.finalPath,
          expectedSize: task.totalSize,
        );
        if (written != null) {
          await updateTask(task.id,
              status: DownloadStatus.completed, progress: 1.0, finalPath: written);
          debugPrint("💾 Fichier finalisé avec succès (via erreur 416).");
        } else {
          debugPrint("❌ Erreur lors du déplacement du fichier après une erreur 416.");
          await updateTask(task.id, status: DownloadStatus.failed);
        }
      } else if (e.type != DioExceptionType.cancel) {
        debugPrint("💀 Erreur Dio initiale: ${e.message}");
        await _failOrRequeue(task.id, e);
      }
    } catch (e) {
      debugPrint("💀 Erreur Système non gérée : $e");
      await _failOrRequeue(task.id, e);
    } finally {
      releaseToken();
      _clearProgressThrottle(task.id);
    }
  }

  /// Annule un téléchargement en cours.
  ///
  /// D3A-07 — Sans effet pendant la FINALISATION : le transfert réseau est
  /// fini, le partiel devient le fichier final. La tuile retirait déjà
  /// « Annuler » dans cet état, mais la notification et le moniteur le
  /// proposaient encore — et `canceled` était ensuite écrasé par la fin.
  Future<void> cancelTask(String taskId) async {
    final DownloadStatus? status = tasksNotifier.value
        .where((t) => t.id == taskId)
        .map((t) => t.status)
        .firstOrNull;
    if (status == DownloadStatus.finalizing) {
      debugPrint('↩️ Annulation ignorée pendant la finalisation : $taskId');
      return;
    }
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

  /// §dlNetRetry — Remises en file déjà accordées à chaque tâche.
  ///
  /// En mémoire seulement, et c'est assez : au redémarrage de l'app la tâche
  /// est de toute façon reconciliée (`_reconcileTasksOnStartup`), et un
  /// compteur qui repart de zéro une fois par lancement ne fait pas une boucle.
  final Map<String, int> _networkRequeues = {};

  /// §dlNetRetry — Aiguille une tâche interrompue : remise en FILE si le
  /// réseau a lâché, échec sinon.
  ///
  /// **Le défaut corrigé** : toute erreur de flux tombait en `failed`, et la
  /// file ne regarde que les `queued` — une coupure d'une minute condamnait
  /// donc un transfert déjà à 90 %. La reprise `Range` existait déjà ; il ne
  /// manquait que de ne pas fermer la porte.
  ///
  /// ⚠️ Le plafond (`kMaxNetworkRequeues`) n'est pas décoratif : une source qui
  /// coupe la connexion à chaque tentative RESSEMBLE à une panne réseau vue de
  /// l'app. Sans lui, elle serait martelée toute la nuit.
  ///
  /// D3A-09 — Le message gardé sur la tâche (et affiché par la tuile) passe par
  /// `describeError` : c'était le texte BRUT de l'exception, en anglais, avec
  /// le nom d'hôte ou le chemin complet. Le brut reste dans le journal, rédigé
  /// au puits.
  Future<void> _failOrRequeue(String taskId, Object error) async {
    final DownloadFailureKind kind = classifyDownloadFailure(error);
    if (kind == DownloadFailureKind.canceled) return;

    final int already = _networkRequeues[taskId] ?? 0;
    if (shouldRequeueAfterFailure(kind: kind, requeues: already)) {
      _networkRequeues[taskId] = already + 1;
      debugPrint('🔌 §dlNetRetry — reseau perdu, tache remise en file '
          '(${already + 1}/$kMaxNetworkRequeues) : $taskId');
      // ⚠️ `updateTask` et non `enqueue` : `enqueue` refuse une tâche encore
      // en vol (`_inFlight`), et nous sommes précisément en train d'en sortir.
      // Le `pump()` du `whenComplete` de `startDownloadTask` la fera partir.
      await updateTask(taskId, status: DownloadStatus.queued);
      // Le réseau est peut-être déjà revenu : que la file le constate.
      unawaited(NetworkStatusService.refresh());
      return;
    }
    await updateTask(taskId,
        status: DownloadStatus.failed, errorMessage: describeError(error));
  }

  /// Rejoue l'aiguillage d'une erreur, sans réseau ni fichier (tests).
  @visibleForTesting
  Future<void> failOrRequeueForTest(String taskId, Object error) =>
      _failOrRequeue(taskId, error);

  /// Marque une tâche comme en vol, sans transfert réel (tests).
  @visibleForTesting
  void markInFlightForTest(String taskId, Future<void> run) =>
      _inFlight[taskId] = run;

  /// Oublie les transferts marqués en vol par [markInFlightForTest].
  @visibleForTesting
  void clearInFlightForTest() => _inFlight.clear();

  /// Arrête le sondage de la file retenue (tests) : sans ça, son `Timer`
  /// périodique survivrait au test qui l'a armé.
  @visibleForTesting
  void resetQueueForTest() => _setHold(null);

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
  void resetProgressThrottle(String taskId) {
    _clearProgressThrottle(taskId);
    _clearRestartPolicy(taskId);
  }

  /// §dlLoop — Ce que la politique anti-boucle a retenu d'une tâche : date de
  /// la dernière relance automatique et octets reçus à cet instant. `null` =
  /// aucune relance automatique connue, donc la prochaine est autorisée.
  ///
  /// Exposé pour le test de non-régression : le défaut n'était pas dans la
  /// règle (pure et déjà testée) mais dans le fait que ses ENTRÉES étaient
  /// effacées entre deux tentatives.
  @visibleForTesting
  ({DateTime? at, int? bytes}) restartPolicyStateForTest(String taskId) =>
      (at: _lastAutoRestart[taskId], bytes: _bytesAtLastAutoRestart[taskId]);

  /// Simule ce que fait la fin d'un transfert (le `finally` de `_runDownload`),
  /// sans réseau ni fichier.
  @visibleForTesting
  void endOfTransferCleanupForTest(String taskId) =>
      _clearProgressThrottle(taskId);

  /// Inscrit une relance automatique, comme le fait `_maybeAutoRestart`.
  @visibleForTesting
  void noteAutoRestartForTest(String taskId, DateTime at, int bytes) {
    _lastAutoRestart[taskId] = at;
    _bytesAtLastAutoRestart[taskId] = bytes;
  }

  /// Libère les compteurs de throttle d'une tâche terminée/supprimée.
  ///
  /// ⚠️ **Appelée à la fin de CHAQUE transfert**, donc aussi entre les deux
  /// moitiés d'une relance (`restartTask` coupe le flux, attend sa fin, puis
  /// repart). Elle ne doit donc contenir que des états de FLUX — ceux qui
  /// meurent avec la connexion. Les états de POLITIQUE (§dlLoop) vivent dans
  /// [_clearRestartPolicy] : les mettre ici revenait à effacer le garde-fou
  /// anti-boucle juste avant qu'il ait à servir.
  void _clearProgressThrottle(String taskId) {
    _lastNotifiedPct.remove(taskId);
    _lastNotifiedAt.remove(taskId);
    _lastPersistedAt.remove(taskId);
    // §dlWatchdog — le débit se mesure PAR CONNEXION : le pic de la précédente
    // ne dit rien de la nouvelle (cf. la remise à zéro dans `_maybeAutoRestart`).
    _throughput.remove(taskId);
  }

  /// §dlLoop — Oublie l'historique des relances AUTOMATIQUES d'une tâche.
  ///
  /// **Le défaut corrigé (2026-09-08, signalé par l'utilisateur : « si on sort
  /// de l'application la relance se lance en boucle »).** `shouldAutoRestart`
  /// refuse une relance à moins de 30 s de la précédente, ou si celle-ci n'a
  /// pas rapporté 1 Mo. Ses deux entrées sont précisément ces deux tables — et
  /// elles étaient vidées par `_clearProgressThrottle`, appelée à la fin du
  /// transfert que la relance venait d'interrompre. Les deux valeurs étaient
  /// donc `null` au tour suivant, `shouldAutoRestart(null, null)` rendait
  /// `true`, et ni le délai ni le gain minimal ne s'appliquaient JAMAIS d'une
  /// relance à la suivante. En arrière-plan, où le débit s'effondre face au pic
  /// mesuré au premier plan, le décrochage se déclenche à chaque fenêtre de
  /// 5 s : la boucle était armée.
  ///
  /// Ces compteurs ne s'effacent donc qu'avec la tâche elle-même, ou quand elle
  /// aboutit — jamais entre deux tentatives de la MÊME tâche.
  void _clearRestartPolicy(String taskId) {
    _lastAutoRestart.remove(taskId);
    _bytesAtLastAutoRestart.remove(taskId);
    _networkRequeues.remove(taskId); // §dlNetRetry
  }

  /// Met à jour une tâche existante et notifie l'UI.
  Future<void> updateTask(String taskId,
      {DownloadStatus? status,
      double? progress,
      int? totalSize,
      String? errorMessage,
      // §dlEpisode — La finalisation peut avoir dû se pousser d'un cran
      // (« nom (2).mp4 ») pour ne pas écraser un fichier existant : la tâche
      // doit alors porter le chemin RÉEL, sinon « Lire » et « Supprimer »
      // viseraient un fichier qui n'est pas le sien.
      String? finalPath}) async {
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
        finalPath: finalPath,
      );

      // §dlLoop — Une tâche ABOUTIE n'a plus d'historique de relance à
      // défendre. ⚠️ `canceled` n'est PAS un état final ici : une relance y
      // passe techniquement (couper le flux, puis reprendre au même octet) —
      // l'y inclure remettrait exactement la boucle qu'on vient de retirer.
      if (status == DownloadStatus.completed) _clearRestartPolicy(taskId);

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
    _clearRestartPolicy(taskId); // §dlLoop — la tâche disparaît, son historique aussi
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
///
/// Rend le chemin **réellement utilisé** (`null` en cas d'échec) : il peut
/// différer de [finalPath] — voir §dlEpisode ci-dessous.
@visibleForTesting
Future<String?> finalizeDownloadForTest({
  required String tempPath,
  required String finalPath,
  int expectedSize = 0,
}) =>
    _finalizeDownload(
      tempPath: tempPath,
      finalPath: finalPath,
      expectedSize: expectedSize,
    );

Future<String?> _finalizeDownload({
  required String tempPath,
  required String finalPath,
  int expectedSize = 0,
}) async {
  final file = File(tempPath);
  if (!await file.exists()) {
    debugPrint("Erreur de finalisation : le fichier source n'existe pas à $tempPath");
    return null;
  }

  // D3A-03 — La taille se contrôle AVANT tout renommage. Contrôlée après,
  // un partiel tronqué (disque plein) devenait un film visible dans la
  // galerie, la reprise était perdue et « Relancer » repartait de zéro.
  final int size = await file.length();
  if (size == 0) {
    debugPrint("⚠️ Fichier partiel vide : rien à finaliser");
    return null;
  }
  if (expectedSize > 0 && size < expectedSize) {
    debugPrint("⚠️ Fichier tronqué : $size / $expectedSize octets — partiel conservé");
    return null;
  }

  // Le partiel est-il déjà dans le dossier de destination ? On le déduit des
  // dossiers parents plutôt que d'un champ du modèle : les tâches DÉJÀ
  // persistées (partiel en cache) prennent ainsi automatiquement le repli,
  // sans migration.
  if (file.parent.path == File(finalPath).parent.path) {
    try {
      // §dlEpisode — ⚠️ **DERNIER garde-fou avant un écrasement silencieux.**
      // `rename()` remplace sa cible sans lever : c'est ainsi que les épisodes
      // d'une même série se sont effacés les uns les autres. Le nom est déjà
      // rendu unique à la création de la tâche, mais le dossier public est
      // PARTAGÉ — un fichier a pu y apparaître entre-temps (autre tâche,
      // copie manuelle, §dlOrphans). On ne remplace donc jamais : on se pousse.
      final String target = await _freeFinalPath(finalPath);
      await file.rename(target);
      debugPrint("⚡ Finalisation instantanée (rename) — $target");
      return target;
    } catch (e) {
      debugPrint("⚠️ Rename impossible ($e) → repli MediaStore");
    }
  }

  if (Platform.isWindows) {
    final success = await StorageService.saveVideoToGallery(
      tempPath: tempPath,
      fileName: File(finalPath).uri.pathSegments.isNotEmpty
          ? File(finalPath).uri.pathSegments.last
          : 'video.mp4',
    );
    return success ? finalPath : null;
  }

  // D3A-10 — Le repli MediaStore REMPLACE un fichier de même nom (il efface
  // avant d'insérer) et tire ce nom de celui du partiel. On lui donne donc un
  // nom LIBRE, en renommant le partiel dans son propre dossier ; en cas
  // d'échec il reprend son nom, pour que la reprise le retrouve.
  final String target = await _freeFinalPath(finalPath);
  final String wantedName = target.substring(target.lastIndexOf('/') + 1);
  final int slash = tempPath.lastIndexOf('/');
  final String currentName = tempPath.substring(slash + 1);
  String source = tempPath;
  if (currentName != wantedName) {
    final String renamed =
        slash >= 0 ? '${tempPath.substring(0, slash)}/$wantedName' : wantedName;
    try {
      await file.rename(renamed);
      source = renamed;
    } catch (e) {
      debugPrint("⚠️ Partiel non renommé avant MediaStore ($e)");
    }
  }
  final bool ok = await _copyToMediaStore(source);
  if (!ok) {
    if (source != tempPath) {
      try {
        await File(source).rename(tempPath);
      } catch (_) {}
    }
    return null;
  }
  // Nom libre effectivement donné à MediaStore → chemin exact ; sinon
  // (renommage impossible) le chemin attendu, comme avant.
  return (source != tempPath || currentName == wantedName) ? target : finalPath;
}

/// §dlEpisode — [finalPath] s'il est libre, sinon le premier « nom (N).ext »
/// qui l'est.
Future<String> _freeFinalPath(String finalPath) async {
  final int slash = finalPath.lastIndexOf('/');
  final String dir = slash >= 0 ? finalPath.substring(0, slash) : '';
  final String name = slash >= 0 ? finalPath.substring(slash + 1) : finalPath;
  for (int i = 0; i < 99; i++) {
    final String candidate = downloadNameCandidate(name, i);
    final String path = dir.isEmpty ? candidate : '$dir/$candidate';
    if (await File(path).exists()) continue;
    if (i > 0) {
      debugPrint('📄 §dlEpisode — « $name » existe deja, ecrit sous « $candidate »');
    }
    return path;
  }
  return finalPath;
}

/// Repli historique : copie du cache privé vers le stockage public via
/// MediaStore. Retourne `true` en cas de succès.
Future<bool> _copyToMediaStore(String tempPath) async {
  if (!Platform.isAndroid) return false;
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
