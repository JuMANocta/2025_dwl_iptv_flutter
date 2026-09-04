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

**§videoStatsPlus (2026-09-02) — mesurer ce que le conteneur ne déclare pas.**
Extension du patch 3, marquée `§videoStatsPlus` dans
`VideoPlayerMethodHandler.kt`. Le constat : `player.videoFormat` porte
`frameRate` et `bitrate`… **quand le flux les déclare**. Un TS live n'en déclare
aucun — sur une chaîne 4K réelle, l'encart n'affichait donc **ni images/s ni
débit**. Ajouté :
- **`renderedFps`** — images/s RÉELLEMENT rendues, dérivées de
  `videoDecoderCounters.renderedOutputBufferCount` échantillonné entre deux
  relevés. C'est l'`estimated-vf-fps` de mpv, que §tourFix avait retiré du
  modèle faute d'équivalent : il y en a un, il se calcule au lieu de se lire.
  ⚠️ `ensureUpdated()` obligatoire (compteurs incrémentés sur le thread de
  rendu, publiés paresseusement) ; échantillon ignoré sous 0,5 s, sinon le
  chiffre saute.
- **`networkBitrate` / `bytesTransferred`** — via `onBandwidthEstimate`. Le
  débit **servi**, à distinguer du débit **annoncé** : un panel qui bride ne se
  voit que là. Mesuré sur une chaîne 4K : 423 Mb/s en pointe de téléchargement.
- **`skippedFrames`**, et la piste **audio** (codec, canaux, échantillonnage,
  décodeur) — qui n'était exposée nulle part.

⚠️ Toutes ces valeurs sont remises à zéro dans `resetStats()` : garder le débit
du flux précédent ferait mentir l'encart pendant les premières secondes du
suivant.

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

**Patch 9 — `mediaInfo` par chargement (§nowPlaying, 2026-09-04).** Amont,
les métadonnées « Now Playing » (titre, sous-titre, image) ne se posaient que
par le champ `final` du constructeur de `NativeVideoPlayerController` :
figées pour la vie du contrôleur. Or l'app en réutilise **un seul** pour
enchaîner les épisodes (§episodeMeta) — la notification aurait porté le titre
du premier film pour toujours. Le natif lisait pourtant déjà `mediaInfo` à
chaque `load` (`handleLoad` → `updateMediaInfo`) : seul le côté Dart
l'empêchait de changer. `load()` et `loadUrl()` acceptent un `mediaInfo`
optionnel, replié sur le champ du constructeur. ⚠️ **C'est ce paramètre — et
lui seul — qui active la MediaSession, la notification `MediaStyle` et le
service de premier plan `mediaPlayback`** du paquet : `null` = rien ne
démarre, ce qui est le comportement voulu sur téléviseur.

**Patch 10 — jeton de session sans réflexion (§nowPlaying, 2026-09-04).**
`buildNotification()` convertissait le jeton Media3 par **réflexion**
(`getSessionCompatToken()`) puis `as? android.support.v4…MediaSessionCompat.Token`.
Depuis Media3 1.4 la méthode rend un `androidx.media3.session.legacy…Token` :
le cast rendait `null` **sans exception**, le repli « notification sans jeton »
était pris en silence, et la notification n'avait **aucun bouton** ni aucune
commande depuis l'écran verrouillé. ⚠️ Constaté à l'AVD, pas déduit :
`dumpsys notification` sans extra `android.mediaSession`, `dumpsys
media_session` → « Media button session is null », `input keyevent 127` sans
effet sur la lecture. Remplacé par la voie officielle
`MediaStyleNotificationHelper.MediaStyle(session)` (media3-session), qui prend
la `MediaSession` Media3 directement ; `androidx.media` n'est plus utilisé ici.

Patchs 5 à 8, appliqués pendant §engineVendor et marqués dans le code :
5 `NO_VIEW` n'est pas une panne (fermeture), 6 précision de `seek`,
7 `stopNow()` avant `dispose`, 8 langue audio préférée (§trackLangPref).

## 🛡️ Réserve §engineFeatures — NE PAS « nettoyer »

Un audit du 2026-09-01 a inventorié ce qui, dans ce paquet, n'est pas encore
appelé par l'app. **Décision utilisateur explicite : tout est à GARDER** — ce
sont les fonctionnalités pour lesquelles le vendorage a été choisi (« il y a
les options de cast etc. qui pourront servir »). Ne prendre AUCUN de ces blocs
pour du code mort :

- **Cast/Chromecast** : `lib/cast.dart` + `src/services/cast/` (~980 l. Dart,
  + dépendance `multicast_dns`) — ✅ **branché le 2026-09-04 (§castSend)** via
  `lib/data/services/cast_service.dart`, importé par le point d'entrée séparé
  `package:better_native_video_player/cast.dart` (pas le barrel). **Aucun
  patch** du paquet n'a été nécessaire ; ⚠️ le récepteur ne pousse son statut
  que sur changement d'état, l'app l'interroge (`requestStatus()`) chaque
  seconde ;
- **Notifications / MediaSession / écran verrouillé** :
  `VideoPlayerNotificationHandler.kt` + `VideoPlayerMediaSessionService.kt`
  (~607 l. Kotlin, deps `media3-session` + `androidx.media`) ;
- **PiP** : dépendance `floating` (l'app passe `allowsPictureInPicture: false`
  pour l'instant) ;
- **Téléchargements natifs** (`video_download_controller*`, `VideoCacheManager.kt`),
  **playlists**, **analytics de lecture**, **sous-titres sidecar**,
  **vignettes storyboard**, **AirPlay** (iOS) et le dossier `ios/` complet.

Le jour où l'une de ces capacités est branchée → §engineFeatures en roadmap.

**§apkDiet (2026-09-02) n'a retiré ZÉRO ligne d'ici**, et c'est un résultat, pas
un oubli. Le régime d'APK visait justement ce paquet en apparence : les
bibliothèques natives font 94,6 % du poids. Mais la mesure a montré que le
volume n'est pas dans les *fonctionnalités* — il est dans le nombre d'**ABI**.
Le même code Media3, compilé pour trois architectures au lieu de deux, coûtait
22,5 Mo ; supprimer Cast, les notifications et le PiP réunis n'aurait rendu
qu'une fraction de cela, en brûlant la réserve. Retirer une architecture inutile
ne coûte aucune capacité ; retirer du code en coûte.

## Écarts déjà appliqués à la copie

- `CLAUDE.md` amont renommé **`UPSTREAM_CLAUDE.md`** : laissé tel quel, il serait
  chargé comme instructions projet dès qu'on travaille dans ce sous-dossier.
- `example/`, `.dart_tool/`, `build/` retirés.
- **`packages/better_native_video_extractor/` supprimé (2026-09-01).**
  Sous-paquet amont d'extraction d'URL YouTube/Vimeo, **jamais importé** :
  aucune référence dans `lib/`, ni dans le `pubspec.yaml` de l'app, ni dans
  celui du paquet vendoré. Il dépendait de `youtube_explode_dart` et de
  `package:test`, absents de la résolution → il injectait **106 erreurs** dans
  chaque `flutter analyze`, qui restait donc rouge en permanence.
  ⚠️ Le vrai coût n'était pas les 64 Ko : un `analyze` rouge en permanence
  **cache les régressions réelles**. Après retrait : 106 erreurs → 0.
  ↩️ Récupérable par `git revert` (le dossier était suivi par git).
- Aucun autre écart à ce jour — l'étape 1 du plan est une copie **à
  l'identique**, vérifiée : build natif OK et duel au comportement inchangé
  (mêmes verdicts sur les mêmes titres).

## patch 13 — le service de lecture doit se déclarer AVANT de se retirer (2026-09-05)

`VideoPlayerMediaSessionService.onStartCommand` sortait par `stopSelf()` quand
il n'avait pas de notification à afficher, avec le commentaire « bail cleanly ».

⚠️ **`stopSelf()` ne satisfait PAS le contrat de `startForegroundService()`.**
Android exige `startForeground()` dans les ~5 s, sinon il **tue le processus**.
Constaté sur Galaxy S25 (Android 16) le 2026-09-05 : quitter le lecteur puis en
relancer un depuis la fiche produisait
`ForegroundServiceDidNotStartInTimeException` — plantage complet de l'app,
exactement 5 s après le démarrage du service.

Le service se déclare désormais TOUJOURS, avec une notification de repli
minimale si besoin, et ne se retire qu'ensuite. Couvre aussi la course où
`stop()` arrive avant `onStartCommand`.
