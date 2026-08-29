import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// §videoFit — Format d'image du lecteur.
///
/// Une source 2.35:1 sur un écran 16/9 laisse des bandes noires en haut et en
/// bas ; une source 4:3 en laisse sur les côtés. Trois façons de traiter ça,
/// dans l'ordre du moins au plus destructif — c'est aussi l'ordre du menu :
/// on ne perd rien, on rogne, on déforme.
enum VideoFitMode {
  /// Image entière, proportions respectées. Bandes noires possibles.
  original(
    BoxFit.contain,
    'Original',
    'Image entière · bandes noires possibles',
    Icons.fit_screen_rounded,
  ),

  /// Agrandit jusqu'à remplir l'écran **sans déformer** : les bandes noires
  /// disparaissent, mais les bords de l'image sortent du cadre.
  zoom(
    BoxFit.cover,
    'Zoom',
    'Efface les bandes noires · rogne les bords',
    Icons.zoom_out_map_rounded,
  ),

  /// Remplit l'écran en **déformant** l'image. Aucune perte de contenu, mais
  /// les proportions sont fausses.
  stretch(
    BoxFit.fill,
    'Plein écran',
    'Remplit tout · image légèrement déformée',
    Icons.aspect_ratio_rounded,
  );

  const VideoFitMode(this.boxFit, this.label, this.description, this.icon);

  /// Ce qui est réellement passé à `Video(fit:)`.
  final BoxFit boxFit;
  final String label;
  final String description;
  final IconData icon;

  /// Mode suivant dans le cycle (bouton inline du lecteur).
  VideoFitMode get next => values[(index + 1) % values.length];
}

/// §videoFit — Mémorise le format choisi d'une vidéo à l'autre.
///
/// Volontairement HORS de `PerfConfig` : ce n'est pas un réglage de
/// performance, ça n'a rien à faire dans la page Optimisation ni dans les
/// presets Confort/Équilibré/Performance. Une préférence de lecture, un
/// stockage à elle.
///
/// ⚠️ [current] est lu de façon **synchrone** par le lecteur au moment de
/// construire l'image : la valeur est donc gardée en mémoire et rechargée une
/// seule fois au boot par [load]. Si [load] n'a pas encore tourné, on démarre
/// sur [VideoFitMode.original] — le mode qui ne dénature rien.
abstract final class VideoFitPreference {
  static const _key = 'player_video_fit_v1';

  static VideoFitMode _current = VideoFitMode.original;

  /// Format à appliquer à la prochaine lecture.
  static VideoFitMode get current => _current;

  /// À appeler une fois au démarrage (avec les autres services).
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(_key);
      if (name == null) return;
      _current = VideoFitMode.values.firstWhere(
        (m) => m.name == name,
        orElse: () => VideoFitMode.original,
      );
      debugPrint('✅ §videoFit — format restauré : ${_current.label}');
    } catch (e) {
      debugPrint('⚠️ §videoFit — lecture impossible, format par défaut : $e');
    }
  }

  /// Enregistre le choix. L'écriture disque est en tâche de fond : le lecteur
  /// applique le nouveau format immédiatement, sans attendre.
  static void set(VideoFitMode mode) {
    if (mode == _current) return;
    _current = mode;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString(_key, mode.name))
        .catchError((e) {
      debugPrint('⚠️ §videoFit — écriture impossible : $e');
      return false;
    });
  }
}
