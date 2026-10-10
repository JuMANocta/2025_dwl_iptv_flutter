# AetherStream

**Client IPTV pour Android et Android TV — multi-comptes, EPG, Replay, TMDB.**

Ce dépôt sert uniquement à **distribuer les versions publiées** d'AetherStream. Le code source n'y est pas publié.

---

## ⬇️ Télécharger

👉 **[Dernière version](https://github.com/JuMANocta/2025_dwl_iptv_flutter/releases/latest)** · [Toutes les versions](https://github.com/JuMANocta/2025_dwl_iptv_flutter/releases)

| Fichier | Pour qui |
|---|---|
| `aetherstream_arm64-v8a.apk` | téléphones, tablettes et box récents (processeur 64 bits) — **le bon choix dans la plupart des cas** |
| `aetherstream_armeabi-v7a.apk` | Fire TV Stick et appareils 32 bits |
| `aetherstream.apk` | universel (les deux), en cas de doute — plus lourd |
| `AetherStream_Setup.exe` | Windows, quand la version le propose |

Chaque APK est accompagné de son empreinte `.sha256`.

## 📲 Installation sur Android

1. Autorise l'installation d'applications **de sources inconnues** pour le navigateur ou le gestionnaire de fichiers que tu utilises.
2. Télécharge l'APK qui correspond à ton appareil, ouvre-le, puis installe.

Compatible **Android 7.0 et plus** : smartphones, tablettes, Fire TV Stick et Android TV, processeurs **ARM64 et ARMv7**. Aucune version x86_64 n'est publiée.

> ⚠️ Un appareil qui a reçu un APK par processeur n'accepte plus ensuite l'APK universel (Android le voit comme une version plus ancienne). Pour changer : exporte une sauvegarde `.aether` (**Paramètres → Sauvegarde**), désinstalle, réinstalle, puis restaure.

### Vérifier un fichier (facultatif)

Compare le résultat avec le contenu du fichier `.sha256` correspondant :

```
# Windows (PowerShell)
Get-FileHash .\aetherstream_arm64-v8a.apk -Algorithm SHA256

# Linux / macOS
sha256sum aetherstream_arm64-v8a.apk
```

## 🔄 Mises à jour

Une fois installée, l'application vérifie les nouvelles versions publiées ici, choisit d'elle-même l'APK adapté au processeur et **vérifie son empreinte SHA-256** avant d'ouvrir l'installeur. Vérification manuelle : **Paramètres → À propos**.

## ⚙️ Premiers pas

- Au premier lancement, ajoute un compte IPTV : **URL de playlist M3U** ou **Xtream Codes** (serveur, identifiant, mot de passe).
- Facultatif : pour les affiches et synopsis, renseigne une clé TMDB (*API Read Access Token v4*, gratuite sur [themoviedb.org](https://www.themoviedb.org)) dans **Paramètres → Affiches et infos TMDB**.

AetherStream ne fournit **aucun contenu** : il lit uniquement les listes et services que tu y ajoutes.

## 📄 Licence

Application gratuite pour un usage personnel ; code source non distribué. Voir [LICENSE](LICENSE).
