import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../../main.dart'; // Pour le navigatorKey
import '../../../data/models/download_task.dart';
import '../../../data/services/download_manager_service.dart';
import '../../../core/utils/network.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/storage_file.dart';
import '../../../widgets/terminal_download_dialog.dart';
import '../../../widgets/info_row.dart';
import '../../../l10n/app_localizations.dart';

/// §dlDirectWrite — Dossier de repli pour le fichier partiel.
///
/// N'est plus le chemin NOMINAL : par défaut on télécharge directement à côté
/// du fichier de destination (cf. [_resolvePartPath]), ce qui supprime la copie
/// finale. Ce cache privé ne sert plus que lorsque le dossier public est
/// inaccessible en écriture — auquel cas on retombe sur le trajet historique
/// (cache + `MediaStore.saveFile`).
///
/// On garde le cache EXTERNE (/sdcard/Android/data/.../cache/) plutôt
/// qu'interne : il est sur la même partition flash que /sdcard/Movies/, donc la
/// copie de repli reste la moins lente possible.
Future<String> _getTempDirectory() async {
  final externalDirs = await getExternalCacheDirectories();
  final basePath = (externalDirs != null && externalDirs.isNotEmpty)
      ? externalDirs.first.path
      : (await getTemporaryDirectory()).path;
  final tmp = Directory("$basePath/dl_tmp");
  if (!await tmp.exists()) await tmp.create(recursive: true);
  return tmp.path;
}

/// §dlDirectWrite — Le dossier accepte-t-il vraiment l'écriture ?
///
/// `Directory.exists()` ne suffit pas : sous scoped storage un dossier peut
/// être listable sans être inscriptible. On écrit donc une sonde minuscule
/// qu'on efface aussitôt — aucun résidu.
Future<bool> _canWriteInto(String directory) async {
  final probe = File('$directory/.aether_write_probe');
  try {
    await probe.writeAsString('x', flush: true);
    return true;
  } catch (e) {
    debugPrint('⚠️ §dlDirectWrite: dossier non inscriptible ($directory) — $e');
    return false;
  } finally {
    try {
      if (await probe.exists()) await probe.delete();
    } catch (_) {/* résidu inoffensif */}
  }
}

/// §dlDirectWrite — Emplacement du fichier PARTIEL pendant le téléchargement.
///
/// **Nominal** : à côté du fichier final, donc sur le même volume → la
/// finalisation devient un `rename()` (métadonnées, instantané) au lieu d'une
/// copie de plusieurs Go qui bloquait le thread UI d'Android jusqu'à l'ANR.
/// Le nom est préfixé d'un point (invisible du scanner média et des
/// explorateurs) et suffixé `.part` (jamais indexé comme vidéo).
///
/// **Repli** : cache privé, et la finalisation repassera par MediaStore.
/// Le manager déduit le mode à appliquer en comparant les dossiers parents —
/// aucune migration des tâches déjà persistées n'est donc nécessaire.
Future<String> _resolvePartPath(String finalDirectory, String fileName) async {
  if (await _canWriteInto(finalDirectory)) {
    return '$finalDirectory/.$fileName.part';
  }
  final tempDirectory = await _getTempDirectory();
  debugPrint('↩️ §dlDirectWrite: repli cache privé → $tempDirectory');
  return '$tempDirectory/$fileName';
}

String sanitizeFilename(String filename) => filename.replaceAll(RegExp(r'[\\/*?:"<>|]'), "_");

String _ext(String name) {
  final i = name.lastIndexOf('.');
  return (i >= 0 && i < name.length - 1) ? name.substring(i + 1).toLowerCase() : '';
}

Future<void> verifierEtTelecharger({
  required String url,
  required String nom,
  String? releaseYear, // NOUVEAU PARAMÈTRE
  required BuildContext context
}) async {
  if (!context.mounted) return;
  final downloadManager = DownloadManagerService();

  final existingTask = downloadManager.tasksNotifier.value.firstWhere(
          (t) => t.url == url, orElse: () => DownloadTask.empty());

  // --- LOGIQUE DE GESTION DES TÂCHES EXISTANTES (COMPLÈTE AVEC REPRISE) ---
  if (existingTask.id.isNotEmpty) {
    switch (existingTask.status) {

    // CAS 1 : C'est déjà téléchargé. On notifie l'utilisateur.
      case DownloadStatus.completed:
        debugPrint("✅ Ce fichier est déjà sauvegardé.");
        return;

    // CAS 2 : C'est déjà en cours, en attente ou en pause. On ouvre le moniteur.
      case DownloadStatus.downloading:
      case DownloadStatus.queued:
      case DownloadStatus.paused:
        debugPrint("⏳ Ce téléchargement est déjà dans la liste (état: ${existingTask.status}).");
        final rootContext = navigatorKey.currentContext;
        if (rootContext != null && rootContext.mounted) {
          showDialog(
              context: rootContext,
              builder: (_) => TerminalDownloadDialog(taskId: existingTask.id));
        }
        return;

    // CAS 3 : La tâche existe mais a échoué/été annulée. ON LA REPREND !
      case DownloadStatus.failed:
      case DownloadStatus.canceled:
        debugPrint("🔄 Tâche existante trouvée (état: ${existingTask.status}). Reprise du téléchargement...");

        // On demande simplement au manager de relancer CETTE tâche existante.
        downloadManager.startDownloadTask(existingTask);

        // On affiche le moniteur pour que l'utilisateur voie la reprise.
        final rootContext = navigatorKey.currentContext;
        if (rootContext != null && rootContext.mounted) {
          showDialog(
              context: rootContext,
              builder: (_) => TerminalDownloadDialog(
                taskId: existingTask.id,
                isResume: true,
              ));
        }
        return;
      case DownloadStatus.finalizing:
        debugPrint("✅ Stream terminé. Finalisation...");
        return;
    }
  }

  // Si on arrive ici, c'est qu'aucune tâche n'existait pour cette URL.
  debugPrint("🚀 Lancement d'un nouveau téléchargement pour : $nom");
  await _telechargerFichierVideo(url: url, nom: nom, releaseYear: releaseYear, context: context);
}

Future<int?> probeContentLength(Dio dio, String url) async {
  // On utilise directement la "feinte" de la requête GET partielle,
  // car elle est plus fiable pour obtenir le 'content-length'.
  final completer = Completer<int?>();
  final cancelToken = CancelToken();

  try {
    // On lance une requête GET qui télécharge en streaming.
    dio.get(
      url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream, // TRÈS IMPORTANT: on ne télécharge pas tout le corps
        followRedirects: true,
      ),
    ).then((response) {
      // Dès qu'on reçoit la réponse (les en-têtes sont arrivés)...
      final cl = response.headers.value('content-length');
      if (!completer.isCompleted) {
        completer.complete(cl != null ? int.tryParse(cl) : null);
      }
    }).catchError((error, stackTrace) {
      if (!completer.isCompleted) {
        completer.complete(null); // La requête a échoué avant d'avoir les en-têtes
      }
    }).whenComplete(() {
      // Dans tous les cas, on ANNULE immédiatement la requête pour ne pas télécharger le fichier.
      cancelToken.cancel();
    });

  } catch (e) {
    // Si une DioException de type 'cancel' arrive ici, c'est normal et attendu, on l'ignore.
    if (kDebugMode && e is! DioException && e.toString().contains('Request newFuture')) {
      debugPrint("⚠️ Erreur inattendue dans probeContentLength avec GET: $e");
    }
    if (!completer.isCompleted) {
      completer.complete(null);
    }
  }

  // On retourne le résultat obtenu (ou null si tout a échoué).
  return completer.future;
}

/// --- FONCTION DE TÉLÉCHARGEMENT (REVUE POUR DÉLÉGUER) ---
Future<void> _telechargerFichierVideo({required String url, required String nom, String? releaseYear, required BuildContext context}) async {
  final l10n = AppLocalizations.of(context)!;
  final downloadManager = DownloadManagerService();

  // 1. On sonde la taille du fichier AVANT de créer la tâche
  int? totalSize;
  try {
    final dio = await NetworkUtils.buildDio(url);
    totalSize = await probeContentLength(dio, url);
  } catch (e) {
    debugPrint("❓ Impossible de sonder la taille du fichier: $e");
  }

  // 2. On affiche l'AlertDialog de confirmation.
  if (!context.mounted) return;

  // On prépare l'extension pour l'afficher dans le dialogue
  final String extension = _ext(url).toUpperCase();

  final bool? confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      // 1. Row pour combiner icône et texte
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start, // Aligne l'icône en haut si le texte prend plusieurs lignes
        children: [
          const Icon(Icons.download_for_offline_outlined, size: 28),
          const SizedBox(width: 12),
          // Expanded est la clé ! Il empêche le texte de déborder.
          Expanded(
            child: Text(nom),
          ),
        ],
      ),

      // 2. Un contenu structuré avec une Column
      content: Column(
        mainAxisSize: MainAxisSize.min, // la Column ne prends pas toute la hauteur
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 24),
          // 3. Des informations claires et iconifiées
          InfoRow(
            icon: Icons.straighten, // Icône pour la taille
            label: l10n.downloadDialogFileSizeLabel,
            value: totalSize != null ? formatFileSize(totalSize) : l10n.downloadDialogUnknownSize,
          ),
          if (extension.isNotEmpty) ...[
            const SizedBox(height: 8),
            InfoRow(
              icon: Icons.description_outlined, // Icône pour le type
              label: l10n.downloadDialogFileTypeLabel,
              value: extension,
            ),
          ],
        ],
      ),

      // 4. Des actions plus claires
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        FilledButton.icon( // On ajoute une icône au bouton principal
          icon: const Icon(Icons.download_rounded),
          label: Text(l10n.download),
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );

  // 4. Si l'utilisateur annule, on arrête tout.
  if (confirm != true) {
    if (context.mounted) {
      debugPrint("Téléchargement annulé.");
    }
    return; // Arrêt complet de la fonction
  }

  // 5.OBTENIR LE CHEMIN DE SAUVEGARDE SÉCURISÉ
  final storageService = StorageService();
  final String? finalSaveDirectory = await storageService.getAppMoviesPath();

  if (finalSaveDirectory == null) {
    // Si on n'a pas pu obtenir le chemin (permission refusée), on notifie et on arrête.
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Permission denied. The download cannot begin.")),
      );
    }
    return;
  }

  // 6. CRÉATION DE LA TÂCHE AVEC LE BON CHEMIN
  String baseFileName = sanitizeFilename(nom);
  // Ajout de l'année au nom de fichier si disponible
  if (releaseYear != null && releaseYear.isNotEmpty) {
    baseFileName = '$baseFileName ($releaseYear)';
  }

  final fileExt = extension.isNotEmpty ? extension.toLowerCase() : 'mp4';
  if (_ext(baseFileName).isEmpty) baseFileName = '$baseFileName.$fileExt';

  // On construit le chemin final en utilisant le dossier obtenu par notre service.
  final finalPath = "$finalSaveDirectory/$baseFileName";
  // §dlDirectWrite — Fichier partiel dans le dossier FINAL quand c'est possible
  // (finalisation = rename instantané), sinon cache privé + MediaStore.
  final tempPath = await _resolvePartPath(finalSaveDirectory, baseFileName);
  final taskId = 'task_${DateTime.now().millisecondsSinceEpoch}';

  final newTask = DownloadTask(
    id: taskId,
    url: url,
    displayName: nom,
    finalPath: finalPath,
    tempPath: tempPath,
    totalSize: totalSize ?? 0,
    status: DownloadStatus.queued,
    createdAt: DateTime.now(),
    releaseYear: releaseYear,
  );

  // 7. AJOUT AU MANAGER ET DÉMARRAGE EN ARRIÈRE-PLAN
  await downloadManager.addTask(newTask);
  downloadManager.startDownloadTask(newTask);

  // 8. AFFICHAGE DU DIALOGUE "MONITEUR"
  final rootContext = navigatorKey.currentContext;
  if (rootContext == null || !rootContext.mounted) return;

  showDialog(
    context: rootContext,
    barrierDismissible: true,
    builder: (context) => TerminalDownloadDialog(taskId: taskId),
  );
}
