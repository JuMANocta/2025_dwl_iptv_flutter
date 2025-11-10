import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:path_provider/path_provider.dart';
import '../models/iptv_account.dart';
import 'iptv_account_service.dart';

/// Service responsable du téléchargement et de la gestion de la playlist M3U.
class PlaylistService {
  static const String playlistName = 'iptv_links.m3u';

  /// Durée de validité de la playlist en cache avant de forcer un nouveau téléchargement.
  static const Duration playlistCacheDuration = Duration(hours: 24);

  /// Retourne le chemin complet où la playlist doit être stockée.
  static Future<String> playlistPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$playlistName';
  }

  /// Supprime la playlist M3U existante si elle est présente.
  static Future<void> deleteExisting() async {
    try {
      final file = File(await playlistPath());
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Ignorer les erreurs de suppression, ce n'est pas critique.
    }
  }

  /// Récupère le chemin de la playlist si elle est fraîche,
  /// sinon la télécharge. C'est la fonction à appeler depuis l'extérieur.
  static Future<String> getOrDownloadPlaylist() async {
    final path = await playlistPath();
    final file = File(path);

    // 1. Vérifier si le fichier existe
    if (await file.exists()) {
      // 2. Si oui, vérifier sa date de modification
      final lastModified = await file.lastModified();
      final now = DateTime.now();

      // 3. Vérifier si la liste n'est pas périmée
      if (now.difference(lastModified) < playlistCacheDuration) {
        // Utiliser debugPrint pour des logs de débogage clairs
        // ignore: avoid_print
        print("✅ Playlist trouvée en cache et encore valide. Pas de téléchargement.");
        return path; // La liste est fraîche, on la retourne directement
      } else {
        // ignore: avoid_print
        print("⏳ Playlist trouvée en cache mais périmée. Retéléchargement...");
      }
    } else {
      // ignore: avoid_print
      print("ℹ️ Aucune playlist en cache. Téléchargement initial...");
    }

    // 4. Si la liste n'existe pas ou est périmée, on la télécharge
    return downloadCurrentM3U();
  }

  /// Construit l'URL de la playlist à partir des informations d'un compte.
  /// Centralise la logique de construction d'URL pour tous les modes.
  static Future<String> _buildUrlForCurrentAccount() async {
    final IptvAccount? acc = await IptvAccountService.getCurrentAccount();

    if (acc == null) {
      throw StateError("Aucun compte IPTV n'est actuellement sélectionné.");
    }

    if (acc.mode == IptvAuthMode.completeUrl) {
      final url = acc.completeUrl?.trim();
      if (url != null && url.isNotEmpty) {
        return url;
      }
    } else {
      final baseUrl = (acc.baseUrl ?? '').trim();
      final username = (acc.username ?? '').trim();
      final password = (acc.password ?? '').trim();

      if (baseUrl.isNotEmpty && username.isNotEmpty && password.isNotEmpty) {
        // Logique de construction d'URL avec les paramètres.
        final uri = Uri.parse(baseUrl);
        return uri.replace(
          queryParameters: {
            ...uri.queryParameters, // Conserve les paramètres existants dans l'URL de base
            'username': username,
            'password': password,
            'type': 'm3u_plus',
            'output': 'ts',
          },
        ).toString();
      }
    }

    throw StateError('La configuration du compte IPTV est invalide ou incomplète.');
  }

  /// Télécharge la playlist pour le compte actuellement actif.
  /// La logique a été entièrement revue pour être plus simple et robuste.
  static Future<String> downloadCurrentM3U() async {
    // 1. Obtenir l'URL et le chemin de destination.
    final url = await _buildUrlForCurrentAccount();
    final destinationPath = await playlistPath();
    final tempPath = '$destinationPath.part'; // Fichier temporaire

    // 2. Créer une instance de Dio dédiée et simple.
    final dio = Dio();
    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      return HttpClient()..badCertificateCallback = (cert, host, port) => true;
    };

    // 3. Télécharger le fichier dans un bloc try/finally pour garantir le nettoyage.
    try {
      await dio.download(
        url,
        tempPath,
        options: Options(
          receiveTimeout: const Duration(seconds: 60), // Timeout plus long pour les listes
          followRedirects: true,
          validateStatus: (status) => status != null && status >= 200 && status < 300,
        ),
      );

      // 4. Vérifier que le fichier téléchargé n'est pas vide.
      final tempFile = File(tempPath);
      if (!await tempFile.exists() || await tempFile.length() == 0) {
        throw StateError('Le fichier de playlist téléchargé est vide.');
      }

      // 5. Renommer le fichier temporaire pour finaliser l'opération.
      await deleteExisting(); // Supprime l'ancienne playlist
      await tempFile.rename(destinationPath); // Le fichier .part devient le fichier final

      return destinationPath;
    } catch (e) {
      if (e is DioException) {
        // Si on a un code d'erreur HTTP (4xx, 5xx), on le précise.
        if (e.response?.statusCode != null) {
          throw HttpException(
              'Erreur du serveur (${e.response!.statusCode}) lors du téléchargement de la playlist.'
          );
        }
        // Sinon, c'est probablement une erreur réseau (timeout, DNS...).
        throw HttpException('Erreur réseau lors du téléchargement: ${e.message}');
      }
      // Pour toutes les autres erreurs (fichier vide, etc.)
      throw HttpException('Échec du téléchargement de la playlist: ${e.toString()}');
    } finally {
      // 6. GARANTIR le nettoyage du fichier temporaire.
      // Ce bloc s'exécute toujours, que le téléchargement ait réussi ou échoué.
      try {
        final tempFile = File(tempPath);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {
        // Ignorer les erreurs de suppression du fichier temporaire.
      }
    }
  }
}
