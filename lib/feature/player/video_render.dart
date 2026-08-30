import 'package:flutter/foundation.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// §video4kBench — Banc d'essai du chemin de rendu vidéo.
///
/// ## Pourquoi ce levier existe
///
/// Relevé sur la box Android TV réelle (2026-08-30, §video4k) pendant 2 min 07
/// d'un film 4K HDR 10 bits : `hw=mediacodec-copy`, `res=3840x2072`, 24 img/s,
/// et surtout `perdues=15 → 1029`.
///
/// Soit **8,12 images perdues par seconde, une sur trois**, avec un
/// `decoder-frame-drop-count` resté à zéro : le décodeur tient, c'est
/// l'affichage qui jette. Et surtout, ce taux est **rigoureusement invariant
/// au débit** (identique à 1,4 et à 5,3 Mb/s) — donc ni le réseau ni la source.
/// Le coupable est le chemin `mediacodec-copy` retenu par `hwdec=auto-safe` :
/// chaque image redescend en mémoire centrale (~16 Mo) avant de remonter en
/// texture, deux fois 380 Mo/s à 24 img/s.
///
/// ## Pourquoi un réglage plutôt qu'un correctif direct
///
/// Le levier évident ([VideoRenderMode.direct]) a un **prix** :
/// `mediacodec_embed` est un rendu direct dans la Surface Android, où mpv ne
/// dessine **ni OSD ni sous-titres**. L'OSD ne coûte rien (les contrôles
/// d'AetherStream sont 100 % Flutter par-dessus), mais les **sous-titres
/// VOSTFR seraient perdus**. On ne peut donc pas l'imposer par défaut, et le
/// choix ne peut pas se faire à l'aveugle : il se mesure, sur la box, avec
/// « Infos vidéo ».
///
/// ⚠️ Chaque essai coûte un cycle de release (la box tourne un APK signé CI,
/// un `install` debug effacerait comptes et favoris) — d'où un banc d'essai
/// embarqué plutôt qu'une constante à recompiler.
///
/// ⚠️ Délibérément **hors de `PerfConfig`**, comme `VideoFitPreference` et
/// `VideoStatsPreference` : ce n'est pas un paramètre de profil, ça n'a rien à
/// faire dans les presets Confort/Équilibré/Performance ni dans les backups
/// `.aether` — un réglage de diagnostic qui voyagerait d'un appareil à l'autre
/// appliquerait à un téléphone sain le contournement d'une box malade.
enum VideoRenderMode {
  /// Comportement historique : on laisse media_kit décider (`vo=gpu`,
  /// `hwdec=auto-safe`). Sur la box, ça donne `mediacodec-copy`.
  auto(
    label: 'Auto',
    detail: 'Défaut media_kit — sur box TV : copie mémoire',
    vo: null,
    hwdec: null,
  ),

  /// Zéro copie : MediaCodec décode directement dans la Surface Android.
  /// ⚠️ Supprime les sous-titres rendus par mpv.
  direct(
    label: 'Direct',
    detail: 'Zéro copie · ⚠️ sans sous-titres',
    vo: 'mediacodec_embed',
    hwdec: 'mediacodec',
  ),

  /// Le chemin copy-back, forcé explicitement — pour comparer sans dépendre de
  /// ce qu'`auto-safe` décide ce jour-là sur ce flux.
  copy(
    label: 'Copie',
    detail: 'Copie mémoire forcée — le témoin à battre',
    vo: 'gpu',
    hwdec: 'mediacodec-copy',
  ),

  /// Décodage processeur. C'est ce que l'émulateur imposait (et où il ne
  /// perdait aucune image) : le témoin qui a innocenté le code.
  software(
    label: 'Logiciel',
    detail: 'Décodage processeur — témoin émulateur',
    vo: 'gpu',
    hwdec: 'no',
  );

  const VideoRenderMode({
    required this.label,
    required this.detail,
    required this.vo,
    required this.hwdec,
  });

  final String label;
  final String detail;

  /// `null` ⇒ on ne surcharge pas, media_kit applique son défaut de plateforme.
  final String? vo;
  final String? hwdec;
}

/// §video4kBench — Stratégie de synchro A/V, second levier du banc.
///
/// `display-resample` est le réglage historique (§avSync) : il resample l'audio
/// sur le refresh de l'écran. C'est le plus coûteux, et sur un VO qui peine il
/// peut à lui seul provoquer du framedrop — d'où le témoin `audio`, qui ne
/// coûte rien et, contrairement au rendu direct, **ne casse aucun sous-titre**.
/// À essayer AVANT d'accepter le prix de [VideoRenderMode.direct].
enum VideoSyncMode {
  displayResample(
    label: 'Écran',
    detail: 'display-resample — réglage historique',
    value: 'display-resample',
  ),
  audio(
    label: 'Audio',
    detail: 'video-sync=audio — le plus léger',
    value: 'audio',
  );

  const VideoSyncMode({
    required this.label,
    required this.detail,
    required this.value,
  });

  final String label;
  final String detail;
  final String value;
}

/// §video4kBench — Mémorise les choix du banc d'essai d'une lecture à l'autre.
///
/// Persistant par nécessité : un diagnostic se fait sur plusieurs films
/// d'affilée, et sur TV il n'y a pas de logcat (§tvLogs) pour recouper.
///
/// ⚠️ Les deux réglages ne s'appliquent qu'à la **prochaine lecture** : `vo` et
/// `hwdec` sont figés à la construction du `VideoController`, et les changer en
/// pleine lecture forcerait une reconfiguration de la chaîne vidéo — soit
/// exactement l'effet « le film se relance » déjà payé par §tv4kScale.
abstract final class VideoRenderPreference {
  static const _modeKey = 'player_video_render_mode_v1';
  static const _syncKey = 'player_video_sync_mode_v1';

  static VideoRenderMode _mode = VideoRenderMode.auto;
  static VideoSyncMode _sync = VideoSyncMode.displayResample;

  static VideoRenderMode get mode => _mode;
  static VideoSyncMode get sync => _sync;

  /// Vrai dès qu'un réglage s'écarte du comportement historique — sert à
  /// signaler dans le journal qu'un relevé n'a PAS été fait en configuration
  /// d'origine (une mesure dont on a oublié le banc est une mesure perdue).
  static bool get isOverridden =>
      _mode != VideoRenderMode.auto || _sync != VideoSyncMode.displayResample;

  /// Configuration à passer au `VideoController`. `null` quand rien n'est
  /// surchargé → media_kit garde strictement son comportement par défaut.
  static VideoControllerConfiguration? get controllerConfiguration {
    if (_mode.vo == null && _mode.hwdec == null) return null;
    return VideoControllerConfiguration(vo: _mode.vo, hwdec: _mode.hwdec);
  }

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _mode = _byName(
          prefs.getString(_modeKey), VideoRenderMode.values, VideoRenderMode.auto);
      _sync = _byName(prefs.getString(_syncKey), VideoSyncMode.values,
          VideoSyncMode.displayResample);
      if (isOverridden) {
        debugPrint('🔬 §video4kBench — rendu=${_mode.name} sync=${_sync.name}');
      }
    } catch (e) {
      debugPrint('⚠️ §video4kBench — lecture impossible : $e');
    }
  }

  static void setMode(VideoRenderMode value) {
    if (value == _mode) return;
    _mode = value;
    _persist(_modeKey, value.name);
  }

  static void setSync(VideoSyncMode value) {
    if (value == _sync) return;
    _sync = value;
    _persist(_syncKey, value.name);
  }

  /// Remet le banc au comportement d'origine.
  static void reset() {
    setMode(VideoRenderMode.auto);
    setSync(VideoSyncMode.displayResample);
  }

  static void _persist(String key, String value) {
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString(key, value))
        .catchError((e) {
      debugPrint('⚠️ §video4kBench — écriture impossible : $e');
      return false;
    });
  }

  /// Repli sur [fallback] si la valeur stockée ne correspond à rien de connu
  /// (réglage retiré d'une version à l'autre) — jamais d'exception au boot.
  static T _byName<T extends Enum>(String? name, List<T> values, T fallback) {
    if (name == null) return fallback;
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }
}
