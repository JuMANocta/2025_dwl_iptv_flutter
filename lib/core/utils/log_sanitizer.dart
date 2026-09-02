/// Outils pour ne pas logger de credentials en clair.
///
/// **Contexte sécurité** : les URLs Xtream Codes contiennent `username` et
/// `password` directement dans le path (`/movie/USER/PASS/123.mkv`) ou en query
/// (`?username=...&password=...`). Les `debugPrint` qui affichent ces URLs
/// fuitent les credentials dans logcat — exposé sur device rooté ou ADB.
///
/// Utiliser [redactUrl] dans tout `debugPrint` qui mentionne une URL utilisateur.
library;

/// §tourFix — Dernier segment d'une forme Xtream NUE : un id numérique, avec
/// ou SANS extension (`12345.mkv`, `987.ts`, `9541`).
///
/// ⚠️ **L'extension est OPTIONNELLE, et ce n'est pas un détail** : les chaînes
/// TV des playlists « Ultimate » sont servies en URL nue *sans* extension
/// (`http://serveur/{user}/{pass}/{id}`), et c'est le format le plus répandu
/// du catalogue. Une première version exigeait `\.\w+` — elle laissait donc
/// fuir en clair exactement les URLs les plus nombreuses.
/// `XtreamCredentials.tryExtract` note d'ailleurs l'extension `[.ext]` comme
/// optionnelle : ce qu'on sait extraire, on doit savoir le masquer.
final RegExp _nakedXtreamLastSegment = RegExp(r'^\d+(\.\w+)?$');

/// Masque les credentials dans une URL Xtream Codes / IPTV.
///
/// - Query `username` / `password` → `***`
/// - Path Xtream `/{type}/{user}/{pass}/{id}` → `/{type}/***/***/{id}`
/// - Path timeshift `/timeshift/{user}/{pass}/{min}/{date}/{id}` → idem
/// - Path Xtream NU `/{user}/{pass}/{id}.ext` → `/***/***/{id}.ext` (§tourFix)
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
  var prefixRedacted = false;
  for (var i = 0; i < segs.length; i++) {
    if (prefixes.contains(segs[i].toLowerCase()) && i + 2 < segs.length) {
      segs[i + 1] = '***'; // user
      segs[i + 2] = '***'; // pass
      prefixRedacted = true;
      // skip already-redacted segments
      i += 2;
    }
  }

  // §tourFix — Forme Xtream NUE `/{user}/{pass}/{id}[.ext]` SANS préfixe
  // (documentée dans XtreamCredentials.tryExtract) : elle traversait intacte
  // et finissait en clair dans le journal servi en HTTP sur le LAN (§tvLogs).
  //
  // Deux garde-fous contre les faux positifs, repris À L'IDENTIQUE de
  // `tryExtract` — le masquage et l'extraction doivent reconnaître le MÊME
  // format, sinon on masque ce qu'on ne lit pas, ou pire l'inverse :
  //   1. exactement 3 segments, le dernier étant un id numérique ;
  //   2. user et pass ne contiennent pas de point (un vrai identifiant n'a pas
  //      d'extension) → `/api/v2/status.json` et `/docs/v1/guide.pdf` passent
  //      intacts.
  // Appliquée seulement si la règle à préfixe n'a rien masqué : sur
  // `/movie/{user}/{pass}` le comportement existant reste intact.
  if (!prefixRedacted &&
      segs.length == 3 &&
      _nakedXtreamLastSegment.hasMatch(segs[2]) &&
      !segs[0].contains('.') &&
      !segs[1].contains('.')) {
    segs[0] = '***'; // user
    segs[1] = '***'; // pass
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
