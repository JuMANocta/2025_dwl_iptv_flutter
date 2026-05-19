/// Outils pour ne pas logger de credentials en clair.
///
/// **Contexte sécurité** : les URLs Xtream Codes contiennent `username` et
/// `password` directement dans le path (`/movie/USER/PASS/123.mkv`) ou en query
/// (`?username=...&password=...`). Les `debugPrint` qui affichent ces URLs
/// fuitent les credentials dans logcat — exposé sur device rooté ou ADB.
///
/// Utiliser [redactUrl] dans tout `debugPrint` qui mentionne une URL utilisateur.
library;

/// Masque les credentials dans une URL Xtream Codes / IPTV.
///
/// - Query `username` / `password` → `***`
/// - Path Xtream `/{type}/{user}/{pass}/{id}` → `/{type}/***/***/{id}`
/// - Path timeshift `/timeshift/{user}/{pass}/{min}/{date}/{id}` → idem
/// - Renvoie une chaîne vide si l'URL est invalide / nulle.
String redactUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  Uri? uri;
  try {
    uri = Uri.parse(url);
  } catch (_) {
    return '<url invalide>';
  }

  final qp = Map<String, dynamic>.from(uri.queryParametersAll);
  if (qp.containsKey('username')) qp['username'] = '***';
  if (qp.containsKey('password')) qp['password'] = '***';

  // Redact path segments after known Xtream prefixes (live/movie/series/timeshift).
  const prefixes = {'live', 'movie', 'series', 'timeshift'};
  final segs = uri.pathSegments.toList();
  for (var i = 0; i < segs.length; i++) {
    if (prefixes.contains(segs[i].toLowerCase()) && i + 2 < segs.length) {
      segs[i + 1] = '***'; // user
      segs[i + 2] = '***'; // pass
      // skip already-redacted segments
      i += 2;
    }
  }

  final rebuilt = uri.replace(
    pathSegments: segs,
    queryParameters: qp.isEmpty ? null : qp.map((k, v) => MapEntry(k, v.toString())),
  );
  return rebuilt.toString();
}

/// Masque les credentials d'un objet `XtreamCredentials` pour les logs.
/// Garde uniquement host + port pour le debug.
String redactServer(String? server) {
  if (server == null || server.isEmpty) return '';
  try {
    final uri = Uri.parse(server);
    final port = uri.hasPort && uri.port != 0 ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  } catch (_) {
    return '<server invalide>';
  }
}
