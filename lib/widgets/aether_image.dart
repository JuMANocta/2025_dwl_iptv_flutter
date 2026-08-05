import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/utils/image_cache_config.dart';

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
class AetherImage extends StatelessWidget {
  /// URL distante. `null`/vide → [fallback] directement (pas de requête).
  final String? url;

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
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.alignment = Alignment.center,
    this.borderRadius,
    this.fallback,
    this.showFallbackWhileLoading = false,
  });

  Widget _fallback(BuildContext context) =>
      fallback?.call(context) ?? const SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    final u = url;
    Widget child;

    if (u == null || u.isEmpty) {
      child = _fallback(context);
    } else {
      child = CachedNetworkImage(
        imageUrl: u,
        cacheManager: AetherImageCache.forUrl(u),
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        memCacheWidth: cacheWidth,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        errorWidget: (ctx, _, __) => _fallback(ctx),
        placeholder: showFallbackWhileLoading
            ? (ctx, _) => _fallback(ctx)
            : null,
      );
    }

    if (borderRadius != null) {
      child = ClipRRect(borderRadius: borderRadius!, child: child);
    }
    return child;
  }
}
