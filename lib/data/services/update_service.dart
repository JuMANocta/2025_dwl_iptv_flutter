import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/platform/installer_service.dart';

/// Informations sur une release disponible.
class UpdateInfo {
  final String tagName;     // ex: "v1.2.0"
  final String releaseName; // ex: "AetherStream v1.2.0"
  final String? body;       // Markdown du changelog GitHub
  final String downloadUrl; // URL directe de l'APK
  final int? sizeBytes;

  /// §updateBanner — Version INSTALLÉE, pour la confronter à [tagName].
  ///
  /// Elle était déjà lue (`PackageInfo`) pour décider s'il faut proposer la
  /// mise à jour, mais **jamais renvoyée** : le bandeau annonçait donc une
  /// version cible sans dire de quoi on part.
  final String localVersion;

  /// §updateBanner — Page GitHub de la release (`html_url` du JSON), pour
  /// remplacer le changelog dumpé en texte brut par un lien vers la source.
  final String? htmlUrl;

  const UpdateInfo({
    required this.tagName,
    required this.releaseName,
    this.body,
    required this.downloadUrl,
    this.sizeBytes,
    required this.localVersion,
    this.htmlUrl,
  });
}

/// §userError — Résultat d'une vérification de mise à jour, en trois états.
sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

/// Une version plus récente existe.
class UpdateAvailable extends UpdateCheckResult {
  final UpdateInfo info;
  const UpdateAvailable(this.info);
}

/// La version installée est la dernière publiée.
class UpToDate extends UpdateCheckResult {
  const UpToDate();
}

/// On n'a PAS pu répondre — et [reason] dit pourquoi, en français, sans URL.
class UpdateUnavailable extends UpdateCheckResult {
  final String reason;
  const UpdateUnavailable(this.reason);
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
  /// Silencieux en cas d'erreur réseau (l'utilisateur n'est pas dérangé) —
  /// c'est la forme voulue pour la vérification AUTOMATIQUE du démarrage.
  /// Pour une vérification DEMANDÉE par l'utilisateur, préférer
  /// [checkForUpdateDetailed] : « à jour » et « GitHub injoignable » ne
  /// doivent pas se confondre (§userError, audit 2026-09-03 n°3).
  static Future<UpdateInfo?> checkForUpdate() async {
    final UpdateCheckResult r = await checkForUpdateDetailed();
    return r is UpdateAvailable ? r.info : null;
  }

  /// §userError — Même vérification, mais qui DIT ce qui s'est passé.
  ///
  /// Avant, `null` couvrait quatre cas (à jour, GitHub injoignable, HTTP ≠ 200,
  /// release sans APK) et la page « À propos » répondait « Vous êtes à jour »
  /// aux quatre. Sur une action explicite, c'est un texte qui ment.
  static Future<UpdateCheckResult> checkForUpdateDetailed() async {
    try {
      final response = await http
          .get(Uri.parse(_apiUrl),
              headers: {'Accept': 'application/vnd.github.v3+json'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('⚠️ UpdateService: HTTP ${response.statusCode}');
        return UpdateUnavailable(
            'GitHub a répondu HTTP ${response.statusCode}.');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = data['tag_name'] as String? ?? '';
      final releaseName = data['name'] as String? ?? tagName;
      final body = data['body'] as String?;

      // Cherche l'asset correspondant à la plateforme (.exe pour Windows, .apk pour Android)
      final assets = data['assets'] as List<dynamic>? ?? [];
      final extension = Platform.isWindows ? '.exe' : '.apk';
      final asset = assets.firstWhere(
        (a) => (a['name'] as String?)?.toLowerCase().endsWith(extension) == true,
        orElse: () => null,
      );
      if (asset == null) {
        debugPrint('⚠️ UpdateService: aucun $extension dans la release $tagName');
        return UpdateUnavailable(
            "La dernière release ($tagName) ne contient pas de fichier $extension.");
      }

      final downloadUrl = asset['browser_download_url'] as String? ?? '';
      final sizeBytes = asset['size'] as int?;

      // Lecture version locale
      final info = await PackageInfo.fromPlatform();
      final localVersion = info.version; // ex: "1.2.0"

      debugPrint('🔍 UpdateService: local=$localVersion remote=$tagName');

      if (!_isNewer(tagName, localVersion)) {
        debugPrint('✅ UpdateService: déjà à jour ($localVersion)');
        return const UpToDate();
      }

      return UpdateAvailable(UpdateInfo(
        tagName: tagName,
        releaseName: releaseName,
        body: body,
        downloadUrl: downloadUrl,
        sizeBytes: sizeBytes,
        // §updateBanner — On renvoie le build complet (`1.2.0+45`) : c'est ce
        // qui distingue deux versions au même numéro public.
        localVersion: '${info.version}+${info.buildNumber}',
        htmlUrl: data['html_url'] as String?,
      ));
    } on TimeoutException {
      debugPrint('⚠️ UpdateService: vérification échouée → délai dépassé');
      return const UpdateUnavailable("GitHub n'a pas répondu à temps.");
    } catch (e) {
      debugPrint('⚠️ UpdateService: vérification échouée → $e');
      return const UpdateUnavailable(
          'Impossible de joindre GitHub. Vérifie la connexion.');
    }
  }

  /// Télécharge l'APK et lance l'installation.
  /// [onProgress] reçoit une valeur entre 0.0 et 1.0.
  static Future<void> downloadAndInstall(
    String url, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    // Demander la permission d'installer (spécifique plateforme)
    final hasPermission = await InstallerService.ensurePermission();
    if (!hasPermission) {
      debugPrint('❌ UpdateService: permission d\'installation refusée');
      throw Exception('Permission d\'installation refusée');
    }

    final cacheDir = await getTemporaryDirectory();
    final updatePath = '${cacheDir.path}/aetherstream_update.${Platform.isWindows ? 'exe' : 'apk'}';

    debugPrint('🚀 UpdateService: téléchargement → $url');

    final dio = Dio();
    await dio.download(
      url,
      updatePath,
      cancelToken: cancelToken,
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress?.call(received / total);
      },
    );

    debugPrint('✅ UpdateService: téléchargement terminé → $updatePath');

    // Lance l'installeur via le service multi-plateforme
    await InstallerService.install(updatePath, downloadUrl: url);
    debugPrint('📦 UpdateService: installation lancée');
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  /// Retourne true si [remoteTag] ("v1.2.1") est plus récent que [localVersion] ("1.2.0").
  /// Ignore le build number (+N) de la version locale — la comparaison porte
  /// uniquement sur le triplet majeur.mineur.patch.
  static bool _isNewer(String remoteTag, String localVersion) {
    try {
      // Retire le 'v' initial et le build number éventuel (+N)
      final remoteClean = remoteTag.replaceFirst(RegExp(r'^v'), '').split('+').first;
      final localClean  = localVersion.split('+').first;

      final remote = remoteClean.split('.').map(int.parse).toList();
      final local  = localClean .split('.').map(int.parse).toList();

      debugPrint('🔍 UpdateService: remote=$remoteClean local=$localClean');

      for (int i = 0; i < remote.length; i++) {
        final r = remote[i];
        final l = i < local.length ? local[i] : 0;
        if (r > l) return true;
        if (r < l) return false;
      }
      return false;
    } catch (e) {
      debugPrint('⚠️ UpdateService: comparaison version échouée → $e');
      return false;
    }
  }
}
