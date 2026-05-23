/// Mode d’authentification
/// - [completeUrl] : l’utilisateur fournit directement l’URL .m3u complète.
/// - [separate]   : on construit l’URL à partir de baseUrl + username + password (style Xtream Codes).
enum StreamAuthMode { completeUrl, separate }
enum PlaylistType { m3u, simple }

class StreamAccount {
  /// Identifiant unique stocké dans le secure storage (ex: "acc_1712345678901").
  final String id;
  /// Label affiché à l’utilisateur (ex: "Mon Compte #1").
  final String label;
  /// Mode d’authentification.
  final StreamAuthMode mode;
  /// URL .m3u complète (si mode == completeUrl).
  final String? completeUrl;
  /// Base URL (ex: https://host:port/) si mode == separate.
  final String? baseUrl;
  /// Identifiant si mode == separate.
  final String? username;
  /// Mot de passe si mode == separate.
  final String? password;
  /// Cookies optionnels à injecter dans les requêtes.
  final String? cookies;
  /// Type de playlist (m3u ou simple).
  final PlaylistType playlistType;
  /// Date de création (info utile pour tri/diagnostic).
  DateTime createdAt;

  StreamAccount({
    required this.id,
    required this.label,
    required this.mode,
    this.completeUrl,
    this.baseUrl,
    this.username,
    this.password,
    this.cookies,
    this.playlistType = PlaylistType.m3u,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Construit l’URL .m3u utilisable pour télécharger la playlist.
  /// - En mode [completeUrl], renvoie `completeUrl` **normalisée**
  ///   (`type=m3u` → `type=m3u_plus`, cf. [_ensureM3uPlus]).
  /// - En mode [separate], construit l’URL standard Xtream Codes :
  ///   `{baseUrl}/get.php?username=<u>&password=<p>&type=m3u_plus&output=ts`
  String? buildM3uUrl() {
    if (mode == StreamAuthMode.completeUrl) {
      final raw = (completeUrl ?? '').trim();
      if (raw.isEmpty) return null;
      return _ensureM3uPlus(raw);
    }

    final b = (baseUrl ?? '').trim();
    final u = (username ?? '').trim();
    final p = (password ?? '').trim();
    if (b.isEmpty || u.isEmpty || p.isEmpty) return null;

    // Normalise le slash
    final hasSlash = b.endsWith('/');
    final base = hasSlash ? b.substring(0, b.length - 1) : b;
    final String typeValue = playlistType == PlaylistType.simple ? 'simple' : 'm3u_plus';

    return "$base/get.php?username=$u&password=$p&type=$typeValue&output=ts";

  }

  /// Réécrit `?type=m3u` → `?type=m3u_plus` (et idem `&type=m3u`) dans une
  /// URL Xtream Codes complète. Sans ça, le provider renvoie une playlist
  /// "simple" sans les attributs EXTINF (`tvg-logo`, `tvg-id`, `group-title`)
  /// → l'app n'a pas de vignettes, pas de groupage par catégorie, pas d'EPG
  /// matching XMLTV. C'est le 1er piège quand un utilisateur colle une URL
  /// fournie par défaut par son provider.
  ///
  /// Préserve `type=m3u_plus`, `type=simple` et tout autre type custom.
  /// Robuste aux query strings malformées (fallback : retour de l'URL telle
  /// quelle, l'app retombera juste sur "pas de vignettes").
  static String _ensureM3uPlus(String url) {
    try {
      final uri = Uri.parse(url);
      final params = Map<String, String>.from(uri.queryParameters);
      final t = params['type']?.toLowerCase().trim();
      if (t == 'm3u') {
        params['type'] = 'm3u_plus';
        return uri.replace(queryParameters: params).toString();
      }
      return url;
    } catch (_) {
      return url;
    }
  }

  String? buildPlayerApiUrl() {
    // Mode separate : on utilise baseUrl tel quel.
    if (mode == StreamAuthMode.separate && (baseUrl ?? '').trim().isNotEmpty) {
      try {
        final uri = Uri.parse(baseUrl!);
        return Uri(
          scheme: uri.scheme,
          host: uri.host,
          port: uri.port,
          path: '/player_api.php',
        ).toString();
      } catch (_) {
        return null;
      }
    }

    // §17a — Mode completeUrl : tenter l'extraction des creds depuis l'URL
    // Xtream pour reconstruire le player_api.php. La plupart des URLs ".m3u
    // complètes" fournies par les providers sont en réalité du Xtream
    // déguisé (`/get.php?username=X&password=Y&type=m3u_plus`).
    if (mode == StreamAuthMode.completeUrl &&
        (completeUrl ?? '').trim().isNotEmpty) {
      final creds = XtreamCredentials.tryExtract(completeUrl!.trim());
      if (creds == null) return null;
      try {
        final uri = Uri.parse(creds.host);
        return Uri(
          scheme: uri.scheme,
          host: uri.host,
          port: uri.port,
          path: '/player_api.php',
        ).toString();
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// §17a — Retourne les credentials Xtream utilisables pour appeler
  /// `player_api.php`, quelle que soit la `mode` du compte. Pour les comptes
  /// `separate`, retourne les champs `username`/`password` du modèle. Pour les
  /// comptes `completeUrl`, tente l'extraction depuis l'URL.
  /// Null si rien d'extractible (URL non-Xtream / Flussonic / autre).
  ({String host, String username, String password})? resolveXtreamCredentials() {
    if (mode == StreamAuthMode.separate) {
      final b = (baseUrl ?? '').trim();
      final u = (username ?? '').trim();
      final p = (password ?? '').trim();
      if (b.isEmpty || u.isEmpty || p.isEmpty) return null;
      try {
        final uri = Uri.parse(b);
        final host = Uri(scheme: uri.scheme, host: uri.host, port: uri.port).toString();
        return (host: host, username: u, password: p);
      } catch (_) {
        return null;
      }
    }
    return XtreamCredentials.tryExtract((completeUrl ?? '').trim());
  }

  /// Indique si le compte a de quoi construire une URL .m3u.
  bool get isUsable => buildM3uUrl() != null;

  /// Sérialisation JSON (stockage sécurisé).
  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'mode': mode == StreamAuthMode.completeUrl ? 'complete' : 'separate',
    'completeUrl': completeUrl,
    'baseUrl': baseUrl,
    'username': username,
    'password': password,
    'cookies': cookies,
    'playlistType': playlistType.name,
    'createdAt': createdAt.toIso8601String(),
  };

  /// Désérialisation JSON.
  factory StreamAccount.fromJson(Map<String, dynamic> j) {
    return StreamAccount(
      id: j['id'] as String,
      label: (j['label'] as String?)?.trim().isNotEmpty == true
          ? (j['label'] as String).trim()
          : 'Compte IPTV',
      mode: (j['mode'] == 'complete')
          ? StreamAuthMode.completeUrl
          : StreamAuthMode.separate,
      completeUrl: j['completeUrl'] as String?,
      baseUrl: j['baseUrl'] as String?,
      username: j['username'] as String?,
      password: j['password'] as String?,
      cookies: j['cookies'] as String?,
      playlistType: PlaylistType.values.byName(j['playlistType'] ?? 'm3u'),
      createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
    );
  }

  /// Copie immuable pratique pour modifier quelques champs.
  StreamAccount copyWith({
    String? id,
    String? label,
    StreamAuthMode? mode,
    String? completeUrl,
    String? baseUrl,
    String? username,
    String? password,
    String? cookies,
    PlaylistType? playlistType,
    DateTime? createdAt,
  }) {
    return StreamAccount(
      id: id ?? this.id,
      label: label ?? this.label,
      mode: mode ?? this.mode,
      completeUrl: completeUrl ?? this.completeUrl,
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      cookies: cookies ?? this.cookies,
      playlistType: playlistType ?? this.playlistType,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() =>
      'StreamAccount(id=$id, label=$label, mode=$mode, usable=$isUsable)';
}

/// §17a — Helper d'extraction des credentials Xtream depuis une URL "complète".
///
/// Couvre les 2 formats les plus courants :
///   1. Query params : `http://host:port/get.php?username=X&password=Y&type=m3u_plus`
///   2. Path Xtream  : `http://host:port/{username}/{password}/{stream_id}.ext`
///
/// Retourne `null` si l'URL n'est pas Xtream-compatible (Flussonic, format
/// custom…), auquel cas l'app affichera "info indisponible" pour ce compte.
class XtreamCredentials {
  static ({String host, String username, String password})? tryExtract(
    String rawUrl,
  ) {
    if (rawUrl.isEmpty) return null;
    Uri? uri;
    try {
      uri = Uri.parse(rawUrl);
    } catch (_) {
      return null;
    }
    if (uri.scheme.isEmpty || uri.host.isEmpty) return null;

    final origin =
        Uri(scheme: uri.scheme, host: uri.host, port: uri.port).toString();

    // Format 1 : query params username/password (incluant /get.php).
    final qpUser = uri.queryParameters['username']?.trim();
    final qpPass = uri.queryParameters['password']?.trim();
    if (qpUser != null && qpUser.isNotEmpty && qpPass != null && qpPass.isNotEmpty) {
      return (host: origin, username: qpUser, password: qpPass);
    }

    // Format 2 : path Xtream `/{user}/{pass}/{stream_id}[.ext]`.
    // On accepte `/live/`, `/movie/`, `/series/`, `/timeshift/` comme préfixe
    // optionnel, puis 2 segments user/pass, puis au moins 1 segment de plus.
    final segments = uri.pathSegments
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    if (segments.length >= 3) {
      const prefixes = {'live', 'movie', 'series', 'timeshift'};
      int startIdx = 0;
      if (prefixes.contains(segments.first.toLowerCase())) startIdx = 1;
      if (segments.length >= startIdx + 3) {
        final u = segments[startIdx];
        final p = segments[startIdx + 1];
        // Heuristique anti-faux-positif : user et pass ne ressemblent pas à
        // un chemin de fichier (pas d'extension `.m3u8`, pas de point).
        if (u.isNotEmpty &&
            p.isNotEmpty &&
            !u.contains('.') &&
            !p.contains('.')) {
          return (host: origin, username: u, password: p);
        }
      }
    }

    return null;
  }
}
