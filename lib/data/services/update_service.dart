import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/platform/installer_service.dart';
import '../../core/utils/user_error.dart';
import '../../l10n/l10n_ext.dart';
import 'update_policy.dart';

/// Informations sur une release disponible.
class UpdateInfo {
  final String tagName;     // ex: "v1.2.0"
  final String releaseName; // ex: "AetherStream v1.2.0"
  final String? body;       // Markdown du changelog GitHub
  final String downloadUrl; // URL directe de l'APK
  final int? sizeBytes;

  /// §updAbi — Nom de l'APK retenu pour CET appareil (`aetherstream_<abi>.apk`
  /// ou l'universel), cf. [chooseUpdateApk].
  final String assetName;

  /// §updAbi — URL du `<apk>.sha256` publié par la CI. L'APK n'est passé à
  /// l'installeur qu'après comparaison de son empreinte avec celle-ci.
  final String sha256Url;

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
    required this.assetName,
    required this.sha256Url,
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
            L10n.current.updGithubHttp(response.statusCode));
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = data['tag_name'] as String? ?? '';
      final releaseName = data['name'] as String? ?? tagName;
      final body = data['body'] as String?;


      // Lecture version locale
      final info = await PackageInfo.fromPlatform();
      final localVersion = info.version; // ex: "1.2.0"

      debugPrint('🔍 UpdateService: local=$localVersion remote=$tagName');

      // §updAbi — La version AVANT les fichiers : une release déjà installée
      // qui n'aurait pas d'APK pour cet appareil n'est pas une panne, c'est
      // « à jour ».
      if (!isNewerVersion(tagName, localVersion)) {
        debugPrint('✅ UpdateService: déjà à jour ($localVersion)');
        return const UpToDate();
      }

      final List<ReleaseAsset> assets =
          (data['assets'] as List<dynamic>? ?? const [])
              .map(ReleaseAsset.fromJson)
              .whereType<ReleaseAsset>()
              .toList();
      if (Platform.isWindows) {
        final ReleaseAsset? exe = assets
            .where((a) => a.name.toLowerCase().endsWith('.exe'))
            .firstOrNull;
        if (exe == null) {
          debugPrint('⚠️ UpdateService: aucun .exe dans la release $tagName');
          return UpdateUnavailable('No .exe installer found in release $tagName');
        }
        return UpdateAvailable(UpdateInfo(
          tagName: tagName,
          releaseName: releaseName,
          body: body,
          downloadUrl: exe.url,
          sizeBytes: exe.size,
          assetName: exe.name,
          sha256Url: '',
          localVersion: '${info.version}+${info.buildNumber}',
          htmlUrl: data['html_url'] as String?,
        ));
      }

      if (!assets.any((a) => a.name.toLowerCase().endsWith('.apk'))) {
        debugPrint('⚠️ UpdateService: aucun APK dans la release $tagName');
        return UpdateUnavailable(L10n.current.updNoApk(tagName));
      }

      // §updAbi — L'APK de CET appareil : la split de son ABI si la release
      // en porte une, l'universel seulement depuis une installation
      // universelle (cf. `update_policy.dart` — une split installée ne peut
      // pas redescendre à l'universel, Android refuserait).
      final int installedCode = int.tryParse(info.buildNumber) ?? 0;
      final List<String> abis = await _supportedAbis();
      final ReleaseAsset? apk = chooseUpdateApk(
        assets: assets,
        supportedAbis: abis,
        installedVersionCode: installedCode,
      );
      if (apk == null) {
        debugPrint('⚠️ UpdateService: aucun APK installable dans $tagName '
            '(ABI $abis, versionCode $installedCode)');
        return UpdateUnavailable(L10n.current.updNoApkForDevice(tagName));
      }

      // D1B-08 — Jamais d'installation sans empreinte ni hors des releases de
      // ce dépôt : on ne PROPOSE pas ce qu'on refuserait d'installer.
      final ReleaseAsset? checksum = checksumAssetFor(assets, apk);
      if (checksum == null ||
          !isTrustedReleaseDownloadUrl(apk.url) ||
          !isTrustedReleaseDownloadUrl(checksum.url)) {
        debugPrint('⚠️ UpdateService: ${apk.name} invérifiable '
            '(empreinte ${checksum == null ? 'absente' : 'présente'})');
        return UpdateUnavailable(L10n.current.updUnverifiable);
      }
      debugPrint('📦 UpdateService: APK retenu → ${apk.name} (ABI $abis)');

      return UpdateAvailable(UpdateInfo(
        tagName: tagName,
        releaseName: releaseName,
        body: body,
        downloadUrl: apk.url,
        sizeBytes: apk.size,
        assetName: apk.name,
        sha256Url: checksum.url,
        // §updateBanner — On renvoie le build complet (`1.2.0+45`) : c'est ce
        // qui distingue deux versions au même numéro public.
        localVersion: '${info.version}+${info.buildNumber}',
        htmlUrl: data['html_url'] as String?,
      ));
    } on TimeoutException {
      debugPrint('⚠️ UpdateService: vérification échouée → délai dépassé');
      return UpdateUnavailable(L10n.current.updTimeout);
    } catch (e) {
      debugPrint('⚠️ UpdateService: vérification échouée → $e');
      return UpdateUnavailable(L10n.current.updUnreachable);
    }
  }

  /// Télécharge l'APK et lance l'installation.
  /// [onProgress] reçoit une valeur entre 0.0 et 1.0.
  ///
  /// D1B-08 / §updAbi — L'APK n'atteint l'installeur qu'après DEUX contrôles :
  /// sa taille (celle annoncée par GitHub) et son empreinte SHA-256 (le
  /// `.sha256` publié par la CI). Avant, un fichier tronqué par une coupure
  /// partait tel quel à l'installeur, qui répondait par une erreur d'analyse
  /// sans explication. Tout échec lève une [UserFacingException] : le dialogue
  /// l'affiche par `describeError`, jamais par `toString()`.
  static Future<void> downloadAndInstall(
    UpdateInfo update, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    // Demander la permission d'installer (spécifique plateforme)
    final hasPermission = await InstallerService.ensurePermission();
    if (!hasPermission) {
      debugPrint('❌ UpdateService: permission d\'installation refusée');
      throw UserFacingException(L10n.current.updInstallDenied);
    }

    // Défense en profondeur : l'objet vient de [checkForUpdateDetailed], qui a
    // déjà filtré — mais c'est ICI qu'on installe.
    if (!isTrustedReleaseDownloadUrl(update.downloadUrl)) {
      throw UserFacingException(L10n.current.updUnverifiable);
    }
    if (Platform.isAndroid && !isTrustedReleaseDownloadUrl(update.sha256Url)) {
      throw UserFacingException(L10n.current.updUnverifiable);
    }

    // §security — revue 2026-09-11, D2B-12 — L'APK vit dans `cache/updates/`,
    // le SEUL dossier que le FileProvider rend partageable (`file_paths.xml`)
    // et que le canal `install_apk` accepte.
    final cacheDir = await getTemporaryDirectory();
    final updatesDir = Directory('${cacheDir.path}/updates');
    await updatesDir.create(recursive: true);
    final ext = Platform.isWindows ? 'exe' : 'apk';
    final targetPath = '${updatesDir.path}/aetherstream_update.$ext';
    final File targetFile = File(targetPath);
    // Ancien emplacement (racine du cache) : plus jamais relu.
    try {
      final legacyFile = File('${cacheDir.path}/aetherstream_update.$ext');
      if (await legacyFile.exists()) await legacyFile.delete();
    } catch (_) {/* le système videra le cache */}

    debugPrint('🚀 UpdateService: téléchargement → ${update.assetName}');

    // D1B-08 — `Dio()` nu n'avait AUCUN délai : un GitHub qui cesse de
    // répondre laissait le dialogue sur « DOWNLOADING… » pour toujours.
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 2),
    ));

    String? expectedSha;
    if (Platform.isAndroid && update.sha256Url.isNotEmpty) {
      // L'empreinte D'ABORD : quelques octets, et sans elle on n'installera pas
      final Response<String> shaResponse = await dio.get<String>(
        update.sha256Url,
        cancelToken: cancelToken,
        options: Options(responseType: ResponseType.plain),
      );
      expectedSha = parseSha256Digest(shaResponse.data ?? '');
      if (expectedSha == null) {
        debugPrint('❌ UpdateService: empreinte illisible pour ${update.assetName}');
        throw UserFacingException(L10n.current.updUnverifiable);
      }
    }

    // Un reste d'une tentative précédente ne doit jamais être installé.
    if (await targetFile.exists()) await targetFile.delete();
    await dio.download(
      update.downloadUrl,
      targetPath,
      cancelToken: cancelToken,
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress?.call(received / total);
      },
    );

    final int actualSize = await targetFile.length();
    final int? expectedSize = update.sizeBytes;
    if (expectedSize != null && actualSize != expectedSize) {
      debugPrint('❌ UpdateService: taille $actualSize ≠ $expectedSize annoncés');
      await _discard(targetFile);
      throw UserFacingException(L10n.current.updCorrupted);
    }
    if (expectedSha != null) {
      final Digest actualSha = await sha256.bind(targetFile.openRead()).first;
      if (actualSha.toString() != expectedSha) {
        debugPrint('❌ UpdateService: empreinte ${actualSha.toString()} ≠ '
            '$expectedSha attendue');
        await _discard(targetFile);
        throw UserFacingException(L10n.current.updCorrupted);
      }
      debugPrint('✅ UpdateService: téléchargement vérifié (SHA-256) → $targetPath');
    } else {
      debugPrint('✅ UpdateService: téléchargement terminé → $targetPath');
    }

    // Lance l'installeur via le service multi-plateforme
    await InstallerService.install(targetPath, downloadUrl: update.downloadUrl);
    debugPrint('📦 UpdateService: installation lancée');
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  /// §updAbi — ABI de l'appareil, dans SON ordre de préférence
  /// (`Build.SUPPORTED_ABIS`). Vide si illisible : [chooseUpdateApk] retombe
  /// alors sur l'universel quand c'est permis.
  static Future<List<String>> _supportedAbis() async {
    if (!Platform.isAndroid) return const [];
    try {
      final AndroidDeviceInfo info = await DeviceInfoPlugin().androidInfo;
      return info.supportedAbis;
    } catch (e) {
      debugPrint('⚠️ UpdateService: ABI illisibles → $e');
      return const [];
    }
  }

  static Future<void> _discard(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('⚠️ UpdateService: suppression de l\'APK rejeté impossible → $e');
    }
  }
}
