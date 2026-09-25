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
⚠️ **Amendé le 2026-09-11 (revue de code, lot 8b, D2B-13) : UN client pour tout
le processus.** `insecureHttpFactory` construisait un `SSLContext` et un
`OkHttpClient` complets (pool de connexions, tâche de nettoyage) à CHAQUE
chargement de flux — un par zap, l'app demandant le bypass pour tout flux
distant —, et chaque pool abandonné gardait ses connexions inactives vers le
panel jusqu'à 5 min. Le client « trust-all » vit désormais dans le
`companion object` (`insecureClient`, `by lazy` : construit à la première
demande de bypass, jamais avant) ; seules les en-têtes varient, posées sur la
fabrique (`OkHttpDataSource.Factory(client).setDefaultRequestProperties`), donc
toujours PAR FLUX. Le périmètre ne change pas : le client n'est pris que par un
flux distant qui le demande — le partager n'élargit pas le bypass.

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

## patch 31 — casque et montre : « suivant » = +30 s, « précédent » = −30 s (2026-09-25, suite de §notifAudit P8)

**Décision utilisateur** : les touches « piste suivante / précédente » d'un casque,
d'une montre ou d'un autoradio avancent / reculent de 30 s, PARTOUT SAUF EN DIRECT
(films, séries, replay, fichier local), diffusion Cast comprise (elles commandent
alors le téléviseur).
**Le manque.** Depuis le patch 29, un contrôleur de notification est connecté : Media3
lui confie les touches média (`MediaSessionImpl.applyMediaButtonKeyEvent`), et
« précédent / suivant » d'ExoPlayer lui sont retirés — elles ne faisaient plus rien.
Les lui rendre aurait ramené « précédent » = retour au début du film.
**Le patch.** `MediaSession.Callback.onMediaButtonEvent` : `KEYCODE_MEDIA_NEXT` /
`SKIP_FORWARD` → événement `mediaAction` `seekForward`, `PREVIOUS` / `SKIP_BACKWARD`
→ `seekBack`, quand l'app l'a demandé (`setMediaActions(keys: true)`) ; sinon (direct)
Media3 garde la main, comme avant. Media3 ne passe que les appuis ; une répétition
(touche maintenue) est absorbée sans nouveau saut. La carte média du système ne
change pas (pas de « précédent / suivant » remis).
⚠️ App au PREMIER PLAN, la touche va d'abord à Flutter : le lecteur l'intercepte
(`PlayerPage._onMediaTrackKey`, règle `mediaTrackKeySeek`) avant les raccourcis
§mediaKeys de la racine — au téléphone seulement : sur TV, ⏭ reste « épisode
suivant ». Double appui du bouton unique d'un casque : non traité (il ne faisait
déjà rien sur un film seul). Tests : `test/now_playing_actions_test.dart`.

## patch 30 — l'affiche de la notification part avec l'agent IPTV et suit les redirections (2026-09-25, §notifAudit P10)

**Le manque.** `downloadArtwork` (patch 18) ouvrait l'URL avec l'agent par défaut
d'Android (« Dalvik/… ») et laissait `HttpURLConnection` gérer les redirections —
qu'il refuse de franchir entre HTTP et HTTPS. Les logos de chaînes (`tvg-logo`)
vivent souvent sur l'hôte du panel, qui filtre l'agent comme pour le flux
(§iptvUaCompat) : la notification d'une chaîne restait sans image. Et en cas
d'échec, `NpLog.e` écrivait `e.message` — pour une `FileNotFoundException`
(404, 500 d'un panel), c'est l'URL, **y compris en release**.
**Le patch.** `NativeVideoPlayerMediaInfo.artworkHeaders` (Dart) → `mediaInfo
["artworkHeaders"]` ; l'app y met le MÊME profil que le flux (`Media3Engine.
_iptvHeaders`, un seul endroit). Redirections suivies à la main (4 au plus,
HTTP/HTTPS seulement), code HTTP vérifié avant de lire. Échec : `NpLog.w` avec le
seul NOM de l'exception (ou le code HTTP) ; plus aucune URL au journal, même en
débogage (les deux `NpLog.d` qui la citaient).
⚠️ Hypothèse de la cause, pas mesure : l'audit l'avait posée sans la revérifier.
Si une chaîne reste sans vignette après ce patch, regarder le journal
(`Artwork refused (HTTP …)` / `Artwork unavailable (…)`) : un certificat invalide
sur l'hôte du logo n'est volontairement PAS toléré ici (le bypass reste scopé aux
flux, patch 2).

## patch 29 — ±30 s et « épisode suivant » dans la notification de lecture (2026-09-25, §notifAudit P8)

**Le manque.** La notification n'avait que lecture/pause — et encore : avant
Android 13, elle n'avait AUCUN bouton (pas un seul `addAction`, le système
n'affiche que ceux de la notification) ; à partir d'Android 13, le système lit
l'état de la SESSION, où ExoPlayer exposait « précédent », qui relance un film
seul depuis le début d'un appui.
**Le patch** (`VideoPlayerNotificationHandler`, `VideoPlayerMethodHandler`,
canal + contrôleur Dart) :
- méthode `setMediaActions(seek, next, labels)` : ce que l'app demande en plus
  de lecture/pause, avec les libellés traduits par l'app (§l10nAll) ;
- **Android 13+** : commandes de session maison (`aether.media.SEEK_BACK`,
  `SEEK_FORWARD`, `NEXT`) posées en `MediaButtonPreferences` (icônes Media3
  `ICON_SKIP_BACK_30` / `ICON_SKIP_FORWARD_30` / `ICON_NEXT`) ; « précédent /
  suivant » d'ExoPlayer retirés des commandes que voit le système QUAND nos
  boutons sont là (sinon il leur donne les deux places principales) ;
- ⚠️ **Le piège** (lu dans le bytecode de media3-session 1.5.0,
  `MediaSessionImpl.onConnectOnHandler` + `PlayerWrapper.createPlaybackStateCompat`) :
  les commandes que la session du SYSTÈME expose ne sont fixées QUE par le
  « contrôleur de notification » de Media3 (un `MediaController` de l'app
  connecté avec l'indice `androidx.media3.session.MediaNotificationManager`).
  Sans `MediaSessionService`, personne ne le crée : les boutons de session
  n'apparaissaient nulle part. Le gestionnaire le crée lui-même
  (`connectNotificationController`), et le libère AVANT la session. À
  revérifier à chaque montée de Media3 (clé privée).
- **Avant Android 13** : les mêmes boutons en `addAction` (−30 s · lecture/pause ·
  +30 s en vue compacte, puis suivant), sur des `PendingIntent` de diffusion
  reçus par un récepteur non exporté (même garde que `MainActivity`), enregistré
  et retiré avec la session.
- Le natif N'EXÉCUTE rien : il envoie l'événement `mediaAction` (`seekBack`,
  `seekForward`, `playPause`, `next`) ; l'app passe par les mêmes chemins que ses
  gestes (diffusion en cours → le téléviseur, amnistie §stallCount, épisode
  suivant). Les sauts n'apparaissent que si le flux se laisse parcourir
  (`COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM`, suivi par `onAvailableCommandsChanged`).
- Aucun service démarré ou arrêté par ce patch (§fgsSafeStart, patch 13) : une
  notification DÉJÀ affichée est reposée par `notify()`, jamais ressuscitée.
Libellés : ceux de l'app ; à défaut, la ressource de l'app par son NOM (méthode
du patch 21 : `notif_play`, `notif_pause` existent) ; à défaut, celle de Media3.
Tests : `test/now_playing_actions_test.dart` (la règle, côté app).

## patch 28 — les sous-titres remontent au-dessus des contrôles (2026-09-25, R50)

**Le manque.** Sur TV (recette §tvPlayerPanel), rangée d'options et barre
affichées, le sous-titre rendu par la `SubtitleView` NATIVE (sous la couche
Flutter) se dessinait sur la barre de progression ; au téléphone, même bloc bas
(§playerPanel), même recouvrement.
**Le patch.** Méthode `setSubtitleBottomInset(inset)` (pixels logiques = dp) :
`VideoPlayerView` TRANSLATE la `SubtitleView` des deux chemins d'affichage de la
part des contrôles qui mord sur le CADRE de l'image (les bandes noires d'un
2,39:1 en absorbent une partie ; en « zoom » le cadre déborde), bornée à la
moitié du cadre, en 250 ms (le fondu des contrôles). Recalculée à toute mise en
page du conteneur, du cadre ou de la vue (taille de vidéo, format, rotation,
PiP). ⚠️ Une vue tombée sous 60 % de sa hauteur depuis la pose de la marge
(entrée en PiP par le geste Accueil, que l'app apprend APRÈS coup) remet les
sous-titres en place sans attendre l'app : sinon ils sautaient au milieu de la
fenêtre flottante le temps que l'app renvoie 0. Côté Dart, la surcouche des sous-titres « sidecar » (sous-titres en ligne,
dessinés par Flutter) suit la même marge (`AnimatedPadding`), avec la MÊME règle
(`subtitleLiftInBox`, exportée et testée : `test/subtitle_inset_test.dart`). Le
contrôleur mémorise la marge et la renvoie à une vue recréée.
⚠️ Pourquoi pas une marge (`padding`) : Media3 calcule la taille du texte — et
celle des sous-titres en image, DVB/PGS — en fraction de la hauteur de la vue :
les sous-titres rapetissaient à chaque apparition des contrôles. Et pas
`setBottomPaddingFraction` : elle ignore les répliques positionnées (SSA, DVB,
PGS). Contrepartie assumée de la translation : une réplique placée tout en HAUT
(rare : panneaux SSA) peut être rognée tant que les contrôles sont affichés.

## patch 27 — le tampon a un plafond en OCTETS choisi par l'app, et un arrière (2026-09-21, §bufferBudget)

**Le manque.** `buildPlayer` ne posait que les DURÉES (`setBufferDurationsMs`) :
le plafond en octets restait celui que `DefaultLoadControl` calcule (~125 Mio pour
la vidéo), prioritaire sur la durée, et alloué dans le tas Java — plus que ce
qu'une box à 128 Mo peut donner. Aucun tampon arrière : « −10 s » retéléchargeait.
**Le patch.** `NativeVideoPlayerAndroidBufferConfig` gagne `targetBufferBytes`
(`<= 0` = défaut Media3) et `backBufferMs` (`0` = rien) ; `SharedPlayerManager.
buildPlayer` les pose (`setTargetBufferBytes`, `setBackBuffer(ms, true)`) et fixe
`setPrioritizeTimeOverSizeThresholds(false)` explicitement : le plafond gagne.
L'app calcule les deux (`lib/feature/player/buffer_policy.dart`) : 40 % de
`memoryClass` (sonde §deviceCaps), entre 32 Mio et le défaut Media3 ; 10 s
d'arrière dès 30 s de tampon (Complet / Équilibré), rien en Léger.

## patch 26 — la piste vidéo se coupe écran éteint, le son continue (2026-09-16, §bgAudio)

**Le manque.** Écran éteint, `VideoPlayerView` fait `clearVideoSurface` et
`MediaCodecVideoRenderer` continue de décoder sur une surface de substitution :
de la batterie dépensée pour du son seul (fiche §bgAudio, point 2).
**Le patch.** Méthode `setVideoTrackEnabled(enabled)` (Kotlin
`VideoPlayerMethodHandler`, canal + contrôleur Dart) : `setTrackTypeDisabled(
C.TRACK_TYPE_VIDEO, !enabled)`. L'app la pose en `AppLifecycleState.paused`
(téléphone seulement, ni PiP, ni Cast — `background_video_policy.dart`) et la
défait en `resumed` : ExoPlayer resélectionne la piste vidéo à la position
courante, sans réouverture.
⚠️ Le GAIN n'est pas encore mesuré (batterie avant/après sur le S25, 30 min
écran éteint, même film) : c'est la recette de la fiche. Sans cette mesure, le
patch reste une hypothèse raisonnable, pas un résultat.

## patch 25 — « sans son » : la piste audio se coupe, l'image continue (2026-09-16, R5 / §audioFallback)

**Le manque.** `Media3Engine.disableAudio()` était vide : la branche « lecture
sans son » de §audioFallback l'annonçait sans rien couper — et de toute façon
inatteignable, la reconnaissance de l'erreur étant taillée sur les messages de
mpv (D2A-10). Le natif ne connaissait pour l'audio que « imposer » (≥ 0) et
« automatique » (-1, patch 22).
**Le patch.** Index **-2** dans `handleSetAudioTrack` = `setTrackTypeDisabled(
C.TRACK_TYPE_AUDIO, true)` (`NativeVideoPlayerAudioTrack.off()` côté Dart) ;
`-1` et tout index ≥ 0 rallument le type. Côté app : `player_error.dart`
classe l'erreur sur le CODE Media3 (`AUDIO_TRACK_*` audio par nature ;
`DECODER_*` / `DECODING_*` départagés sur le message brut : rendu et type
MIME), `Media3Engine.lastErrorWasAudio` porte le verdict, et le lecteur
enchaîne bascule PUIS `retryPlayback` (après une erreur, ExoPlayer est à
l'arrêt : changer la sélection seul ne relance rien).
Test : `test/player_error_test.dart`.

## patch 24 — le canal `native_video_player/assets` retiré (2026-09-16, R6 / D2B-09 e)

`resolveAssetPath` (extraction d'un asset Flutter vers le cache pour ExoPlayer)
n'avait aucun appelant Dart ; le README amont le listait comme fonctionnalité.
Retiré de `NativeVideoPlayerPlugin.onAttachedToEngine`, README ajusté.
↩️ Récupérable par `git revert` si une vidéo embarquée revenait un jour.
⚠️ **La copie iOS reste en place, volontairement** (`ios/…/Factory/
VideoPlayerViewFactory.swift`, le même canal `native_video_player/assets`) :
le projet est Android-only (`ios: false`), ce fichier n'est jamais compilé, et
le laisser garde le diff avec l'amont lisible. Décision du coordinateur,
2026-09-17.

## patch 23 — `FullscreenManager.exitFullscreen` restaure vraiment les barres (2026-09-16, R20 / §barsRestore)

Même défaut que celui corrigé dans le lecteur de l'app (§barsRestore) :
`SystemUiMode.edgeToEdge` seul ne fait que `setDecorFitsSystemWindows` et
n'efface jamais les drapeaux de masquage d'`immersiveSticky` — les barres
restaient cachées pour le reste de la session. Désormais `manual` + toutes
les surcouches, PUIS `edgeToEdge`. L'app n'utilise pas ce gestionnaire
aujourd'hui ; le patch évite qu'il resserve avec le défaut.

## patch 22 — les pistes savent revenir à « automatique », et un échec de piste remonte (2026-09-13, R43)

**Le manque.** Le natif ne connaissait que deux gestes par type de piste : *imposer*
un index ≥ 0 (`TrackSelectionOverride`) ou, pour le texte seulement, *couper*
(`-1` → `setTrackTypeDisabled(TEXT, true)`). Aucun chemin ne rendait la main au
sélecteur d'ExoPlayer : après une coupure, le seul retour était d'imposer une
piste, donc d'épingler une LANGUE ; après une langue audio (patch 8), rien ne la
défaisait. Côté Dart, `setSubtitleTrack` / `setAudioTrack` du canal avalaient
toute `PlatformException` dans un `debugPrint` : l'app ne pouvait pas distinguer
une piste posée d'une écriture perdue (R42, point 6 de R43).

**Le patch.**
- `VideoPlayerMethodHandler.handleSetSubtitleTrack` : index **`-2`** = automatique →
  `setTrackTypeDisabled(TEXT, false)` + `clearOverridesOfType(TEXT)` +
  `setPreferredTextLanguage(null)` ; événement `subtitleChange` index -2, langue `auto`.
- `handleSetAudioTrack` : index **`-1`** = automatique → `clearOverridesOfType(AUDIO)` +
  `setPreferredAudioLanguage(null)` ; événement `audioTrackChange` index -1. ⚠️ Peut
  re-demuxer (~3 s, §trackRebuffer) : c'est un geste explicite de l'utilisateur.
- Dart : `NativeVideoPlayerSubtitleTrack.auto()` (`isAuto`), `NativeVideoPlayerAudioTrack.auto()`
  (`isAuto`) ; `video_player_method_channel.dart` **laisse remonter** l'exception des deux
  méthodes ; le contrôleur protège seul le chemin sidecar (inutilisé par l'app).
- ⚠️ Sans vue de plateforme, `_methodChannel` est nul et le contrôleur ne fait RIEN sans
  lever : le pré-contrôle `isInitialized` côté app reste nécessaire (`Media3Engine`).
- Android seulement ; le côté iOS du paquet n'est pas touché (jamais construit).

⚠️ Reprise d'une version amont : rejouer les deux branches natives et retirer les
`try/catch` des deux méthodes du canal, sinon « Revenir à l'automatique » tombe en
`INVALID_INDEX` et les échecs redeviennent muets.

## patch 21 — le canal de la notification de lecture parle la langue de l'appareil (2026-09-11, revue de code, lot 7)

Numéroté 21 à la fusion : le lot 6 de la même revue a pris le patch 20 (voir
plus bas).

**D2B-17.** `VideoPlayerNotificationHandler.createNotificationChannel` et
`VideoPlayerMediaSessionService.placeholderNotification` créaient le canal
`CHANNEL_ID` sous les libellés amont « Video Player » / « Media playback
controls », écrits en dur : un téléphone en français les montrait en anglais
dans Paramètres > Notifications. Le nom et la description sont désormais lus
dans les ressources de l'APPLICATION par leur nom
(`getIdentifier("notif_channel_playback", "string", packageName)` et
`notif_channel_playback_desc`), définies dans
`android/app/src/main/res/values/strings.xml` (français, défaut) et
`values-en/strings.xml`. La brique ne dépend pas de la classe `R` de l'app ;
si la ressource manque, les libellés amont reviennent. `res/raw/keep.xml`
(app) protège ces noms du rétrécissement des ressources en release.

⚠️ Reprise d'une version amont : réappliquer ces deux lectures, ou le canal
repasse en anglais.

## patch 19 — plus de sonde HLS parallèle, erreurs sans pile en release (2026-09-11, revue de code, lot 4)

**D2B-02.** `VideoPlayerMethodHandler` lançait, pour toute URL `.m3u8`,
`VideoPlayerQualityHandler.fetchHLSQualities` : une **seconde connexion** au
panel par `URL.openConnection()` — UA Dalvik, sans délai, sans bypass TLS. Sur
un abonnement « 1 / 1 » elle concurrence la lecture (§hostGate) ; un panel qui
filtre l'UA répond 500 (§iptvUaCompat), et `HttpURLConnection` lève alors
`FileNotFoundException(url)` — le message EST l'URL `/live/USER/PASS/id.m3u8`,
que `NpLog.e` écrivait dans logcat **y compris en release**. L'app n'utilise
aucune de ces qualités (grep vide de `getAvailableQualities`, `qualitiesStream`,
`setQuality` dans `lib/`) : la sonde est coupée par `FETCH_HLS_QUALITIES =
false` (companion du handler). Si elle revient : délais de 8 s posés, et son
échec part en `NpLog.w` (filtré) avec le seul nom de l'exception.

**D2B-16.** `NpLog.e` restait émis avec la pile complète en release : la pile
n'y est plus passée que sur un build débogable (le message, lui, reste).

Numéroté 19 à la fusion : le lot 3 de la même revue a pris les patchs 15 à 18
(voir plus bas).

## patch 20 — code mort retiré du natif, restes versionnés supprimés (2026-09-11, revue de code, lot 6)

Suppression pure : aucun comportement ne change. Chaque symbole a été regrepé
dans `lib/`, `test/`, `android/` et `packages/` juste avant sa suppression
(y compris noms de canaux et chaînes de méthode).

**D2B-09 (a)** — `VideoPlayerNotificationHandler` : `startPositionUpdates` /
`stopPositionUpdates` et leur `positionUpdateRunnable`. Le Runnable n'avait
pour corps que `handler.postDelayed(this, 1000)` : un réveil du looper
principal par seconde pendant toute la vie de la session, pour rien —
`MediaSession` publie seule la position d'ExoPlayer. `handler` reste (deux
autres usages).
**(b)** — `bitmapToByteArray` : définition seule.
**(c)** — `VideoPlayerMethodHandler` : `isAutoQuality` (écrit, jamais lu),
`lastBitrateCheck` et `bitrateCheckInterval` (jamais lus), et le
`getActivity(ctx)` privé qui ne s'appelait que lui-même (import `Activity`
retiré avec lui).
**(d)** — `NativeVideoPlayerPlugin.getAllViews()` : aucun appelant ; son
commentaire « Used by MainActivity » était faux (le PiP passe par le canal
maison `aetherstream/pip`, §pipPhone).
✅ **(e) traité le 2026-09-16 (patch 24, R6)** : le canal `native_video_player/assets`
(`resolveAssetPath`) n'avait aucun appelant Dart ; retiré sur décision du
coordinateur (revue, R6).

**D2B-19** — Restes versionnés supprimés :
`android/src/test/kotlin/com/example/native_video_player/NativeVideoPlayerPluginTest.kt`
(appelait `onMethodCall` et `getPlatformVersion`, qui n'existent pas : un
`./gradlew test` du module ne compilait pas) et
`packages/better_native_video_extractor/analysis_options.yaml` (seul fichier
restant du sous-paquet supprimé le 2026-09-01, cf. « Écarts »).

**D1B-21** — commentaires seulement : `load(allowInvalidCertificate:)` dans
`native_video_player_controller.dart` et le bloc « client OkHttp tolérant »
de `VideoPlayerMethodHandler.kt` citaient `NetworkUtils.buildBaseDio` ; il
s'appelle désormais `buildIptvBaseDio()` côté app (le second oubli a été
trouvé à la relecture).

## patch 14 — la libération du lecteur ne gèle plus la sortie (2026-09-06)

`VideoPlayerMethodHandler.handleDispose` appelait `SharedPlayerManager.removePlayer`
— donc `ExoPlayer.release()` — **sur le thread principal**, avant de répondre à
Flutter.

⚠️ **`release()` est BLOQUANT** : il attend que le thread de lecture interne
ait rendu ses décodeurs, jusqu'à `releaseTimeoutMs` (500 ms par défaut, plus
sur un SoC de téléviseur lent à libérer un décodeur matériel). Pendant ce
blocage, Flutter ne produit plus une image. Mesuré le 2026-09-06 avec
§jankMeter sur les 1,5 s qui suivent la fermeture du lecteur : émulateur
téléphone **5 à 9 frames, pire frame 429 ms** ; émulateur TV 15 à 18 frames,
pire 127 ms. Signalement utilisateur : « sortir d'un film ou d'une série est
très long ».

`stop()` reste immédiat (image et son coupés), la réponse à Flutter part tout
de suite, et `removePlayer` est **posté 450 ms plus tard** sur le looper
principal — le temps que la transition de sortie soit dessinée. Le lecteur
partagé reste inscrit ce court instant, sans effet : le contrôleur Dart est
déjà détruit et un nouveau lecteur reçoit un nouvel identifiant.

⚠️ Ne pas « corriger » en libérant depuis un autre thread : Media3 exige que
`release()` soit appelé depuis le thread de l'application looper du lecteur.

⚠️ **Le report couvre les DEUX chemins** : `handleDispose` (routé par la vue) ET
`disposeController` (`NativeVideoPlayerPlugin`). Sur téléviseur, c'est le second
qui libère vraiment : la vue de plateforme est déjà démontée quand le contrôleur
Dart se détruit, et le premier échoue en `NO_VIEW` (journal de la TV de
l'utilisateur, 1.18.7, le 2026-09-06). Un patch qui ne différait que le premier
ne changeait rien pour la télé.

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

## patchs 15 à 18 — revue de code du 2026-09-11 (lot 3, lecteur et Cast)

**Patch 15 — la libération différée ne libère que l'instance visée (D2B-01).**
Le commentaire du patch 14 affirmait qu'« un nouveau lecteur reçoit un nouvel
identifiant » : c'était **faux**, l'app construisait tous ses contrôleurs avec
`id: 7000`. Or tout le natif est indexé par cet identifiant (lecteur partagé,
gestionnaire de notification, canal d'événements du contrôleur). Zapping rapide
(chaîne A, Retour, chaîne B en moins d'une seconde) : B pouvait récupérer
l'ExoPlayer de A encore inscrit, que le report de 450 ms arrêtait puis libérait
sous ses pieds ; ou le démontage du canal de A emportait celui de B.
Deux moitiés :
- côté app, `Media3Engine` attribue un identifiant **par moteur** (7000, 7001…) ;
- côté natif, `handleDispose` et `disposeController` capturent l'`ExoPlayer`
  inscrit au moment du `dispose`, et `SharedPlayerManager.removePlayerIfCurrent`
  ne libère à l'échéance que si c'est **toujours lui** (`===`).
⚠️ Le report de 450 ms reste légitime (patch 14) : seul son présupposé était faux.
⚠️ Restant connu : `VideoPlayerNotificationHandler.release()` de l'ancien lecteur
coupe le service `mediaPlayback` et la notification (id 1001, partagés) — si le
suivant a déjà publié la sienne, elle disparaît jusqu'à sa prochaine transition
lecture/pause. Le lecteur, lui, n'est plus touché.

**Patch 16 — `CastSession.connect` ferme la session si le LAUNCH échoue (D2B-06).**
Premier patch du Cast (jusqu'ici branché sans patch, §castSend). Sur délai
dépassé ou `LAUNCH_ERROR`, l'`await` sortait en exception sans rien fermer ;
l'appelant ne recevant jamais la session, le socket TLS restait ouvert et un
PING partait toutes les 5 s pour la vie du processus (un de plus par essai).
Test : `test/cast_session_connect_test.dart` (serveur TLS local muet).

**Patch 17 — l'observateur de cycle de vie du contrôleur est retiré (D2B-05).**
Ajouté à la construction, jamais retiré : chaque lecteur ouvert laissait un
contrôleur mort retenu par `WidgetsBinding`. Gardé dans un champ, retiré au
début de `dispose()`. La condition passe de `Platform.isAndroid` à
`defaultTargetPlatform == TargetPlatform.android` (identique sur appareil,
simulable en test). Test : `test/lifecycle_observer_leak_test.dart`.

**Patch 18 — l'affiche de la notification de lecture est bornée (D2B-07).**
`loadArtwork` n'avait ni délai (0 = infini), ni fermeture de flux, décodait en
pleine résolution et ne s'annulait jamais. Même patron que
`AetherCastService.downloadBitmap` : délais de 8 s, `use {}` + `disconnect()`,
décodage sous-échantillonné vers ~512 px, tâche annulée par `release()` et par
une affiche plus récente. ⚠️ L'UA de cette requête (§notifAudit P10) n'est PAS
traité ici → **patch 30** (2026-09-25).
