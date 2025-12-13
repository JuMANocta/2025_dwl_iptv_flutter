class AccountInfo {
  final String username;
  final String status;
  final DateTime? expirationDate;
  final int activeConnections;
  final int maxConnections;
  final bool isTrial;

  AccountInfo({
    required this.username,
    required this.status,
    this.expirationDate,
    required this.activeConnections,
    required this.maxConnections,
    required this.isTrial,
  });

  // Factory pour créer une instance depuis le JSON de l'API
  factory AccountInfo.fromJson(Map<String, dynamic> json) {
    // Le JSON est souvent niché dans une clé 'user_info'
    final userInfo = json['user_info'] ?? json;

    DateTime? expDate;
    // L'API renvoie souvent un timestamp en secondes (Unix time)
    if (userInfo['exp_date'] != null && userInfo['exp_date'] != 'null') {
      final timestamp = int.tryParse(userInfo['exp_date'].toString());
      if (timestamp != null) {
        // Multiplier par 1000 pour convertir en millisecondes
        expDate = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
      }
    }

    return AccountInfo(
      username: userInfo['username']?.toString() ?? 'Inconnu',
      status: userInfo['status']?.toString() ?? 'Inconnu',
      expirationDate: expDate,
      activeConnections: int.tryParse(userInfo['active_cons']?.toString() ?? '0') ?? 0,
      maxConnections: int.tryParse(userInfo['max_connections']?.toString() ?? '0') ?? 0,
      isTrial: userInfo['is_trial']?.toString() == '1',
    );
  }
}
