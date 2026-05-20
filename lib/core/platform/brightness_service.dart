import 'dart:io' show Platform;
import 'brightness_android.dart';
import 'brightness_windows.dart';

/// Interface pour la gestion de la luminosité de l'écran
/// de manière multi-plateforme.
abstract class PlatformBrightness {
  /// Retourne la luminosité actuelle de l'écran (0.0 à 1.0).
  Future<double> get current;

  /// Définit la luminosité de l'écran (0.0 à 1.0).
  Future<void> set(double value);

  /// Réinitialise la luminosité aux paramètres système.
  Future<void> reset();
}

/// Point d'accès unique pour les services de luminosité.
class BrightnessService {
  static PlatformBrightness? _instance;

  static PlatformBrightness get instance {
    if (_instance == null) {
      if (Platform.isAndroid) {
        _instance = AndroidBrightness();
      } else if (Platform.isWindows) {
        _instance = WindowsBrightness();
      } else {
        throw UnsupportedError('Plateforme non supportée pour la luminosité');
      }
    }
    return _instance!;
  }

  /// Alias statiques.
  static Future<double> get current => instance.current;
  static Future<void> set(double value) => instance.set(value);
  static Future<void> reset() => instance.reset();
}
