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
    // 1. Demander les permissions nécessaires
    final bool permissionGranted = await _requestStoragePermission();
    if (!permissionGranted) {
      debugPrint("Permission de stockage refusée par l'utilisateur.");
      // Idéalement, ici, on afficherait un message à l'utilisateur.
      return null;
    }

    // 2. Trouver le répertoire "Movies" public
    Directory? moviesDir;
    try {
      // getExternalStorageDirectories est la méthode la plus fiable et recommandée.
      final dirs = await getExternalStorageDirectories(type: StorageDirectory.movies);
      if (dirs != null && dirs.isNotEmpty) {
        moviesDir = dirs.first;
      } else {
        // En cas d'échec (très rare), on tente un fallback.
        moviesDir = await getExternalStorageDirectory();
      }
    } catch (e) {
      debugPrint("Erreur critique : Impossible de trouver le dossier Movies. Erreur: $e");
      return null;
    }

    if (moviesDir == null) {
      debugPrint("Erreur: Le répertoire Movies est null.");
      return null;
    }

    // 3. Construire et créer le sous-dossier de l'application
    final Directory appPath = Directory('${moviesDir.path}/$_appName');
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
