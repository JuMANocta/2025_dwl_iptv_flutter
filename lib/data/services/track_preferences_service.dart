import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// §5 — Préférence GLOBALE de langue audio / sous-titre, mémorisée et
/// ré-appliquée (best-effort, match par langue) à l'ouverture de chaque média.
///
/// Valeurs stockées (clé de match = `track.language` sinon `track.id`) :
///   - [audio]    : langue audio préférée, ou `null` = laisser mpv choisir.
///   - [subtitle] : `null` = auto, `'no'` = sous-titres désactivés, sinon langue.
///
/// Statique + chargé une fois au boot (cf. `main()`), cohérent avec les autres
/// services (FavoritesService, WatchProgressService…).
class TrackPreferencesService {
  static const String _kAudio = 'track_pref_audio_v1';
  static const String _kSub = 'track_pref_sub_v1';

  static String? audio;
  static String? subtitle;
  static bool _loaded = false;

  static Future<void> init() async {
    if (_loaded) return;
    try {
      final p = await SharedPreferences.getInstance();
      audio = p.getString(_kAudio);
      subtitle = p.getString(_kSub);
    } catch (e) {
      debugPrint('❌ TrackPreferencesService: chargement — $e');
    }
    _loaded = true;
  }

  static Future<void> setAudio(String? value) async {
    audio = value;
    await _save(_kAudio, value);
  }

  static Future<void> setSubtitle(String? value) async {
    subtitle = value;
    await _save(_kSub, value);
  }

  static Future<void> _save(String key, String? value) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (value == null) {
        await p.remove(key);
      } else {
        await p.setString(key, value);
      }
    } catch (e) {
      debugPrint('❌ TrackPreferencesService: persistence — $e');
    }
  }
}
