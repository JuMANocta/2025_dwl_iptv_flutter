import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:path_provider/path_provider.dart';
import '../models/iptv_account.dart';
import 'iptv_account_service.dart';

/// Service responsable du téléchargement et de la gestion de la playlist M3U.
class PlaylistService {
  static const String playlistName = 'iptv_links.m3u';

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
    // Pas besoin de `buildDio` externe, qui est fait pour le téléchargement de vidéos.
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
      // En cas d'erreur (HTTP, réseau, fichier vide), on propage une erreur claire.
      // Le bloc `finally` s'occupera du nettoyage.
      if (e is DioException) {
        throw HttpException('Erreur réseau lors du téléchargement: ${e.message}');
      }
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
