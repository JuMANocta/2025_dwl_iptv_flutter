import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/parsed_playlist.dart';
import '../models/stream_account.dart';
import 'load_failure.dart';
import 'parsed_playlist_service.dart';
import 'xtream_api_service.dart';
import 'hidden_regions_service.dart';
import '../../feature/search/m3u_filter.dart';

/// §23 — Téléchargement du **catalogue JSON brut** (`player_api.php`).
///
/// Remplace `XtreamM3uBuilder` : au lieu d'assembler un M3U texte (puis de le
/// re-parser à coup de regex), on sauvegarde directement les réponses JSON de
/// la JSON API dans `playlist_<id>.json`. Le fichier est ensuite consommé par
/// `XtreamCatalogParser` qui produit les `M3uEntry` **sans round-trip ni perte
/// d'information** (tmdb_id, synopsis, rating, backdrops… que le M3U ne
/// transportait pas).
///
/// Format du fichier :
/// ```json
/// {
///   "v": 1,
///   "host": "http://…", "user": "…", "pass": "…",
///   "live":   [ {…stream + "_cat": "Nom catégorie"}, … ],
///   "vod":    [ … ],
///   "series": [ … ]
/// }
/// ```
/// Les noms de catégories sont **dénormalisés** dans chaque item (`_cat`) pour
/// que le parser n'ait pas besoin des listes de catégories.
///
/// ⚠️ Le fichier contient les credentials (comme l'ancien .m3u dont chaque URL
/// les embarquait) — répertoire privé app, même niveau d'exposition qu'avant.
class XtreamCatalogService {
  XtreamCatalogService._();

  /// Marqueur de format écrit dans le fichier catalogue (clé `'v'`).
  ///
  /// Revue 2026-09-11, D1A-15 — ⚠️ AUCUN lecteur ne le vérifie :
  /// `XtreamCatalogParser` ne lit pas `'v'`, et le cache analysé ne s'invalide
  /// que sur la date du fichier et `ParsedPlaylist.schemaVersion`. Changer le
  /// format impose donc d'ajouter ce contrôle au parseur, pas seulement
  /// d'incrémenter cette valeur. Gardé tel quel pour ne pas changer le
  /// fichier écrit.
  static const int fileVersion = 1;

  /// Télécharge le catalogue complet de [account] et l'écrit dans [destPath]
  /// (écriture atomique via fichier temporaire).
  ///
  /// §catalogTruth — **Le contrat a changé.** Avant, la méthode rendait `true`
  /// dès qu'une section n'était pas vide, puis écrasait le catalogue précédent.
  /// Sur un panel limité à une connexion, les 6 actions partaient en parallèle,
  /// le panel refusait les surnuméraires par un `403 Too many connections`,
  /// l'échec était avalé en `[]`, et un catalogue **amputé** remplaçait
  /// définitivement un catalogue complet.
  ///
  /// Désormais :
  /// - les actions partent **une par une** (le journal devient lisible, et on
  ///   abandonne dès la première section perdue au lieu de harceler le panel) ;
  /// - **toute section de contenu en échec ⇒ on n'écrit pas**, l'ancien
  ///   catalogue est conservé et l'échec est rendu avec son motif ;
  /// - même quand les 6 actions réussissent, une chute à zéro par rapport au
  ///   catalogue précédent est refusée (un panel saturé sait répondre
  ///   `200 []`).
  static Future<CatalogDownloadResult> downloadCatalog(
      StreamAccount account, String destPath) async {
    final creds = XtreamApiService.credentialsOf(account);
    if (creds == null) {
      return (
        written: false,
        failure: LoadFailureKind.badAccount,
        detail: 'identifiants Xtream inextractibles',
      );
    }

    final sw = Stopwatch()..start();

    // §hostGate — SÉQUENTIEL. Les 6 actions passent de toute façon par le
    // portillon (une requête à la fois par hôte) ; les enchaîner ici rend le
    // journal chronologique et permet d'abandonner tôt.
    final liveCats = await XtreamApiService.getLiveCategoriesResult(account);
    final live = await XtreamApiService.getLiveStreamsResult(account);
    final failLive = _fatal('get_live_streams', live) ??
        _fatalCats('get_live_categories', liveCats, live);
    if (failLive != null) return failLive;

    final vodCats = await XtreamApiService.getVodCategoriesResult(account);
    final vod = await XtreamApiService.getVodStreamsResult(account);
    final failVod = _fatal('get_vod_streams', vod) ??
        _fatalCats('get_vod_categories', vodCats, vod);
    if (failVod != null) return failVod;

    final seriesCats = await XtreamApiService.getSeriesCategoriesResult(account);
    final series = await XtreamApiService.getSeriesResult(account);
    final failSeries = _fatal('get_series', series) ??
        _fatalCats('get_series_categories', seriesCats, series);
    if (failSeries != null) return failSeries;

    var liveF = live.items!;
    var vodF = vod.items!;
    var seriesF = series.items!;

    // ⚠️ Compteurs pris AVANT le filtre régions : masquer une région est un
    // choix de l'utilisateur, pas une régression. Le garde-fou ci-dessous doit
    // détecter un panel qui répond `200 []`, pas un réglage volontaire.
    final nLive = liveF.length;
    final nVod = vodF.length;
    final nSeries = seriesF.length;

    // §langFilter — Filtre AU TÉLÉCHARGEMENT : les régions masquées ne sont même
    // pas écrites dans le catalogue `.json` → la "liste définitive" sur disque
    // est directement réduite. (Le filtre au PARSE reste actif pour réagir
    // instantanément à un changement de réglage sans re-télécharger ; le disque
    // se réduit au prochain refresh.)
    // §regionGaps (2026-09-05) — Les noms de catégories sont résolus ICI, AVANT
    // le filtre.
    // ⚠️ **C'est l'ordre des opérations qui créait l'asymétrie** : ce filtre
    // tournait avant `_injectCategoryNames`, donc `_cat` n'existait pas encore
    // et seule la voie TITRE était appliquée. Une région encodée dans la
    // CATÉGORIE (« Films Italiens ») était bien masquée à l'affichage (filtre
    // au parse) mais restait écrite sur le disque à chaque refresh.
    final liveNames = _categoryNames(liveCats.items ?? const []);
    final vodNames = _categoryNames(vodCats.items ?? const []);
    final seriesNames = _categoryNames(seriesCats.items ?? const []);

    if (HiddenRegionsService.hasAny) {
      final hidden = HiddenRegionsService.hidden;
      // Revue 2026-09-11, D1A-11 — Catégorie mémorisée par nom de catégorie :
      // un calcul par catégorie du panel (quelques centaines), pas un par
      // item. Même prédicat, même résultat (`contentCategoryLabel` est pure).
      final categoryMemo = CategoryLabelMemo();
      bool Function(Map<String, dynamic>) keepWith(Map<String, String> names) =>
          (it) => !isRegionHiddenForCategory(
                name: (it['name'] ?? '').toString(),
                category: categoryMemo
                    .of(names[(it['category_id'] ?? '').toString()]),
                hidden: hidden,
              );
      liveF = liveF.where(keepWith(liveNames)).toList();
      vodF = vodF.where(keepWith(vodNames)).toList();
      seriesF = seriesF.where(keepWith(seriesNames)).toList();
    }

    debugPrint('📡 XtreamCatalog « ${account.label} » en ${sw.elapsedMilliseconds} ms : '
        'live=${liveF.length} vod=${vodF.length} series=${seriesF.length}');

    // §catalogTruth — Garde anti-régression : on compare au catalogue déjà
    // analysé (en-tête du cache, aucune décompression complète).
    final previous = await ParsedPlaylistService.countsOf(account.id);
    final verdict = CatalogAcceptance.shouldWrite(
      liveOk: true,
      vodOk: true,
      seriesOk: true,
      nLive: nLive,
      nVod: nVod,
      nSeries: nSeries,
      previous: previous,
    );
    if (!verdict.write) {
      debugPrint('🛑 §catalogTruth « ${account.label} » : écriture refusée — '
          '${verdict.detail}');
      return (
        written: false,
        failure: verdict.failure,
        detail: verdict.detail,
      );
    }

    // Dénormalisation : injecte le nom de catégorie dans chaque item.
    // §parseAudit2026-06-30 — Constat n°3 : un `category_id` sans correspondance
    // dans la liste catégories (provider désynchronisé/tronqué) ne reçoit
    // aucun `_cat` → l'entrée tombe silencieusement dans "Autres" côté parse.
    // Log récapitulatif (observabilité seulement, comportement inchangé).
    final unresolvedLive = _injectCategoryNames(liveF, liveNames);
    final unresolvedVod = _injectCategoryNames(vodF, vodNames);
    final unresolvedSeries = _injectCategoryNames(seriesF, seriesNames);
    final unresolvedTotal = unresolvedLive + unresolvedVod + unresolvedSeries;
    if (unresolvedTotal > 0) {
      debugPrint('⚠️ XtreamCatalog: $unresolvedTotal item(s) sans catégorie '
          'résolue (category_id inconnu) — live=$unresolvedLive vod=$unresolvedVod '
          'series=$unresolvedSeries → tombent dans "Autres"');
    }

    final payload = <String, dynamic>{
      'v': fileVersion,
      'host': creds.host,
      'user': creds.username,
      'pass': creds.password,
      'live': liveF,
      'vod': vodF,
      'series': seriesF,
    };

    final tempPath = '$destPath.part';
    final temp = File(tempPath);
    try {
      // Revue 2026-09-11, D1A-12 — Mêmes octets que
      // `writeAsString(jsonEncode(payload), flush: true)`, sans la chaîne
      // entière ni le gel qui l'accompagnait (cf. `writeJsonMapChunked`).
      final Stopwatch swWrite = Stopwatch()..start();
      await writeJsonMapChunked(tempPath, payload);
      debugPrint('💾 XtreamCatalog « ${account.label} » écrit en '
          '${swWrite.elapsedMilliseconds} ms (§D1A-12, par tranches)');
      await temp.rename(destPath);
    } catch (e) {
      // ⚠️ Sans ce nettoyage, un `.part` de plusieurs dizaines de Mo restait
      // sur le disque après chaque écriture avortée (§acctPurge ne le voit pas
      // : il porte bien l'id du compte).
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {}
      debugPrint('❌ XtreamCatalog « ${account.label} » : écriture impossible ($e)');
      return (
        written: false,
        failure: LoadFailureKind.cacheGone,
        detail: 'écriture du catalogue impossible',
      );
    }
    return (written: true, failure: null, detail: null);
  }

  /// Échec d'une section de CONTENU → refus d'écrire, catalogue précédent gardé.
  static CatalogDownloadResult? _fatal(String action, XtreamListResult r) {
    if (r.items != null) return null;
    debugPrint('🛑 §catalogTruth $action a échoué (${r.error}) → le catalogue '
        'précédent est conservé');
    return (
      written: false,
      failure: r.kind == LoadFailureKind.busy
          ? LoadFailureKind.busy
          : LoadFailureKind.amputated,
      detail: '$action : ${r.error ?? 'échec'}',
    );
  }

  /// Échec d'une liste de CATÉGORIES. Fatal **seulement si** la section de
  /// contenu correspondante a des items : sans les noms de catégories, les
  /// 60 000 entrées tomberaient toutes dans « Autres » — l'accueil serait
  /// détruit aussi sûrement qu'avec une section vide.
  static CatalogDownloadResult? _fatalCats(
      String action, XtreamListResult cats, XtreamListResult content) {
    if (cats.items != null) return null;
    if ((content.items?.isEmpty ?? true)) {
      debugPrint('⚠️ §catalogTruth $action a échoué mais la section est vide '
          '→ sans conséquence');
      return null;
    }
    return _fatal(action, cats);
  }

  /// Map `category_id` → nom de catégorie.
  static Map<String, String> _categoryNames(List<Map<String, dynamic>> cats) {
    final out = <String, String>{};
    for (final c in cats) {
      final id = (c['category_id'] ?? '').toString();
      final name = (c['category_name'] ?? '').toString();
      if (id.isNotEmpty && name.isNotEmpty) out[id] = name;
    }
    return out;
  }

  /// Retourne le nombre d'items dont le `category_id` n'a pas de correspondance
  /// dans [catNames] (observabilité — Constat n°3, §parseAudit2026-06-30).
  static int _injectCategoryNames(
    List<Map<String, dynamic>> items,
    Map<String, String> catNames,
  ) {
    var unresolved = 0;
    for (final it in items) {
      final catId = (it['category_id'] ?? '').toString();
      final name = catNames[catId];
      if (name != null) {
        it['_cat'] = name;
      } else {
        unresolved++;
      }
    }
    return unresolved;
  }
}

/// Revue 2026-09-11, D1A-12 — Taille visée d'une tranche écrite.
const int _kChunkBytes = 256 * 1024;

/// Revue 2026-09-11, D1A-12 — Au-delà, la tranche en cours est écrite même
/// si elle n'a pas atteint [_kChunkBytes] : c'est ce qui borne le temps passé
/// d'affilée sur le thread UI (même règle que le parseur M3U, §ramDiet).
const int _kSliceMs = 8;

/// Revue 2026-09-11, D1A-12 — **Écrit `jsonEncode(map)` dans [path], octet
/// pour octet, sans jamais construire la chaîne entière.**
///
/// Ce que faisait `writeAsString(jsonEncode(payload), flush: true)` sur un
/// catalogue de 60 Mo, d'un seul tenant sur le thread UI (et aussi pendant
/// qu'on navigue : passe « reprise », `refreshIfStale`, « Tout recharger ») :
/// le texte JSON complet (UTF-16, ~120 Mo), puis sa copie UTF-8 (60 Mo), puis
/// l'écriture — trois passes et deux gros intermédiaires, l'écran figé tout
/// du long.
///
/// Ici, élément par élément avec `JsonUtf8Encoder`, qui produit directement
/// l'UTF-8 que `jsonEncode` + `utf8.encode` auraient donné (c'est son contrat
/// documenté) : ni texte intermédiaire, ni seconde passe, et le travail rend
/// la main toutes les [_kChunkBytes] ou [_kSliceMs] — chaque écriture de
/// tranche est une attente d'E/S pendant laquelle l'interface dessine.
///
/// **Mêmes octets** : `{` + `"clé":valeur` séparés par `,` + `}`, une
/// liste = `[` + éléments séparés par `,` + `]`, sans espace — exactement la
/// sortie de `jsonEncode` sans indentation. Vérifié par
/// `test/catalog_file_writer_test.dart` (comparaison octet à octet).
/// **Même durabilité** : `RandomAccessFile` + `flush()` avant fermeture, ce
/// que fait `writeAsString(…, flush: true)`.
///
/// ⛔ Pas d'isolate ici : il faudrait lui ENVOYER le graphe décodé (des
/// centaines de milliers de maps), et cette copie se fait sur le thread qui
/// envoie — le thread UI — en doublant la mémoire du catalogue.
@visibleForTesting
Future<void> writeJsonMapChunked(String path, Map<String, Object?> map) async {
  final JsonUtf8Encoder encoder = JsonUtf8Encoder();
  const int openBrace = 0x7B, closeBrace = 0x7D;
  const int openBracket = 0x5B, closeBracket = 0x5D;
  const int comma = 0x2C, colon = 0x3A;

  final RandomAccessFile raf = await File(path).open(mode: FileMode.write);
  try {
    final BytesBuilder buffer = BytesBuilder();
    final Stopwatch slice = Stopwatch()..start();

    buffer.addByte(openBrace);
    bool firstKey = true;
    for (final MapEntry<String, Object?> e in map.entries) {
      if (!firstKey) buffer.addByte(comma);
      firstKey = false;
      buffer.add(encoder.convert(e.key));
      buffer.addByte(colon);
      final Object? value = e.value;
      if (value is List) {
        buffer.addByte(openBracket);
        for (int i = 0; i < value.length; i++) {
          if (i > 0) buffer.addByte(comma);
          buffer.add(encoder.convert(value[i]));
          if (buffer.length >= _kChunkBytes ||
              slice.elapsedMilliseconds >= _kSliceMs) {
            await raf.writeFrom(buffer.takeBytes());
            slice.reset();
          }
        }
        buffer.addByte(closeBracket);
      } else {
        buffer.add(encoder.convert(value));
      }
    }
    buffer.addByte(closeBrace);
    await raf.writeFrom(buffer.takeBytes());
    await raf.flush();
  } finally {
    await raf.close();
  }
}

/// Résultat d'un téléchargement de catalogue.
///
/// `written == false` ne veut PAS dire « rien à faire » : `failure` dit
/// pourquoi, et l'appelant doit conserver le catalogue précédent plutôt que de
/// repartir sur `get.php` quand la panne est un panel saturé.
typedef CatalogDownloadResult = ({
  bool written,
  LoadFailureKind? failure,
  String? detail,
});

/// §catalogTruth — **La décision d'écrire, isolée du réseau.**
///
/// Toute la logique « ce catalogue mérite-t-il d'écraser le précédent ? » tient
/// dans une fonction pure, donc testable sans panel ni fichier.
abstract final class CatalogAcceptance {
  /// [nLive]/[nVod]/[nSeries] : compteurs **bruts** (avant le filtre régions).
  /// [previous] : compteurs du catalogue déjà analysé, ou `null` s'il n'y en a
  /// jamais eu — dans ce cas on écrit, il n'y a rien à protéger.
  ///
  /// ⚠️ Les compteurs de [previous] sont **post-filtrage** (ils viennent de la
  /// playlist analysée). On ne teste donc QUE le passage à zéro, jamais un
  /// pourcentage : comparer des ordres de grandeur entre deux mesures qui ne
  /// comptent pas la même chose produirait des faux refus à répétition.
  static ({bool write, LoadFailureKind? failure, String? detail}) shouldWrite({
    required bool liveOk,
    required bool vodOk,
    required bool seriesOk,
    required int nLive,
    required int nVod,
    required int nSeries,
    PlaylistCounts? previous,
  }) {
    if (!liveOk || !vodOk || !seriesOk) {
      final ko = [
        if (!liveOk) 'chaînes',
        if (!vodOk) 'films',
        if (!seriesOk) 'séries',
      ].join(', ');
      return (
        write: false,
        failure: LoadFailureKind.amputated,
        detail: 'section(s) en échec : $ko',
      );
    }

    if (nLive == 0 && nVod == 0 && nSeries == 0) {
      return (
        write: false,
        failure: LoadFailureKind.noSource,
        detail: 'le panel n\'a renvoyé aucun contenu',
      );
    }

    if (previous != null) {
      final sectionsVidees = [
        if (nLive == 0 && previous.tv > 0) 'chaînes (${previous.tv} → 0)',
        if (nVod == 0 && previous.films > 0) 'films (${previous.films} → 0)',
        if (nSeries == 0 && previous.series > 0)
          'séries (${previous.series} → 0)',
      ];
      if (sectionsVidees.isNotEmpty) {
        return (
          write: false,
          failure: LoadFailureKind.amputated,
          detail: 'chute à zéro : ${sectionsVidees.join(', ')}',
        );
      }
    }

    return (write: true, failure: null, detail: null);
  }
}
