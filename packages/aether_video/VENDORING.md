# Paquet VENDORÉ — ne pas confondre avec une dépendance

Ce dossier est une **copie** de `better_native_video_player` **1.5.2**
(pub.dev, licence **MIT**), prise le **2026-08-31** et versionnée dans le dépôt.

`pubspec.yaml` de l'app y pointe par `path: packages/aether_video`.
⚠️ **Le nom de paquet reste `better_native_video_player`** : c'est délibéré, ça
évite de toucher un seul `import` dans l'app.

## Pourquoi une copie plutôt qu'une dépendance

Quatre manques qu'on ne peut pas corriger depuis l'extérieur. Ce sont eux, et
eux seuls, qui justifient le coût du vendorage :

| # | Manque | Correctif prévu | Ce qu'on perdrait sinon |
|---|---|---|---|
| 1 | `setVolume` plafonné à `1.0` | `LoudnessEnhancer` sur la session audio | le boost **0→200 %** (§audio) |
| 2 | aucun bypass SSL | `DataSource.Factory` trust-all **scopé IPTV** | les panels HTTPS à certificat invalide |
| 3 | aucun `AnalyticsListener` | `onDroppedVideoFrames`, `onVideoInputFormatChanged`, `videoDecoderCounters` | **§videoStats** |
| 4 | `RESIZE_MODE_FIT` figé (`android/.../VideoPlayerView.kt`) | exposer `setResizeMode` | **§videoFit** |

## Ce qui a justifié le changement de moteur

Duel mesuré sur **deux matériels réels** (téléviseur Philips + téléphone),
26 fichiers chacun, critère identique des deux côtés :
**Media3 n'a aucun échec de décodage propre, et libmpv ne rattrape rien.**
⚠️ L'émulateur disait l'inverse — ses codecs `c2.goldfish.*` délèguent au GPU de
l'hôte. **Ne jamais juger la compatibilité des formats depuis un émulateur.**

## Reprendre une version amont

Les mises à jour ne sont **plus gratuites**. Pour resynchroniser :

1. `flutter pub cache add better_native_video_player -v <version>` ;
2. comparer avec ce dossier (`diff -r`) ;
3. reporter les changements amont **en rejouant nos patchs** — ils sont tous
   marqués `§engineVendor` en commentaire dans le code ;
4. rejouer le duel sur la TV **et** sur un téléphone physique avant de valider.

## Écarts déjà appliqués à la copie

- `CLAUDE.md` amont renommé **`UPSTREAM_CLAUDE.md`** : laissé tel quel, il serait
  chargé comme instructions projet dès qu'on travaille dans ce sous-dossier.
- `example/`, `.dart_tool/`, `build/` retirés.
- Aucun autre écart à ce jour — l'étape 1 du plan est une copie **à
  l'identique**, vérifiée : build natif OK et duel au comportement inchangé
  (mêmes verdicts sur les mêmes titres).
