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
    if (acc == null) {
      throw const HttpException(
          "Aucun compte actif sélectionné. Veuillez en choisir un dans les paramètres.");
    }
    final dir = await getApplicationDocumentsDirectory();
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
        debugPrint(
            "✅ Playlist trouvée en cache et encore valide. Pas de téléchargement.");
        return path;
      } else {
        debugPrint(
            "⏳ Playlist trouvée en cache mais périmée. Retéléchargement...");
      }
    } else {
      debugPrint("ℹ️ Aucune playlist en cache. Téléchargement initial...");
    }
    return downloadCurrentM3U();
  }

  static Future<String> _buildUrlForCurrentAccount() async {
    final acc = await StreamAccountService.getCurrentAccount();
    // Normalement, playlistPath() a déjà vérifié ça, mais c'est une sécurité.
    if (acc == null) throw const HttpException("Aucun compte actif sélectionné.");
    final url = acc.buildM3uUrl();
    if (url == null || url.isEmpty) {
      throw HttpException("L'URL de la playlist pour le compte '${acc.label}' est invalide. Veuillez vérifier sa configuration.");
    }
    return url;
  }

  static Future<String> downloadCurrentM3U() async {
    String url = '';
    String destinationPath = '';
    String tempPath = '';

    try {
      url = await _buildUrlForCurrentAccount();
      destinationPath = await playlistPath();
      tempPath = '$destinationPath.part';

      final dio = await NetworkUtils.buildDio(url);

      await dio.download(
        url,
        tempPath,
        options: Options(
          receiveTimeout: const Duration(seconds: 60),
          followRedirects: true,
          validateStatus: (status) =>
          status != null && status >= 200 && status < 300,
        ),
      );

      final tempFile = File(tempPath);
      if (!await tempFile.exists() || await tempFile.length() == 0) {
        throw const HttpException("Le serveur a renvoyé un fichier vide. Vérifiez l'URL de la playlist.");
      }

      await tempFile.rename(destinationPath);
      debugPrint("✅ Playlist téléchargée et mise en cache avec succès.");
      return destinationPath;
    } on DioException catch (e) {
      if (tempPath.isNotEmpty) {
        final tempFile = File(tempPath);
        if (await tempFile.exists()) {
          try {
            await tempFile.delete();
          } catch (_) {}
        }
      }

      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          throw HttpException("Le serveur a mis trop de temps à répondre (timeout).\nVérifiez votre connexion ou l'adresse du serveur.");
        case DioExceptionType.badResponse:
          final statusCode = e.response?.statusCode;
          if (statusCode != null) {throw HttpException("Le serveur a répondu avec une erreur : $statusCode.\nVérifiez l'URL de la playlist.");
          }
          throw HttpException("Réponse invalide du serveur. Vérifiez l'URL de la playlist.");
        case DioExceptionType.connectionError:
          throw const HttpException("Erreur de connexion.\nAssurez-vous d'être connecté à internet et que l'hôte est accessible.");
        case DioExceptionType.cancel:
          throw const HttpException("Le téléchargement a été annulé.");
        default:
          throw HttpException("Erreur réseau inconnue : ${e.message}");
      }
    } on HttpException {
      rethrow;
    } catch (e) {
      throw HttpException("Une erreur inattendue est survenue : ${e.toString()}");
    }
  }
}
