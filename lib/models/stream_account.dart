/// Mode d’authentification IPTV.
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
  /// - En mode [completeUrl], renvoie `completeUrl`.
  /// - En mode [separate], construit l’URL standard Xtream Codes :
  ///   `{baseUrl}/get.php?username=<u>&password=<p>&type=m3u&output=ts`
  String? buildM3uUrl() {
    if (mode == StreamAuthMode.completeUrl) {
      return (completeUrl ?? '').trim().isEmpty ? null : completeUrl!.trim();
    }

    final b = (baseUrl ?? '').trim();
    final u = (username ?? '').trim();
    final p = (password ?? '').trim();
    if (b.isEmpty || u.isEmpty || p.isEmpty) return null;

    // Normalise le slash
    final hasSlash = b.endsWith('/');
    final base = hasSlash ? b.substring(0, b.length - 1) : b;
    final String typeValue = playlistType == PlaylistType.simple ? 'simple' : 'm3u';

    return "$base/get.php?username=$u&password=$p&type=$typeValue&output=ts";

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
