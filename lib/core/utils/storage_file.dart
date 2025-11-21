import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// Service dédié à la gestion des chemins de stockage et des permissions.
class StorageService {
  static const String _appName = "AetherStream";

  /// Obtient le chemin complet vers le dossier de l'application dans le répertoire "Movies".
  /// Crée le dossier s'il n'existe pas et gère les permissions nécessaires.
  ///
  /// Retourne le chemin du dossier en cas de succès, ou `null` si les permissions
  /// sont refusées ou si une erreur survient.
  Future<String?> getAppMoviesPath() async {
    // 1. Demander les permissions
    final bool permissionGranted = await _requestStoragePermission();
    if (!permissionGranted) {
      debugPrint("Permission de stockage refusée par l'utilisateur.");
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
      debugPrint("Erreur critique lors de la recherche du dossier Movies : $e");
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
      return appPath.path;
    } catch (e) {
      debugPrint("Erreur lors de la création du dossier '$_appName'. Erreur: $e");
      return null;
    }
  }

  /// Gère la demande de permission en fonction de la version d'Android.
  Future<bool> _requestStoragePermission() async {
    if (!Platform.isAndroid) return true; // Pas besoin sur les autres plateformes

    final deviceInfo = await DeviceInfoPlugin().androidInfo;
    PermissionStatus status;

    if (deviceInfo.version.sdkInt >= 33) {
      // Android 13+ : on demande l'accès spécifique aux vidéos.
      status = await Permission.videos.request();
    } else {
      // Versions antérieures : on demande l'accès général au stockage.
      status = await Permission.storage.request();
    }

    return status.isGranted;
  }
}
