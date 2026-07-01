---
name: windows-sync-and-release
description: Automates the synchronization of windows-port branch with newSkin and handles Windows installer build, git pushing, and GitHub Release asset upload.
---

# Windows Sync and Release Skill

Ce skill automatise et guide la synchronisation de la branche `windows-port` avec les dernières fonctionnalités de la branche `newSkin` (Android), la compilation de l'exécutable et de l'installeur Windows, la mise à jour des dépôts Git et l'envoi de l'installeur sur GitHub Releases.

## Pipeline d'exécution

### Étape 1 : Synchronisation Git
1. Récupérer les derniers commits de la branche distante :
   ```bash
   git fetch origin
   ```
2. Fusionner les modifications d'Android :
   ```bash
   git merge origin/newSkin
   ```
3. Résoudre les conflits éventuels en préservant le layout Desktop (NavigationRail large, bouton Plein écran) et l'accélération matérielle Windows (`hwdec: auto-safe`).

### Étape 2 : Alignement et Bump de Version
1. Lire la version courante dans `pubspec.yaml` (ex: `1.13.0+87`).
2. Définir une version d'installeur Windows incrémentée à 4 chiffres (ex: `AppVersion=1.13.0.1`) dans le fichier [aetherstream_setup.iss](file:///c:/Users/juman/StudioProjects/dwl_iptv_windows/windows/runner/aetherstream_setup.iss).

### Étape 3 : Compilation et Packaging
1. Récupérer les dépendances :
   ```bash
   flutter pub get
   ```
2. Lancer l'analyse statique :
   ```bash
   flutter analyze
   ```
3. Compiler l'exécutable de release Windows :
   ```bash
   flutter build windows
   ```
4. Générer l'installeur via le compilateur Inno Setup :
   ```powershell
   & "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" windows/runner/aetherstream_setup.iss
   ```

### Étape 4 : Validation et Envoi
1. Commiter la configuration de l'installeur et forcer l'ajout du binaire généré (car gitignoré) :
   ```bash
   git add windows/runner/aetherstream_setup.iss
   git add -f build/windows/x64/runner/Release/INSTALLER/AetherStream_Setup.exe
   git commit -m "[windows] update setup installer binary and script to v<version>"
   ```
2. Pousser les modifications sur le dépôt :
   ```bash
   git push origin windows-port
   ```
3. Attacher le `.exe` directement à la Release GitHub en utilisant le CLI GitHub `gh` :
   ```bash
   gh release upload v<version> build/windows/x64/runner/Release/INSTALLER/AetherStream_Setup.exe --clobber
   ```
