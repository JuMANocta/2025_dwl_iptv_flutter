import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../core/utils/image_cache_config.dart';

/// §imgThrash — Largeur de **décodage** d'une vignette affichée sur
/// [logicalWidth] px logiques.
///
/// **Pourquoi ce helper existe** : les `cacheWidth` étaient des constantes
/// (360 pour les cartes d'accueil, 320 pour le hero) alors que les vignettes
/// mesurent ~120-145 px logiques. Une affiche 2:3 décodée à 360 px occupe
/// 360×540×4 ≈ 777 Ko en RAM, contre ≈ 265 Ko à la bonne taille : **~3× de
/// gaspillage**, qui saturait le cache image et provoquait un re-décodage
/// permanent sur TV (vignettes qui disparaissent puis reviennent).
///
/// La bonne valeur est la largeur de rendu × `devicePixelRatio` : décoder plus
/// finement ne se voit pas, décoder moins finement rend flou. Le plafond [max]
/// protège les écrans à très forte densité, où le produit s'emballe sans gain
/// perceptible sur une vignette.
int decodeWidthFor(
  BuildContext context,
  double logicalWidth, {
  int max = 400,
}) {
  final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
  return (logicalWidth * dpr).round().clamp(80, max);
}

/// §imgRightSize — Largeurs que le serveur d'images TMDB accepte dans
/// `/t/p/w<N>/`, de la plus petite à la plus grande.
///
/// Vérifié le 2026-09-25 sur `image.tmdb.org` : les sept rendent 200 aussi bien
/// sur une AFFICHE que sur un FOND (le serveur ne distingue pas les types
/// d'image), alors qu'une largeur hors liste (`w999`) rend 400. On s'en tient
/// donc à cette échelle : une taille inventée coûterait un aller-retour raté
/// avant le repli.
const List<int> kTmdbWidths = [92, 154, 185, 342, 500, 780, 1280];

/// §imgRightSize — En dessous de cette part du besoin, une image est « trop
/// petite » et on la demande plus grande. Au-dessus, l'agrandissement ne se
/// voit pas : monter coûterait des octets sans rien montrer de plus (une
/// affiche 600 px pour un décodage à 640 px reste nette).
const double kTmdbUpscaleTolerance = 0.85;

/// §imgRightSize — Part du besoin qu'une largeur RÉÉCRITE doit couvrir : on
/// demande la plus petite largeur ≥ 90 % du décodage, pas ≥ 100 %.
///
/// Mesuré le 2026-09-25 sur l'AVD téléphone (1080×2400, 420 dpi) : les
/// vignettes s'y décodent à 360 px. Couvrir 100 % choisissait `w500`
/// (~110 Ko) alors que `w342` ne manque que de 5 % — gain réel ~25 % au lieu
/// de ~60 % (71 affiches `w500` dans le cache TMDB). Un agrandissement de
/// 11 % au plus ne se voit pas sur une vignette ; au-delà, on prend la
/// largeur suivante. ⚠️ Toujours ≥ [kTmdbUpscaleTolerance] : une image
/// « assez grande » ne doit jamais être remplacée par une plus petite qu'elle
/// sous ce seuil.
const double kTmdbDownscaleTolerance = 0.9;

final RegExp _tmdbSizedPath =
    RegExp(r'^(https?://image\.tmdb\.org/t/p/)([^/?#]+)(/[^?#]+)$');
final RegExp _tmdbWidthToken = RegExp(r'^w(\d+)$');
final RegExp _tmdbBestToken = RegExp(r'^w(\d+)_and_h\d+_bestv2$');

/// Largeur que porte un segment de taille TMDB, `null` si on ne sait pas la
/// lire SANS changer le cadrage.
///
/// `w600_and_h900_bestv2` fait TENIR l'image dans une boîte, sans la rogner :
/// c'est la même image que `w600`. Les variantes `_face` / `_multi_faces`
/// ROGNENT (sur le visage), et `h632` se règle en hauteur : les réécrire
/// changerait le cadrage, on n'y touche pas.
int? _tmdbTokenWidth(String token) {
  if (token == 'original') return 1 << 30;
  final m = _tmdbWidthToken.firstMatch(token) ?? _tmdbBestToken.firstMatch(token);
  return m == null ? null : int.tryParse(m.group(1)!);
}

/// §imgRightSize (2026-09-25) — L'adresse TMDB à la taille dont l'écran a
/// BESOIN : [neededPx] est la largeur de décodage (`cacheWidth`), en pixels
/// physiques. **Pure** — testée (`test/tmdb_sized_url_test.dart`).
///
/// **Le constat, mesuré le 2026-09-22.** Les images « du fournisseur » sont en
/// majorité des adresses TMDB choisies par le panel, en grand format :
/// PremiumV2 en sert 16 104 en `w600_and_h900_bestv2` et 9 047 en `w1280`.
/// Une vignette de rangée se décode à ~290 px : on téléchargeait (et stockait
/// sur disque) 3 à 10 fois trop d'octets — une affiche de 145 Ko quand 61 Ko
/// donnent exactement les mêmes pixels à l'écran, puisque le DÉCODAGE était
/// déjà borné à la taille affichée (§imgThrash).
///
/// **La règle.**
///   - On DESCEND vers la plus petite largeur de [kTmdbWidths] qui couvre
///     90 % de [neededPx] ([kTmdbDownscaleTolerance]) — jamais en dessous :
///     un décodage à 360 px prend `w342` (5 % d'écart, invisible), un
///     décodage à 400 px prend `w500`.
///   - On MONTE une image trop petite (le `w185` de certaines listes pour une
///     vignette de 290 px, flou) — seulement si elle manque de plus de 15 %
///     ([kTmdbUpscaleTolerance]), et vers la même cible.
///   - Une image entre 85 et 90 % du besoin est gardée telle quelle : la cible
///     serait plus grande qu'elle, jamais plus petite.
///   - Inchangé : sans largeur connue, hôte non TMDB, adresse avec paramètres,
///     segment dont le cadrage changerait (`_face`, `h632`), ou quand la
///     réécriture ne ferait rien gagner.
/// Le schéma (`http`/`https`) est gardé tel quel : il décide du cache disque
/// qui range l'image (`AetherImageCache.forUrl`).
///
/// ⚠️ L'adresse d'origine reste le REPLI (voir [AetherImage.candidates]) : si
/// la taille réécrite échoue, l'image d'origine est essayée juste après.
String tmdbSizedUrl(String url, int? neededPx) {
  if (neededPx == null || neededPx <= 0) return url;
  final m = _tmdbSizedPath.firstMatch(url);
  if (m == null) return url;
  final int? current = _tmdbTokenWidth(m.group(2)!);
  if (current == null) return url;

  int? target;
  for (final int w in kTmdbWidths) {
    if (w >= neededPx * kTmdbDownscaleTolerance) {
      target = w;
      break;
    }
  }
  if (current >= neededPx * kTmdbUpscaleTolerance) {
    // Assez grande : on ne fait que descendre, et seulement si ça allège.
    if (target == null || target >= current) return url;
  } else {
    // Nettement trop petite : on monte (au plus haut de l'échelle).
    target ??= kTmdbWidths.last;
    if (target <= current) return url;
  }
  return '${m.group(1)}w$target${m.group(3)}';
}

/// §imgRightSize — Compteurs de recette : combien d'adresses TMDB ont été
/// demandées à la taille d'affichage, et combien de fois la taille réécrite a
/// échoué (repli sur l'adresse d'origine).
///
/// Une ligne au journal pour les premières réécritures, puis toutes les 200 :
/// assez pour prouver en recette que la taille réécrite est servie et que le
/// repli ne tourne pas en boucle, sans noyer le journal (une rangée recyclée
/// recompte ses cartes). Les noms de fichier TMDB sont publics : aucune
/// adresse de fournisseur n'est journalisée.
abstract final class TmdbResizeStats {
  static int down = 0;
  static int up = 0;
  static int fallbacks = 0;

  static String _describe(String url) {
    final m = _tmdbSizedPath.firstMatch(url);
    if (m == null) return '?';
    final String path = m.group(3)!;
    return '${m.group(2)} ${path.substring(path.lastIndexOf('/') + 1)}';
  }

  static void noteRewrite(String from, String to, int neededPx) {
    final int? a = _tmdbTokenWidth(_tmdbSizedPath.firstMatch(from)?.group(2) ?? '');
    final int? b = _tmdbTokenWidth(_tmdbSizedPath.firstMatch(to)?.group(2) ?? '');
    final bool upward = a != null && b != null && b > a;
    upward ? up++ : down++;
    final int total = down + up;
    if (total <= 3 || total % 200 == 0) {
      debugPrint('🖼️ §imgRightSize : ${_describe(from)} → ${_describe(to).split(' ').first} (décodage $neededPx px) — $total réécrites (↓ $down · ↑ $up), $fallbacks repli(s)');
    }
  }

  static void noteFallback(String failed) {
    fallbacks++;
    if (fallbacks <= 20 || fallbacks % 50 == 0) {
      debugPrint('⚠️ §imgRightSize : taille réécrite en échec (${_describe(failed)}) → adresse d\'origine — $fallbacks repli(s) sur ${down + up} réécrites');
    }
  }
}

/// §imgDiskCache — Image réseau **avec cache disque**, partagée par toute l'app.
///
/// Remplace les 14 `Image.network` dupliqués : ceux-ci n'avaient qu'un cache
/// mémoire (évincé sous pression → re-téléchargement à chaque affichage sur
/// Fire Stick). Ici les octets sont persistés sur disque via
/// [AetherImageCache] (politique TMDB longue / provider courte).
///
/// Reprend à l'identique le comportement des appels remplacés :
///   - [cacheWidth] → `memCacheWidth` (cap de DÉCODAGE, §imgPerf) ;
///   - [fallback] → `errorWidget` (et `placeholder` si
///     [showFallbackWhileLoading], seul comportement des 2 sites qui avaient
///     un `loadingBuilder`) ;
///   - aucun fondu (`fadeInDuration: zero`) pour ne pas introduire d'effet
///     visuel qui n'existait pas.
///
/// ⚠️ **Ne PAS rajouter `maxWidthDiskCache` / `maxHeightDiskCache`** (§imgFix,
/// 2026-08-05 — retiré après avoir cassé le backdrop des fiches). Trois raisons :
///   1. `cached_network_image` **assert** que le `cacheManager` est un
///      `ImageCacheManager` dès qu'un de ces caps est fourni
///      (`_image_loader.dart:89`). Nos managers sont des `CacheManager` nus →
///      l'assertion casse en debug, le flux part en erreur et l'image est
///      remplacée par le `fallback` (fiche au fond gris).
///   2. C'est **redondant pour TMDB** : l'URL porte déjà la taille
///      (`/t/p/w1280/…`), donc le fichier téléchargé est déjà capé et
///      `image.width > maxWidth` est faux → aucun redimensionnement.
///   3. C'est **contre-productif pour les images provider** : le
///      redimensionnement ré-encode en **PNG**
///      (`image_cache_manager.dart:98`), ce qui peut peser plus lourd que le
///      JPEG d'origine.
/// Pour limiter le poids stocké, jouer sur la taille demandée dans l'URL.
class AetherImage extends StatefulWidget {
  /// URL distante. `null`/vide → on passe à [alternates], puis à [fallback].
  final String? url;

  /// §logoFallback — Adresses de repli, essayées **dans l'ordre** quand la
  /// précédente échoue à charger.
  ///
  /// **Le problème qu'elles règlent.** Une adresse d'image peut être présente
  /// et **morte** : le serveur d'un fournisseur répond 404, ou ne répond plus.
  /// Jusqu'ici on affichait le repli et l'affaire était close — alors qu'une
  /// AUTRE liste du même groupe proposait souvent une image parfaitement
  /// valide, et que TMDB en avait une de toute façon.
  ///
  /// ⚠️ Conséquence en cascade, mesurée : `_HomeCard` ne consultait TMDB que
  /// si AUCUNE version ne portait de `tvg-logo`. Une seule adresse morte
  /// suffisait donc à perdre **l'affiche ET la catégorie** (§inferredCat).
  final List<String> alternates;

  /// §logoFallback — Appelé quand **toutes** les adresses ont échoué.
  ///
  /// C'est le signal qui permet à l'appelant de déclencher un repli TMDB : on
  /// ne le fait qu'après avoir constaté l'échec, jamais par précaution — une
  /// requête réseau par vignette serait ruineuse sur une grosse playlist.
  final VoidCallback? onAllFailed;

  final double? width;
  final double? height;
  final BoxFit fit;

  /// Cap de décodage en mémoire (ex-`Image.network(cacheWidth:)`).
  final int? cacheWidth;

  /// Cadrage — `topCenter` sur les photos de casting (garde les yeux).
  final Alignment alignment;

  /// Arrondi appliqué à l'image ET au fallback.
  final BorderRadius? borderRadius;

  /// Widget de repli : erreur réseau, URL vide, et chargement si
  /// [showFallbackWhileLoading]. Par défaut : rien (`SizedBox.shrink`).
  final WidgetBuilder? fallback;

  /// Affiche [fallback] PENDANT le chargement (ex-`loadingBuilder`).
  final bool showFallbackWhileLoading;

  const AetherImage({
    super.key,
    required this.url,
    this.alternates = const [],
    this.onAllFailed,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.alignment = Alignment.center,
    this.borderRadius,
    this.fallback,
    this.showFallbackWhileLoading = false,
  });

  /// Adresses à essayer, dans l'ordre, sans doublon ni valeur vide.
  ///
  /// §imgRightSize — Chaque adresse TMDB est d'abord essayée à la taille dont
  /// l'écran a besoin ([tmdbSizedUrl] sur [cacheWidth]), puis TELLE QU'ELLE
  /// avant de passer au repli suivant : si le serveur refuse la taille
  /// réécrite, on retombe sur l'image d'origine, pas sur une autre image.
  List<String> get candidates {
    final out = <String>[];
    for (final u in [url, ...alternates]) {
      if (u == null || u.isEmpty) continue;
      final sized = tmdbSizedUrl(u, cacheWidth);
      if (!out.contains(sized)) out.add(sized);
      if (!out.contains(u)) out.add(u);
    }
    return out;
  }

  @override
  State<AetherImage> createState() => _AetherImageState();
}

class _AetherImageState extends State<AetherImage> {
  /// Index de l'adresse en cours d'essai.
  int _index = 0;

  /// Adresses déjà constatées en échec.
  ///
  /// ⚠️ Indispensable : `errorWidget` est rappelé à **chaque build** tant que
  /// l'image est en erreur. Sans cette garde, on avancerait plusieurs fois pour
  /// un seul échec et on brûlerait toute la liste de replis d'un coup.
  final Set<String> _failed = <String>{};

  /// Vrai une fois [AetherImage.onAllFailed] émis — il ne doit partir qu'une
  /// seule fois par jeu d'adresses.
  bool _notifiedFailure = false;

  /// §imgRightSize — [AetherImage.candidates] calculés une fois par jeu
  /// d'adresses (le build d'une rangée en relit des dizaines à chaque frame).
  late List<String> _candidates;

  /// §imgRightSize — Adresses RÉÉCRITES à la taille d'affichage : un échec sur
  /// l'une d'elles est un repli vers l'adresse d'origine, compté au journal.
  final Set<String> _sized = <String>{};

  @override
  void initState() {
    super.initState();
    _candidates = _computeCandidates();
  }

  List<String> _computeCandidates() {
    final List<String> out = widget.candidates;
    _sized.clear();
    final int? need = widget.cacheWidth;
    for (final u in [widget.url, ...widget.alternates]) {
      if (u == null || u.isEmpty || need == null) continue;
      final String sized = tmdbSizedUrl(u, need);
      if (sized != u && _sized.add(sized)) {
        TmdbResizeStats.noteRewrite(u, sized, need);
      }
    }
    return out;
  }

  @override
  void didUpdateWidget(covariant AetherImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Les listes recyclent leurs cartes : un nouveau jeu d'adresses doit
    // repartir du premier candidat, pas hériter des échecs du précédent.
    // §imgRightSize — `cacheWidth` compte aussi : il décide de la taille TMDB.
    if (oldWidget.url == widget.url &&
        oldWidget.cacheWidth == widget.cacheWidth &&
        listEquals(oldWidget.alternates, widget.alternates)) {
      return;
    }
    final before = _candidates;
    final now = _computeCandidates();
    _candidates = now;
    if (!listEquals(before, now)) {
      _index = 0;
      _failed.clear();
      _notifiedFailure = false;
    }
  }

  /// §logoFallback — Passe à l'adresse suivante après un échec de chargement.
  ///
  /// ⚠️ Reporté à la frame suivante : `errorWidget` est appelé PENDANT le
  /// build, où `setState` est interdit.
  void _advanceAfter(String failedUrl, List<String> candidates) {
    if (_failed.contains(failedUrl)) return;
    _failed.add(failedUrl);
    if (_sized.contains(failedUrl)) TmdbResizeStats.noteFallback(failedUrl);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_index + 1 < candidates.length) {
        setState(() => _index++);
      } else if (!_notifiedFailure) {
        _notifiedFailure = true;
        widget.onAllFailed?.call();
      }
    });
  }

  Widget _fallback(BuildContext context) =>
      widget.fallback?.call(context) ?? const SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    final candidates = _candidates;
    Widget child;

    if (candidates.isEmpty) {
      child = _fallback(context);
      // Aucune adresse du tout : c'est aussi un « tout a échoué », et c'est
      // même le cas le plus fréquent sur les listes sans `tvg-logo`.
      if (!_notifiedFailure && widget.onAllFailed != null) {
        _notifiedFailure = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onAllFailed!.call();
        });
      }
    } else {
      final u = candidates[_index.clamp(0, candidates.length - 1)];
      child = CachedNetworkImage(
        // §posterFlash (2026-09-08) — ⚠️ **La clé n'est pas décorative.**
        // Signalement : « les images au chargement de la série sont pas la
        // bonne pendant une seconde ». Sans clé, changer `imageUrl` réutilise
        // l'élément et son image DÉJÀ DÉCODÉE : la vignette continue d'afficher
        // le titre précédent le temps que la nouvelle arrive (lecture sans
        // coupure d'`Image`). Deux chemins y mènent : le recyclage des cartes
        // dans les rangées de l'accueil, et le remplacement affiche
        // fournisseur → TMDB sur la fiche, une fois la recherche résolue.
        // ⚠️ Le prix assumé : un bref vide (ou le repli) au lieu d'une image
        // qui n'est pas la bonne. Montrer le mauvais titre est pire que ne
        // rien montrer — c'est ce que dit le signalement.
        key: ValueKey<String>(u),
        imageUrl: u,
        cacheManager: AetherImageCache.forUrl(u),
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        alignment: widget.alignment,
        memCacheWidth: widget.cacheWidth,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        errorWidget: (ctx, _, __) {
          _advanceAfter(u, candidates);
          return _fallback(ctx);
        },
        placeholder: widget.showFallbackWhileLoading
            ? (ctx, _) => _fallback(ctx)
            : null,
      );
    }

    if (widget.borderRadius != null) {
      child = ClipRRect(borderRadius: widget.borderRadius!, child: child);
    }
    return child;
  }
}
