import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'storage_service.dart';

class WindowsStorage implements PlatformStorage {
  static const String _appName = "AetherStream";

  @override
  Future<void> init() async {
    // Rien à initialiser spécifiquement pour Windows.
  }

  @override
  Future<bool> ensurePermission() async {
    // Windows ne demande pas de permissions au runtime via permission_handler.
    return true;
  }

  @override
  Future<String?> getAppMoviesPath() async {
    try {
      String? videosPath;
      
      final Directory? dir = await getDownloadsDirectory();
      if (dir != null) {
        final root = dir.parent.path;
        videosPath = '$root/Videos';
        if (!await Directory(videosPath).exists()) {
          videosPath = dir.path;
        }
      } else {
        final userProfile = Platform.environment['USERPROFILE'];
        if (userProfile != null) {
          videosPath = '$userProfile/Videos';
        }
      }

      if (videosPath == null) return null;

      final Directory appPath = Directory('$videosPath/$_appName');
      if (!await appPath.exists()) {
        await appPath.create(recursive: true);
      }
      return appPath.path;
    } catch (e) {
      debugPrint("❌ Erreur lors de la création du dossier Windows : $e");
      return null;
    }
  }

  @override
  Future<bool> saveVideoToGallery({
    required String tempPath,
    required String fileName,
  }) async {
    try {
      final String? appPath = await getAppMoviesPath();
      if (appPath == null) return false;

      final String finalPath = '$appPath/$fileName';
      final File tempFile = File(tempPath);
      
      if (await tempFile.exists()) {
        await tempFile.copy(finalPath);
        await tempFile.delete();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("💀 Erreur lors du déplacement du fichier sur Windows : $e");
      return false;
    }
  }

  @override
  Future<void> deleteVideo(String finalPath) async {
    try {
      final file = File(finalPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint("⚠️ WindowsStorage: suppression fichier échouée : $e");
    }
  }
}
