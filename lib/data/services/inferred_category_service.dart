import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// §inferredCat — Catégorie DÉDUITE d'un titre, pour les listes qui n'en
/// fournissent aucune.
///
/// **Le problème mesuré.** Certaines listes ne portent aucune information de
/// rangement : le format « Ultimate » (`URL#Name:Titre`) n'a pas de
/// `group-title`, et l'API JSON du même panel répond `live=0 vod=0 series=0`.
/// Sur une liste réelle : **153 062 entrées sur 153 062 sans groupe**. Quand
/// c'est le compte PRINCIPAL, l'accueil n'affiche qu'une seule rangée,
/// « Autres ».
///
/// **D'où vient la catégorie.** Ces listes-là sont justement celles qui ne
/// fournissent pas non plus d'affiche : l'app interroge donc déjà TMDB pour
/// chacune de leurs vignettes visibles (`TmdbPosterCache`). La réponse contient
/// `genre_ids` — la catégorie ne coûte **aucune requête supplémentaire**, il
/// suffisait de ne plus la jeter.
///
/// **Conséquence assumée : le rangement se remplit à l'usage.** Un titre jamais
/// affiché reste dans « Autres ». C'est le prix à payer pour ne pas lancer
/// 153 000 requêtes au démarrage — et comme la résolution suit le défilement,
/// ce que l'utilisateur regarde est justement ce qui se range en premier.
///
/// ⚠️ Persisté : sans ça le rangement repartirait de zéro à chaque lancement,
/// ce qui le rendrait inutile. Même famille que §tmdbUrlPersist (roadmap).
abstract final class InferredCategoryService {
  // §catFix (2026-09-05) — `_v2` : le vocabulaire a changé ('Enfants' →
  // 'Jeunesse', 'Musique' → 'Musical', fusion Classiques→Cultes). Les clés de
  // groupe, elles, n'ont pas bougé : sans ce bump, les libellés déjà persistés
  // survivraient au bump de `schemaVersion` et l'accueil afficherait les DEUX
  // vocabulaires côte à côte — exactement le défaut qu'on corrige.
  static const _key = 'inferred_category_v2';

  /// Plafond d'entrées. Au-delà, on cesse d'en ajouter plutôt que d'évincer :
  /// une catégorie déjà connue vaut mieux qu'une nouvelle, et l'éviction ferait
  /// « sauter » des titres d'une rangée à l'autre entre deux lancements.
  static const _maxEntries = 20000;

  static final Map<String, String> _cache = {};

  /// Incrémenté quand de nouvelles catégories ont été apprises. L'accueil s'y
  /// abonne : sans ça, un titre rangé en cours de défilement ne rejoindrait sa
  /// rangée qu'au prochain lancement.
  ///
  /// ⚠️ **Volontairement GROUPÉ, jamais notifié à chaque apprentissage.** Au
  /// défilement, des dizaines de vignettes se rangent par seconde ; ce
  /// notifieur entre dans la clé de regroupement de l'accueil, qui re-trie
  /// TOUTE la playlist. Le notifier à chaque titre re-grouperait 150 000
  /// entrées des dizaines de fois par seconde — c'est exactement l'erreur
  /// §favAudit (les favoris re-groupaient la playlist à chaque cœur). Un seul
  /// signal toutes les [_persistDelay] suffit : le rangement se met à jour par
  /// paliers, ce qui est imperceptible et gratuit.
  static final ValueNotifier<int> version = ValueNotifier(0);

  static const _persistDelay = Duration(seconds: 5);

  /// Écritures en attente — on ne touche pas au disque à chaque vignette
  /// résolue (il y en a des dizaines par seconde au défilement).
  static bool _dirty = false;

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      decoded.forEach((k, v) {
        if (k is String && v is String && v.isNotEmpty) _cache[k] = v;
      });
      debugPrint('✅ §inferredCat — ${_cache.length} catégories déduites '
          'restaurées');
    } catch (e) {
      debugPrint('⚠️ §inferredCat — lecture impossible : $e');
    }
  }

  /// Catégorie connue pour cette clé de groupe, ou `null`.
  static String? get(String? groupKey) {
    if (groupKey == null || groupKey.isEmpty) return null;
    return _cache[groupKey];
  }

  /// Enregistre la catégorie apprise pour une clé de groupe.
  static void learn(String? groupKey, String? category) {
    if (groupKey == null || groupKey.isEmpty) return;
    if (category == null || category.isEmpty) return;
    if (_cache[groupKey] == category) return;
    if (_cache.length >= _maxEntries && !_cache.containsKey(groupKey)) return;
    _cache[groupKey] = category;
    _schedulePersist();
  }

  /// Écriture disque groupée : au défilement, des dizaines de titres se rangent
  /// par seconde. Une écriture par titre saturerait le disque pour rien.
  static void _schedulePersist() {
    if (_dirty) return;
    _dirty = true;
    Future.delayed(_persistDelay, () async {
      _dirty = false;
      // Un SEUL signal pour tout ce qui a été appris pendant la fenêtre.
      version.value++;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_key, jsonEncode(_cache));
      } catch (e) {
        debugPrint('⚠️ §inferredCat — écriture impossible : $e');
      }
    });
  }

  /// Oublie tout (entretien / tests).
  static Future<void> clear() async {
    _cache.clear();
    version.value++;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }

  /// Nombre de titres rangés grâce à TMDB, faute de catégorie dans la liste.
  ///
  /// §tmdbCacheUi — N'est plus réservé aux tests : la page de la clé TMDB
  /// l'affiche pour rendre ce cache lisible, à côté du bouton qui le vide.
  static int get count => _cache.length;
}
