import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'storage_service.dart';

class AndroidStorage implements PlatformStorage {
  static const String _appName = "AetherStream";

  @override
  Future<void> init() async {
    await MediaStore.ensureInitialized();
    MediaStore.appFolder = _appName;
  }

  @override
  Future<bool> ensurePermission() async {
    final deviceInfo = await DeviceInfoPlugin().androidInfo;
    PermissionStatus status;

    if (deviceInfo.version.sdkInt >= 33) {
      status = await Permission.videos.request();
    } else {
      status = await Permission.storage.request();
    }

    return status.isGranted;
  }

  @override
  Future<String?> getAppMoviesPath() async {
    final bool permissionGranted = await ensurePermission();
    if (!permissionGranted) {
      debugPrint("❌ Permission de stockage refusée par l'utilisateur.");
      return null;
    }

    String? finalPath;

    try {
      final dirs = await getExternalStorageDirectories(type: StorageDirectory.movies);
      if (dirs != null && dirs.isNotEmpty) {
        final rootPath = dirs.first.path.split('/Android/')[0];
        finalPath = '$rootPath/Movies';
      } else {
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          final rootPath = externalDir.path.split('/Android/')[0];
          finalPath = '$rootPath/Movies';
        }
      }
    } catch (e) {
      debugPrint("❌ Erreur critique lors de la recherche du dossier Movies : $e");
      return null;
    }

    if (finalPath == null) return null;

    final Directory appPath = Directory('$finalPath/$_appName');
    try {
      if (!await appPath.exists()) {
        await appPath.create(recursive: true);
      }
      return appPath.path;
    } catch (e) {
      debugPrint("❌ Erreur lors de la création du dossier '$_appName': $e");
      return null;
    }
  }

  @override
  Future<bool> saveVideoToGallery({
    required String tempPath,
    required String fileName,
  }) async {
    final file = File(tempPath);
    if (!await file.exists()) {
      debugPrint("Erreur de déplacement : le fichier source n'existe pas à $tempPath");
      return false;
    }

    try {
      final mediaStore = MediaStore();
      await mediaStore.saveFile(
        tempFilePath: tempPath,
        dirType: DirType.video,
        dirName: DirName.movies,
        relativePath: null, // Utilise MediaStore.appFolder
      );
      return true;
    } catch (e) {
      debugPrint("💀 Erreur MediaStore lors de la sauvegarde du fichier: $e");
      return false;
    }
  }

  @override
  Future<void> deleteVideo(String finalPath) async {
    try {
      final fileName = finalPath.split('/').last;
      if (fileName.isNotEmpty) {
        await MediaStore().deleteFile(
          fileName: fileName,
          dirType: DirType.video,
          dirName: DirName.movies,
        );
      }
    } catch (e) {
      debugPrint("⚠️ AndroidStorage: suppression MediaStore échouée : $e");
    }
  }
}
