/// Outils pour ne pas logger de credentials en clair.
///
/// **Contexte sécurité** : les URLs Xtream Codes contiennent `username` et
/// `password` directement dans le path (`/movie/USER/PASS/123.mkv`) ou en query
/// (`?username=...&password=...`). Les `debugPrint` qui affichent ces URLs
/// fuitent les credentials dans logcat — exposé sur device rooté ou ADB.
///
/// Utiliser [redactUrl] dans tout `debugPrint` qui mentionne une URL utilisateur.
library;

/// §tourFix — Préfixes de type de la forme Xtream « chemin »
/// (`/live/{user}/{pass}/{id}`…). Comparés en minuscules.
const Set<String> kXtreamPathPrefixes = {'live', 'movie', 'series', 'timeshift'};

/// §tourFix — revue 2026-09-11, D5A-02 / D1B-03 — **LE prédicat partagé** :
/// où sont l'identifiant et le mot de passe dans une URL Xtream « chemin ».
///
/// [segs] = les segments NON VIDES du chemin (un slash final ou doublé crée un
/// segment vide : il ne compte pas). Rend les rangs (user, pass) dans [segs],
/// ou `null` si la forme n'est pas reconnue.
///
/// Règle (celle de `XtreamCredentials.tryExtract`, déplacée ici À
/// L'IDENTIQUE) : un préfixe de type optionnel ([kXtreamPathPrefixes]), puis
/// user, pass, puis AU MOINS un segment de plus — le dernier est quelconque
/// (`12345.mkv`, `9541` des listes « Ultimate » sans extension, `index.m3u8`,
/// `m3u_plus`…). Seul garde-fou : user et pass ne contiennent pas de point
/// (un vrai identifiant n'a pas d'extension) → `/assets/logo.png/42` n'est
/// pas une URL Xtream.
///
/// ⚠️ **Pourquoi un seul prédicat.** `redactUrl` avait sa propre copie « à
/// l'identique » qui ne l'était pas : exactement 3 segments NON filtrés, un
/// dernier segment numérique, et jamais appliquée si la règle à préfixe avait
/// déjà masqué quelque chose. `tryExtract` lisait donc des identifiants que le
/// masquage laissait en clair — `/{user}/{pass}/index.m3u8`,
/// `/playlist/{user}/{pass}/m3u_plus`, `/{user}/{pass}/9541/` (slash final),
/// `/{user}/{pass}/live/x/y` — jusque dans le journal persisté (§logPersist)
/// et servi sur le LAN (`/logs.txt`). Deux copies d'une règle finissent
/// toujours par diverger : il n'y en a plus qu'une, et
/// `test/xtream_redact_invariant_test.dart` vérifie le contrat croisé.
({int user, int pass})? xtreamPathCredentialIndexes(List<String> segs) {
  if (segs.length < 3) return null;
  final int start =
      kXtreamPathPrefixes.contains(segs.first.toLowerCase()) ? 1 : 0;
  if (segs.length < start + 3) return null;
  final String u = segs[start];
  final String p = segs[start + 1];
  if (u.isEmpty || p.isEmpty || u.contains('.') || p.contains('.')) {
    return null;
  }
  return (user: start, pass: start + 1);
}

/// Préfixes après lesquels le MASQUAGE efface deux segments. Plus large que
/// [kXtreamPathPrefixes] (l'extraction), jamais plus étroit.
///
/// Revue 2026-09-11, D5A-02 — `playlist` : la forme panel
/// `/playlist/{user}/{pass}/m3u_plus`. `tryExtract` y lit (faussement)
/// `playlist` / `{user}` — masquer EXACTEMENT ce qu'il extrait laissait donc
/// le vrai mot de passe en clair. On le masque ici sans toucher à
/// l'extraction : lui faire lire les bons identifiants ferait passer ces
/// comptes par l'API JSON au lieu du M3U — un changement de chargement que
/// rien n'a mesuré.
const Set<String> _maskPrefixes = {...kXtreamPathPrefixes, 'playlist'};

/// Masque les credentials dans une URL Xtream Codes / IPTV.
///
/// - Query `username` / `password` → `***`
/// - Path Xtream `/{type}/{user}/{pass}/{id}` → `/{type}/***/***/{id}`
/// - Path timeshift `/timeshift/{user}/{pass}/{min}/{date}/{id}` → idem
/// - Path Xtream NU `/{user}/{pass}/{…}` → `/***/***/{…}` (§tourFix, même
///   prédicat que l'extraction : [xtreamPathCredentialIndexes])
/// - `user:pass@hôte` → `***@hôte` (revue 2026-09-11, D1B-09 fusionné dans
///   D1B-03 : un compte « URL complète » peut porter ses identifiants là)
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
  // Règle historique, plus LARGE que l'extraction (elle masque après un
  // préfixe placé n'importe où) : gardée telle quelle, masquer plus que ce
  // qu'on extrait ne fuit rien.
  final segs = uri.pathSegments.toList();
  for (var i = 0; i < segs.length; i++) {
    if (_maskPrefixes.contains(segs[i].toLowerCase()) &&
        i + 2 < segs.length) {
      segs[i + 1] = '***'; // user
      segs[i + 2] = '***'; // pass
      // skip already-redacted segments
      i += 2;
    }
  }

  // §tourFix — revue 2026-09-11, D5A-02 / D1B-03 — Ce que `tryExtract` sait
  // EXTRAIRE, on le MASQUE : même prédicat, calculé sur les segments NON
  // VIDES du chemin d'ORIGINE (comme l'extraction), puis reporté sur leurs
  // rangs réels. ⚠️ Appliqué TOUJOURS, plus seulement « si la règle à préfixe
  // n'a rien masqué » : sur `/{user}/{pass}/live/x/y` elle masquait x et y et
  // laissait user et pass en clair.
  //
  // ⚠️ Arbitrage assumé (règle LARGE) : `/api/v2/status.json` est désormais
  // masqué en `/***/***/status.json`. `tryExtract` en extrait (api, v2), et
  // un identifiant Xtream est une chaîne LIBRE : aucune règle lexicale ne
  // distingue « api/v2 » d'un vrai couple user/pass. Un faux positif coûte de
  // la lisibilité au journal ; un faux négatif, un mot de passe en clair.
  final List<int> nonEmpty = <int>[
    for (var i = 0; i < uri.pathSegments.length; i++)
      if (uri.pathSegments[i].isNotEmpty) i,
  ];
  final idx = xtreamPathCredentialIndexes(
      <String>[for (final int i in nonEmpty) uri.pathSegments[i]]);
  if (idx != null) {
    segs[nonEmpty[idx.user]] = '***'; // user
    segs[nonEmpty[idx.pass]] = '***'; // pass
  }

  final rebuilt = uri.replace(
    // D1B-09 — `http://user:pass@hôte/…` : `replace` CONSERVAIT l'userInfo.
    userInfo: uri.userInfo.isEmpty ? null : '***',
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
