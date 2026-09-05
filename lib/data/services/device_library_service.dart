// §dlOrphans (2026-09-05) — Les fichiers présents sur l'appareil mais absents
// de la liste des téléchargements.
//
// **Le défaut, mesuré** (Galaxy S25, 2026-09-04) : `/Movies/AetherStream/`
// contenait 5 films (8,5 Go), la page Téléchargements n'en montrait qu'un,
// annulé, avec « Terminés 0 ». Les téléchargements finissent dans MediaStore,
// la page ne lit que les `DownloadTask` de SharedPreferences, et les deux
// divergent : vidage des données, réinstallation, tâche basculée en `failed`
// par la réconciliation alors que le fichier était complet.
//
// **Miroir de §acctPurge, pas son doublon.** §acctPurge EFFACE des fichiers
// sans propriétaire dans le cache privé ; ici on MONTRE des fichiers complets
// et légitimes du dossier public. Jamais de suppression d'office — un fichier
// de `/Movies/AetherStream/` peut avoir été déposé là par l'utilisateur.
//
// **Déclenchement MANUEL** (décision utilisateur, 2026-09-04) : un bouton ⟳
// dans la page, pas un balayage à chaque ouverture. Le résultat est mémorisé
// pour survivre à la fermeture de la page.
//
// ⚠️ L'inventaire passe par MediaStore (canal natif `aetherstream/media`),
// pas par `Directory.list()` : sur Android 10+, le dossier public n'est pas
// lisible par chemin pour les fichiers d'une autre origine — et une
// réinstallation change l'origine.

import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/download_task.dart';

/// Une vidéo du dossier public, telle que MediaStore la décrit.
class DeviceVideo {
  /// `content://media/external/video/media/{id}` — la clé de suppression.
  final String uri;

  /// Nom de fichier avec extension (`DISPLAY_NAME`).
  final String name;

  /// Chemin absolu (`DATA`) — c'est lui que le lecteur ouvre.
  final String path;
  final int size;
  final DateTime modifiedAt;

  const DeviceVideo({
    required this.uri,
    required this.name,
    required this.path,
    required this.size,
    required this.modifiedAt,
  });

  /// Le nom sans extension, pour l'affichage.
  String get title {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  Map<String, dynamic> toJson() => {
        'u': uri,
        'n': name,
        'p': path,
        's': size,
        'm': modifiedAt.millisecondsSinceEpoch,
      };

  static DeviceVideo fromJson(Map<String, dynamic> j) => DeviceVideo(
        uri: j['u'] as String,
        name: j['n'] as String,
        path: j['p'] as String,
        size: (j['s'] as num?)?.toInt() ?? 0,
        modifiedAt:
            DateTime.fromMillisecondsSinceEpoch((j['m'] as num?)?.toInt() ?? 0),
      );
}

/// Ce qu'un balayage a donné — pour l'annoncer (§userError : un bouton qui ne
/// dit rien se lit comme une panne).
class DeviceScanResult {
  final List<DeviceVideo> orphans;
  final bool permissionDenied;
  const DeviceScanResult(this.orphans, {this.permissionDenied = false});

  int get totalBytes => orphans.fold<int>(0, (a, v) => a + v.size);
}

abstract final class DeviceLibraryService {
  static const MethodChannel _channel = MethodChannel('aetherstream/media');
  static const String _prefsKey = 'device_videos_v1';

  /// Le dossier des téléchargements, tel que `DownloadManagerService` le
  /// nomme dans MediaStore.
  static const String relativePath = 'Movies/AetherStream/';

  /// Les orphelins du dernier balayage (mémorisés entre deux lancements).
  static final ValueNotifier<List<DeviceVideo>> videos =
      ValueNotifier<List<DeviceVideo>>(const []);
  static final ValueNotifier<bool> scanning = ValueNotifier<bool>(false);

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List)
          .whereType<Map<String, dynamic>>()
          .map(DeviceVideo.fromJson)
          .toList();
      videos.value = list;
    } catch (e) {
      debugPrint('⚠️ DeviceLibraryService.init : $e');
    }
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKey, jsonEncode(videos.value.map((v) => v.toJson()).toList()));
    } catch (e) {
      debugPrint('⚠️ DeviceLibraryService._persist : $e');
    }
  }

  /// **La règle, pure et testée** : un fichier est orphelin s'il n'est le
  /// résultat d'aucune tâche TERMINÉE. Une tâche `failed` ou `canceled` dont
  /// le fichier existe pourtant complet est précisément le cas mesuré — le
  /// fichier doit remonter, la tâche ne sait pas le lire.
  static List<DeviceVideo> orphansOf(
    List<DeviceVideo> files,
    Iterable<DownloadTask> tasks,
  ) {
    final known = <String>{
      for (final t in tasks)
        if (t.status == DownloadStatus.completed && t.finalPath.isNotEmpty)
          _baseName(t.finalPath),
    };
    return files.where((f) => !known.contains(f.name)).toList();
  }

  static String _baseName(String path) {
    final i = path.lastIndexOf('/');
    return i >= 0 ? path.substring(i + 1) : path;
  }

  /// Balaye le dossier public et mémorise les orphelins. Ne lève jamais :
  /// une permission refusée ou un canal absent (tests, autre plateforme)
  /// rendent un résultat vide, annoncé comme tel.
  static Future<DeviceScanResult> scan(Iterable<DownloadTask> tasks) async {
    if (scanning.value) return DeviceScanResult(videos.value);
    scanning.value = true;
    try {
      if (!await _ensurePermission()) {
        return const DeviceScanResult([], permissionDenied: true);
      }
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'listVideos',
        {'relativePath': relativePath},
      );
      final files = (raw ?? const [])
          .whereType<Map>()
          .map((m) => DeviceVideo(
                uri: (m['uri'] as String?) ?? '',
                name: (m['name'] as String?) ?? '',
                path: (m['path'] as String?) ?? '',
                size: (m['size'] as num?)?.toInt() ?? 0,
                modifiedAt: DateTime.fromMillisecondsSinceEpoch(
                    (m['modified'] as num?)?.toInt() ?? 0),
              ))
          .where((v) => v.name.isNotEmpty)
          .toList();
      final orphans = orphansOf(files, tasks);
      videos.value = orphans;
      await _persist();
      debugPrint('📂 §dlOrphans : ${files.length} fichier(s) dans '
          '$relativePath, ${orphans.length} hors liste');
      return DeviceScanResult(orphans);
    } on MissingPluginException {
      return const DeviceScanResult([]);
    } catch (e) {
      debugPrint('❌ §dlOrphans scan : $e');
      return DeviceScanResult(videos.value);
    } finally {
      scanning.value = false;
    }
  }

  /// Supprime un orphelin. `false` = refusé (par Android ou par l'utilisateur
  /// dans le dialogue système) ; le fichier reste listé dans ce cas.
  static Future<bool> delete(DeviceVideo v) async {
    bool ok = false;
    try {
      ok = await _channel.invokeMethod<bool>('deleteVideo', {'uri': v.uri}) ??
          false;
    } on MissingPluginException {
      ok = false;
    } catch (e) {
      debugPrint('❌ §dlOrphans delete : $e');
    }
    if (ok) {
      videos.value = videos.value.where((x) => x.uri != v.uri).toList();
      await _persist();
    }
    return ok;
  }

  /// Retire de la liste ce qui n'existe plus (sans balayage MediaStore).
  static Future<void> forget(DeviceVideo v) async {
    videos.value = videos.value.where((x) => x.uri != v.uri).toList();
    await _persist();
  }

  /// Même logique que `StorageFile._requestStoragePermission` : vidéos sur
  /// Android 13+, stockage avant. Sans elle MediaStore ne rend que nos
  /// propres fichiers — précisément ceux qui ne sont PAS orphelins.
  static Future<bool> _ensurePermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final PermissionStatus status = info.version.sdkInt >= 33
          ? await Permission.videos.request()
          : await Permission.storage.request();
      return status.isGranted || status.isLimited;
    } catch (_) {
      return true; // en doute, on tente le balayage : MediaStore tranchera
    }
  }
}
