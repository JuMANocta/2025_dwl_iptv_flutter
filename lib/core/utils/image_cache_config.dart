import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

/// §imgDiskCache — Cache DISQUE des images (2026-08-05).
///
/// **Problème résolu** : `Image.network` n'a qu'un cache MÉMOIRE
/// (`ImageCache`, évincé dès que la RAM se tend — exactement le cas Fire Stick
/// avec une grosse playlist). Résultat : les vignettes se re-téléchargeaient à
/// chaque retour sur la home. Le `cacheWidth` (§imgPerf) limitait le coût de
/// DÉCODAGE, pas les requêtes réseau.
///
/// **Deux politiques**, mais attention à ne pas se tromper de source
/// principale : **l'essentiel des vignettes vient des LISTES**, pas de TMDB.
/// Le hero (`bestLogoUrl`) et les cartes de recherche n'utilisent QUE l'image
/// du provider, et la carte de home fait `bestLogoUrl(...) ?? _tmdbPoster` —
/// TMDB n'est qu'un **fallback** quand la liste ne fournit aucune image.
/// Le cache `provider` porte donc le gros du bénéfice → quota le plus large.
///   - **Provider / XMLTV** (`logoUrl`, `backdropUrl`, icônes EPG) : source
///     principale des vignettes. Rétention généreuse, mais < TMDB car un panel
///     peut réattribuer un id (le bouton « Vider le cache images » d'
///     Optimisation est le recours si une affiche a changé côté fournisseur).
///   - **TMDB** (`image.tmdb.org`) : chemin immuable → rétention la plus
///     longue, mais quota d'objets plus serré (backdrops/stills lourds, et on
///     revoit rarement deux fois la même fiche).
///
/// ⚠️ `stalePeriod` explicite est INDISPENSABLE : les panels IPTV renvoient
/// souvent `no-cache`/`no-store`, ce qui court-circuiterait un cache purement
/// HTTP. Ici la durée de validité est décidée côté app.
abstract final class AetherImageCache {
  static const String _tmdbKey = 'aether_img_tmdb';
  static const String _providerKey = 'aether_img_provider';

  /// Préfixe des URLs produites par `TmdbService.getPosterUrl` — seule forme
  /// d'URL TMDB utilisée dans l'app.
  static const String _tmdbPrefix = 'https://image.tmdb.org/t/p/';

  /// Affiches / backdrops / photos TMDB (fallback + fiche) : chemin immuable
  /// → rétention la plus longue, quota serré (images unitairement lourdes :
  /// backdrops w1280, stills w780).
  /// §imgThrash — quota relevé de 400 à 1500. À 400 objets, une simple session
  /// de navigation dépassait le plafond et `flutter_cache_manager` évinçait les
  /// plus anciennes : la visite suivante repartait donc **en réseau**.
  static final CacheManager tmdb = CacheManager(
    Config(
      _tmdbKey,
      stalePeriod: const Duration(days: 60),
      maxNrOfCacheObjects: 1500,
    ),
  );

  /// Posters/logos des LISTES + icônes EPG — **source principale des
  /// vignettes** (home, hero, recherche) → le plus gros quota.
  ///
  /// §imgThrash — Quota relevé de 1200 à 4000. L'accueil seul représente déjà
  /// ~900 vignettes (≈20 catégories × 15 items × 3 types), avant le hero, la
  /// recherche et les fiches : 1200 était dépassé en une session, et chaque
  /// éviction se payait en **re-téléchargement**. À 20-60 Ko pièce, 4000 objets
  /// ≈ 150 Mo de disque — mesurés et purgeables depuis Paramètres →
  /// Optimisation.
  static final CacheManager provider = CacheManager(
    Config(
      _providerKey,
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 4000,
    ),
  );

  /// Manager adapté à [url] (TMDB vs provider).
  static CacheManager forUrl(String url) =>
      url.startsWith(_tmdbPrefix) ? tmdb : provider;

  /// Vide les deux caches (bouton « Vider le cache images » — Optimisation).
  static Future<void> emptyAll() async {
    try {
      await tmdb.emptyCache();
      await provider.emptyCache();
      debugPrint('🧹 §imgDiskCache : cache images vidé');
    } catch (e) {
      debugPrint('❌ §imgDiskCache : purge échouée — $e');
    }
  }

  /// Taille totale occupée sur le disque, en octets (0 si illisible).
  ///
  /// `flutter_cache_manager` range ses fichiers dans un sous-dossier du cache
  /// système portant la clé du Config — on somme les deux dossiers plutôt que
  /// d'interroger sa base interne (API non publique).
  static Future<int> totalSizeBytes() async {
    var total = 0;
    for (final key in const [_tmdbKey, _providerKey]) {
      try {
        final dir = await getTemporaryDirectory();
        final cacheDir = Directory('${dir.path}/$key');
        if (!await cacheDir.exists()) continue;
        await for (final f in cacheDir.list(recursive: true)) {
          if (f is File) total += await f.length();
        }
      } catch (_) {
        // dossier illisible / concurrent delete → on ignore
      }
    }
    return total;
  }
}
