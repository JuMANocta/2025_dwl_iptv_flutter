// §updAbi (revue 2026-09-11, lot 9) — Quel APK la mise à jour in-app prend
// dans une release qui en porte TROIS (universel + une split par ABI).
//
// Un mauvais choix ne se rattrape pas chez l'utilisateur : Android REFUSE un
// APK dont le versionCode est inférieur à celui en place, et le plugin Gradle
// de Flutter donne aux splits `codeAbi × 1000 + build` (armeabi-v7a = 1,
// arm64-v8a = 2). Pour le build 152 : universel 152, v7a 1152, arm64 2152.

import 'dart:io';

import 'package:aetherStream/data/services/update_policy.dart';
import 'package:flutter_test/flutter_test.dart';

const String _base =
    'https://github.com/JuMANocta/2025_dwl_iptv_flutter/releases/download/v1.18.19/';

ReleaseAsset _a(String name, {int? size}) =>
    ReleaseAsset(name: name, url: '$_base$name', size: size);

/// Une release telle que `release.yml` la publie.
final List<ReleaseAsset> _full = [
  _a('aetherstream.apk'),
  _a('aetherstream.apk.sha256'),
  _a('aetherstream_arm64-v8a.apk'),
  _a('aetherstream_arm64-v8a.apk.sha256'),
  _a('aetherstream_armeabi-v7a.apk'),
  _a('aetherstream_armeabi-v7a.apk.sha256'),
];

const List<String> _phone64 = ['arm64-v8a', 'armeabi-v7a', 'armeabi'];
const List<String> _stick32 = ['armeabi-v7a', 'armeabi'];

String? _pick(List<ReleaseAsset> assets, List<String> abis, int installed) =>
    chooseUpdateApk(
      assets: assets,
      supportedAbis: abis,
      installedVersionCode: installed,
    )?.name;

void main() {
  group('depuis une installation UNIVERSELLE (versionCode < 1000)', () {
    test('un téléphone 64 bits prend la split arm64', () {
      expect(_pick(_full, _phone64, 151), 'aetherstream_arm64-v8a.apk');
    });

    test('un Fire TV Stick 32 bits prend la split armeabi-v7a', () {
      // L'ordre de SUPPORTED_ABIS décide : un appareil 32 bits n'annonce
      // jamais arm64, et la split arm64 ne s'y installerait pas.
      expect(_pick(_full, _stick32, 151), 'aetherstream_armeabi-v7a.apk');
    });

    test('l\'ordre des fichiers de la release ne décide jamais', () {
      expect(_pick(_full.reversed.toList(), _phone64, 151),
          'aetherstream_arm64-v8a.apk');
      expect(_pick(_full.reversed.toList(), _stick32, 151),
          'aetherstream_armeabi-v7a.apk');
    });

    test('ABI illisibles ou non publiées → l\'universel', () {
      expect(_pick(_full, const [], 151), kUniversalApkName);
      // L'émulateur x86_64 : aucune split publiée pour lui.
      expect(_pick(_full, const ['x86_64'], 151), kUniversalApkName);
    });

    test('une release d\'avant le split (universel seul) reste installable', () {
      expect(_pick([_a('aetherstream.apk')], _phone64, 151), kUniversalApkName);
    });
  });

  group('depuis une installation SPLIT (versionCode ≥ 1000)', () {
    test('une split arm64 reste sur arm64', () {
      expect(_pick(_full, _phone64, 2151), 'aetherstream_arm64-v8a.apk');
    });

    test('JAMAIS l\'universel : 152 < 2151, Android refuserait', () {
      expect(_pick([_a('aetherstream.apk')], _phone64, 2151), isNull);
      expect(_pick([_a('aetherstream.apk')], const [], 1151), isNull);
    });

    test('jamais vers un code d\'ABI plus petit (1152 < 2151)', () {
      final List<ReleaseAsset> sansArm64 = [
        _a('aetherstream.apk'),
        _a('aetherstream_armeabi-v7a.apk'),
      ];
      expect(_pick(sansArm64, _phone64, 2151), isNull);
    });

    test('une split v7a sur un appareil 64 bits peut MONTER vers arm64', () {
      // 2152 > 1151 : permis, et c'est la meilleure build pour l'appareil.
      expect(_pick(_full, _phone64, 1151), 'aetherstream_arm64-v8a.apk');
      expect(_pick(_full, _stick32, 1151), 'aetherstream_armeabi-v7a.apk');
    });
  });

  group('noms et empreintes', () {
    test('la casse d\'un nom de fichier ne compte pas', () {
      final List<ReleaseAsset> upper = [_a('AetherStream_ARM64-v8a.APK')];
      expect(_pick(upper, _phone64, 151), 'AetherStream_ARM64-v8a.APK');
    });

    test('isSplitInstall suit la règle codeAbi × 1000 + build', () {
      expect(isSplitInstall(151), isFalse);
      expect(isSplitInstall(999), isFalse);
      expect(isSplitInstall(1151), isTrue);
      expect(isSplitInstall(2151), isTrue);
    });

    test('chaque APK a SON empreinte, jamais celle d\'un autre', () {
      final ReleaseAsset arm64 = _full[2];
      expect(checksumAssetFor(_full, arm64)?.name,
          'aetherstream_arm64-v8a.apk.sha256');
      expect(checksumAssetFor(_full, _full.first)?.name,
          'aetherstream.apk.sha256');
      expect(checksumAssetFor([arm64, _full[1]], arm64), isNull);
    });

    test('parseSha256Digest lit la sortie de sha256sum', () {
      final String hex = 'ab' * 32;
      expect(parseSha256Digest('$hex  aetherstream.apk\n'), hex);
      expect(parseSha256Digest('\n${hex.toUpperCase()} *aetherstream.apk'), hex);
      expect(parseSha256Digest(''), isNull);
      expect(parseSha256Digest('pas une empreinte'), isNull);
      expect(parseSha256Digest('${'a' * 63}  f.apk'), isNull);
    });

    test('ReleaseAsset.fromJson ignore un élément mal formé sans lever', () {
      expect(ReleaseAsset.fromJson(null), isNull);
      expect(ReleaseAsset.fromJson({'name': 'x.apk'}), isNull);
      final ReleaseAsset? ok = ReleaseAsset.fromJson({
        'name': 'aetherstream.apk',
        'browser_download_url': '${_base}aetherstream.apk',
        'size': 31457280,
      });
      expect(ok?.size, 31457280);
      expect(ReleaseAsset.fromJson({
        'name': 'a.apk',
        'browser_download_url': '${_base}a.apk',
        'size': '12',
      })?.size, isNull);
    });
  });

  group('D1B-08 — on n\'installe que depuis les releases de CE dépôt', () {
    test('une URL de release en HTTPS passe', () {
      expect(isTrustedReleaseDownloadUrl('${_base}aetherstream.apk'), isTrue);
      // Casse du propriétaire : GitHub l'ignore, nous aussi.
      expect(
          isTrustedReleaseDownloadUrl(
              'https://github.com/jumanocta/2025_DWL_IPTV_FLUTTER/releases/download/v1/a.apk'),
          isTrue);
    });

    test('tout le reste est refusé', () {
      expect(isTrustedReleaseDownloadUrl('http://github.com/JuMANocta/'
          '2025_dwl_iptv_flutter/releases/download/v1/a.apk'), isFalse);
      expect(isTrustedReleaseDownloadUrl('https://evil.example/JuMANocta/'
          '2025_dwl_iptv_flutter/releases/download/v1/a.apk'), isFalse);
      expect(isTrustedReleaseDownloadUrl('https://github.com/autre/'
          '2025_dwl_iptv_flutter/releases/download/v1/a.apk'), isFalse);
      expect(isTrustedReleaseDownloadUrl('https://github.com/JuMANocta/'
          '2025_dwl_iptv_flutter/archive/refs/heads/master.zip'), isFalse);
      expect(isTrustedReleaseDownloadUrl('pas une url'), isFalse);
      expect(isTrustedReleaseDownloadUrl(''), isFalse);
    });
  });

  // ⚠️ Le contrat entre la CI et l'app : si `release.yml` renomme un APK, la
  // mise à jour ne le trouve plus — et on ne le verrait qu'après publication.
  test('release.yml publie les noms que la mise à jour cherche, universel EN PREMIER', () {
    final String yml = File('.github/workflows/release.yml').readAsStringSync();
    final List<String> published = RegExp(r'^\s+(aetherstream[\w.-]*\.apk)\s*$',
            multiLine: true)
        .allMatches(yml)
        .map((m) => m.group(1)!)
        .toList();
    expect(published, contains(kUniversalApkName));
    expect(published, contains(splitApkNameFor('arm64-v8a')));
    expect(published, contains(splitApkNameFor('armeabi-v7a')));
    // Les versions déjà installées prennent le PREMIER `.apk` de la release :
    // ce doit être l'universel, le seul qui s'installe partout.
    expect(published.first, kUniversalApkName);
    for (final String apk in published) {
      expect(yml, contains('$apk.sha256'), reason: 'empreinte de $apk');
    }
  });

  // Relecture revue 2026-09-11, lot 9 — L'ordre du YAML ne suffit PAS : l'API
  // GitHub rend les `assets[]` TRIÉS PAR NOM (octet par octet), pas dans
  // l'ordre de téléversement (mesuré sur cli/cli et ripgrep). Ce test rejoue
  // ce tri et ce que font les versions ≤ 1.18.18 : « premier `.apk` venu ».
  // Avec des splits nommées `aetherstream-<abi>.apk`, il prenait la split
  // arm64 (« - » 0x2D < « . » 0x2E) — et un Fire TV Stick 32 bits ne peut pas
  // l'installer.
  test('trié par NOM comme le rend l\'API, le premier .apk reste l\'universel', () {
    final List<String> names = [
      for (final String abi in kAbiVersionCodes.keys) ...[
        splitApkNameFor(abi),
        '${splitApkNameFor(abi)}.sha256',
      ],
      '$kUniversalApkName.sha256',
      kUniversalApkName,
    ]..sort(); // String.compareTo : ordre des unités de code, comme l'API.
    final String firstApk = names.firstWhere((n) => n.endsWith('.apk'));
    expect(firstApk, kUniversalApkName);
    // Et le piège existe bien : le nom avec tiret passait devant.
    final List<String> withDash = ['aetherstream-arm64-v8a.apk', kUniversalApkName]
      ..sort();
    expect(withDash.first, isNot(kUniversalApkName));
  });
}
