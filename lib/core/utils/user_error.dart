import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../diagnostics/log_buffer.dart' show sanitizeForLog;

/// §userError — Transforme une exception en phrase française **affichable**.
///
/// **Pourquoi ce fichier existe** : neuf snackbars de l'app affichaient
/// `'❌ Échec : $e'`, c'est-à-dire le `toString()` d'une `DioException`. Or
/// `stream_account_service.dart` le documente depuis §logHygiene : pour
/// certains types, cette exception **inclut l'URL de requête avec les
/// identifiants Xtream** (`?username=…&password=…`). Le journal §tvLogs était
/// protégé par [sanitizeForLog] ; l'**écran** ne l'était pas.
///
/// Trois garanties :
///   1. **jamais d'URL ni d'identifiant** — tout texte qui n'est pas produit ici
///      passe par [sanitizeForLog] en dernier filet (invariant §tourFix : ce
///      que `XtreamCredentials.tryExtract` sait lire, on sait le masquer) ;
///   2. **français** (§frOnly) et **actionnable** : la phrase dit quoi vérifier ;
///   3. **court** : une snackbar, pas une stack trace (borne [_maxLength]).
///
/// Le mapping `DioExceptionType` reprend celui de `playlist_service.dart`,
/// qui était le meilleur de l'app mais enfermé dans un `catch` privé.
String describeError(Object? error) {
  if (error == null) return 'Une erreur inattendue est survenue.';
  final String raw = _describe(error);
  return _cap(sanitizeForLog(raw));
}

const int _maxLength = 180;

String _describe(Object error) {
  if (error is DioException) return _describeDio(error);
  if (error is HttpException) {
    // Déjà en français dans l'app (playlist_service, playlist_reload_service)
    // — on garde le message, le filet redact s'applique quand même.
    return _stripPrefix(error.message);
  }
  if (error is SocketException) {
    return 'Connexion impossible : réseau coupé ou serveur injoignable.';
  }
  if (error is TimeoutException) {
    return 'Le serveur a mis trop de temps à répondre.';
  }
  if (error is HandshakeException || error is TlsException) {
    return 'Connexion sécurisée refusée par le serveur (certificat).';
  }
  if (error is FormatException) {
    return 'Réponse illisible du serveur (format inattendu).';
  }
  if (error is FileSystemException) {
    return 'Impossible de lire ou d\'écrire le fichier sur l\'appareil.';
  }
  if (error is ArgumentError || error is StateError) {
    return 'Une erreur interne est survenue.';
  }
  return _stripPrefix(error.toString());
}

String _describeDio(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
      return 'Le serveur a mis trop de temps à répondre. '
          'Vérifie ta connexion ou l\'adresse du serveur.';
    case DioExceptionType.badResponse:
      final int? code = e.response?.statusCode;
      if (code == null) {
        return 'Réponse invalide du serveur. Vérifie l\'adresse.';
      }
      if (code == 401 || code == 403) {
        return 'Accès refusé par le serveur (HTTP $code). '
            'Vérifie les identifiants du compte.';
      }
      if (code == 404) {
        return 'Adresse introuvable sur le serveur (HTTP 404).';
      }
      if (code >= 500) {
        return 'Le serveur est en erreur (HTTP $code). Réessaie plus tard.';
      }
      return 'Le serveur a répondu avec une erreur (HTTP $code).';
    case DioExceptionType.connectionError:
      return 'Erreur de connexion : vérifie que tu es en ligne '
          'et que le serveur est accessible.';
    case DioExceptionType.badCertificate:
      return 'Connexion sécurisée refusée par le serveur (certificat).';
    case DioExceptionType.cancel:
      return 'Opération annulée.';
    case DioExceptionType.unknown:
      // ⚠️ C'est LE type dont le `toString()` embarque l'URL de requête.
      final Object? cause = e.error;
      if (cause != null && cause is! DioException) return _describe(cause);
      return 'Erreur réseau inconnue.';
  }
}

/// `Exception: …`, `HttpException: …`, `Bad state: …` → on garde le message.
///
/// Les préfixes s'EMPILENT (`Exception('Bad state: foo')` donne
/// `Exception: Bad state: foo`) : on les retire tous, pas seulement le
/// premier — sinon l'utilisateur lit encore du jargon Dart.
String _stripPrefix(String s) {
  final RegExp prefix = RegExp(
      r'^(?:[A-Za-z]+Exception|Exception|Bad state|Invalid argument\(s\))\s*:\s*');
  String out = s.trim();
  RegExpMatch? m = prefix.firstMatch(out);
  while (m != null) {
    out = out.substring(m.end).trim();
    m = prefix.firstMatch(out);
  }
  return out.isEmpty ? 'Une erreur inattendue est survenue.' : out;
}

String _cap(String s) {
  final String one = s.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();
  if (one.length <= _maxLength) return one;
  return '${one.substring(0, _maxLength - 1).trimRight()}…';
}
