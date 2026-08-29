import 'package:cached_network_image/cached_network_image.dart';
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
  List<String> get candidates {
    final out = <String>[];
    for (final u in [url, ...alternates]) {
      if (u == null || u.isEmpty) continue;
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

  @override
  void didUpdateWidget(covariant AetherImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Les listes recyclent leurs cartes : un nouveau jeu d'adresses doit
    // repartir du premier candidat, pas hériter des échecs du précédent.
    final before = oldWidget.candidates;
    final now = widget.candidates;
    if (before.length != now.length ||
        !List.generate(now.length, (i) => before[i] == now[i]).every((e) => e)) {
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
    final candidates = widget.candidates;
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
