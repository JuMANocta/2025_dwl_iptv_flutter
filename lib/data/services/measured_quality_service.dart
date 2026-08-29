import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/quality_scale.dart';

/// §qualityTruth — Ce qu'un flux a RÉELLEMENT servi, mesuré à la lecture.
@immutable
class MeasuredQuality {
  final int width;
  final int height;

  /// Quand la mesure a été faite. Une liste peut changer d'encodage : une
  /// mesure d'il y a six mois n'engage plus grand-chose.
  final DateTime measuredAt;

  const MeasuredQuality({
    required this.width,
    required this.height,
    required this.measuredAt,
  });

  /// Étiquette de définition déduite de la hauteur. Barème PARTAGÉ avec
  /// l'encart du lecteur ([QualityScale]) : la fiche et le lecteur ne doivent
  /// pas pouvoir se contredire.
  String get definitionLabel => QualityScale.labelForHeight(height);

  /// Verdict face à la qualité annoncée par la liste pour ce flux.
  QualityVerdict verdictFor(String? announced) =>
      QualityScale.compare(announced, definitionLabel);

  String get resolutionLabel => '$width×$height';

  /// Sérialisation compacte « LxH@epoch ». Une map de maps JSON coûterait plus
  /// cher à écrire et à relire pour trois entiers.
  String encode() =>
      '${width}x$height@${measuredAt.millisecondsSinceEpoch ~/ 1000}';

  static MeasuredQuality? decode(String raw) {
    final at = raw.split('@');
    if (at.length != 2) return null;
    final wh = at[0].split('x');
    if (wh.length != 2) return null;
    final w = int.tryParse(wh[0]);
    final h = int.tryParse(wh[1]);
    final t = int.tryParse(at[1]);
    if (w == null || h == null || t == null || h <= 0) return null;
    return MeasuredQuality(
      width: w,
      height: h,
      measuredAt: DateTime.fromMillisecondsSinceEpoch(t * 1000),
    );
  }
}

/// §qualityTruth — Mémorise la définition réellement servie par chaque flux.
///
/// **Pourquoi** : la qualité affichée partout dans l'app vient du **titre**
/// (`TitleMetadata.quality`), donc du fournisseur — et certains annoncent du 4K
/// pour servir du 1080p. Une fois qu'un flux a été lu, on sait. Cette mesure
/// permet à la fiche d'afficher le vrai, à côté du promis.
///
/// ⚠️ **La mesure est enregistrée à CHAQUE lecture**, indépendamment de
/// l'encart de diagnostic §videoStats : celui-ci s'active à la demande, alors
/// que la mesure doit s'accumuler toute seule pour avoir de la valeur.
///
/// Clé = `PlayerMedia.resumeKey` (`progressKey ?? path`), donc l'URL RÉSEAU du
/// flux — la même que `M3uEntry.url` côté fiche. Conséquence voulue : un film
/// téléchargé puis lu en local se mesure sous la clé de son flux d'origine,
/// exactement comme la reprise de lecture (§1e).
abstract final class MeasuredQualityService {
  static const _key = 'measured_quality_v1';

  /// Plafond d'entrées. Au-delà, les plus ANCIENNES mesures sautent : une
  /// mesure fraîche vaut mieux qu'une mesure d'un encodage disparu.
  static const _maxEntries = 800;

  static final Map<String, MeasuredQuality> _cache = {};

  /// Incrémenté à chaque nouvelle mesure — les écrans qui affichent la qualité
  /// s'y abonnent pour se redessiner (même motif que `FavoritesService`).
  static final ValueNotifier<int> version = ValueNotifier(0);

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      decoded.forEach((k, v) {
        if (k is String && v is String) {
          final quality = MeasuredQuality.decode(v);
          if (quality != null) _cache[k] = quality;
        }
      });
      debugPrint('✅ §qualityTruth — ${_cache.length} mesures restaurées');
    } catch (e) {
      debugPrint('⚠️ §qualityTruth — lecture impossible : $e');
    }
  }

  /// Mesure connue pour ce flux, ou `null`.
  static MeasuredQuality? get(String? url) {
    if (url == null || url.isEmpty) return null;
    return _cache[url];
  }

  /// Enregistre ce qui vient d'être décodé.
  ///
  /// Ré-écrit sans condition quand la valeur change : si le fournisseur a
  /// ré-encodé son flux, c'est la mesure du jour qui fait foi.
  static void record(String? url, {required int width, required int height}) {
    if (url == null || url.isEmpty || height <= 0 || width <= 0) return;
    final previous = _cache[url];
    if (previous != null &&
        previous.width == width &&
        previous.height == height) {
      return; // rien de neuf : ni notification ni écriture disque
    }
    _cache[url] = MeasuredQuality(
      width: width,
      height: height,
      measuredAt: DateTime.now(),
    );
    _evictIfNeeded();
    version.value++;
    _persist();
  }

  static void _evictIfNeeded() {
    if (_cache.length <= _maxEntries) return;
    final entries = _cache.entries.toList()
      ..sort((a, b) => a.value.measuredAt.compareTo(b.value.measuredAt));
    for (final e in entries.take(_cache.length - _maxEntries)) {
      _cache.remove(e.key);
    }
  }

  /// Écriture en tâche de fond : la lecture vidéo ne doit jamais attendre le
  /// disque pour une donnée d'agrément.
  static void _persist() {
    SharedPreferences.getInstance().then((prefs) {
      final map = _cache.map((k, v) => MapEntry(k, v.encode()));
      return prefs.setString(_key, jsonEncode(map));
    }).catchError((e) {
      debugPrint('⚠️ §qualityTruth — écriture impossible : $e');
      return false;
    });
  }

  /// Oublie toutes les mesures (bouton d'entretien / tests).
  static Future<void> clear() async {
    _cache.clear();
    version.value++;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }

  @visibleForTesting
  static int get count => _cache.length;
}
