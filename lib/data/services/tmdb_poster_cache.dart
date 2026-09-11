import 'visual_language_service.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/diagnostics/prefs_probe.dart';
import 'inferred_category_service.dart';
import 'tmdb_api_service.dart';
import 'tmdb_service.dart';

/// 🖼️ Cache mémoire des affiches TMDB résolues à la volée pour les entrées
/// dont le M3U ne fournit pas de `tvg-logo`.
///
/// Contexte (§Ultimate) : la playlist Ultimate met `tvg-logo=""` (vide) sur
/// la VOD — contrairement aux listes Premium/VOD qui embarquent directement
/// l'URL TMDB. Sans fallback, ces fiches n'affichent qu'une icône.
///
/// Règles perf (grosse playlist) :
/// - une seule recherche TMDB par (titre, type, année) — résultat **mis en
///   cache même quand il est null** (évite de re-tenter à chaque scroll),
///   pourvu que TMDB ait vraiment répondu : une erreur ou l'absence de clé
///   ne sont PAS un « introuvable » (revue 2026-09-11, D1B-01) ;
/// - les appels concurrents pour la même clé sont dédupliqués (`_inFlight`) ;
/// - rien n'est tenté si aucune clé TMDB n'est configurée.
class TmdbPosterCache {
  TmdbPosterCache._();

  static final Map<String, String?> _cache = {};
  static final Map<String, Future<String?>> _inFlight = {};

  /// §tmdbUrlPersist — Clé de stockage. Le **suffixe de version** est ce qui
  /// permet d'invalider tout le cache quand l'heuristique de recherche change :
  /// une résolution obtenue par un `_cleanQuery` bogué (cf. §cleanQuery, qui
  /// décapitait 8 259 titres) doit pouvoir être jetée d'un coup, sans quoi on
  /// servirait indéfiniment de mauvaises affiches.
  ///
  /// ⚠️ **À incrémenter à CHAQUE modification de `_cleanQuery`, de
  /// `fetchPosterAndGenre` ou du barème de recherche TMDB.**
  static const _prefsKey = 'tmdb_poster_cache_v2';

  /// Plafond d'entrées. Au-delà, on cesse d'ajouter plutôt que d'évincer : une
  /// résolution déjà connue vaut mieux qu'une nouvelle, et une éviction ferait
  /// réapparaître des vignettes vides déjà réglées.
  static const _maxEntries = 20000;

  /// Écriture différée — au défilement, des dizaines de titres se résolvent par
  /// seconde ; une écriture disque par vignette saturerait le stockage.
  static const _persistDelay = Duration(seconds: 5);
  static bool _dirty = false;

  /// ⚠️ §posterLang — **La langue fait partie de la clé.** Ce cache est
  /// persisté (§tmdbUrlPersist) : sans elle, changer « Langue des visuels »
  /// aurait continué de servir indéfiniment les affiches résolues dans
  /// l'ancienne langue, y compris après redémarrage — exactement le piège du
  /// suffixe `_v2` déjà payé sur ce cache.
  static String _key(String query, bool isTv, String? year) =>
      '${query.toLowerCase().trim()}|$isTv|${year ?? ''}'
      '|${VisualLanguageService.resolvedTag}';

  /// §tmdbUrlPersist — Recharge le cache depuis le disque. À awaiter au boot.
  ///
  /// **Pourquoi ça compte.** Ces entrées ne sont pas des images (couvertes
  /// depuis §imgDiskCache) mais des **recherches TMDB** — les requêtes les plus
  /// lentes de l'app — déclenchées pour chaque titre dont la liste ne fournit
  /// aucune affiche. Sur un catalogue « Ultimate » (aucun `tvg-logo`, aucun
  /// `tmdb_id`), c'était une vague d'appels réseau **à chaque lancement**.
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Revue 2026-09-11, D1B-14 — Une ligne au démarrage : la taille réelle
      // des préférences, ce cache compris. C'est la mesure qui décide de le
      // sortir dans un fichier dédié (seuil de la revue : ~500 Ko). Non
      // attendue : elle lit la taille du fichier, rien n'en dépend.
      unawaited(PrefsProbe.logFootprint(prefs));
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      var negatives = 0;
      decoded.forEach((k, v) {
        if (k is! String) return;
        // ⚠️ Les résultats NÉGATIFS (`null`) sont restaurés eux aussi : ce sont
        // eux qui évitent de re-chercher indéfiniment un titre que TMDB ne
        // connaît pas. Les jeter ferait repartir la vague d'appels qu'on veut
        // justement supprimer.
        if (v == null) {
          _cache[k] = null;
          negatives++;
        } else if (v is String && v.isNotEmpty) {
          _cache[k] = v;
        }
      });
      debugPrint('✅ §tmdbUrlPersist — ${_cache.length} résolutions TMDB '
          'restaurées (dont $negatives négatives)');
    } catch (e) {
      debugPrint('⚠️ §tmdbUrlPersist — lecture impossible : $e');
    }
  }

  /// Écriture groupée : un seul passage disque pour tout ce qui a été résolu
  /// pendant la fenêtre.
  static void _schedulePersist() {
    if (_dirty) return;
    _dirty = true;
    Future.delayed(_persistDelay, () async {
      _dirty = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        // Revue 2026-09-11, D1B-14 — Même écriture, chronométrée : journalisée
        // seulement si elle prend plus de 8 ms au thread UI.
        await PrefsProbe.setStringTimed(
            prefs, _prefsKey, () => jsonEncode(_cache),
            tag: '§tmdbUrlPersist');
      } catch (e) {
        debugPrint('⚠️ §tmdbUrlPersist — écriture impossible : $e');
      }
    });
  }

  /// Revue 2026-09-11, D1B-01 — Oublie les seuls titres « introuvables »
  /// (`null`), pas les affiches trouvées. Appelé quand la clé TMDB CHANGE
  /// (page TMDB, restauration `.aether`, console web) : un négatif mémorisé
  /// avant la bonne clé (ou persisté par une version antérieure à ce
  /// correctif, qui mémorisait aussi les erreurs) laissait le titre sans
  /// affiche après chaque redémarrage, sans un mot. Les affiches trouvées
  /// restent valables quelle que soit la clé : les jeter relancerait une
  /// vague de recherches pour rien.
  static Future<void> forgetNegatives() async {
    final int before = _cache.length;
    _cache.removeWhere((_, v) => v == null);
    final int dropped = before - _cache.length;
    if (dropped == 0) return;
    debugPrint('🧹 §tmdbUrlPersist — $dropped titres introuvables oubliés (clé TMDB changée)');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_cache));
    } catch (e) {
      debugPrint('⚠️ §tmdbUrlPersist — écriture impossible : $e');
    }
  }

  /// Oublie tout (entretien / changement de clé TMDB).
  static Future<void> clear() async {
    _cache.clear();
    _inFlight.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }

  @visibleForTesting
  static int get count => _cache.length;

  /// §tmdbCacheUi — Ce que la page TMDB affiche pour rendre ce cache LISIBLE.
  ///
  /// Le second chiffre est le plus important : ce sont les titres que TMDB ne
  /// connaît pas. Ils sont mémorisés **exprès** — 68 % du cache à la mesure de
  /// §tmdbUrlPersist — pour ne pas relancer la même recherche infructueuse à
  /// chaque lancement. Sans cette explication, un utilisateur qui voit
  /// « 4 000 mémorisées, 2 700 introuvables » croit à une panne.
  static int get resolvedCount => _cache.length;

  /// Nombre d'entrées NÉGATIVES (titre inconnu de TMDB).
  static int get unknownCount =>
      _cache.values.where((v) => v == null).length;

  /// Recherches réellement parties sur le réseau depuis le lancement.
  /// C'est la mesure qui prouve que la persistance sert à quelque chose.
  static int get networkResolutions => _networkResolutions;

  /// Lecture synchrone : URL d'affiche si déjà résolue, sinon null.
  static String? cached(String query, bool isTv, String? year) =>
      _cache[_key(query, isTv, year)];

  /// True si la clé a déjà été résolue (y compris résultat négatif null).
  static bool isResolved(String query, bool isTv, String? year) =>
      _cache.containsKey(_key(query, isTv, year));

  /// Résout l'affiche (réseau si nécessaire) et met le résultat en cache.
  ///
  /// §inferredCat — [categoryKey] : clé de groupe sous laquelle mémoriser la
  /// catégorie déduite des genres TMDB. Facultative : les listes qui rangent
  /// déjà leurs contenus n'en ont pas besoin, et de toute façon elles
  /// fournissent une affiche, donc ne passent pas par ici.
  static Future<String?> resolve({
    required String query,
    required bool isTv,
    String? year,
    String? groupTitle,
    String? categoryKey,
  }) {
    final k = _key(query, isTv, year);
    if (_cache.containsKey(k)) return Future.value(_cache[k]);
    final pending = _inFlight[k];
    if (pending != null) return pending;

    final Future<String?> future =
        _doResolve(query, isTv, year, groupTitle, categoryKey).then((r) {
      // §tmdbUrlPersist — On mémorise AUSSI les titres introuvables
      // (`url == null`), et on les persiste : c'est ce qui empêche de
      // re-chercher à chaque lancement un titre que TMDB ne connaît pas.
      //
      // ⚠️ Revue 2026-09-11, D1B-01 — mais SEULEMENT si la réponse est
      // DÉFINITIVE (TMDB a répondu « 0 résultat »). Sans clé, hors ligne, sur
      // un 401 ou un 429, rien n'a été cherché : persister `null` laissait ces
      // titres sans affiche après chaque redémarrage (jusqu'à 20 000), même
      // une fois la bonne clé saisie. Une erreur se retente au prochain
      // affichage.
      if ((r.url != null || r.definitive) &&
          (_cache.length < _maxEntries || _cache.containsKey(k))) {
        _cache[k] = r.url;
        _schedulePersist();
      }
      return r.url;
    }).catchError((Object e) {
      // Revue 2026-09-11, D1B-23 — une résolution qui LÈVE (lecture de la clé
      // dans le trousseau, par exemple) : rien en cache, et surtout rien de
      // coincé — sinon ce futur en erreur était rendu à tous les appels
      // suivants de la session.
      debugPrint('⚠️ §tmdbUrlPersist — résolution impossible : $e');
      return null;
    }).whenComplete(() {
      // ⚠️ Corps en BLOC, jamais `() => _inFlight.remove(k)` : `remove` rend
      // le futur retiré — CE futur-ci — et `whenComplete` attend le futur
      // rendu par son rappel : il s'attendrait lui-même, pour toujours
      // (interblocage trouvé par tmdb_poster_cache_negative_test).
      _inFlight.remove(k);
    });
    _inFlight[k] = future;
    return future;
  }

  /// §tmdbUrlPersist — Nombre de recherches TMDB réellement parties sur le
  /// réseau depuis le lancement.
  ///
  /// Instrument de mesure : c'est le seul moyen de vérifier que la persistance
  /// fait son travail. Sans clé TMDB configurée, il reste à zéro.
  static int _networkResolutions = 0;

  /// Revue 2026-09-11 (relecture de D1B-01) — Présence de la clé TMDB,
  /// mémorisée par génération de `TmdbService`. `resetInstance()` suit CHAQUE
  /// écriture ou effacement de la clé (page TMDB, restauration `.aether`,
  /// console web) et fait avancer `generation` : le mémo tombe tout seul.
  ///
  /// ⚠️ Pourquoi il existe : depuis D1B-01, « pas de clé » n'est plus mis en
  /// cache comme un introuvable. Sans ce mémo, chaque vignette montée chez un
  /// utilisateur SANS clé relisait le trousseau (canal natif), à chaque
  /// défilement et à chaque session — là où un seul `null` persisté suffisait.
  static int _keyCheckedGen = -1;
  static bool _keyPresent = false;

  static Future<bool> _hasKey() async {
    final int gen = TmdbService.generation;
    if (gen == _keyCheckedGen) return _keyPresent;
    final bool present = await TmdbApiService.hasApiKey();
    // Clé changée PENDANT la lecture : on ne mémorise pas une réponse périmée.
    if (gen == TmdbService.generation) {
      _keyPresent = present;
      _keyCheckedGen = gen;
    }
    return present;
  }

  /// `definitive` : TMDB a vraiment répondu (cf. `fetchPosterAndGenre`). Sans
  /// clé, rien n'est cherché — donc rien de définitif (D1B-01).
  static Future<({String? url, bool definitive})> _doResolve(String query,
      bool isTv, String? year, String? groupTitle, String? categoryKey) async {
    if (!await _hasKey()) {
      return (url: null, definitive: false);
    }
    // Journalisé par paliers de 25 : une ligne par recherche noierait le
    // journal (des dizaines par seconde au défilement), et ce qui nous
    // intéresse est le VOLUME, pas le détail.
    _networkResolutions++;
    if (_networkResolutions % 25 == 0) {
      debugPrint('🔍 §tmdbUrlPersist — $_networkResolutions recherches TMDB '
          'réseau depuis le lancement (${_cache.length} en cache)');
    }
    final r = await TmdbService.instance.fetchPosterAndGenre(
      query: query,
      isTv: isTv,
      year: year,
      groupTitle: groupTitle,
    );
    // §inferredCat — On range le titre même quand TMDB n'a pas d'affiche : une
    // catégorie sans image reste utile, l'inverse aussi.
    InferredCategoryService.learn(categoryKey, r.category);
    return (url: r.posterUrl, definitive: r.definitive);
  }
}
