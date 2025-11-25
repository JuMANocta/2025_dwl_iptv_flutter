import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/utils/network.dart';
import 'stream_account_service.dart';

class PlaylistService {
  static const String _playlistBaseName = 'playlist';
  static const Duration playlistCacheDuration = Duration(hours: 24);

  static Future<String> playlistPath() async {
    final acc = await StreamAccountService.getCurrentAccount();
    if (acc == null) throw StateError("Aucun compte sélectionné pour déterminer le chemin de la playlist.");

    final dir = await getApplicationDocumentsDirectory();
    // Le nom du fichier inclut l'ID du compte pour un cache unique !
    // ex: playlist_1a2b3c.m3u
    return '${dir.path}/${_playlistBaseName}_${acc.id}.m3u';
  }

  static Future<void> deleteExisting() async {
    try {
      final path = await playlistPath();
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static Future<String> getOrDownloadPlaylist() async {
    final path = await playlistPath();
    final file = File(path);

    if (await file.exists()) {
      final lastModified = await file.lastModified();
      if (DateTime.now().difference(lastModified) < playlistCacheDuration) {
        debugPrint("✅ Playlist trouvée en cache et encore valide. Pas de téléchargement.");
        return path;
      } else {
        debugPrint("⏳ Playlist trouvée en cache mais périmée. Retéléchargement...");
      }
    } else {
      debugPrint("ℹ️ Aucune playlist en cache. Téléchargement initial...");
    }
    return downloadCurrentM3U();
  }

  static Future<String> _buildUrlForCurrentAccount() async {
    final acc = await StreamAccountService.getCurrentAccount();
    if (acc == null) throw StateError("Aucun compte IPTV sélectionné.");
    final url = acc.buildM3uUrl();
    if (url == null || url.isEmpty) throw StateError('Configuration de compte invalide.');
    return url;
  }

  static Future<String> downloadCurrentM3U() async {
    final url = await _buildUrlForCurrentAccount();
    final destinationPath = await playlistPath();
    final tempPath = '$destinationPath.part';

    final dio = await NetworkUtils.buildDio(url);

    try {
      await dio.download(
        url,
        tempPath,
        options: Options(
          receiveTimeout: const Duration(seconds: 60),
          followRedirects: true,
          validateStatus: (status) => status != null && status >= 200 && status < 300,
        ),
      );

      final tempFile = File(tempPath);
      if (!await tempFile.exists() || await tempFile.length() == 0) {
        throw StateError('Le fichier de playlist téléchargé est vide.');
      }

      await tempFile.rename(destinationPath);
      debugPrint("✅ Playlist téléchargée et mise en cache avec succès pour le compte actuel.");
      return destinationPath;

    } catch (e) {
      // Nettoyage en cas d'erreur
      final tempFile = File(tempPath);
      if (await tempFile.exists()) {
        try { await tempFile.delete(); } catch (_) {}
      }

      // Propagation d'une erreur claire
      if (e is DioException) {
        if (e.response?.statusCode != null) {
          throw HttpException('Erreur du serveur (${e.response!.statusCode}) lors du téléchargement.');
        }
        throw HttpException('Erreur réseau lors du téléchargement: ${e.message}');
      }
      throw HttpException('Échec du téléchargement de la playlist: ${e.toString()}');
    }
  }
}
