import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'installer_service.dart';

class AndroidInstaller implements PlatformInstaller {
  @override
  Future<bool> ensurePermission() async {
    final status = await Permission.requestInstallPackages.status;
    if (status.isDenied) {
      final result = await Permission.requestInstallPackages.request();
      return result.isGranted;
    }
    return status.isGranted;
  }

  @override
  Future<void> install(String filePath, {String? downloadUrl}) async {
    const channel = MethodChannel('aetherstream/install_apk');
    await channel.invokeMethod('install', {'path': filePath});
  }
}
