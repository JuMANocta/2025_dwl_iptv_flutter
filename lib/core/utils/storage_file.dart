import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// R14 (D1B-22) — La permission « vidéos » conditionne-t-elle l'ÉCRITURE de
/// nos propres fichiers dans `Movies/AetherStream/` ?
///
/// **Non, à partir d'Android 10 (API 29).** Le stockage cloisonné donne à
/// chaque application le droit de créer et d'écrire SES fichiers dans les
/// dossiers média partagés, sans aucune permission ; `READ_MEDIA_VIDEO` ne
/// sert qu'à LIRE ceux des autres — chez nous, à retrouver les fichiers d'une
/// installation précédente (`DeviceLibraryService`, §dlOrphans).
///
/// **Le défaut payé** : `getAppMoviesPath` demandait la permission d'entrée de
/// jeu et rendait `null` au moindre refus. Un refus — que Google Play refusera
/// lui-même d'accorder pour un usage comme le nôtre — ANNULAIT donc le
/// téléchargement, alors que tout le chemin d'écriture était disponible.
///
/// ⚠️ Avant Android 10, écrire hors du bac à sable exige bien
/// `WRITE_EXTERNAL_STORAGE` : là, un refus est un vrai mur.
bool storagePermissionNeededToWrite(int sdkInt) => sdkInt < 29;

/// Service dédié à la gestion des chemins de stockage et des permissions.
class StorageService {
  static const String _appName = "AetherStream";

  /// Obtient le chemin complet vers le dossier de l'application dans le répertoire "Movies".
  /// Crée le dossier s'il n'existe pas.
  ///
  /// R14 — Rend `null` seulement si le chemin lui-même est introuvable, ou si
  /// l'appareil est antérieur à Android 10 ET refuse le stockage. Un dossier
  /// qu'on n'a pas pu créer n'arrête plus rien : §dlDirectWrite sonde de toute
  /// façon l'écriture (`DirectWriteProbe`) et retombe sur le cache privé +
  /// MediaStore, qui n'exige aucune permission.
  Future<String?> getAppMoviesPath() async {
    // 1. Permission — seulement là où elle décide vraiment de quelque chose.
    if (!await _ensureWritePermission()) {
      debugPrint("❌ Permission de stockage refusée (Android 9 ou antérieur).");
      return null;
    }

    // 2. Trouver le répertoire "Movies" public (LOGIQUE AMÉLIORÉE)
    Directory? moviesDir;
    String? finalPath;

    try {
      // Méthode 1 : La plus fiable
      final dirs = await getExternalStorageDirectories(type: StorageDirectory.movies);
      if (dirs != null && dirs.isNotEmpty) {
        moviesDir = dirs.first;
        // On retire la partie privée pour remonter à la racine du stockage partagé
        final rootPath = moviesDir.path.split('/Android/')[0];
        finalPath = '$rootPath/Movies';
        debugPrint("🔍 [PATH] Trouvé via Méthode 1: $finalPath");
      }

      // Méthode 2 (Fallback) : Si la première échoue, on construit le chemin manuellement
      if (finalPath == null) {
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          final rootPath = externalDir.path.split('/Android/')[0];
          finalPath = '$rootPath/Movies';
          debugPrint("🔍 [PATH] Construit via Méthode 2 (Fallback): $finalPath");
        }
      }

    } catch (e) {
      debugPrint("❌ Erreur critique lors de la recherche du dossier Movies : $e");
      return null;
    }

    if (finalPath == null) {
      debugPrint("❌ Erreur: Impossible de déterminer le chemin du dossier Movies.");
      return null;
    }

    // 3. Construire et créer le sous-dossier de l'application
    final Directory appPath = Directory('$finalPath/$_appName');
    try {
      if (!await appPath.exists()) {
        await appPath.create(recursive: true);
        debugPrint("Dossier créé : ${appPath.path}");
      }
    } catch (e) {
      // R14 — ⚠️ On rend le chemin QUAND MÊME : MediaStore sait créer ce
      // dossier à la finalisation, et la sonde d'écriture directe décidera
      // seule du trajet du fichier partiel. Rendre `null` ici, c'était
      // abandonner un téléchargement parfaitement réalisable.
      debugPrint("⚠️ Dossier '$_appName' non créé ($e) — repli MediaStore");
    }
    return appPath.path;
  }

  /// R14 — Ne demande la permission que là où elle décide de l'écriture.
  /// Android 10+ : rien à demander, on écrit nos propres fichiers.
  Future<bool> _ensureWritePermission() async {
    if (!Platform.isAndroid) return true; // Pas besoin sur les autres plateformes

    final int sdkInt;
    try {
      sdkInt = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    } catch (e) {
      // Version inconnue : on ne bloque pas un téléchargement sur un doute.
      debugPrint("⚠️ Version d'Android inconnue ($e) — écriture tentée");
      return true;
    }
    if (!storagePermissionNeededToWrite(sdkInt)) return true;
    final PermissionStatus status = await Permission.storage.request();
    return status.isGranted || status.isLimited;
  }
}
