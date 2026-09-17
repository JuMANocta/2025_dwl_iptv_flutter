/// Outils pour ne pas logger de credentials en clair.
///
/// **Contexte sécurité** : les URLs Xtream Codes contiennent `username` et
/// `password` directement dans le path (`/movie/USER/PASS/123.mkv`) ou en query
/// (`?username=...&password=...`). Les `debugPrint` qui affichent ces URLs
/// fuitent les credentials dans logcat — exposé sur device rooté ou ADB.
///
/// Utiliser [redactUrl] dans tout `debugPrint` qui mentionne une URL utilisateur.
library;

// R35 — `isRfc1918` : la notion « adresse privée » existe déjà et n'a qu'UNE
// définition (même raison qu'un seul prédicat Xtream, §tourFix). C'est aussi
// exactement le prédicat qui décide où nos serveurs Cast acceptent d'écouter.
import 'lan_address.dart' show isRfc1918;

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

/// R35 (recette Cast du 2026-09-12) — La FORME d'un jeton de session de nos
/// serveurs locaux : 32 caractères hexadécimaux pour le relais Cast et le
/// serveur de fichiers (`Random.secure`, 16 octets), 16 caractères de
/// l'alphabet sans ambiguïté (ni 0/O ni 1/I) pour la console web (D1B-02).
///
/// Le seuil est à 24 hexadécimaux et non à 32 : un jeton dont la longueur
/// changerait doit rester masqué, et rien d'UTILE dans une URL n'a cette forme
/// (un id de flux Xtream est court, un nom de fichier porte un point).
/// Le motif, écrit UNE fois : les deux expressions ci-dessous n'en sont que
/// deux ancrages.
const String _tokenBody = r'(?:[0-9a-fA-F]{24,}|[A-HJ-NP-Z2-9]{16})';

final RegExp _localServerToken = RegExp('^$_tokenBody\$');

/// R35 — Le même motif cherché DANS une valeur, et non sur la valeur entière.
///
/// ⚠️ **Pourquoi pas seulement la version ancrée.** Le puits du journal
/// capture l'URL avec `https?://[^\s"'<>\\]+` (`sanitizeForLog`), une classe
/// qui n'exclut ni le point ni la parenthèse : la ponctuation de fin de phrase
/// entre DANS l'URL. `…/?t=HJKLMNPQRSTUVWXY.` sortait donc en clair, une règle
/// de FORME étant défaite par un seul caractère parasite là où les règles
/// Xtream, qui masquent par POSITION, ne le sont pas.
///
/// Les bornes sont alphanumériques et non `\b` : `\b` ne coupe pas sur `_`, un
/// caractère de mot — `sess_<jeton>` doit se masquer.
final RegExp _localServerTokenRun =
    RegExp('(?<![0-9A-Za-z])$_tokenBody(?![0-9A-Za-z])');

/// R35 — `true` si [value] EST un jeton de nos serveurs locaux (valeur
/// entière). Exposé pour que `test/xtream_redact_invariant_test.dart`
/// verrouille la FORME elle-même, et pas seulement une URL d'exemple.
bool looksLikeLocalServerToken(String value) =>
    _localServerToken.hasMatch(value);

/// R35 — Les adresses où NOS serveurs écoutent, et elles seules : une adresse
/// privée RFC 1918 (`lanIpv4` — ce que le serveur de fichiers Cast et le
/// relais EXIGENT avant de démarrer) ou la boucle locale (`adb forward` de la
/// console web, §consoleLock).
///
/// ⚠️ **Pourquoi cette borne.** Sans elle, la règle masquerait aussi les
/// hachages des CDN PUBLICS : mesuré dans les dumps (`lib/iptv_exemple/`), de
/// vraies chaînes sont servies en `.../out/v1/<32 hexa>/index_2.m3u8`. Deux
/// chaînes deviendraient indiscernables au journal — précisément ce qu'on y
/// cherche quand une lecture échoue — sans rien protéger de plus.
///
/// ⚠️ **Arbitrage assumé, en sens inverse** : sur une adresse privée, rien ne
/// distingue nos serveurs d'un panel IPTV ou d'un NAS auto-hébergé — un
/// identifiant de session HLS en 32 hexadécimaux y sera masqué lui aussi. Même
/// arbitrage que `/api/v2/status.json` plus bas : un faux positif ne coûte que
/// de la lisibilité au journal, un faux négatif ouvre le flux au voisin de
/// Wi-Fi.
bool _isLocalServerHost(String host) =>
    isRfc1918(host) ||
    host == '127.0.0.1' ||
    host == 'localhost' ||
    host == '::1';

/// §subOnline (2026-09-17) — Les paramètres de query dont la VALEUR est un
/// secret, masqués **quel que soit l'hôte**.
///
/// ⚠️ **Pourquoi « quel que soit l'hôte ».** Les deux autres règles de ce
/// fichier sont bornées : les formes Xtream portent sur le CHEMIN, et le
/// masquage par forme (R35) ne s'applique qu'aux adresses où NOS serveurs
/// écoutent. Une clé d'API part, elle, vers un hôte PUBLIC — `sub.wyzie.io`
/// pour les sous-titres en ligne, `api.themoviedb.org` pour TMDB — et aucune
/// des deux règles ne mordait. Le journal étant persisté (§logPersist) puis
/// servi en clair sur le LAN (§tvLogs), c'était la forme exacte de la fuite
/// R35, à ceci près que la clé appartient à l'utilisateur et qu'il l'a payée
/// de son inscription.
///
/// ⚠️ **Arbitrage assumé, le même que partout ici** : masquer par NOM est
/// large. Un paramètre légitimement nommé `key` (un identifiant de tri, une
/// clé de cache) sera masqué lui aussi. Un faux positif coûte de la lisibilité
/// au journal ; un faux négatif publie une clé d'API sur le réseau local.
///
/// ⛔ Ce n'est PAS un doublon du masquage par forme de R35 : celui-là attrape
/// une valeur de jeton sous N'IMPORTE quel nom (`?t=…`), mais seulement sur un
/// hôte local ; celui-ci attrape N'IMPORTE quelle valeur sous un nom connu, sur
/// tout hôte. Aucun des deux ne sait faire le travail de l'autre.
const Set<String> _secretQueryParams = <String>{
  'username',
  'password',
  'pass',
  'pwd',
  'key',
  'api_key',
  'apikey',
  'token',
  'access_token',
  'auth_token',
  'auth',
  'secret',
};

/// Masque les credentials dans une URL Xtream Codes / IPTV.
///
/// - Query `username` / `password`, et tout nom de [_secretQueryParams]
///   (`key`, `api_key`, `token`…), sur TOUT hôte → `***`
/// - Path Xtream `/{type}/{user}/{pass}/{id}` → `/{type}/***/***/{id}`
/// - Path timeshift `/timeshift/{user}/{pass}/{min}/{date}/{id}` → idem
/// - Path Xtream NU `/{user}/{pass}/{…}` → `/***/***/{…}` (§tourFix, même
///   prédicat que l'extraction : [xtreamPathCredentialIndexes])
/// - `user:pass@hôte` → `***@hôte` (revue 2026-09-11, D1B-09 fusionné dans
///   D1B-03 : un compte « URL complète » peut porter ses identifiants là)
/// - R35 — Sur une adresse où NOS serveurs écoutent ([_isLocalServerHost]),
///   toute suite ayant la forme d'un jeton ([_localServerTokenRun]), dans un
///   segment de chemin comme dans une valeur de query → `***`. ⚠️ Le prédicat
///   public [looksLikeLocalServerToken] répond à une autre question : « cette
///   valeur ENTIÈRE est-elle un jeton » — il ne décrit pas le masquage.
/// - Renvoie une chaîne vide si l'URL est invalide / nulle.
String redactUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  Uri? uri;
  try {
    uri = Uri.parse(url);
  } catch (_) {
    return '<url invalide>';
  }

  // Masquage par NOM de paramètre, sur TOUT hôte (cf. [_secretQueryParams]).
  // ⚠️ Comparaison en minuscules : `apiKey=` et `API_KEY=` valent `api_key=`.
  final qp = Map<String, dynamic>.from(uri.queryParametersAll);
  for (final String k in qp.keys.toList()) {
    if (_secretQueryParams.contains(k.toLowerCase())) qp[k] = '***';
  }

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

  // §castLan / R35 — recette Cast du 2026-09-12 : le jeton était publié par le
  // canal même qu'il devait protéger. Le relais Cast sert `/<jeton>/relay.mp4`
  // — DEUX segments : ni la règle à préfixe (elle exige `i + 2 < segs.length`)
  // ni le prédicat §tourFix (moins de 3 segments → `null`) ne mordaient, et
  // l'URL partait telle quelle au journal persisté (§logPersist) puis servi
  // sur le LAN (§tvLogs).
  //
  // La règle porte sur la FORME et sur l'adresse d'écoute, jamais sur une
  // route : une route qui change (`/local/…` déplacé, un serveur de plus)
  // reste couverte. C'était le défaut du masquage ACCIDENTEL de
  // `/local/<jeton>/media.mkv`, que §tourFix prenait pour un couple user/pass.
  // ⚠️ Ce n'est PAS une deuxième copie du filet `token=` de `sanitizeForLog` :
  // celui-là masque par NOM de paramètre dans du texte libre (`token: abc`),
  // celui-ci par FORME de valeur à l'intérieur d'une URL. Aucun des deux ne
  // sait faire le travail de l'autre — le filet par nom ignore `?t=`, et une
  // règle de forme ne peut pas masquer un mot de passe choisi par l'humain.
  if (_isLocalServerHost(uri.host)) {
    for (var i = 0; i < segs.length; i++) {
      segs[i] = segs[i].replaceAll(_localServerTokenRun, '***');
    }
    // La console web, elle, porte son jeton en query (`?t=…`).
    for (final String k in qp.keys.toList()) {
      final Object? v = qp[k];
      final List<String> values = v is List
          ? <String>[for (final Object? e in v) '$e']
          : <String>['$v'];
      if (values.any((String s) => s.contains(_localServerTokenRun))) {
        qp[k] = values
            .map((String s) => s.replaceAll(_localServerTokenRun, '***'))
            .join(',');
      }
    }
  }

  final rebuilt = uri.replace(
    // D1B-09 — `http://user:pass@hôte/…` : `replace` CONSERVAIT l'userInfo.
    userInfo: uri.userInfo.isEmpty ? null : '***',
    pathSegments: segs,
    // §subOnline (2026-09-17) — Les valeurs sont passées TELLES QUELLES.
    //
    // ⚠️ Défaut trouvé en verrouillant le masquage des clés : ce `map` faisait
    // `v.toString()` sur des valeurs qui viennent de `queryParametersAll`,
    // c'est-à-dire des `List<String>`. Un paramètre non masqué ressortait donc
    // entre CROCHETS — `?id=286217` devenait `?id=%5B286217%5D` — et toute URL
    // recopiée d'un journal était inutilisable. Aucun test ne le voyait :
    // `%5Bm3u_plus%5D` contient encore `m3u_plus`. `Uri.replace` sait recevoir
    // une `Iterable<String>` et rend alors le paramètre répété, ce qui est la
    // forme d'origine.
    queryParameters: qp.isEmpty ? null : qp,
  );
  // ⚠️ `Uri` encode `*` en `%2A` : le masque ressortait en `%2A%2A%2A`, que
  // personne ne lit comme « masqué ». On le rétablit APRÈS l'encodage — c'est
  // la seule suite qui ne peut pas venir des données, puisqu'on vient de
  // l'écrire nous-mêmes.
  return rebuilt.toString().replaceAll('%2A%2A%2A', '***');
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
