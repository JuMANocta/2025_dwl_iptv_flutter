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
///
/// ⚠️ §imgRightSize (2026-09-25) — Le partage réel n'est pas « liste contre
/// TMDB » mais « adresse `https://image.tmdb.org` ou non » ([forUrl]) : les
/// listes qui servent des affiches TMDB en `https` (PremiumV2 : 25 702 images
/// sur 29 183) remplissent le cache [tmdb], pas [provider].
abstract final class AetherImageCache {
  static const String _tmdbKey = 'aether_img_tmdb';
  static const String _providerKey = 'aether_img_provider';

  /// Préfixe des URLs produites par `TmdbService.getPosterUrl` — seule forme
  /// d'URL TMDB utilisée dans l'app.
  static const String _tmdbPrefix = 'https://image.tmdb.org/t/p/';

  /// §imgRightSize — Quotas retenus pour cette session : ceux de l'espace
  /// libre mesuré au démarrage ([configure]), sinon ceux d'un espace inconnu.
  static ImageDiskQuota _quota = imageDiskQuota();
  static ImageDiskQuota get quota => _quota;

  static CacheManager? _tmdb;
  static CacheManager? _provider;

  /// §imgRightSize — Fixe les quotas d'après l'espace libre, AVANT la
  /// première image. Rend `false` (et le journal le dit) si un cache existe
  /// déjà : `flutter_cache_manager` fige son quota à la construction, et un
  /// second `CacheManager` sur la même clé partagerait sa base.
  ///
  /// Appelé par `DeviceCapsService.init()` pendant `_initServices` — donc
  /// après `runApp` (§bootFast) et avant l'accueil, premier écran à images.
  static bool configure({int? freeMb}) {
    final ImageDiskQuota next = imageDiskQuota(freeMb: freeMb);
    if (_tmdb != null || _provider != null) {
      debugPrint('⚠️ §imgRightSize : caches d\'images déjà ouverts, quotas ${_quota.tier.name} gardés (demandé : ${next.tier.name}, ${freeMb ?? '?'} Mo libres)');
      return false;
    }
    _quota = next;
    debugPrint('💾 §imgRightSize : ${freeMb ?? '?'} Mo libres → quotas ${next.tier.name} (listes ${next.provider}, TMDB ${next.tmdb} images)');
    return true;
  }

  /// Affiches / backdrops / photos TMDB (fallback + fiche) : chemin immuable
  /// → rétention la plus longue.
  /// §imgThrash — quota relevé de 400 à 1500. À 400 objets, une simple session
  /// de navigation dépassait le plafond et `flutter_cache_manager` évinçait les
  /// plus anciennes : la visite suivante repartait donc **en réseau**.
  /// §imgRightSize — quota selon l'espace libre ([imageDiskQuota]).
  static CacheManager get tmdb => _tmdb ??= CacheManager(
        Config(
          _tmdbKey,
          stalePeriod: const Duration(days: 60),
          maxNrOfCacheObjects: _quota.tmdb,
        ),
      );

  /// Posters/logos des LISTES + icônes EPG — **source principale des
  /// vignettes** (home, hero, recherche) → le plus gros quota.
  ///
  /// §imgThrash — Quota relevé de 1200 à 4000. L'accueil seul représente déjà
  /// ~900 vignettes (≈20 catégories × 15 items × 3 types), avant le hero, la
  /// recherche et les fiches : 1200 était dépassé en une session, et chaque
  /// éviction se payait en **re-téléchargement**. Purgeables depuis
  /// Paramètres → Optimisation.
  /// ⚠️ §imgRightSize — mesuré le 2026-09-22 : 119 Ko par image au téléphone,
  /// 185 Ko sur TV (et non 20-60 Ko) ; d'où le quota selon l'espace libre.
  static CacheManager get provider => _provider ??= CacheManager(
        Config(
          _providerKey,
          stalePeriod: const Duration(days: 30),
          maxNrOfCacheObjects: _quota.provider,
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

/// §imgRightSize — Quotas du cache disque des images, en NOMBRE d'images :
/// `flutter_cache_manager` ne connaît pas d'autre unité.
@immutable
class ImageDiskQuota {
  /// Cache des adresses hors `https://image.tmdb.org` (listes, EPG).
  final int provider;

  /// Cache des adresses `https://image.tmdb.org` (celles de l'app ET celles
  /// des listes qui pointent vers TMDB).
  final int tmdb;

  /// Palier, pour le journal.
  final ImageDiskTier tier;

  const ImageDiskQuota({
    required this.provider,
    required this.tmdb,
    required this.tier,
  });

  @override
  bool operator ==(Object other) =>
      other is ImageDiskQuota &&
      other.provider == provider &&
      other.tmdb == tmdb &&
      other.tier == tier;

  @override
  int get hashCode => Object.hash(provider, tmdb, tier);

  @override
  String toString() => 'ImageDiskQuota(${tier.name}: $provider / $tmdb)';
}

/// §imgRightSize — Paliers de stockage, du plus serré au plus large
/// (identifiants de journal, jamais affichés).
enum ImageDiskTier { critique, serre, standard, large }

/// §imgRightSize — Sous ce seuil d'espace libre, le stockage est CRITIQUE :
/// Android lui-même commence à vider les caches des applications.
const int kCriticalStorageMb = 512;

/// §imgRightSize — Sous ce seuil, le stockage est SERRÉ (box ~8 Go) : un film
/// téléchargé, écrit sur le même stockage, n'y tient plus à l'aise.
const int kTightStorageMb = 2048;

/// §imgRightSize — Au-delà, le stockage est LARGE : on garde plus d'images.
const int kRoomyStorageMb = 8192;

/// §imgRightSize — Paliers, du plus serré au plus large.
///
/// ⛔ §imgThrash : le palier `standard` ne descend JAMAIS sous les nombres
/// d'avant (listes 4 000, TMDB 1 500) — relevés parce qu'ils saturaient en
/// une session. Seuls les paliers serrés descendent, et ils gardent de quoi
/// tenir un accueil (~900 vignettes, réparties entre les deux caches).
/// Le cache TMDB monte à 2 500 dès le palier standard : ses images sont
/// désormais demandées à la taille affichée (`tmdbSizedUrl`), une affiche
/// w342 pèse ~60 Ko contre ~145 Ko en `w600_and_h900_bestv2` — 2 500 images
/// pèsent moins que les 1 500 d'avant.
const ImageDiskQuota kImageDiskCritical =
    ImageDiskQuota(provider: 600, tmdb: 400, tier: ImageDiskTier.critique);
const ImageDiskQuota kImageDiskTight =
    ImageDiskQuota(provider: 1500, tmdb: 1000, tier: ImageDiskTier.serre);
const ImageDiskQuota kImageDiskStandard =
    ImageDiskQuota(provider: 4000, tmdb: 2500, tier: ImageDiskTier.standard);
const ImageDiskQuota kImageDiskRoomy =
    ImageDiskQuota(provider: 6000, tmdb: 4000, tier: ImageDiskTier.large);

/// §imgRightSize (2026-09-25) — Quotas du cache disque des images selon
/// l'espace LIBRE du stockage interne ([freeMb], `null` = pas mesuré).
/// **Pure** — testée (`test/image_budget_test.dart`).
///
/// **Le constat, mesuré le 2026-09-22.** Les quotas étaient fixes (4 000 +
/// 1 500 images) et supposaient 20-60 Ko par image ; les AVD en montraient 119
/// (téléphone) à 185 Ko (TV) : jusqu'à 500-700 Mo de disque, que l'appareil
/// ait 50 Go libres ou 800 Mo.
///
/// **La règle.** Plus de place → plus d'images gardées (moins de
/// retéléchargements en parcourant un gros catalogue) ; stockage serré → moins,
/// pour laisser la place aux téléchargements. Sans mesure : le palier
/// standard, jamais une réduction à l'aveugle.
///
/// ⚠️ Limite connue : la mesure inclut ce que le cache occupe déjà. Un
/// appareil juste au-dessus d'un seuil peut changer de palier d'un démarrage à
/// l'autre ; le changement évince les images les moins récemment vues, rien de
/// plus.
ImageDiskQuota imageDiskQuota({int? freeMb}) {
  if (freeMb == null || freeMb <= 0) return kImageDiskStandard;
  if (freeMb < kCriticalStorageMb) return kImageDiskCritical;
  if (freeMb < kTightStorageMb) return kImageDiskTight;
  if (freeMb < kRoomyStorageMb) return kImageDiskStandard;
  return kImageDiskRoomy;
}

/// §imgRightSize — Le défaut de Flutter pour le cache d'images décodées.
/// ⛔ §imgThrash : le budget AUTOMATIQUE ne descend jamais en dessous — sous
/// 100 Mo, la TV saccadait (re-décodage en boucle).
const int kFlutterImageCacheMb = 100;

/// §imgRightSize — Plafond du relèvement automatique : au-delà, un écran de
/// plus en mémoire ne se voit plus, et la mémoire sert mieux ailleurs.
const int kImageCacheCeilingMb = 256;

/// §imgRightSize (2026-09-25) — Budget du cache d'images DÉCODÉES
/// (`PaintingBinding.instance.imageCache`), en Mo. **Pure** — testée.
///
/// [configuredMb] est le réglage « Mémoire des images » (profil ou choix de
/// l'utilisateur) ; [memoryClassMb] la classe mémoire mesurée par la sonde
/// (§deviceCaps), `null` tant qu'elle n'a rien mesuré.
///
/// **La règle — ne fait que RELEVER.** Sur un appareil qui a de la mémoire, le
/// cache monte à 75 % de la classe mémoire, plafonné à [kImageCacheCeilingMb] :
/// plus de vignettes restent décodées, moins de re-décodage en revenant sur
/// une rangée. Classe 128 Mo (box à 1-2 Go) → 96 Mo, sous le réglage : rien ne
/// change ; AVD TV (192 Mo) → 144 Mo ; téléphone à 256 Mo → 192 Mo.
///
/// Jamais relevé :
///   - sans mesure, ou sur un appareil que le constructeur déclare à faible
///     mémoire (`lowRamDevice`) ;
///   - quand l'utilisateur a lui-même choisi MOINS que le défaut de Flutter
///     (60-90 Mo) : c'est une décision explicite, prise parce que la mémoire
///     manquait — la relever en silence ferait mentir le réglage.
/// Jamais abaissé : le résultat vaut toujours au moins [configuredMb].
///
/// ⚠️ Même logique que §bufferBudget (`buffer_policy.dart`), mais le cache
/// d'images vit hors du tas Java : la classe mémoire n'y est qu'un INDICE de
/// la gamme de l'appareil, pas une limite. Flutter vide ce cache de lui-même
/// quand Android signale une pression mémoire.
int imageCacheBudgetMb({
  required int configuredMb,
  int? memoryClassMb,
  bool lowRamDevice = false,
}) {
  if (configuredMb < kFlutterImageCacheMb) return configuredMb;
  if (lowRamDevice || memoryClassMb == null || memoryClassMb <= 0) {
    return configuredMb;
  }
  final int share = memoryClassMb * 3 ~/ 4;
  final int raised =
      share > kImageCacheCeilingMb ? kImageCacheCeilingMb : share;
  return raised > configuredMb ? raised : configuredMb;
}
