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

## Les quatre patchs — APPLIQUÉS le 2026-08-31 (étape 2/6)

Tous marqués `§engineVendor patch N` en commentaire dans le code.

**Patch 4 — `setResizeMode` (§videoFit).** `RESIZE_MODE_FIT` était figé à la
construction de la vue. ⚠️ Il y a **deux chemins d'affichage** — le `PlayerView`
du mode normal et l'`AspectRatioFrameLayout` du mode allégé : ne patcher qu'un
seul donnerait un réglage qui marche dans une configuration et pas dans l'autre.
Constantes nommées `AetherResizeMode` (fit / fill / zoom) plutôt que des entiers
nus.

**Patch 3 — `AnalyticsListener` (§videoStats).** Images perdues, codec, débit,
résolution, et surtout le **nom du décodeur** — c'est lui qui dit « matériel ou
logiciel », l'équivalent du `hwdec-current` de mpv. Compteurs remis à zéro à
chaque chargement, pour rester comparables entre moteurs.
⚠️ `getVideoStats()` renvoie **`null`** si le natif ne répond pas, **jamais des
zéros** : un zéro se lirait comme une mesure (leçon §hwdecUnknown).
⚠️ « Matériel » se déduit du **nom** du décodeur (`c2.android.*` / `OMX.google.*`
= logiciel) : Android n'expose pas de drapeau fiable. Heuristique assumée.

**Patch 2 — Bypass SSL SCOPÉ.** Beaucoup de panels servent en HTTPS avec un
certificat auto-signé, et media_kit posait `tls-verify=no` : **la lecture en
bénéficiait déjà**, ne pas le reproduire aurait cassé des flux qui marchent.
⚠️ `DefaultHttpDataSource` n'expose aucun réglage SSL → ajout de
`media3-datasource-okhttp` (+0,1 Mo), seule voie qui n'altère pas la
configuration du processus.
⚠️ **Opt-in, par flux** (`load(allowInvalidCertificate: true)`), jamais global :
même discipline que `NetworkUtils` côté Dart, TMDB/GitHub/XMLTV restent stricts.

**Patch 1 — `LoudnessEnhancer` (§audio).** `player.volume` d'ExoPlayer est borné
à 1.0 : il atténue, il n'amplifie pas. L'app monte à **200 %** et démarre à
125 % sur TV, parce que les flux IPTV sont encodés bas. Gain en millibels
(200 % = +6,02 dB = 602 mB).
⚠️ L'effet est lié à un `audioSessionId` : **recréé quand la session change**,
et **reposé à chaque chargement**, sinon l'amplification est perdue au 2e film.
⚠️ Encapsulé : sur un appareil sans cet effet, le volume plafonne à 100 % au
lieu de faire échouer la lecture.

## Écarts déjà appliqués à la copie

- `CLAUDE.md` amont renommé **`UPSTREAM_CLAUDE.md`** : laissé tel quel, il serait
  chargé comme instructions projet dès qu'on travaille dans ce sous-dossier.
- `example/`, `.dart_tool/`, `build/` retirés.
- Aucun autre écart à ce jour — l'étape 1 du plan est une copie **à
  l'identique**, vérifiée : build natif OK et duel au comportement inchangé
  (mêmes verdicts sur les mêmes titres).
