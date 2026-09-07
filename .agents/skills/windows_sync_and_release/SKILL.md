---
name: windows-sync-and-release
description: Automates the synchronization of the windows-port branch with upstream newSkin tags/releases when the user asks "nouveau tag", "nouveau tag go", "go pour le dernier tag", "sync tag", "mise à jour Windows". Covers Git fetch/merge, resolving recurring Windows conflicts, l10n guard adherence, testing, Windows release compilation, Inno Setup installer packaging (ISCC), Git push, and GitHub Release asset upload.
---

# Windows Sync and Release Skill

Ce skill formalise le protocole complet de synchronisation de la branche `windows-port` avec les dernières releases amont de la branche `newSkin` (Android).
Il guide l'agent à travers la résolution de conflits récurrents, le respect des contraintes strictes du projet, les tests de non-régression, la compilation de l'installeur Inno Setup et la publication GitHub Release.

---

## 🛑 Règles d'or & Contraintes Inviolables

1. **NE JAMAIS COMMITER LE DOSSIER `.claude/` NI MODIFIER LE `.gitignore`** :
   - L'utilisateur a explicitement stipulé : *"ne touche pas le gitignore je ne veux pas commit les fichiers .claude"*.
   - Toujours vérifier via `git status` avant tout commit que rien dans `.claude/` n'est indexé.
2. **Architecture Vidéo Hybride (§dualEngine)** :
   - **Windows** : Utilise obligatoirement `MpvPlaybackEngine` (`media_kit` + libmpv avec décodage matériel GPU DirectX 11 / D3D11va).
   - **Android** : Utilise `Media3Engine` / `better_native_video_player`.
   - **Ne JAMAIS tenter d'utiliser `better_native_video_player` sous Windows** (plugin Android natif incompatible Windows).
3. **Cliquet de Non-Régression de Traduction (`test/l10n_guard_test.dart`)** :
   - Le projet intègre un cliquet strict interdisant l'ajout de chaînes françaises accentuées écrites en dur dans le code UI de `lib/`.
   - Utiliser systématiquement `context.l10n.*`, `AppLocalizations.of(context)!.*` ou `L10n.current.*` pour les messages localisés.
   - Pour les stubs de plateforme non supportée ou messages techniques internes, utiliser l'anglais sans accents (ex: `'Unsupported platform for ...'`).
4. **Layout Desktop Windows** :
   - Maintenir le layout adaptatif desktop : `NavigationRail` lorsque la largeur dépasse 700px (`useRail = isTv || isWide`), raccourcis clavier et toggle plein écran via `window_manager`.

---

## 📋 Pipeline d'Exécution Pas-à-Pas

### Étape 1 : Inspection Amont et Fusion Git

1. Récupérer l'ensemble des branches et tags distants :
   ```bash
   git fetch origin --tags
   ```
2. Identifier le dernier tag publié sur `origin/newSkin` :
   ```bash
   git log origin/newSkin -n 1 --oneline
   git tag --sort=-v:refname | head -n 5
   ```
3. Lancer la fusion de `origin/newSkin` dans `windows-port` :
   ```bash
   git merge origin/newSkin
   ```

---

### Étape 2 : Résolution des Conflits Récurrents

En cas de conflits (`git status`), appliquer les patterns éprouvés suivants :

#### 1. `lib/core/navigation/main_navigation.dart`
- **Rail Desktop & Wide Screen** : Préserver la détection `isWide = MediaQuery.of(context).size.width > 700` et `useRail = isTv || isWide`.
- **Plein écran Windows** : Conserver le mixin `with WindowListener` et l'état `_isFullScreen`.
- **Destination 3 (Paramètres)** : Lorsque l'utilisateur clique sur la destination 3 dans le Rail, appeler `onOpenSettings()` sans modifier l'index sélectionné.
- **OfflineBanner** : Conserver le composant `OfflineBanner` au-dessus de l'`IndexedStack` (sans l'onglet Paramètres dans la pile, car ouvert en route modale).

#### 2. `lib/data/services/update_service.dart`
- **Recherche d'Asset Multiplateforme** : Chercher `.exe` sur Windows et `.apk` sur Android :
  ```dart
  final extension = Platform.isWindows ? '.exe' : '.apk';
  final asset = assets.firstWhere(
    (a) => (a['name'] as String?)?.toLowerCase().endsWith(extension) == true,
    orElse: () => null,
  );
  if (asset == null) {
    return UpdateUnavailable(
      Platform.isWindows
          ? 'No .exe installer found in release $tagName'
          : L10n.current.updNoApk(tagName),
    );
  }
  ```
- **Permission & Installation** : Déléguer à `InstallerService` :
  ```dart
  final hasPermission = await InstallerService.ensurePermission();
  if (!hasPermission) {
    throw Exception(L10n.current.updInstallDenied);
  }
  // ...
  await InstallerService.install(updatePath, downloadUrl: url);
  ```

#### 3. `lib/feature/downloads/widgets/download_task_tile.dart`
- Conserver l'import de `package:media_store_plus/media_store_plus.dart` qui est utilisé dans le bloc `if (Platform.isAndroid)` pour nettoyer le MediaStore Android.

#### 4. `lib/feature/settings/settings_page.dart`
- Préserver l'entrée de la console Web pour TV et Windows :
  ```dart
  if (PlatformTv.isTv || Platform.isWindows) ...[
    _SectionHeader(title: context.l10n.settingsSectionPhone),
    _SettingsTile(
      icon: Icons.smartphone,
      accentColor: kAccentPrimary,
      title: context.l10n.settingsWebConsole,
      subtitle: context.l10n.settingsWebConsoleSub,
      onTap: _openPhoneConfig,
    ),
  ]
  ```
- Utiliser `context.l10n.settingsUsageReset` pour le SnackBar de confirmation.

#### 5. `lib/feature/player/mpv_playback_engine.dart` & `AetherPlaybackEngine`
- Si `AetherPlaybackEngine` a reçu de nouveaux paramètres (ex: `AetherNowPlaying? nowPlaying`), les reporter dans `MpvPlaybackEngine.open` et `MpvPlaybackEngine.openFile`.

---

### Étape 3 : Alignement de la Version

1. Lire la version amont dans `pubspec.yaml` (ex: `version: 1.18.15+148`).
2. Mettre à jour `AppVersion` dans `windows/runner/aetherstream_setup.iss` avec le numéro sémantique exact (sans le numéro de build) :
   ```ini
   AppVersion=1.18.15
   ```
3. *(Optionnel)* Mettre à jour localement les versions indiquées dans `.claude/CLAUDE.md` et `.claude/windows_port.md`, **sans jamais les commiter**.

---

### Étape 4 : Validation Qualité & Tests

1. Récupération des dépendances Flutter :
   ```bash
   flutter pub get
   ```
2. Analyse statique (doit être 100% propre, 0 erreur, 0 avertissement) :
   ```bash
   flutter analyze
   ```
3. Exécution de la suite de tests :
   ```bash
   flutter test
   ```
   - *Note* : Si `test/widget_test.dart` échoue à cause du template compteur Flutter par défaut, s'assurer qu'il porte `skip: true`.
   - *Note* : Le test `test/l10n_guard_test.dart` doit passer avec succès (`All tests passed!`).

---

### Étape 5 : Compilation de l'Exécutable et de l'Installeur

1. Compiler l'exécutable Windows en mode Release :
   ```bash
   flutter build windows --release
   ```
2. Compiler l'installeur Inno Setup via le compilateur ISCC :
   ```powershell
   & "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" windows/runner/aetherstream_setup.iss
   ```
3. Vérifier que le binaire a bien été généré dans :
   `build\windows\x64\runner\Release\INSTALLER\AetherStream_Setup.exe`

---

### Étape 6 : Commit Git et Push

1. Indexer les fichiers sources résolus et le script d'installation :
   ```bash
   git add lib/ windows/runner/aetherstream_setup.iss pubspec.lock test/widget_test.dart
   ```
2. Forcer l'ajout de l'installeur généré (qui est ignoré par défaut dans le `.gitignore`) :
   ```bash
   git add -f build/windows/x64/runner/Release/INSTALLER/AetherStream_Setup.exe
   ```
3. **Vérification critique avant commit** :
   ```bash
   git status
   ```
   S'assurer formellement qu'aucun fichier du dossier `.claude/` n'apparaît dans les modifications indexées.
4. Créer le commit de fusion et d'installeur :
   ```bash
   git commit -m "[windows] sync origin/newSkin v<tag>+<build> & update setup installer v<tag>"
   ```
5. Pousser la branche sur le dépôt distant :
   ```bash
   git push origin windows-port
   ```

---

### Étape 7 : Téléversement sur GitHub Releases

1. Vérifier l'existence de la release correspondant au tag sur GitHub :
   ```bash
   gh release view v<version>
   ```
2. Téléverser l'installeur Windows généré en remplaçant l'existant si nécessaire (`--clobber`) :
   ```bash
   gh release upload v<version> build/windows/x64/runner/Release/INSTALLER/AetherStream_Setup.exe --clobber
   ```
3. Vérifier la présence de l'asset dans la release :
   ```bash
   gh release view v<version>
   ```
   La liste des assets doit contenir `AetherStream_Setup.exe` aux côtés de `aetherstream.apk`.
