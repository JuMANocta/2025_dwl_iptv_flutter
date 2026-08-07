# AetherStream

<p align="center">
  <img src="assets/icon/AetherStreamIcon.png" alt="AetherStream Logo" width="120"/>
</p>

<p align="center">
  <strong>Client IPTV Android complet — multi-comptes, EPG, Replay, TMDB</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-1.14.1+92-blue?style=flat-square"/>
  <img src="https://img.shields.io/badge/platform-Android-green?style=flat-square&logo=android"/>
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?style=flat-square&logo=flutter"/>
  <img src="https://img.shields.io/badge/minSdk-24-orange?style=flat-square"/>
</p>

---

## Présentation

**AetherStream** est une application Android construite avec Flutter permettant de regarder des chaînes IPTV, des films et des séries via une playlist M3U ou un serveur Xtream Codes. Elle intègre un système de replay (timeshift), un EPG (guide des programmes), l'enrichissement visuel via TMDB et un gestionnaire de téléchargements.

---

## Fonctionnalités

### 📺 Lecture
- Lecture de flux réseau (HLS, MPEG-TS) et fichiers locaux via **libmpv** (`media_kit`)
- Player plein écran paysage avec contrôles entièrement custom
- **Gestures** : double-tap ±10s, swipe horizontal seek, swipe vertical volume/luminosité
- **Verrouillage écran** : le cadenas désactive aussi les gestes (plus de seek/volume accidentel)
- **Boost audio** : volume amplifiable jusqu'à 200 %, démarrage à 130 % pour compenser les flux IPTV faiblement encodés
- **Synchro A/V** : `video-sync=display-resample` + buffer 64 Mo + audio-pitch-correction → dialogues calés sur l'image
- Vitesse de lecture : 0.5x / 0.75x / 1x / 1.25x / 1.5x / 2x
- **Reprise de lecture** : position sauvegardée toutes les 10s, bouton "Reprendre depuis X:XX" + barre cyan sur les vignettes
- **Reprise cross-source** : un film regardé en streaming puis téléchargé reprend à la même position depuis le fichier local (même clé `progressKey: entry.url`)
- **Oublier la reprise** : tile dédiée dans l'action sheet + long-press menu (snackbar UNDO 4s) pour retirer un film/série de la pile Reprendre
- **Épisode suivant** : bouton ▶▶ dans les contrôles séries (auto-saisi depuis la fiche détail)
- **Wakelock** : écran maintenu allumé pendant la lecture, libéré en pause/erreur
- Reconnexion automatique ×3 avec swap automatique d'extension `.ts` ↔ `.m3u8` (compatibilité maximale serveurs)
- Retry réseau coupé en arrière-plan (économie batterie)
- Overlay buffering central avec délai anti-clignotement
- Badge contextuel : 🔴 DIRECT / 🟡 REPLAY / 🔵 FILM / 🟣 SÉRIE
- Barre de progression replay (mode timeshift)

### 📋 Playlist & Comptes
- **Multi-comptes** : plusieurs fournisseurs IPTV simultanément, aggregation automatique en recherche
- **Deux modes** : URL complète M3U ou Xtream Codes (serveur + identifiants)
- Cache playlist 24h (1 fichier par compte) + parsing JSON.gz mémorisé
- Bascule de compte actif réactive : la home se reconfigure dès le changement de priorité
- Recherche et filtres en temps réel — Films / Séries / Chaînes TV
- **Historique de recherche** : 10 dernières requêtes en suggestions (chips dismissibles)
- Regroupement automatique des chaînes par qualité (4K / FHD / HD / SD), dédoublonnage des flux identiques
- Séparation des homonymes par catégorie `group-title` (ex: anime vs live-action) avec badge visuel

### ⏪ Replay / EPG
- Timeshift Xtream Codes avec picker manuel (jour + heure + durée + qualité FHD/HD/SD)
- **Grille EPG XMLTV** : sélection directe d'un programme dans la grille pour le replay
- EPG "En cours / Ensuite" dans la fiche chaîne via XMLTV (source TNT France, cache 12h)
- Détection automatique du meilleur format de flux (`.ts` prioritaire, fallback `.m3u8`)
- Support des formats catchup : Xtream Codes path-based et Flussonic (`{utc}/{lutc}`)

### 🎬 TMDB
- Enrichissement automatique : affiches, synopsis, **casting avec photos**, bande-annonce YouTube (ouverture dans l'app YouTube)
- Recherche intelligente en 4 passes (type, année, langue...)
- Désambiguïsation par année et genre `group-title` (évite les confusions films/séries homonymes)
- Fiche épisode : still TMDB, titre épisode, note ★, date de diffusion, synopsis
- Fiche détail film/série avec crédits complets + bouton **♥ Favori** + reprise de lecture intégrée
- Squelettes (skeleton placeholders) pendant le chargement TMDB pour éviter les sauts d'UI

### 🏠 Accueil streaming-style
- **Hero "jeu de cartes"** (films/séries) : pile de 10 cartes empilées en éventail avec effet 3D (padding blanc "papier" 3px + box-shadow stack simulant l'épaisseur). 5 cartes "Reprendre" triées par dernière lecture + **tendances TMDB de la semaine présentes dans la playlist** (matching exact, cache 24h ; repli sur les nouveautés si pas de clé TMDB)
- **Swipe horizontal** sur le hero pour naviguer manuellement entre les cartes (pause auto-rotation pendant le drag, snap avec biais de vélocité au relâché)
- Auto-rotation 6 s entre les cartes (continue après un swipe manuel)
- Hero 16/9 classique conservé sur la page Chaînes (live)
- Hero remonte jusqu'à la status bar (l'icône ⚙️ flotte par-dessus, l'inclinaison libère le coin haut-droit)
- 3 pages swipeables : Séries / Films / Chaînes (PageView + tabs animées sous le hero)
- Catégories triées : ⭐ Favoris → 🇫🇷 France (TV) → 🔥 New → genres → Autres
- Films/Séries en carrousels horizontaux (poster 2:3), Chaînes en grille 3 colonnes (logo carré)
- Limite 25 items par section + tile "Voir tout" qui ouvre la liste complète. **Favoris sans plafond** (curation utilisateur)
- Tuile **REPRENDRE LA CHAÎNE** en tête de la page Chaînes (dernière chaîne TV regardée)
- Long-press sur une carte → menu contextuel (Lire/Reprendre, Oublier la reprise, Voir détails, Télécharger, Favori)
- Recherche in-place via la NavigationBar (pas de page séparée)
- Onboarding 3 écrans au tout premier lancement (welcome / playlist / TMDB)
- AppBar épurée (nom de compte retiré — visible dans Settings → Comptes uniquement)

### ❤️ Favoris
- Films, séries **et** chaînes TV (cross-comptes, cross-variantes)
- Auto-ajout au lancement de la lecture (silencieux)
- Long-press menu sur les cartes + icon-button compact dans la fiche détail
- Section ⭐ Favoris dupliquée en tête de la page concernée
- Stockage `SharedPreferences` (clé canonique `<type>|<groupKey>`)

### ⬇️ Téléchargements
- Téléchargement avec suivi de progression
- Reprise sur interruption (header `Range`)
- Sauvegarde dans `/Movies/AetherStream/` via MediaStore Android

### 🔄 Mise à jour in-app
- Vérification automatique au démarrage via l'API GitHub Releases
- Téléchargement et installation de l'APK directement depuis l'application

### 🔒 Sécurité & confidentialité
- **SSL bypass scoped** : accepté uniquement pour les serveurs IPTV utilisateur, jamais pour TMDB/GitHub/XMLTV (HTTPS strict)
- **`network_security_config.xml`** : cleartext interdit sur les APIs publiques connues
- **`allowBackup="false"`** + règles d'extraction excluant tout → pas de fuite credentials via `adb backup`
- **Logs sanitisés** : `redactUrl()` / `redactServer()` masquent `user:pass` dans logcat
- **Stockage chiffré** des comptes IPTV et clé TMDB (`flutter_secure_storage` / EncryptedSharedPreferences)

---

## Installation

### Depuis les Releases GitHub

Télécharge `aetherstream.apk` depuis la page [Releases](https://github.com/JuMANocta/2025_dwl_iptv_flutter/releases) et installe-le directement sur ton appareil Android (minSdk 24 — Android 7.0+).

Compatible **smartphones, tablettes, Fire Stick et Android TV** (Philips, Sony, etc.) — toutes architectures ARM64 / ARMv7 / x86_64.

> ⚠️ L'installation d'APK hors Play Store nécessite d'activer **"Sources inconnues"** dans les paramètres Android.

### Depuis les sources

```bash
# Cloner le dépôt
git clone https://github.com/JuMANocta/2025_dwl_iptv_flutter.git
cd 2025_dwl_iptv_flutter

# Installer les dépendances
flutter pub get

# Lancer en debug
flutter run

# Build APK universel (téléphone + TV + Fire Stick)
flutter build apk --release
```

---

## Configuration

### 1. Ajouter un compte IPTV

Au premier lancement, l'application redirige vers la page de gestion des comptes. Deux modes disponibles :

- **URL complète** : colle l'URL de ta playlist M3U
- **Xtream Codes** : renseigne le serveur, le nom d'utilisateur et le mot de passe

### 2. Clé API TMDB *(optionnel)*

Pour bénéficier des affiches, synopsis et informations TMDB :

1. Crée un compte sur [themoviedb.org](https://www.themoviedb.org)
2. Génère un **Bearer Token (API Read Access Token v4)**
3. Renseigne-le dans **Paramètres → Clé API TMDB**

> Sans clé TMDB, l'application fonctionne normalement mais sans enrichissement visuel.

### 3. Paramètres

Toutes les options sont regroupées dans **⚙️ Paramètres** (icône en haut à droite de l'accueil) :
- **Comptes IPTV** : gestion des providers + compte actif
- **Clé API TMDB** : token Bearer + lien direct vers la page d'inscription
- **Guide des chaînes** : statut + refresh du cache XMLTV
- **Personnalisation** : thèmes + 5 presets (Matrix, Blade Runner, Tron, Minimaliste, Classic)
- **Statistiques playlist** : nombre de films/séries/chaînes du compte actif
- **Recharger la playlist** : force le retéléchargement
- **À propos** : version + check des mises à jour manuel

---

## Architecture

```
lib/
├── main.dart                          # Point d'entrée + _LaunchDecider (onboarding / accounts / home)
├── core/
│   ├── navigation/main_navigation.dart # NavigationBar 3 onglets (Accueil / Recherche / Téléchargements)
│   ├── themes/                        # colors.dart, themes.dart, AppThemeConfig, AetherThemeExtension
│   └── utils/                         # NetworkUtils (SSL bypass scoped), log_sanitizer, SecureStorage
├── data/
│   ├── models/                        # StreamAccount, M3uEntry, ParsedPlaylist, Media, DownloadTask, XmltvProgram
│   └── services/                      # Tous statiques/singletons :
│        ├── StreamAccountService      #   comptes IPTV + currentAccountIdNotifier
│        ├── PlaylistService           #   cache M3U 24h, multi-comptes
│        ├── ParsedPlaylistService     #   hub central JSON.gz + mémoire (entriesWithPriority)
│        ├── DownloadManagerService    #   Dio stream + reprise + MediaStore
│        ├── TmdbService / TmdbApiService #   recherche TMDB 4 passes + Bearer Token
│        ├── ReplayService             #   Xtream timeshift + EPG short
│        ├── XmltvService              #   EPG TNT France (cache 12h)
│        ├── FavoritesService          #   §1d favoris cross-comptes
│        ├── WatchProgressService      #   §1e reprise (save 10s + dispose)
│        ├── SearchHistoryService      #   §1i historique recherche
│        ├── LastWatchedChannelService #   §1i dernière chaîne TV
│        └── UpdateService             #   MAJ in-app GitHub Releases
├── feature/
│   ├── accounts/                      # AccountsPage (§1g refondue), EditAccountSheet, PlaylistManagementPage
│   ├── downloads/                     # Gestionnaire de téléchargements
│   ├── home/home_page.dart            # Hub principal : carrousels, hero, recherche in-place
│   ├── onboarding/onboarding_page.dart # §1i — 3 écrans au 1er lancement + OnboardingService
│   ├── player/                        # PlayerPage + AetherPlayerController + widgets (lifecycle §1h, buffering, etc.)
│   ├── replay/                        # ReplaySheet + ReplayDatePickerSheet
│   ├── search/                        # M3uParser, M3uFilter (dedupeTvVersions), DetailsPage, ActorDetailsPage
│   ├── settings/                      # SettingsPage (hub), ThemeSettings, TmdbKey (§1g), Xmltv (§1g)
│   └── update/                        # Mise à jour in-app (GitHub Releases)
├── widgets/                           # MediaActionSheet (+_FavoriteToggleTile, _PlayResumeTiles, _SkeletonLine),
│                                      # MediaCard, MediaChips, QualityButtons, EpgBlock, TerminalDownloadDialog
└── l10n/                              # Traductions FR / EN
```

### Stack technique

| Composant | Package |
|-----------|---------|
| HTTP / Téléchargements | `dio` |
| Player vidéo | `media_kit` + `media_kit_video` (libmpv) |
| Luminosité | `screen_brightness` |
| Wakelock | `wakelock_plus` |
| Stockage sécurisé | `flutter_secure_storage` |
| Préférences | `shared_preferences` |
| MediaStore Android | `media_store_plus` |
| EPG XMLTV | `xml` |
| Polices | `google_fonts` |
| Permissions | `permission_handler` |
| Réseau | `connectivity_plus` |

---

## Roadmap

### ✅ Terminé
- [x] **Refonte complète du player** — `media_kit`, contrôles custom, gestures, reconnexion auto *(PiP reporté)*
- [x] **Mise à jour in-app** — vérification + téléchargement APK depuis GitHub Releases
- [x] **Grille EPG XMLTV** — sélection programme dans la grille pour le replay
- [x] **Refactoring recherche** — modules séparés (parser, filter, widgets) puis suppression du code mort `recherche_page`/`recherche_m3u` (lot A, 2026-06-11)
- [x] **Système de thème sémantique** — variables `kAccentPrimary/Secondary/Tertiary`, constantes qualité/langue/badges centralisées
- [x] **Thème personnalisable in-app** — `AppThemeConfig` runtime + page Personnalisation : **9 presets** (Matrix, Blade Runner, Tron, Cyberpunk, Synthwave, Phosphore, Nordique, Minimaliste, Classic) et **7 couleurs réglables** dont les couleurs d'état favori ❤ / reprise-alerte / erreur / succès appliquées sur tout le front (§themePlus, 2026-06-11)
- [x] **Téléchargement playlist via JSON API Xtream** (§xtreamApi, 2026-06-04) — Au lieu de tirer `get.php` (qui retourne souvent HTTP 500 silencieux sur les gros panels à cause du timeout PHP), AetherStream construit la playlist en interne via les endpoints `player_api.php?action=…` (live + VOD + séries, 6 actions en parallèle). C'est ce que font tous les clients IPTV modernes (TiviMate, IPTV Smarters Pro, ZenIPTV…). Marche sur des panels où `get.php` ne marche pas. Fallback automatique sur `get.php` pour les providers non-Xtream. Profil de requête `User-Agent: IPTVSmartersPro` (whitelisté par les panels). **Séries** : 1 entrée par série au boot, épisodes chargés à l'ouverture de la fiche (lazy load)
- [x] **Catalogue unifié JSON direct** (§23, 2026-06-10) — les réponses `player_api.php` sont sauvegardées brutes (`playlist_<id>.json`) et parsées **directement** en entrées (plus de round-trip M3U texte) : zéro perte de métadonnées (tmdb_id, synopsis, note, genres, casting, backdrops, replay `tv_archive`). Regex de titre réécrites sur les formats réels des 3 providers (préfixes composés `|FR-4K DV|`, `|VO|STFR|`, suffixes `(MULTI) FHD 2025`, `[MULTi]`, `_sub`) → un même film présent sur plusieurs listes fusionne en **une seule vignette** (8 600+ films communs validés). Image affichée = celle de la **plus grosse liste** (fallback automatique). Fiche film/série complète (synopsis, note, genres) **même sans clé TMDB**. Fallback `get.php` conservé pour les comptes non-Xtream
- [x] **Catégories M3U** — chips de filtre par catégorie dans la recherche (films + séries)
- [x] **Filmographie acteur DISPO** — badge sur les films présents dans la playlist + navigation `DetailsPage`
- [x] **Fiche TMDB même hors listes** (§tmdbOnlyDetails) — dans une filmographie, un titre **sans** badge DISPO ouvre désormais sa fiche TMDB (affiche, synopsis, note, casting, réalisateur, similaires disponibles) au lieu de ne rien faire. Pas de bouton Lire, mais un **« Chercher dans mes listes »** pré-rempli, avec bascule sur le **titre original** — les fournisseurs IPTV nomment souvent en VO, et le repérage automatique est volontairement strict pour ne jamais afficher un faux DISPO
- [x] **Android TV / Fire Stick** (v1.6.0+) — Détection plateforme native, NavigationRail latéral, focus visible Matrix glow sur toutes les cards, action sheets en Dialog focusable, player entièrement contrôlable à la télécommande (OK / ← → / ↑ ↓ / MediaPlayPause / Menu), textScaler ×1.3 pour lisibilité 3 m+
- [x] **Un seul QR, le panneau complet** (§webConsoleOnly) — Tous les points d'entrée « Configurer depuis mon téléphone » (écran sans compte, ajout de playlist, clé TMDB, onboarding TV) ouvrent désormais **la Console web**, et plus un formulaire à champ unique. Le QR mène directement à la bonne page (comptes, TMDB…) tout en gardant le reste du panneau à un clic. Sur TV, c'est le **bouton principal**, donc celui qui prend le focus D-pad. L'onboarding TV passe de 3 à **2 écrans** : un seul scan configure playlist *et* clé TMDB
- [x] **Navigation TV affinée** — Déplacement ↑/↓ « façon Netflix » (change de rangée et se cale à gauche, ne saute plus les rangées courtes comme les favoris), filmographie acteur parcourable ligne par ligne, et **double-appui sur Retour** pour quitter depuis l'accueil (évite les sorties accidentelles à la télécommande)
- [x] **Console web** (v1.8.8) — Un QR + une URL : depuis un PC/téléphone du même réseau, gérer les **comptes IPTV** (CRUD + recharger + compte principal), la **clé TMDB**, le **guide XMLTV**, les **langues/régions**, le **thème**, **réinitialiser les données d'usage** et **importer/exporter une sauvegarde `.aether`** (mot de passe dans le navigateur). Bonus **télécommande** : pavé directionnel + transport player pour piloter la TV depuis le téléphone. Serveur LAN-only sécurisé par token, actif en arrière-plan jusqu'à l'arrêt explicite (ou 30 min)
- [x] **Page d'accueil streaming-style** — carousels par catégorie + recherche in-place + navigation bottom bar
- [x] **Favoris** — films, séries et chaînes (auto-ajout au play, long-press menu contextuel)
- [x] **Reprise de lecture** — barre cyan sur les vignettes + bouton "Reprendre depuis X:XX"
- [x] **Boost audio + synchro A/V** — volume jusqu'à 200 %, display-resample, buffer 64 Mo
- [x] **Wakelock + lifecycle player** — écran reste allumé pendant la lecture, retry réseau coupé en arrière-plan
- [x] **Refonte AccountsPage** — alignement streaming-style + sous-pages dédiées TMDB / XMLTV / Personnalisation / Stats playlist depuis le hub Paramètres
- [x] **Quick wins UX** — lock player bypass-proof, overlay buffering, skeleton TMDB, historique recherche, dernière chaîne TV, skip épisode, onboarding 1re ouverture
- [x] **Dédoublonnage qualité TV** — un seul bouton par qualité même si le provider expose plusieurs flux identiques
- [x] **Hero "jeu de cartes" + ergo home** (v1.5.0) — fan banner 10 cartes avec reprise prioritaire, effet 3D (padding blanc + box-shadow stack), swipe manuel + auto-rotation 6 s, AppBar épurée, hero remonte sous la status bar
- [x] **Reprise cross-source** (v1.5.0) — DL local utilise `progressKey: entry.url` → reprise partagée entre streaming et lecture locale
- [x] **Oublier la reprise** (v1.5.0) — action dédiée dans l'action sheet + long-press menu, snackbar UNDO 4 s, clear sur toutes les variants du groupe
- [x] **Fix home vide après Recharger/Vider cache** (v1.5.0, 2026-05-20) — `ParsedPlaylistService.reloadFromDisk()` atomique : parse AVANT le swap mémoire, plus jamais d'état vide intermédiaire
- [x] **Polish UI §1L** (v1.5.3, 2026-05-21) — champ recherche élargi sous l'AppBar avec arrow_back, gradient dynamique sur ThemeSettingsPage, bouton TÉLÉCHARGER opaque dans DetailsPage, stats playlist multi-comptes (expiration + connexions Xtream + recharger par compte), À propos en vraie page dédiée
- [x] **Sauvegarde / Restauration §10** (v1.5.3, 2026-05-21) — fichier `.aether` chiffré AES-256-GCM + PBKDF2, mot de passe utilisateur, sauvegarde dans `/Download/AetherStream/` (survit à l'uninstall), restaure comptes IPTV + clé TMDB + thème + favoris + progression
- [x] **Bumps Gradle / AGP / Kotlin** (v1.5.3, 2026-05-21) — Gradle 8.14, AGP 8.11.1, Kotlin 2.2.20 (post Flutter 3.44)
- [x] **§3c Android TV / Fire Stick navigation complète** (v1.6.0, 2026-05-21) — détection native UiModeManager + Fire TV feature, NavigationRail latéral, FocusableCard (Matrix glow + scale 1.05) sur cards/comptes/downloads, action sheets en Dialog focusable, Player TV (Shortcuts/Actions sur OK/←→/↑↓/MediaPlayPause/Back/Menu), gestes tactiles désactivés en TV, textScaler ×1.3, touche Menu = équivalent long-press
- [x] **§12 EmptyState unifié + Pull-to-refresh DL** (v1.7.0, 2026-05-22) — widget `EmptyState` cyberpunk réutilisable (icône cerclée + glow Matrix dynamique + CTA optionnel), appliqué dans Downloads / Accounts / Search / Replay. `RefreshIndicator` ajouté sur la page Téléchargements
- [x] **§3c-8 Pairing QR mobile→TV** (v1.7.0, 2026-05-22) — mini-serveur HTTP local (`dart:io HttpServer`) côté TV qui sert un formulaire HTML thémé (CSS variables interpolées depuis `AppThemeConfig` — page mobile rendue dans le thème courant Matrix/Blade Runner/Tron). QR généré par `qr_flutter` (token aléatoire 8 chars anti-snooping, port aléatoire, timeout 10 min). Câblé dans LaunchDecider, OnboardingPage (slides 2/3 TV), AccountsPage (empty + bouton +), TmdbKeyPage (card prioritaire, TextField replié derrière "saisie manuelle avancée")

### 🔒 Sécurité — Hardening 2026-05-19
- [x] SSL bypass scoped aux serveurs IPTV utilisateur uniquement (TMDB / GitHub / XMLTV en HTTPS strict)
- [x] `network_security_config.xml` — cleartext interdit pour les APIs publiques
- [x] `allowBackup="false"` + `data_extraction_rules.xml` — pas de fuite credentials via `adb backup`
- [x] Sanitiseur de logs (`redactUrl` / `redactServer`) — plus aucune URL avec `user:pass` dans logcat

### 📅 Planifié
**🔥 Top priorité (2026-08-05)** :
- [x] **Plafond du cache image en RAM** (§imgMemCache) — réglable dans Optimisation (20-150 Mo, 40 Mo en profil Performance) au lieu des 100 Mo par défaut de Flutter ; rendu possible par le cache disque
- [x] **Cache disque des images** (§imgDiskCache) — vignettes persistées sur disque (widget partagé `AetherImage`, rétention 60 j TMDB / 7 j provider), backdrop de fiche en w1280, ligne « Cache images » + bouton de purge dans Optimisation
- [x] **Statut de démarrage parlant** (§bootStatus) — l'écran de lancement affiche l'étape réelle au lieu du « // initialisation… » figé : vérification du compte, lecture **ou** téléchargement de la playlist, analyse du catalogue **avec pourcentage** (barre déterminée), chargement des autres comptes
- [ ] **Cache d'URL TMDB persistant** (§tmdbUrlPersist) — éviter de refaire toutes les recherches TMDB à chaque démarrage pour les titres sans affiche fournie par la liste
- [x] **Audit de la gestion des favoris** (§favAudit) — la latence venait du groupement de la home, qui se relançait **entièrement à chaque cœur** : la rangée ⭐ (catégorie virtuelle) est désormais recalculée seule. Corrigé aussi : le flag one-shot de réconciliation pouvait n'être jamais posé (scan de la playlist à chaque démarrage) et les regex de `tvGroupKey` étaient recompilées à chaque appel
- [ ] **Plantage lecture 4K sur TV** (§tv4kCrash) — lecture hachée + UI qui plante, investigation prioritaire (lié §tv4kTexture)
- [x] **Téléchargement écrit directement à l'emplacement final** (§dlDirectWrite) — le fichier est téléchargé **dans son dossier de destination** puis simplement renommé : plus de copie de plusieurs Go en fin de parcours (elle s'exécutait sur le thread UI d'Android et faisait planter certains téléphones, en exigeant au passage le double d'espace disque). Corrigés aussi : la progression qui réécrivait toute la liste des tâches sur disque **à chaque bloc reçu**, et les tâches qui pouvaient rester bloquées sur « finalisation » indéfiniment
- [x] **Ergonomie des téléchargements** (§dlErgo) — un appui sur un téléchargement en cours l'**annulait sans confirmation** (et sur TV c'est la touche OK) : le tap déclenche désormais l'action inoffensive (voir la progression / lire / relancer), et tout le reste passe par un **menu ⋯** focusable à la télécommande, avec confirmation avant d'arrêter. Le moniteur gagne un « Fermer » distinct d'« Annuler ». La page reçoit des **filtres avec compteurs** (Tout / En cours / Terminés / Erreurs) et une recherche. Inclut le bouton **Relancer** (§dlRestart)
- [ ] **Téléchargements : reprise auto si bloqué** (§dlWatchdog)
- [x] **Fiche film : réalisateur cliquable + ses films disponibles** (§directorView), **synopsis avant les boutons** (§detailsLayout), **infos TMDB élargies** (§tmdbMore — tagline, nombre de votes, section « Infos » avec pays/studios/statut/durée)
- [ ] **Sens de défilement des carrousels en remontant la page** (§carouselScrollDir)
- [x] **Recherche par personne** (§personSearch) — rangée « Personnes » en tête des résultats (photos rondes + métier), tap → filmographie avec badges DISPO
- [ ] **Enchaînement automatique de l'épisode suivant en fin de lecture** (§autoNextEp) — compte à rebours annulable type Netflix

**Autres** :
- [ ] **Bandeau SYSTEM UPDATE repensé** (§updateBanner) — version actuelle vs release avec animation « decode Matrix » (différence en surbrillance), pluie Matrix sur tout le bandeau, changelog remplacé par un lien vers la release GitHub
- [x] **Ancrage Netflix sur la fiche** (§rowAnchorDetails) — ancrage D-pad « élément focusé à gauche » sur les rangées épisodes / saisons / titres similaires / casting de la fiche
- [x] **Profil Performance suggéré au 1er boot TV** (§perfAutoSuggest) — dialog one-shot sur Fire TV / Android TV détecté (si les réglages perf sont encore aux défauts)
- [x] **Titre d'épisode fourni par le panel** (§epTitleProvider) — fallback du nom TMDB dans la fiche, l'action sheet et l'overlay du player
- [ ] **Fusion des séries éclatées par saison** (§seasonMerge) — rollover d'épisode cross-saisons chez les providers qui séparent chaque saison en série distincte (diagnostic device d'abord)
- [x] **Section « Optimisation » dans Paramètres** (§perfSettings) — profils Confort/Équilibré/Performance, toggle hero banner + rotation auto, nombre de cartes hero et de vignettes par rangée, diagnostic mémoire (RAM + entrées/disque par compte) + bouton « Libérer la mémoire » (Fire Stick / box faibles). Réglages inclus dans la sauvegarde `.aether`
- [x] **Tag de qualité dans le player** (§watchContext a) — badge 4K/FHD/HD/SD dans l'overlay du player
- [x] **Saison/épisode dans le player** (§watchContext b) — `S01 E04` affiché pendant la lecture d'une série
- [x] **Quel « produit »/qualité sur les chaînes** (§watchContext c) — qualité affichée dans le player + labels de boutons suffixés par le compte pour départager les qualités identiques
- [x] **Découpage `home_page.dart`** — 3 435 → 1 416 lignes via `part`/`part of` (`home_card` / `home_hero_fan` / `home_category` / `home_search`)
- [ ] **Grille EPG XMLTV pour replay** — sélection programme dans la grille (en complément du picker manuel)
- [x] **Pistes audio + sous-titres (embarqués)** — sélecteur in-player (bouton CC) + préférence de langue mémorisée
- [ ] **Sous-titres externes** — fichier/URL `.srt` + recherche en ligne auto par TMDB
- [ ] **File d'attente DL + WiFi-only** — sémaphore, reprise auto au retour réseau
- [ ] **Notifications téléchargement** — progression, fin, erreurs (foreground service)
- [ ] **Background audio** — décision produit : continuer l'audio en arrière-plan via foreground service
- [ ] **Cast Chromecast** — diffusion vers récepteurs Cast réseau local
- [ ] **PIN / contrôle parental** — verrouillage app + masquage contenus adultes
- [ ] **Empty states + Pull-to-refresh** — UX unifiée sur toutes les pages
- [ ] **Mode hors-ligne** — bascule auto sur fichiers locaux si pas de réseau
- [ ] **Parsing M3U en isolate** — `compute()` pour ne plus bloquer le thread principal
- [ ] **Téléchargement différentiel** — HEAD + Range requests pour économiser la bande passante
- [ ] **Hardening sécurité v2** — DownloadManagerService → SecureStorage, M3U cache → ApplicationSupport, debugPrint no-op en release
- [ ] **Cleanup perfs** — Image.network avec cacheWidth/cacheHeight, memoization _HomeCard.build, helper launchPlayer factorisé
- [ ] **Tests unitaires** — services purs (parser, filter, replay URL builder, etc.)
- [ ] **Mise à jour des dépendances** — `media_kit_video` v2, `flutter_secure_storage` v10, `google_fonts` v8, migration "Built-in Kotlin" (Flutter ≥ 3.44)
- [ ] **Port Windows** — branche `windows-port` synchronisée à v1.11.2 ; cible : fusion mono-branche + exe Windows attaché aux releases GitHub (voir `.claude/windows_ci_release_plan.md`)

---

## Licence

Projet personnel — tous droits réservés.
