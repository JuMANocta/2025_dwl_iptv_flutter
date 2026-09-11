/// §updAbi (revue 2026-09-11, lot 9) — Les règles PURES de la mise à jour
/// in-app : quel APK prendre dans une release, et quand la proposer.
///
/// **Pourquoi ce fichier existe.** Jusqu'ici une release ne portait qu'UN APK
/// (`aetherstream.apk`, universel armeabi-v7a + arm64-v8a) et `UpdateService`
/// prenait « le premier `.apk` venu ». Le build de production publie désormais
/// un APK PAR ABI (`--split-per-abi`, ~moitié du poids) plus l'universel,
/// gardé pour les versions déjà installées qui, elles, continueront de prendre
/// le premier `.apk` de la liste — d'où le nom des splits, cf.
/// [splitApkNameFor]. Choisir le bon fichier n'est plus trivial, et
/// un mauvais choix ne se rattrape pas côté utilisateur : Android REFUSE
/// d'installer un APK dont le versionCode est plus petit que celui en place.
///
/// ⚠️ **Le versionCode d'une split n'est pas celui du pubspec.** Le plugin
/// Gradle de Flutter le réécrit en `codeAbi × 1000 + build`
/// (`FlutterPlugin.kt`, `FlutterPluginConstants.ABI_VERSION` : armeabi-v7a = 1,
/// arm64-v8a = 2, x86_64 = 4). Donc, pour le build 152 :
///   universel 152 · armeabi-v7a 1152 · arm64-v8a 2152.
/// D'où les deux règles de [chooseUpdateApk] :
///   1. une installation UNIVERSELLE (versionCode < 1000) peut passer à
///      n'importe quelle split (≥ 1000) ou rester sur l'universel ;
///   2. une installation SPLIT ne peut JAMAIS revenir à l'universel (152 <
///      2151 : rétrogradation refusée), ni descendre vers une ABI de code plus
///      petit (1152 < 2151).
///
/// ⚠️ Invariant hors de ce fichier : le build du pubspec doit rester < 1000.
/// Au-delà, « versionCode ≥ 1000 » ne voudrait plus dire « split », et les
/// splits de deux ABI finiraient par se chevaucher.
///
/// Rien ici ne touche au réseau ni à la plateforme : tout est testé dans
/// `test/update_asset_choice_test.dart` et `test/update_version_compare_test.dart`.
library;

import 'package:flutter/foundation.dart';

/// Un fichier attaché à une release GitHub (`assets[]` de l'API).
@immutable
class ReleaseAsset {
  final String name;

  /// `browser_download_url` — l'URL publique, qui redirige vers le stockage.
  final String url;

  /// Taille annoncée par GitHub, en octets (`size`). Sert à refuser un
  /// téléchargement tronqué AVANT l'installeur (D1B-08).
  final int? size;

  const ReleaseAsset({required this.name, required this.url, this.size});

  /// Lecture tolérante d'un élément de `assets[]` : un champ absent ou d'un
  /// type inattendu rend `null` (l'élément est ignoré), jamais une exception.
  static ReleaseAsset? fromJson(Object? json) {
    if (json is! Map) return null;
    final Object? name = json['name'];
    final Object? url = json['browser_download_url'];
    if (name is! String || name.isEmpty || url is! String || url.isEmpty) {
      return null;
    }
    final Object? size = json['size'];
    return ReleaseAsset(name: name, url: url, size: size is int ? size : null);
  }

  @override
  String toString() => 'ReleaseAsset($name)';
}

/// Nom de l'APK universel. C'est aussi le SEUL nom qu'ont connu les releases
/// d'avant le split : le garder à l'identique est ce qui permet aux versions
/// déjà installées de continuer à se mettre à jour.
const String kUniversalApkName = 'aetherstream.apk';

/// Au-delà de ce versionCode, l'installation courante est une split.
const int kSplitVersionCodeBase = 1000;

/// Codes d'ABI du plugin Gradle de Flutter (`FlutterPluginConstants.ABI_VERSION`).
/// ⚠️ À garder aligné sur le SDK : ce sont eux qui font le versionCode des
/// splits. (Le 3 était x86, retiré du SDK.)
const Map<String, int> kAbiVersionCodes = {
  'armeabi-v7a': 1,
  'arm64-v8a': 2,
  'x86_64': 4,
};

/// Nom de l'APK d'une ABI tel que la CI le publie (`release.yml`).
///
/// ⚠️ Séparateur `_`, JAMAIS `-` (relecture revue 2026-09-11, lot 9). L'API
/// GitHub rend les `assets[]` d'une release TRIÉS PAR NOM, octet par octet,
/// et non dans l'ordre de téléversement — mesuré le 2026-09-11 sur
/// `releases/latest` de cli/cli et BurntSushi/ripgrep (identifiants dans le
/// désordre, noms dans l'ordre). Or les versions ≤ 1.18.18 prennent le PREMIER
/// `.apk` de la liste : avec `aetherstream-arm64-v8a.apk`, le `-` (0x2D) passe
/// avant le `.` (0x2E) de `aetherstream.apk`, et un Fire TV Stick 32 bits
/// aurait téléchargé une split arm64 qu'il ne peut pas installer. Le `_`
/// (0x5F) range l'universel EN PREMIER quel que soit l'ordre d'envoi.
String splitApkNameFor(String abi) => 'aetherstream_$abi.apk';

/// Vrai si le versionCode installé est celui d'une split (cf. en-tête).
bool isSplitInstall(int installedVersionCode) =>
    installedVersionCode >= kSplitVersionCodeBase;

/// L'APK à télécharger pour cet appareil, ou `null` si la release n'en
/// contient aucun d'installable.
///
/// [supportedAbis] est `Build.SUPPORTED_ABIS` (`device_info_plus`), dans
/// l'ordre de préférence de l'appareil — un Fire TV Stick en 32 bits annonce
/// `armeabi-v7a` seul, un téléphone récent `arm64-v8a` d'abord. C'est cet
/// ordre qui décide, jamais l'ordre des fichiers de la release.
///
/// [installedVersionCode] est `PackageInfo.buildNumber` : sur une split il
/// vaut `codeAbi × 1000 + build`, ce qui suffit à retrouver l'ABI en place.
ReleaseAsset? chooseUpdateApk({
  required List<ReleaseAsset> assets,
  required List<String> supportedAbis,
  required int installedVersionCode,
}) {
  final Map<String, ReleaseAsset> byName = {
    for (final ReleaseAsset a in assets) a.name.toLowerCase(): a,
  };
  final bool split = isSplitInstall(installedVersionCode);
  final int installedAbiCode =
      split ? installedVersionCode ~/ kSplitVersionCodeBase : 0;

  for (final String abi in supportedAbis) {
    final int? code = kAbiVersionCodes[abi];
    if (code == null) continue; // ABI que la CI ne publie pas (armeabi, x86…)
    // ⚠️ Une split ne descend jamais vers un code d'ABI plus petit : son
    // versionCode serait inférieur à celui en place, Android refuserait.
    if (split && code < installedAbiCode) continue;
    final ReleaseAsset? apk = byName[splitApkNameFor(abi)];
    if (apk != null) return apk;
  }

  // Repli universel — SEULEMENT depuis une installation universelle.
  if (!split) return byName[kUniversalApkName];
  return null;
}

/// L'empreinte publiée à côté d'un APK (`<nom>.sha256`, produite par la CI
/// avec `sha256sum`), ou `null` si la release n'en porte pas.
ReleaseAsset? checksumAssetFor(List<ReleaseAsset> assets, ReleaseAsset apk) {
  final String wanted = '${apk.name}.sha256'.toLowerCase();
  for (final ReleaseAsset a in assets) {
    if (a.name.toLowerCase() == wanted) return a;
  }
  return null;
}

final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

/// Le condensé d'un fichier `sha256sum` (« `<64 hex>  <nom>` »), en
/// minuscules, ou `null` si le contenu n'en contient pas un valide.
String? parseSha256Digest(String content) {
  for (final String line in content.split('\n')) {
    final String t = line.trim();
    if (t.isEmpty) continue;
    final String first = t.split(RegExp(r'\s+')).first.toLowerCase();
    return _hex64.hasMatch(first) ? first : null;
  }
  return null;
}

/// Préfixe des seuls téléchargements acceptés : les fichiers attachés aux
/// releases de CE dépôt. GitHub redirige ensuite vers son stockage, ce que
/// Dio suit ; on valide l'URL de départ, celle que l'API nous a donnée.
const String _kReleasePathPrefix =
    '/jumanocta/2025_dwl_iptv_flutter/releases/download/';

/// D1B-08 — Vrai si [url] est un fichier de release de ce dépôt, en HTTPS.
/// Une réponse d'API altérée ne peut pas nous faire installer autre chose.
bool isTrustedReleaseDownloadUrl(String url) {
  final Uri? u = Uri.tryParse(url);
  if (u == null || u.scheme != 'https' || u.host.toLowerCase() != 'github.com') {
    return false;
  }
  // Les noms d'utilisateur et de dépôt sont insensibles à la casse côté GitHub.
  return u.path.toLowerCase().startsWith(_kReleasePathPrefix);
}

/// D5A-14 — Vrai si [remoteTag] (« v1.2.1 ») est plus récent que
/// [localVersion] (« 1.2.0 » ou « 1.2.0+45 »).
///
/// Le build (`+N`) est ignoré des deux côtés : la comparaison porte sur le
/// triplet majeur.mineur.patch. Un tag illisible rend `false` — ne rien
/// proposer vaut mieux que proposer une rétrogradation.
///
/// ⚠️ Comportement repris À L'IDENTIQUE de l'ancien `UpdateService._isNewer`
/// (sorti ici pour être testé) : ne pas « l'améliorer » sans un test qui dise
/// pourquoi.
bool isNewerVersion(String remoteTag, String localVersion) {
  try {
    final String remoteClean =
        remoteTag.replaceFirst(RegExp(r'^v'), '').split('+').first;
    final String localClean = localVersion.split('+').first;

    final List<int> remote = remoteClean.split('.').map(int.parse).toList();
    final List<int> local = localClean.split('.').map(int.parse).toList();

    for (int i = 0; i < remote.length; i++) {
      final int r = remote[i];
      final int l = i < local.length ? local[i] : 0;
      if (r > l) return true;
      if (r < l) return false;
    }
    return false;
  } catch (e) {
    debugPrint('⚠️ UpdateService: comparaison version échouée → $e');
    return false;
  }
}
