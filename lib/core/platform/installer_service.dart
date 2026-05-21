import 'dart:io' show Platform;
import 'installer_service_android.dart';
import 'installer_service_windows.dart';

/// Interface pour l'installation des mises à jour
/// de manière multi-plateforme.
abstract class PlatformInstaller {
  /// Demande les permissions nécessaires pour l'installation (ex: Android 8+).
  Future<bool> ensurePermission();

  /// Lance l'installation d'un fichier téléchargé.
  Future<void> install(String filePath, {String? downloadUrl});
}

/// Point d'accès unique pour les services d'installation.
class InstallerService {
  static PlatformInstaller? _instance;

  static PlatformInstaller get instance {
    if (_instance == null) {
      if (Platform.isAndroid) {
        _instance = AndroidInstaller();
      } else if (Platform.isWindows) {
        _instance = WindowsInstaller();
      } else {
        throw UnsupportedError('Plateforme non supportée pour l\'installation');
      }
    }
    return _instance!;
  }

  /// Alias statiques.
  static Future<bool> ensurePermission() => instance.ensurePermission();
  static Future<void> install(String filePath, {String? downloadUrl}) =>
      instance.install(filePath, downloadUrl: downloadUrl);
}
