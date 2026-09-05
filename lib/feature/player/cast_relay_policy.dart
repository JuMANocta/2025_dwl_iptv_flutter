/// §castRelay — Décisions PURES du **relais encodé** : quand le récepteur ne
/// sait décoder aucune piste audio du flux, le téléphone peut se mettre au
/// milieu — il télécharge le film, remplace la bande son par une piste que le
/// téléviseur sait lire, et sert le résultat à la télé.
///
/// ⚠️ **Ce n'est pas un mode par défaut, et ça ne doit jamais l'être.** Le
/// téléphone devient le tuyau : le film transite deux fois par son WiFi,
/// occupe plusieurs gigaoctets de stockage temporaire et tient la batterie
/// pendant toute la séance. D'où la règle de ce fichier : **on explique, puis
/// on demande**. L'utilisateur décide en connaissance de cause.
library;

import 'cast_policy.dart';

/// Pourquoi un relais n'est PAS proposé. `null` ⇒ il l'est.
enum CastRelayBlocker {
  /// Le son passe déjà : rien à convertir.
  notNeeded,

  /// Chaîne en direct : le flux n'a pas de fin, donc la conversion non plus —
  /// le stockage temporaire grossirait sans limite.
  liveStream,

  /// Fichier déjà sur le téléphone : hors périmètre de cette première version
  /// (il faudrait le servir tel quel, pas le convertir).
  localFile,

  /// Adresse que le téléphone lui-même ne saurait pas relire.
  unsupportedSource,
}

/// Ce que l'app doit décider avant de proposer une conversion.
typedef CastRelayPlan = ({
  /// `true` ⇒ on peut proposer le relais à l'utilisateur.
  bool offered,

  /// Renseigné quand [offered] est faux.
  CastRelayBlocker? blocker,

  /// Codec de la piste audio à remplacer, pour le dire dans le message.
  String? sourceAudio,
});

/// Peut-on proposer la conversion ?
///
/// [tracks] — pistes du fichier vues par le lecteur local (§engineVendor
/// patch 11). Un relais n'a de sens que si **aucune** n'est décodable par le
/// récepteur : s'il en reste une bonne, on la lui demande, c'est gratuit.
CastRelayPlan castRelayPlan({
  required bool isLocalFile,
  required bool isLive,
  required String url,
  required List<CastAudioTrack> tracks,
}) {
  String? worstCodec() {
    for (final t in tracks) {
      if (castAudioSupport(t.codec) == CastAudioSupport.no) {
        return castAudioCodecName(t.codec);
      }
    }
    return null;
  }

  if (isLocalFile) {
    return (
      offered: false,
      blocker: CastRelayBlocker.localFile,
      sourceAudio: worstCodec(),
    );
  }
  final Uri? uri = Uri.tryParse(url);
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
    return (
      offered: false,
      blocker: CastRelayBlocker.unsupportedSource,
      sourceAudio: worstCodec(),
    );
  }
  if (isLive) {
    return (
      offered: false,
      blocker: CastRelayBlocker.liveStream,
      sourceAudio: worstCodec(),
    );
  }
  // Rien à convertir si le récepteur sait déjà lire une piste.
  if (tracks.isEmpty || castPreferredAudioIndex(tracks) != null) {
    return (
      offered: false,
      blocker: CastRelayBlocker.notNeeded,
      sourceAudio: null,
    );
  }
  return (offered: true, blocker: null, sourceAudio: worstCodec());
}

/// Phrase courte expliquant pourquoi la conversion n'est pas proposée.
/// `null` quand il n'y a rien à dire (cas [CastRelayBlocker.notNeeded]).
String? castRelayBlockerMessage(CastRelayBlocker blocker) {
  return switch (blocker) {
    CastRelayBlocker.notNeeded => null,
    CastRelayBlocker.liveStream =>
      "Une chaîne en direct n'a pas de fin : la conversion non plus. Elle "
          "n'est proposée que sur un film ou un épisode.",
    CastRelayBlocker.localFile =>
      "Un fichier déjà téléchargé ne peut pas encore être converti pour le "
          'téléviseur.',
    CastRelayBlocker.unsupportedSource =>
      "Cette source ne peut pas être relayée par le téléphone.",
  };
}

/// Le texte de consentement : **ce que ça fait, ce que ça coûte, ce que ça ne
/// fera pas**. Trois blocs, dans cet ordre, parce que c'est l'ordre dans
/// lequel on décide.
///
/// [sourceAudio] — nom du codec remplacé (« AC3 (Dolby Digital) »), quand on
/// le connaît.
typedef CastRelayConsent = ({
  String what,
  List<String> costs,

  /// §castAwake — Ce que l'utilisateur peut faire de son téléphone pendant
  /// la diffusion (éteindre l'écran), maintenant que le service la tient.
  String awake,
  List<String> limits,
  String confirmLabel,
  String cancelLabel,
});

/// §castBattery — Sous ce seuil, on demande de brancher : le téléphone
/// porte la diffusion (et tout le film en relais), s'il s'éteint tout
/// s'arrête. Décision utilisateur 2026-09-04 : 15 %.
const int kCastLowBatteryPercent = 15;

/// La note batterie du consentement : un fait utile plutôt qu'une peur.
///
/// **Brancher est toujours conseillé** (demande utilisateur, 2026-09-05) :
/// la conversion fait tourner décodeur et encodeur pendant tout le film, et
/// un téléphone branché n'entre jamais en mode Sommeil. Deux registres, à ne
/// pas confondre : le **conseil** (« si tu peux ») tant que la batterie
/// tient, l'**alerte** (« la diffusion en dépend ») sous le seuil.
String castRelayBatteryNote({int? percent, bool? charging}) {
  if (charging == true) {
    return 'Le téléphone est branché, parfait pour un film.';
  }
  if (percent == null) {
    return 'Branche le téléphone si tu peux : la conversion consomme beaucoup '
        'de batterie.';
  }
  if (percent < kCastLowBatteryPercent) {
    return 'Batterie à $percent % — branche le téléphone, la diffusion en '
        'dépend.';
  }
  return 'Batterie à $percent %. Branche le téléphone si tu peux, la '
      'conversion consomme beaucoup.';
}

/// §castAwake — L'écran peut s'éteindre : le service de premier plan tient un
/// verrou CPU pendant toute la diffusion (`AetherCastService`). Avant lui, la
/// note disait « garde l'appli ouverte » — et l'écran qui s'éteignait tuait
/// la diffusion (constaté le 2026-09-05). Le dire, c'est aussi permettre à
/// l'utilisateur de poser son téléphone au lieu de le tenir allumé deux
/// heures.
const String kCastRelayAwakeNote =
    "Tu peux éteindre l'écran : la diffusion continue en arrière-plan.";

/// §castBattery — L'ALERTE pendant la diffusion : `null` tant que tout va
/// bien ; un texte (à afficher en rouge, écran ET notification) sous
/// [kCastLowBatteryPercent] hors charge.
String? castBatteryWarning({int? percent, bool? charging}) {
  if (percent == null || charging == true) return null;
  if (percent >= kCastLowBatteryPercent) return null;
  return 'Batterie à $percent % — branche le téléphone, la diffusion en '
      'dépend.';
}

/// ⚠️ Volontairement COURT (décision utilisateur 2026-09-04) : une phrase,
/// une note batterie, deux boutons. Le pavé « ce que ça fait / coûte / ne
/// fera pas » faisait peur sans aider à décider. Les limites (stéréo,
/// Dolby Vision, avance bornée) restent vraies mais se découvrent à
/// l'usage. Et **pas de diffusion muette** : on adapte, ou on annule.
CastRelayConsent castRelayConsent({
  required String deviceName,
  String? sourceAudio,
  int? batteryPercent,
  bool? charging,
}) {
  final String device =
      deviceName.trim().isEmpty ? 'la télé' : deviceName.trim();
  return (
    // La phrase se suffit à elle-même : elle nomme l'appareil et dit ce qui
    // sera fait. Un titre par-dessus ne ferait que la répéter.
    what: 'Ce téléviseur ne lit pas le son de ce film. Le téléphone peut '
        "l'adapter pendant la diffusion pour $device.",
    costs: [castRelayBatteryNote(percent: batteryPercent, charging: charging)],
    awake: kCastRelayAwakeNote,
    // §castResume — La conversion part désormais de la position courante :
    // il n'y a plus de « toujours depuis le début » à annoncer.
    limits: const [],
    confirmLabel: 'Adapter et diffuser',
    cancelLabel: 'Annuler',
  );
}

/// Où en est la conversion, pour l'afficher pendant la diffusion.
/// [ready] = durée déjà convertie, [total] = durée du film (peut être nulle).
String castRelayProgressLabel({
  required Duration ready,
  Duration? total,
  required bool playing,
}) {
  String mmss(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  final String avance = 'Converti jusqu\'à ${mmss(ready)}';
  if (total == null || total <= Duration.zero) return avance;
  final int pct = ((ready.inMilliseconds / total.inMilliseconds) * 100)
      .clamp(0, 100)
      .round();
  return playing ? '$avance · $pct %' : '$avance · $pct % · en pause';
}
