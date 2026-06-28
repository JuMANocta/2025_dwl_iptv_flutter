import 'dart:io';
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
    final file = File(filePath);
    if (await file.exists()) {
      try {
        // Lance l'installeur (.exe) de manière détachée
        await Process.start(
          filePath,
          [],
          mode: ProcessStartMode.detached,
        );
        // Quitte immédiatement l'application pour libérer AetherStream.exe
        exit(0);
      } catch (e) {
        // Si l'exécution échoue, fallback sur l'ouverture du lien dans le navigateur
        final uri = Uri.parse(downloadUrl ?? _releasesUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } else {
      final uri = Uri.parse(downloadUrl ?? _releasesUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }
}
