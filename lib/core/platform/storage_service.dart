import 'dart:io' show Platform;
import 'storage_service_android.dart';
import 'storage_service_windows.dart';

/// Interface pour la gestion du stockage et des fichiers multimédias
/// de manière multi-plateforme.
abstract class PlatformStorage {
  /// Initialise le service (ex: configuration du dossier racine sur Android).
  Future<void> init();

  /// Demande les permissions nécessaires pour accéder au stockage.
  Future<bool> ensurePermission();

  /// Retourne le chemin vers le dossier public de l'application (ex: /Movies/AetherStream).
  Future<String?> getAppMoviesPath();

  /// Sauvegarde un fichier temporaire vers l'emplacement final (galerie ou dossier public).
  Future<bool> saveVideoToGallery({
    required String tempPath,
    required String fileName,
  });

  /// Supprime un fichier du stockage public ou de la galerie.
  Future<void> deleteVideo(String finalPath);
}

/// Point d'accès unique pour les services de stockage.
class StorageService {
  static PlatformStorage? _instance;

  static PlatformStorage get instance {
    if (_instance == null) {
      if (Platform.isAndroid) {
        _instance = AndroidStorage();
      } else if (Platform.isWindows) {
        _instance = WindowsStorage();
      } else {
        throw UnsupportedError('Unsupported platform for storage');
      }
    }
    return _instance!;
  }

  /// Alias statiques pour faciliter l'appel.
  static Future<void> init() => instance.init();
  static Future<bool> ensurePermission() => instance.ensurePermission();
  static Future<String?> getAppMoviesPath() => instance.getAppMoviesPath();
  static Future<bool> saveVideoToGallery({
    required String tempPath,
    required String fileName,
  }) => instance.saveVideoToGallery(tempPath: tempPath, fileName: fileName);

  static Future<void> deleteVideo(String finalPath) =>
      instance.deleteVideo(finalPath);
}
