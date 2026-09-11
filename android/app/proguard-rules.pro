# AetherStream — règles R8 de l'application (D2B-04, revue 2026-09-11, lot 9).
#
# ⚠️ R8 EST DÉJÀ ACTIF en release — minification ET réduction des ressources.
# Ce n'est écrit nulle part dans `build.gradle.kts` : c'est le plugin Gradle de
# Flutter qui l'active par défaut (`FlutterPlugin.kt`, `shouldShrinkResources`)
# et qui ajoute CE fichier à la liste des règles s'il existe, après
# `proguard-android-optimize.txt` et les règles propres à Flutter. La doc
# disait « R8 : pas encore » ; les sorties `build/app/outputs/mapping/release/`
# prouvaient le contraire depuis le premier build de release.
#
# Il ne contient volontairement AUCUNE règle. Il marque l'endroit où en poser
# une le jour où R8 retire une classe appelée par réflexion — symptôme :
# `ClassNotFoundException` / `NoSuchMethodException` SEULEMENT en release,
# jamais en debug. Chaque règle ajoutée dit POURQUOI, avec le symptôme vu.
#
# ⚠️ Chemins jamais recettés minifiés sur un appareil PHYSIQUE (le Galaxy S25
# de recette porte un build debug) : §castRelay (Media3 Transformer) et le
# service Cast. C'est là qu'une règle manquante se verrait en premier.
#
# Relire une pile obfusquée — la CI archive tout dans l'artefact
# « symboles-<tag> » (jamais publié dans la release) :
#   · pile JAVA/KOTLIN : `retrace mapping.txt pile.txt`
#     (outil R8 des cmdline-tools du SDK Android) ;
#   · pile DART (`--obfuscate`) : `flutter symbolize -i pile.txt
#     -d symbols/<split|universal>/app.android-arm64.symbols`.
