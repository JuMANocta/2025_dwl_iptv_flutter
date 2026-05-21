import 'package:url_launcher/url_launcher.dart';
import 'installer_service.dart';

class WindowsInstaller implements PlatformInstaller {
  static const _releasesUrl = 'https://github.com/JuMANocta/2025_dwl_iptv_flutter/releases/latest';

  @override
  Future<bool> ensurePermission() async {
    // Pas de permission spécifique au runtime sur Windows pour lancer un navigateur ou un process.
    return true;
  }

  @override
  Future<void> install(String filePath, {String? downloadUrl}) async {
    // Pour l'instant, on redirige vers les releases GitHub sur Windows.
    // L'utilisateur pourra télécharger et lancer l'installeur manuellement.
    final uri = Uri.parse(downloadUrl ?? _releasesUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
