# AetherStream

<p align="center">
  <img src="assets/icon/AetherStreamIcon.png" alt="AetherStream Logo" width="120"/>
</p>

<p align="center">
  <strong>Client IPTV Android complet — multi-comptes, EPG, Replay, TMDB</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-1.2.5+27-blue?style=flat-square"/>
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
- Vitesse de lecture : 0.5x / 0.75x / 1x / 1.25x / 1.5x / 2x
- Verrouillage écran (mode lock — désactive tous les gestures)
- Reconnexion automatique ×3 avec swap automatique d'extension `.ts` ↔ `.m3u8` (compatibilité maximale serveurs)
- Badge contextuel : 🔴 DIRECT / 🟡 REPLAY / 🔵 FILM / 🟣 SÉRIE
- Barre de progression replay (mode timeshift)

### 📋 Playlist & Comptes
- **Multi-comptes** : plusieurs fournisseurs IPTV simultanément
- **Deux modes** : URL complète M3U ou Xtream Codes (serveur + identifiants)
- Cache playlist 24h (1 fichier par compte)
- Recherche et filtres en temps réel — Films / Séries / Chaînes TV
- Regroupement automatique des chaînes par qualité (4K / FHD / HD / SD)
- Séparation des homonymes par catégorie `group-title` (ex: anime vs live-action) avec badge visuel

### ⏪ Replay / EPG
- Timeshift Xtream Codes avec picker manuel (jour + heure + durée + qualité FHD/HD/SD)
- **Grille EPG XMLTV** : sélection directe d'un programme dans la grille pour le replay
- EPG "En cours / Ensuite" dans la fiche chaîne via XMLTV (source TNT France, cache 12h)
- Détection automatique du meilleur format de flux (`.ts` prioritaire, fallback `.m3u8`)
- Support des formats catchup : Xtream Codes path-based et Flussonic (`{utc}/{lutc}`)

### 🎬 TMDB
- Enrichissement automatique : affiches, synopsis, casting, bande-annonce YouTube
- Recherche intelligente en 4 passes (type, année, langue...)
- Désambiguïsation par année et genre `group-title` (évite les confusions films/séries homonymes)
- Fiche épisode : still TMDB, titre épisode, note ★, date de diffusion, synopsis
- Fiche détail film/série avec crédits complets

### ⬇️ Téléchargements
- Téléchargement avec suivi de progression
- Reprise sur interruption (header `Range`)
- Sauvegarde dans `/Movies/AetherStream/` via MediaStore Android

### 🔄 Mise à jour in-app
- Vérification automatique au démarrage via l'API GitHub Releases
- Téléchargement et installation de l'APK directement depuis l'application

---

## Installation

### Depuis les Releases GitHub

Télécharge le dernier APK depuis la page [Releases](https://github.com/JuMANocta/2025_dwl_iptv_flutter/releases) et installe-le directement sur ton appareil Android (minSdk 24 — Android 7.0+).

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

# Build release (recommandé : split par ABI)
flutter build apk --split-per-abi --release
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
3. Renseigne-le dans **Paramètres → Clé TMDB**

> Sans clé TMDB, l'application fonctionne normalement mais sans enrichissement visuel.

---

## Architecture

```
lib/
├── main.dart                          # Point d'entrée + aiguilleur de navigation
├── core/
│   ├── themes/                        # Couleurs et thèmes (clair/sombre)
│   └── utils/                         # NetworkUtils, SecureStorage, ...
├── data/
│   ├── models/                        # StreamAccount, M3uEntry, Media, DownloadTask, XmltvProgram...
│   └── services/                      # PlaylistService, TmdbService, ReplayService, XmltvService...
├── feature/
│   ├── accounts/                      # Gestion des comptes IPTV
│   ├── downloads/                     # Gestionnaire de téléchargements
│   ├── player/                        # Lecteur vidéo (media_kit, contrôles custom, gestures)
│   ├── replay/                        # Picker replay + grille EPG XMLTV
│   ├── search/                        # Recherche : RechercheM3U, M3uParser, M3uFilter
│   └── update/                        # Mise à jour in-app (GitHub Releases)
├── widgets/                           # Widgets réutilisables : cartes, action sheets, EPG, chips
└── l10n/                              # Traductions FR / EN
```

### Stack technique

| Composant | Package |
|-----------|---------|
| HTTP / Téléchargements | `dio` |
| Player vidéo | `media_kit` + `media_kit_video` (libmpv) |
| Luminosité | `screen_brightness` |
| Stockage sécurisé | `flutter_secure_storage` |
| Préférences | `shared_preferences` |
| MediaStore Android | `media_store_plus` |
| EPG XMLTV | `xml` |
| Polices | `google_fonts` |
| Permissions | `permission_handler` |
| Réseau | `connectivity_plus` |

---

## Roadmap

- [x] **Refonte complète du player** — `media_kit`, contrôles custom, gestures, reconnexion auto *(PiP reporté)*
- [x] **Mise à jour in-app** — vérification + téléchargement APK depuis GitHub Releases
- [x] **Grille EPG XMLTV** — sélection programme dans la grille pour le replay
- [x] **Refactoring** — découpage `recherche_page.dart` en modules séparés (parser, filter, widgets)
- [ ] **Parsing M3U en isolate** — `compute()` pour ne plus bloquer le thread principal
- [ ] **Page d'accueil** — trending TMDB + derniers ajoutés, navigation bottom bar, design glassmorphism
- [ ] **Thème personnalisable** — `AppThemeConfig` configurable in-app
- [ ] **Catégories M3U** — sections par genre sur la page d'accueil extraites des `group-title` provider
- [ ] **Favoris** — films, séries et chaînes
- [ ] **En cours de lecture** — reprise depuis la dernière position

---

## Licence

Projet personnel — tous droits réservés.
