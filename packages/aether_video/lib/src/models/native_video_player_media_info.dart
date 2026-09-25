class NativeVideoPlayerMediaInfo {
  const NativeVideoPlayerMediaInfo({
    this.title,
    this.subtitle,
    this.album,
    this.artworkUrl,
    this.artworkHeaders,
  });

  final String? title;
  final String? subtitle;
  final String? album;
  final String? artworkUrl;

  /// AetherStream patch 30 (§notifAudit P10) — En-têtes de la requête de
  /// l'affiche ([artworkUrl]). Le natif la téléchargeait avec l'agent par
  /// défaut d'Android (« Dalvik/… ») : les hôtes de logos des panels, qui
  /// filtrent l'agent comme les flux (§iptvUaCompat), répondaient par une
  /// erreur et la notification d'une chaîne restait sans image.
  final Map<String, String>? artworkHeaders;

  Map<String, dynamic> toMap() => <String, dynamic>{
    if (title != null) 'title': title,
    if (subtitle != null) 'subtitle': subtitle,
    if (album != null) 'album': album,
    if (artworkUrl != null) 'artworkUrl': artworkUrl,
    if (artworkHeaders != null && artworkHeaders!.isNotEmpty)
      'artworkHeaders': artworkHeaders,
  };
}
