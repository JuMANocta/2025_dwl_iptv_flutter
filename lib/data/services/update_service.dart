import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Informations sur une release disponible.
class UpdateInfo {
  final String tagName;     // ex: "v1.2.0"
  final String releaseName; // ex: "AetherStream v1.2.0"
  final String? body;       // Markdown du changelog GitHub
  final String downloadUrl; // URL directe de l'APK
  final int? sizeBytes;

  const UpdateInfo({
    required this.tagName,
    required this.releaseName,
    this.body,
    required this.downloadUrl,
    this.sizeBytes,
  });
}

/// Service de mise à jour in-app via GitHub Releases.
///
/// Flow :
/// 1. [checkForUpdate] → compare la version locale avec le dernier tag GitHub
/// 2. Si plus récent → retourne [UpdateInfo]
/// 3. [downloadAndInstall] → Dio stream vers cache → FileProvider + MethodChannel → Android installe
class UpdateService {
  static const _apiUrl =
      'https://api.github.com/repos/JuMANocta/2025_dwl_iptv_flutter/releases/latest';

  // -------------------------------------------------------------------------
  // API publique
  // -------------------------------------------------------------------------

  /// Vérifie si une mise à jour est disponible.
  /// Retourne [UpdateInfo] si une version plus récente existe, null sinon.
  /// Silencieux en cas d'erreur réseau (l'utilisateur n'est pas dérangé).
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final response = await http
          .get(Uri.parse(_apiUrl),
              headers: {'Accept': 'application/vnd.github.v3+json'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('⚠️ UpdateService: HTTP ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = data['tag_name'] as String? ?? '';
      final releaseName = data['name'] as String? ?? tagName;
      final body = data['body'] as String?;

      // Cherche l'asset nommé "aetherstream.apk"
      final assets = data['assets'] as List<dynamic>? ?? [];
      final apkAsset = assets.firstWhere(
        (a) => (a['name'] as String?)?.toLowerCase().endsWith('.apk') == true,
        orElse: () => null,
      );
      if (apkAsset == null) {
        debugPrint('⚠️ UpdateService: aucun APK dans la release $tagName');
        return null;
      }

      final downloadUrl = apkAsset['browser_download_url'] as String? ?? '';
      final sizeBytes = apkAsset['size'] as int?;

      // Lecture version locale
      final info = await PackageInfo.fromPlatform();
      final localVersion = info.version; // ex: "1.2.0"

      debugPrint('🔍 UpdateService: local=$localVersion remote=$tagName');

      if (!_isNewer(tagName, localVersion)) {
        debugPrint('✅ UpdateService: déjà à jour ($localVersion)');
        return null;
      }

      return UpdateInfo(
        tagName: tagName,
        releaseName: releaseName,
        body: body,
        downloadUrl: downloadUrl,
        sizeBytes: sizeBytes,
      );
    } catch (e) {
      debugPrint('⚠️ UpdateService: vérification échouée → $e');
      return null;
    }
  }

  /// Télécharge l'APK et lance l'installation Android.
  /// [onProgress] reçoit une valeur entre 0.0 et 1.0.
  static Future<void> downloadAndInstall(
    String url, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    // Android 8+ : demander la permission d'installer des APKs inconnus
    if (Platform.isAndroid) {
      final status = await Permission.requestInstallPackages.status;
      if (status.isDenied) {
        final result = await Permission.requestInstallPackages.request();
        if (!result.isGranted) {
          debugPrint('❌ UpdateService: permission REQUEST_INSTALL_PACKAGES refusée');
          throw Exception('Permission d\'installation refusée');
        }
      }
    }

    final cacheDir = await getTemporaryDirectory();
    final apkPath = '${cacheDir.path}/aetherstream_update.apk';

    debugPrint('🚀 UpdateService: téléchargement → $url');

    final dio = Dio();
    await dio.download(
      url,
      apkPath,
      cancelToken: cancelToken,
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress?.call(received / total);
      },
    );

    debugPrint('✅ UpdateService: téléchargement terminé → $apkPath');

    // Lance l'installeur Android via le MethodChannel (FileProvider → content://)
    const channel = MethodChannel('aetherstream/install_apk');
    await channel.invokeMethod('install', {'path': apkPath});
    debugPrint('📦 UpdateService: installation APK lancée');
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  /// Retourne true si [remoteTag] ("v1.2.1") est plus récent que [localVersion] ("1.2.0").
  static bool _isNewer(String remoteTag, String localVersion) {
    try {
      final remote = remoteTag
          .replaceFirst('v', '')
          .split('.')
          .map(int.parse)
          .toList();
      final local = localVersion.split('.').map(int.parse).toList();
      for (int i = 0; i < remote.length; i++) {
        final r = remote[i];
        final l = i < local.length ? local[i] : 0;
        if (r > l) return true;
        if (r < l) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
