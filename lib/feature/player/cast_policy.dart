/// §castSend — Décisions PURES de la diffusion Chromecast. Rien ici ne touche
/// au réseau ni à une plateforme : c'est ce qui les rend testables sous
/// `flutter test`. Le service (`CastService`) ne fait qu'exécuter ce que ces
/// fonctions décident.
///
/// ⚠️ **Le point dur, traité de front** : le Chromecast va chercher l'URL
/// **lui-même**. Il n'envoie ni l'UA `IPTVSmartersPro` ni les cookies de
/// session (§iptvUaCompat), refuse un certificat auto-signé, et son lecteur
/// HTML5 exige des en-têtes CORS sur un manifeste HLS. Une partie des flux ne
/// sera donc pas diffusable — **et ce n'est pas un bug**. Ce fichier décide
/// *avant* de proposer la diffusion, et dit *pourquoi* dans les termes de
/// §userError : jamais un échec muet, jamais une exception brute.
library;

import '../../data/models/stream_account.dart' show XtreamCredentials;

// ── URL & format ────────────────────────────────────────────────────────────

/// Adresse à donner au récepteur pour [url].
///
/// Une chaîne Xtream en direct est servie en **MPEG-TS brut** (`/live/u/p/id.ts`,
/// ou nue `/u/p/id` sur les listes « Ultimate ») : le lecteur HTML5 du
/// récepteur ne sait pas lire ça. Les mêmes panels servent la même chaîne en
/// HLS en remplaçant l'extension par `.m3u8` — c'est cette forme qu'on envoie.
/// Films et séries (`/movie/`, `/series/`) gardent leur conteneur : un `.mkv`
/// ou `.mp4` progressif se lit tel quel.
///
/// ⚠️ Ne réécrit QUE les URL dont [XtreamCredentials.tryExtract] reconnaît la
/// forme « chemin » : une URL quelconque (fichier direct, HLS d'un autre
/// fournisseur) passe inchangée.
String castUrlFor(String url) {
  final Uri? uri = Uri.tryParse(url);
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
    return url;
  }
  final creds = XtreamCredentials.tryExtract(url);
  if (creds == null) return url;
  // Forme « query » (`get.php?username=…`) : rien à réécrire.
  if (uri.queryParameters.containsKey('username')) return url;

  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return url;
  final first = segments.first.toLowerCase();
  if (first == 'movie' || first == 'series' || first == 'timeshift') return url;

  final String last = segments.last;
  final int dot = last.lastIndexOf('.');
  final String ext = dot < 0 ? '' : last.substring(dot + 1).toLowerCase();
  if (ext == 'm3u8') return url;
  // `.ts` ou sans extension → `.m3u8`. Toute autre extension (un `.mp4` sous
  // `/live/` existe chez certains panels) : on ne devine pas.
  if (ext.isNotEmpty && ext != 'ts') return url;

  final String stem = dot < 0 ? last : last.substring(0, dot);
  final newSegments = [...segments]..[segments.length - 1] = '$stem.m3u8';
  return uri.replace(pathSegments: newSegments).toString();
}

/// Type MIME annoncé au récepteur. Il s'en sert pour choisir son lecteur :
/// HLS et DASH passent par le lecteur adaptatif, le reste par la balise vidéo.
String castContentType(String url) {
  final String path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
  final int dot = path.lastIndexOf('.');
  final String ext = dot < 0 ? '' : path.substring(dot + 1);
  return switch (ext) {
    'm3u8' => 'application/x-mpegURL',
    'mpd' => 'application/dash+xml',
    'mp4' || 'm4v' || 'mov' => 'video/mp4',
    'mkv' => 'video/x-matroska',
    'webm' => 'video/webm',
    'ts' => 'video/mp2t',
    'avi' => 'video/x-msvideo',
    'mp3' => 'audio/mpeg',
    'aac' => 'audio/aac',
    _ => 'video/mp4',
  };
}

/// `true` si [url] désigne un flux adaptatif (HLS/DASH) — le seul cas où le
/// récepteur exige des en-têtes CORS (son lecteur adaptatif est du JavaScript
/// qui télécharge manifeste et segments par `fetch`).
bool castNeedsCors(String url) {
  final t = castContentType(url);
  return t == 'application/x-mpegURL' || t == 'application/dash+xml';
}

// ── Éligibilité ─────────────────────────────────────────────────────────────

/// Ce que la sonde réseau a observé en demandant l'URL **comme le récepteur le
/// ferait** : sans UA IPTV, sans cookie, sans tolérance de certificat.
class CastProbe {
  const CastProbe({
    this.statusCode,
    this.tlsFailed = false,
    this.unreachable = false,
    this.corsAllowed = false,
  });

  /// Code HTTP obtenu, `null` si aucune réponse.
  final int? statusCode;

  /// Poignée de main TLS refusée (certificat auto-signé ou inconnu).
  final bool tlsFailed;

  /// Pas de réponse du tout (délai, connexion refusée, hôte inconnu).
  final bool unreachable;

  /// En-tête `Access-Control-Allow-Origin` présent dans la réponse.
  final bool corsAllowed;
}

/// Verdict d'éligibilité : diffusable, ou le motif en clair.
class CastEligibility {
  const CastEligibility._(this.castable, this.reason, this.warning);
  const CastEligibility.ok({String? warning}) : this._(true, null, warning);
  const CastEligibility.no(String reason) : this._(false, reason, null);

  final bool castable;

  /// Motif affiché à l'utilisateur quand [castable] est faux. Toujours en
  /// français, sans URL ni identifiant (§userError).
  final String? reason;

  /// Diffusable, mais avec une réserve à annoncer AVANT d'envoyer (son AC3
  /// que le récepteur risque de ne pas décoder…). L'utilisateur tranche.
  final String? warning;

  CastEligibility withWarning(String? warning) =>
      CastEligibility._(castable, reason, warning ?? this.warning);
}

// ── Le SON : ce que le récepteur saura décoder ──────────────────────────────

/// Une piste audio du fichier, telle que le lecteur LOCAL la voit
/// (§engineVendor patch 11 remonte le codec). Type minimal exprès : ce
/// fichier ne dépend d'aucun moteur, donc il se teste sans appareil.
typedef CastAudioTrack = ({String label, String? codec, int? channels});

/// Verdict d'une piste face au récepteur générique de Google.
enum CastAudioSupport {
  /// Codec listé par Google comme lu par le récepteur (AAC, MP3, Opus…).
  ok,

  /// Codec que le récepteur ne peut que « passer » à un ampli, jamais
  /// décoder lui-même (AC3, E-AC3) ou qui n'est pas listé du tout (DTS,
  /// TrueHD) — c'est le cas « image sans son ».
  no,

  /// Codec inconnu de cette table, ou absent : on ne présume rien.
  unknown,
}

/// Nom lisible d'un codec audio, pour l'afficher à l'utilisateur.
/// `null` si on ne sait pas le nommer.
String? castAudioCodecName(String? codec) {
  if (codec == null || codec.trim().isEmpty) return null;
  final String c = codec.toLowerCase().replaceFirst('audio/', '').trim();
  return switch (c) {
    'ac3' || 'ac-3' => 'AC3 (Dolby Digital)',
    'eac3' || 'ec-3' || 'eac3-joc' || 'ac4' => 'E-AC3 (Dolby Digital Plus)',
    'true-hd' || 'truehd' || 'mlp' => 'Dolby TrueHD',
    'vnd.dts' ||
    'dts' ||
    'vnd.dts.hd' ||
    'dts-hd' ||
    'dtshd' ||
    'vnd.dts.uhd' =>
      'DTS',
    'mp4a-latm' || 'aac' || 'mp4a' => 'AAC',
    'mpeg' || 'mpeg-l2' || 'mp3' => 'MP3',
    'opus' => 'Opus',
    'vorbis' => 'Vorbis',
    'flac' => 'FLAC',
    'raw' || 'wav' || 'pcm' => 'PCM',
    _ => null,
  };
}

/// Le récepteur générique de Google saura-t-il décoder ce codec ?
///
/// ⚠️ **Table tirée de la doc Google + MESURÉE** : la page « Formats
/// supportés » liste FLAC, HE-AAC, LC-AAC, MP3, Opus, Vorbis, WAV/LPCM ; elle
/// ne classe AC-3 et E-AC-3 qu'en **passthrough** (donc suspendu au matériel)
/// et ne mentionne **ni DTS ni TrueHD**. Constaté le 2026-09-04 sur une
/// Philips Android TV 2021/22 : un film AC3 5.1 donne **l'image sans le son**.
/// Un téléphone ne transcode pas → la seule réponse honnête est de le dire
/// avant l'envoi.
CastAudioSupport castAudioSupport(String? codec) {
  final String? name = castAudioCodecName(codec);
  if (name == null) return CastAudioSupport.unknown;
  return switch (name) {
    'AAC' || 'MP3' || 'Opus' || 'Vorbis' || 'FLAC' || 'PCM' =>
      CastAudioSupport.ok,
    _ => CastAudioSupport.no,
  };
}

/// Libellé d'une piste pour la feuille : « FR · AC3 5.1 ».
String castAudioTrackLabel(CastAudioTrack t) {
  final parts = <String>[
    if (t.label.trim().isNotEmpty) t.label.trim(),
    if (castAudioCodecName(t.codec) != null) castAudioCodecName(t.codec)!,
    if (t.channels != null && t.channels! > 0)
      switch (t.channels!) { 1 => 'mono', 2 => 'stéréo', 6 => '5.1', 8 => '7.1', _ => '${t.channels} canaux' },
  ];
  return parts.isEmpty ? 'Piste audio' : parts.join(' · ');
}

/// Ce que l'app doit dire du SON avant d'envoyer [tracks] à un récepteur.
///
/// - toutes les pistes lisibles (ou aucune information) → `null` ;
/// - **une** piste lisible parmi d'autres → on le dit, parce que le récepteur
///   prend la piste PAR DÉFAUT du fichier et qu'on ne peut pas toujours la
///   lui faire changer (voir `CastService` : on essaie, sans garantie) ;
/// - **aucune** piste lisible → « image sans son », en nommant les codecs.
String? castAudioWarningForTracks(List<CastAudioTrack> tracks) {
  if (tracks.isEmpty) return null;
  final verdicts = tracks.map((t) => castAudioSupport(t.codec)).toList();
  final int okCount = verdicts.where((v) => v == CastAudioSupport.ok).length;
  final int noCount = verdicts.where((v) => v == CastAudioSupport.no).length;
  // Aucune piste connue comme problématique : rien à annoncer.
  if (noCount == 0) return null;

  if (okCount > 0) {
    final ok = <String>[
      for (int i = 0; i < tracks.length; i++)
        if (verdicts[i] == CastAudioSupport.ok) castAudioTrackLabel(tracks[i]),
    ];
    return 'Le téléviseur ne décodera pas toutes les pistes de ce flux. '
        "L'app va lui demander : ${ok.first}. Si le son manque quand même, "
        "c'est que le récepteur a gardé sa piste par défaut.";
  }

  final names = <String>[
    for (int i = 0; i < tracks.length; i++)
      if (verdicts[i] == CastAudioSupport.no) castAudioTrackLabel(tracks[i]),
  ];
  final String detail = names.length == 1 ? names.first : names.join(', ');
  return tracks.length == 1
      ? 'Le son de ce flux est en $detail : le récepteur du téléviseur ne sait '
          "pas le décoder (image sans son). L'app ne peut pas le convertir."
      : "Aucune piste audio de ce flux n'est décodable par le récepteur du "
          'téléviseur ($detail) : image sans son. Une autre version du même '
          'titre, en AAC, passerait.';
}

/// Repli quand on ne connaît QUE le codec en cours de lecture (pas la liste
/// des pistes) — conserve le comportement du 2026-09-04.
String? castAudioWarning(String? audioCodec) {
  if (castAudioSupport(audioCodec) != CastAudioSupport.no) return null;
  return castAudioWarningForTracks(
    [(label: '', codec: audioCodec, channels: null)],
  );
}

/// §castAudio — Ce que le RÉCEPTEUR dit avoir trouvé dans le média, résumé
/// pour l'encart de diagnostic. [tracks] = (type, langue, codec) tels
/// qu'annoncés par lui.
///
/// C'est la seule façon de savoir si le choix de piste à distance est
/// possible sur un appareil donné : Google ne documente `EDIT_TRACKS_INFO`
/// que pour HLS et DASH, et un récepteur qui n'annonce rien lira la piste par
/// défaut du conteneur, quoi qu'on lui demande.
String castReceiverTracksSummary(
  List<({String type, String? language, String? codec})> tracks,
) {
  if (tracks.isEmpty) return 'aucune piste annoncée';
  final audio = tracks.where((t) => t.type.toUpperCase() == 'AUDIO').toList();
  if (audio.isEmpty) {
    return '${tracks.length} piste(s), aucune audio';
  }
  final labels = audio.map((t) {
    final name = castAudioCodecName(t.codec) ?? t.codec ?? '?';
    final lang = (t.language ?? '').trim();
    return lang.isEmpty ? name : '$lang $name';
  }).join(', ');
  return '${audio.length} audio : $labels';
}

/// Index (dans [tracks]) de la piste à demander au récepteur : la première
/// lisible par lui. `null` s'il n'y en a aucune, ou si celle par défaut
/// convient déjà.
int? castPreferredAudioIndex(List<CastAudioTrack> tracks) {
  for (int i = 0; i < tracks.length; i++) {
    if (castAudioSupport(tracks[i].codec) == CastAudioSupport.ok) return i;
  }
  return null;
}

/// Peut-on envoyer ce contenu au récepteur ?
///
/// [isLocalFile] — lecture d'un fichier téléchargé. §castLocal (2026-09-06) :
/// il n'est plus refusé — le téléphone le SERT au téléviseur
/// (`CastFileServer`), et [url] est alors l'adresse LAN de ce serveur. ⚠️
/// Sans adresse LAN (données mobiles, [url] vide), le récepteur ne peut pas
/// atteindre le téléphone : on refuse AVANT d'envoyer, avec la raison.
/// [url] — l'adresse **déjà réécrite** par [castUrlFor], ou celle du serveur.
/// [probe] — ce que la sonde a vu ; `null` si elle n'a pas pu tourner.
CastEligibility castEligibility({
  required bool isLocalFile,
  required String url,
  required CastProbe? probe,
}) {
  if (isLocalFile && url.isEmpty) {
    return const CastEligibility.no(
      "Le téléphone n'est pas sur un réseau Wi-Fi : le Chromecast ne peut "
      "pas venir chercher le fichier. Connecte-le au même réseau que la télé.",
    );
  }
  final Uri? uri = Uri.tryParse(url);
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
    return const CastEligibility.no(
      "Cette adresse n'est pas diffusable (ni http ni https).",
    );
  }
  if (probe == null) {
    return const CastEligibility.no(
      "Impossible de vérifier le flux depuis ce réseau. Réessaie dans un "
      'instant.',
    );
  }
  if (probe.tlsFailed) {
    return const CastEligibility.no(
      "Le fournisseur utilise un certificat que le Chromecast refuse (l'app, "
      "elle, l'accepte). Ce flux ne peut pas être diffusé.",
    );
  }
  if (probe.unreachable) {
    return const CastEligibility.no(
      'Le serveur du fournisseur ne répond pas depuis ce réseau.',
    );
  }
  final int code = probe.statusCode ?? 0;
  if (code == 401 || code == 403) {
    return const CastEligibility.no(
      "Ce flux n'est pas diffusable : le fournisseur exige une "
      'identification que le Chromecast ne peut pas transmettre.',
    );
  }
  if (code == 404) {
    return const CastEligibility.no(
      "Le fournisseur ne propose pas ce flux dans un format que le Chromecast "
      'sait lire (HLS).',
    );
  }
  if (code >= 400 || code == 0) {
    return CastEligibility.no(
      "Ce flux n'est pas diffusable : le fournisseur refuse une requête sans "
      "le profil IPTV de l'app (réponse HTTP $code), que le Chromecast ne peut "
      'pas imiter.',
    );
  }
  if (castNeedsCors(url) && !probe.corsAllowed) {
    return const CastEligibility.no(
      "Ce flux n'est pas diffusable : le fournisseur n'autorise pas la lecture "
      "depuis un navigateur (pas d'en-tête CORS), et c'est ainsi que le "
      'Chromecast lit le HLS.',
    );
  }
  return const CastEligibility.ok();
}

// ── Notification ────────────────────────────────────────────────────────────

/// Ce que la notification « Diffusion en cours » doit afficher.
typedef CastNotice = ({String title, String text, bool playing});

/// `null` sur téléviseur (personne n'y diffuse) ou sans permission
/// (Android 13+) — la diffusion continue sans notification, silencieusement,
/// comme §dlNotif.
CastNotice? castNotice({
  required bool isTv,
  required bool granted,
  required String deviceName,
  required String mediaTitle,
  required bool playing,
}) {
  if (isTv || !granted) return null;
  final String device =
      deviceName.trim().isEmpty ? 'Chromecast' : deviceName.trim();
  final String title =
      mediaTitle.trim().isEmpty ? 'AetherStream' : mediaTitle.trim();
  return (
    title: title,
    text: '${playing ? 'Diffusion' : 'En pause'} sur $device',
    playing: playing,
  );
}

/// Texte affiché quand le récepteur signale la fin ou une erreur, à partir de
/// son vocabulaire (`idleReason`). `null` = rien à dire (arrêt volontaire).
String? castIdleMessage(String? idleReason) {
  return switch (idleReason) {
    'FINISHED' => 'Lecture terminée sur le téléviseur.',
    'ERROR' => "Le téléviseur n'a pas pu lire ce flux (format ou adresse "
        'refusés par le récepteur).',
    'INTERRUPTED' => 'Diffusion interrompue par le téléviseur.',
    _ => null,
  };
}
