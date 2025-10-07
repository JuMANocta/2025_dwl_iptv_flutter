/// Mode d’authentification IPTV.
/// - [completeUrl] : l’utilisateur fournit directement l’URL .m3u complète.
/// - [separate]   : on construit l’URL à partir de baseUrl + username + password (style Xtream Codes).
enum IptvAuthMode { completeUrl, separate }

class IptvAccount {
  /// Identifiant unique stocké dans le secure storage (ex: "acc_1712345678901").
  final String id;

  /// Label affiché à l’utilisateur (ex: "Mon Compte #1").
  String label;

  /// Mode d’authentification.
  IptvAuthMode mode;

  /// URL .m3u complète (si mode == completeUrl).
  String? completeUrl;

  /// Base URL (ex: https://host:port/) si mode == separate.
  String? baseUrl;

  /// Identifiant si mode == separate.
  String? username;

  /// Mot de passe si mode == separate.
  String? password;

  /// Cookies optionnels à injecter dans les requêtes.
  String? cookies;

  /// Date de création (info utile pour tri/diagnostic).
  DateTime createdAt;

  IptvAccount({
    required this.id,
    required this.label,
    required this.mode,
    this.completeUrl,
    this.baseUrl,
    this.username,
    this.password,
    this.cookies,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Construit l’URL .m3u utilisable pour télécharger la playlist.
  /// - En mode [completeUrl], renvoie `completeUrl`.
  /// - En mode [separate], construit l’URL standard Xtream Codes :
  ///   `{baseUrl}/get.php?username=<u>&password=<p>&type=m3u&output=ts`
  String? buildM3uUrl() {
    if (mode == IptvAuthMode.completeUrl) {
      return (completeUrl ?? '').trim().isEmpty ? null : completeUrl!.trim();
    }

    final b = (baseUrl ?? '').trim();
    final u = (username ?? '').trim();
    final p = (password ?? '').trim();
    if (b.isEmpty || u.isEmpty || p.isEmpty) return null;

    // Normalise le slash
    final hasSlash = b.endsWith('/');
    final base = hasSlash ? b.substring(0, b.length - 1) : b;

    // On évite Uri.queryParameters ici pour garder exactement le format attendu par certains panels.
    return "$base/get.php?username=$u&password=$p&type=m3u&output=ts";
  }

  /// Indique si le compte a de quoi construire une URL .m3u.
  bool get isUsable => buildM3uUrl() != null;

  /// Sérialisation JSON (stockage sécurisé).
  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'mode': mode == IptvAuthMode.completeUrl ? 'complete' : 'separate',
    'completeUrl': completeUrl,
    'baseUrl': baseUrl,
    'username': username,
    'password': password,
    'cookies': cookies,
    'createdAt': createdAt.toIso8601String(),
  };

  /// Désérialisation JSON.
  factory IptvAccount.fromJson(Map<String, dynamic> j) {
    return IptvAccount(
      id: j['id'] as String,
      label: (j['label'] as String?)?.trim().isNotEmpty == true
          ? (j['label'] as String).trim()
          : 'Compte IPTV',
      mode: (j['mode'] == 'complete')
          ? IptvAuthMode.completeUrl
          : IptvAuthMode.separate,
      completeUrl: j['completeUrl'] as String?,
      baseUrl: j['baseUrl'] as String?,
      username: j['username'] as String?,
      password: j['password'] as String?,
      cookies: j['cookies'] as String?,
      createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
    );
  }

  /// Copie immuable pratique pour modifier quelques champs.
  IptvAccount copyWith({
    String? id,
    String? label,
    IptvAuthMode? mode,
    String? completeUrl,
    String? baseUrl,
    String? username,
    String? password,
    String? cookies,
    DateTime? createdAt,
  }) {
    return IptvAccount(
      id: id ?? this.id,
      label: label ?? this.label,
      mode: mode ?? this.mode,
      completeUrl: completeUrl ?? this.completeUrl,
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      cookies: cookies ?? this.cookies,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() =>
      'IptvAccount(id=$id, label=$label, mode=$mode, usable=$isUsable)';
}
